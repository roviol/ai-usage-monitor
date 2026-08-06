#include "ai_usage/platform.h"

#include <curl/curl.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/file.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <random>
#include <regex>
#include <stdexcept>
#include <thread>

namespace ai_usage {
namespace {

class Fd {
 public:
  explicit Fd(int value = -1) : value_(value) {}
  ~Fd() { Reset(); }
  Fd(const Fd&) = delete;
  Fd& operator=(const Fd&) = delete;
  Fd(Fd&& other) noexcept : value_(other.Release()) {}
  Fd& operator=(Fd&& other) noexcept { if (this != &other) Reset(other.Release()); return *this; }
  int Get() const { return value_; }
  int Release() { const int value = value_; value_ = -1; return value; }
  void Reset(int value = -1) { if (value_ >= 0) close(value_); value_ = value; }
 private:
  int value_;
};

void SetNonBlocking(int descriptor) {
  const int flags = fcntl(descriptor, F_GETFL, 0);
  if (flags >= 0) fcntl(descriptor, F_SETFL, flags | O_NONBLOCK);
}

void Drain(int descriptor, std::string& destination) {
  std::array<char, 4096> buffer{};
  while (true) {
    const auto count = read(descriptor, buffer.data(), buffer.size());
    if (count > 0) destination.append(buffer.data(), static_cast<std::size_t>(count));
    else break;
  }
}

class LinuxProcessRunner final : public IProcessRunner {
 public:
  ProcessResult Run(const ProcessRequest& request) override {
    int inputPipe[2]{};
    int outputPipe[2]{};
    int errorPipe[2]{};
    if (pipe(inputPipe) != 0 || pipe(outputPipe) != 0 || pipe(errorPipe) != 0) throw std::runtime_error("pipe failed");
    const pid_t child = fork();
    if (child < 0) throw std::runtime_error("fork failed");
    if (child == 0) {
      setpgid(0, 0);
      dup2(inputPipe[0], STDIN_FILENO);
      dup2(outputPipe[1], STDOUT_FILENO);
      dup2(errorPipe[1], STDERR_FILENO);
      close(inputPipe[0]); close(inputPipe[1]); close(outputPipe[0]); close(outputPipe[1]); close(errorPipe[0]); close(errorPipe[1]);
      std::vector<std::string> values;
      values.push_back(request.executable.string());
      values.insert(values.end(), request.arguments.begin(), request.arguments.end());
      std::vector<char*> arguments;
      for (auto& value : values) arguments.push_back(value.data());
      arguments.push_back(nullptr);
      execvp(arguments[0], arguments.data());
      _exit(127);
    }
    close(inputPipe[0]); close(outputPipe[1]); close(errorPipe[1]);
    Fd input(inputPipe[1]);
    Fd output(outputPipe[0]);
    Fd error(errorPipe[0]);
    SetNonBlocking(output.Get());
    SetNonBlocking(error.Get());
    if (!request.standardInput.empty()) {
      const char* cursor = request.standardInput.data();
      std::size_t remaining = request.standardInput.size();
      while (remaining > 0) {
        const auto count = write(input.Get(), cursor, remaining);
        if (count <= 0) break;
        cursor += count;
        remaining -= static_cast<std::size_t>(count);
      }
    }
    ProcessResult result;
    const auto deadline = std::chrono::steady_clock::now() + request.timeout;
    const auto inputCloseDeadline = std::chrono::steady_clock::now() + request.standardInputCloseDelay;
    bool inputOpen = !request.standardInput.empty() && request.standardInputCloseDelay > std::chrono::milliseconds{0};
    if (!inputOpen) input.Reset();
    int status = 0;
    while (true) {
      Drain(output.Get(), result.standardOutput);
      Drain(error.Get(), result.standardError);
      const auto waited = waitpid(child, &status, WNOHANG);
      if (waited == child) break;
      if (request.cancellationRequested && request.cancellationRequested()) {
        result.cancelled = true;
        kill(-child, SIGKILL);
        waitpid(child, &status, 0);
        break;
      }
      const auto now = std::chrono::steady_clock::now();
      if (inputOpen && now >= inputCloseDeadline) {
        input.Reset();
        inputOpen = false;
      }
      if (now >= deadline) {
        result.timedOut = true;
        kill(-child, SIGKILL);
        waitpid(child, &status, 0);
        break;
      }
      poll(nullptr, 0, 10);
    }
    Drain(output.Get(), result.standardOutput);
    Drain(error.Get(), result.standardError);
    input.Reset();
    if (WIFEXITED(status)) result.exitCode = WEXITSTATUS(status);
    else if (WIFSIGNALED(status)) result.exitCode = 128 + WTERMSIG(status);
    return result;
  }
};

struct CurlBuffer {
  std::string body;
  std::map<std::string, std::string> headers;
  std::size_t maximum{1024U * 1024U};
  bool overflow{false};
};

std::size_t CurlWrite(char* data, std::size_t size, std::size_t count, void* context) {
  auto& buffer = *static_cast<CurlBuffer*>(context);
  const std::size_t bytes = size * count;
  if (buffer.body.size() + bytes > buffer.maximum) { buffer.overflow = true; return 0; }
  buffer.body.append(data, bytes);
  return bytes;
}

std::size_t CurlHeader(char* data, std::size_t size, std::size_t count, void* context) {
  auto& buffer = *static_cast<CurlBuffer*>(context);
  const std::size_t bytes = size * count;
  std::string line(data, bytes);
  const auto colon = line.find(':');
  if (colon != std::string::npos) {
    auto name = line.substr(0, colon);
    auto value = line.substr(colon + 1);
    while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front()))) value.erase(value.begin());
    while (!value.empty() && (value.back() == '\r' || value.back() == '\n')) value.pop_back();
    buffer.headers[std::move(name)] = std::move(value);
  }
  return bytes;
}

class LinuxHttpClient final : public IHttpClient {
 public:
  LinuxHttpClient() { curl_global_init(CURL_GLOBAL_DEFAULT); }
  HttpResponse Send(const HttpRequest& request) override {
    if (!IsSafeEndpointUrl(request.url, request.allowLoopbackHttp)) throw std::runtime_error("unsafe endpoint URL");
    std::unique_ptr<CURL, decltype(&curl_easy_cleanup)> curl(curl_easy_init(), curl_easy_cleanup);
    if (!curl) throw std::runtime_error("curl_easy_init failed");
    CurlBuffer buffer;
    buffer.maximum = request.maxResponseBytes;
    curl_easy_setopt(curl.get(), CURLOPT_URL, request.url.c_str());
    curl_easy_setopt(curl.get(), CURLOPT_CUSTOMREQUEST, request.method.c_str());
    curl_easy_setopt(curl.get(), CURLOPT_FOLLOWLOCATION, 0L);
    curl_easy_setopt(curl.get(), CURLOPT_TIMEOUT_MS, static_cast<long>(request.timeout.count()));
    curl_easy_setopt(curl.get(), CURLOPT_WRITEFUNCTION, CurlWrite);
    curl_easy_setopt(curl.get(), CURLOPT_WRITEDATA, &buffer);
    curl_easy_setopt(curl.get(), CURLOPT_HEADERFUNCTION, CurlHeader);
    curl_easy_setopt(curl.get(), CURLOPT_HEADERDATA, &buffer);
    curl_easy_setopt(curl.get(), CURLOPT_USERAGENT, "AIUsageMonitor/0.1");
    if (!request.body.empty()) {
      curl_easy_setopt(curl.get(), CURLOPT_POSTFIELDS, request.body.data());
      curl_easy_setopt(curl.get(), CURLOPT_POSTFIELDSIZE, static_cast<long>(request.body.size()));
    }
    curl_slist* rawHeaders = nullptr;
    for (const auto& [name, value] : request.headers) rawHeaders = curl_slist_append(rawHeaders, (name + ": " + value).c_str());
    std::unique_ptr<curl_slist, decltype(&curl_slist_free_all)> headers(rawHeaders, curl_slist_free_all);
    if (headers) curl_easy_setopt(curl.get(), CURLOPT_HTTPHEADER, headers.get());
    const auto code = curl_easy_perform(curl.get());
    if (buffer.overflow) throw std::runtime_error("HTTP response exceeds 1 MiB limit");
    if (code != CURLE_OK) throw std::runtime_error(curl_easy_strerror(code));
    long status = 0;
    curl_easy_getinfo(curl.get(), CURLINFO_RESPONSE_CODE, &status);
    return HttpResponse{static_cast<int>(status), std::move(buffer.headers), std::move(buffer.body)};
  }
};

std::string RandomId() {
  std::random_device random;
  static constexpr char hex[] = "0123456789abcdef";
  std::string result(32, '0');
  for (char& character : result) character = hex[random() & 15U];
  return result;
}

class LinuxSecretStore final : public ISecretStore {
 public:
  LinuxSecretStore() : runner_(std::make_unique<LinuxProcessRunner>()), persistent_(DiscoverExecutable("secret-tool").has_value()) {}
  std::string Protect(const std::string& plainText) override {
    const auto id = RandomId();
    if (persistent_) {
      const auto executable = *DiscoverExecutable("secret-tool");
      const auto result = runner_->Run(ProcessRequest{executable, {"store", "--label=AI Usage Monitor", "service", "ai-usage-monitor", "key", id},
                                                      plainText, std::chrono::milliseconds{5000}});
      if (result.exitCode == 0) return "secret-service:" + id;
    }
    return ProtectSession(plainText);
  }
  std::string ProtectSession(const std::string& plainText) override {
    const auto id = RandomId();
    std::lock_guard lock(sessionMutex_);
    session_[id] = plainText;
    return "session:" + id;
  }
  std::string Unprotect(const std::string& opaque) override {
    if (opaque.starts_with("session:")) {
      std::lock_guard lock(sessionMutex_);
      const auto found = session_.find(opaque.substr(8));
      if (found == session_.end()) throw std::runtime_error("session-only credential expired");
      return found->second;
    }
    if (!opaque.starts_with("secret-service:") || !persistent_) throw std::runtime_error("secure storage unavailable");
    const auto id = opaque.substr(15);
    const auto executable = *DiscoverExecutable("secret-tool");
    const auto result = runner_->Run(ProcessRequest{executable, {"lookup", "service", "ai-usage-monitor", "key", id}, {},
                                                    std::chrono::milliseconds{5000}});
    if (result.exitCode != 0 || result.standardOutput.empty()) throw std::runtime_error("credential not found in Secret Service");
    auto secret = result.standardOutput;
    while (!secret.empty() && (secret.back() == '\r' || secret.back() == '\n')) secret.pop_back();
    return secret;
  }
  bool PersistentAvailable() const override { return persistent_; }
 private:
  std::unique_ptr<IProcessRunner> runner_;
  bool persistent_;
  std::mutex sessionMutex_;
  std::map<std::string, std::string> session_;
};

class SystemClockService final : public IClock {
 public:
  TimePoint Now() const override { return Clock::now(); }
};

class LinuxSingleInstanceSignal final : public ISingleInstanceSignal {
 public:
  explicit LinuxSingleInstanceSignal(const std::filesystem::path& dataRoot)
      : activation_(dataRoot / "activate.request") {
    std::filesystem::create_directories(dataRoot);
    lock_.Reset(open((dataRoot / "instance.lock").c_str(), O_CREAT | O_RDWR, 0600));
    if (lock_.Get() < 0) throw std::runtime_error("cannot open single-instance lock");
    anotherRunning_ = flock(lock_.Get(), LOCK_EX | LOCK_NB) != 0;
  }

  bool IsAnotherRunning() const override { return anotherRunning_; }
  void SignalActivation() override {
    std::ofstream request(activation_, std::ios::binary | std::ios::trunc);
    if (!request) throw std::runtime_error("cannot write activation request");
    request << "show";
  }
  bool ConsumeActivation() override {
    if (!std::filesystem::exists(activation_)) return false;
    std::error_code error;
    std::filesystem::remove(activation_, error);
    return !error;
  }
  bool WaitForActivation(std::chrono::milliseconds timeout) override {
    if (timeout != std::chrono::milliseconds::max()) {
      std::this_thread::sleep_for(timeout);
      return ConsumeActivation();
    }
    while (!std::filesystem::exists(activation_)) std::this_thread::sleep_for(std::chrono::milliseconds{250});
    return ConsumeActivation();
  }

 private:
  Fd lock_;
  std::filesystem::path activation_;
  bool anotherRunning_{false};
};

bool IsLoopbackHost(std::string host) {
  std::transform(host.begin(), host.end(), host.begin(), [](unsigned char character) { return static_cast<char>(std::tolower(character)); });
  return host == "localhost" || host == "127.0.0.1" || host == "[::1]" || host == "::1";
}

}  // namespace

std::unique_ptr<IHttpClient> CreatePlatformHttpClient() { return std::make_unique<LinuxHttpClient>(); }
std::unique_ptr<IProcessRunner> CreatePlatformProcessRunner() { return std::make_unique<LinuxProcessRunner>(); }
std::unique_ptr<ISecretStore> CreatePlatformSecretStore() { return std::make_unique<LinuxSecretStore>(); }
std::unique_ptr<IClock> CreatePlatformClock() { return std::make_unique<SystemClockService>(); }
std::unique_ptr<ISingleInstanceSignal> CreatePlatformSingleInstanceSignal(const std::filesystem::path& dataRoot) {
  return std::make_unique<LinuxSingleInstanceSignal>(dataRoot);
}

std::optional<std::filesystem::path> DiscoverExecutable(const std::string& name) {
  if (name.find('/') != std::string::npos) {
    const std::filesystem::path candidate(name);
    if (access(candidate.c_str(), X_OK) == 0) return candidate;
    return std::nullopt;
  }
  const char* pathValue = std::getenv("PATH");
  if (pathValue == nullptr) return std::nullopt;
  std::string path(pathValue);
  std::size_t begin = 0;
  while (begin <= path.size()) {
    const auto end = path.find(':', begin);
    const auto directory = path.substr(begin, end == std::string::npos ? std::string::npos : end - begin);
    const auto candidate = std::filesystem::path(directory) / name;
    if (access(candidate.c_str(), X_OK) == 0) return candidate;
    if (end == std::string::npos) break;
    begin = end + 1;
  }
  return std::nullopt;
}

std::string ProbeVersion(IProcessRunner& runner, const std::filesystem::path& executable) {
  if (executable.empty()) return {};
  try {
    const auto result = runner.Run(ProcessRequest{executable, {"--version"}, {}, std::chrono::milliseconds{5000}});
    if (result.timedOut) return {};
    auto output = result.standardOutput.empty() ? result.standardError : result.standardOutput;
    while (!output.empty() && (output.back() == '\r' || output.back() == '\n')) output.pop_back();
    return output;
  } catch (...) { return {}; }
}

bool IsSafeEndpointUrl(const std::string& url, bool allowLoopbackHttp) {
  static const std::regex pattern(R"(^(https?)://(\[[^\]]+\]|[^/:?#]+)(?::[0-9]+)?(?:[/?#].*)?$)", std::regex::icase);
  std::smatch match;
  if (!std::regex_match(url, match, pattern)) return false;
  std::string scheme = match[1].str();
  std::transform(scheme.begin(), scheme.end(), scheme.begin(), [](unsigned char character) { return static_cast<char>(std::tolower(character)); });
  return scheme == "https" || (scheme == "http" && allowLoopbackHttp && IsLoopbackHost(match[2].str()));
}

std::string RedactSecrets(std::string text, const std::vector<std::string>& secrets) {
  for (const auto& secret : secrets) {
    if (secret.empty()) continue;
    std::size_t position = 0;
    while ((position = text.find(secret, position)) != std::string::npos) {
      text.replace(position, secret.size(), "<redacted>");
      position += 10;
    }
  }
  static const std::regex authorization(R"((Authorization\s*:\s*)([^\r\n]+))", std::regex::icase);
  return std::regex_replace(text, authorization, "$1<redacted>");
}

}  // namespace ai_usage
