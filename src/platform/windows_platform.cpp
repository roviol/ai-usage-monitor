#include "ai_usage/platform.h"

#include <windows.h>
#include <wincrypt.h>
#include <winhttp.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cctype>
#include <cstddef>
#include <filesystem>
#include <fstream>
#include <map>
#include <mutex>
#include <regex>
#include <stdexcept>
#include <string_view>
#include <thread>

namespace ai_usage {
namespace {

std::wstring Wide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) throw std::runtime_error("invalid UTF-8");
  std::wstring result(static_cast<std::size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::string Utf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (size <= 0) throw std::runtime_error("invalid UTF-16");
  std::string result(static_cast<std::size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), result.data(), size, nullptr, nullptr);
  return result;
}

std::string WindowsError(const char* operation) {
  const DWORD code = GetLastError();
  wchar_t* buffer = nullptr;
  const DWORD size = FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                                    nullptr, code, 0, reinterpret_cast<wchar_t*>(&buffer), 0, nullptr);
  std::wstring message = size > 0 && buffer != nullptr ? std::wstring(buffer, size) : L"unknown";
  if (buffer != nullptr) LocalFree(buffer);
  return std::string(operation) + " failed (" + std::to_string(code) + "): " + Utf8(message);
}

class Handle {
 public:
  Handle() = default;
  explicit Handle(HANDLE value) : value_(value) {}
  ~Handle() { Reset(); }
  Handle(const Handle&) = delete;
  Handle& operator=(const Handle&) = delete;
  Handle(Handle&& other) noexcept : value_(other.Release()) {}
  Handle& operator=(Handle&& other) noexcept {
    if (this != &other) Reset(other.Release());
    return *this;
  }
  HANDLE Get() const { return value_; }
  HANDLE Release() {
    const auto value = value_;
    value_ = nullptr;
    return value;
  }
  void Reset(HANDLE value = nullptr) {
    if (value_ != nullptr && value_ != INVALID_HANDLE_VALUE) CloseHandle(value_);
    value_ = value;
  }
  explicit operator bool() const { return value_ != nullptr && value_ != INVALID_HANDLE_VALUE; }

 private:
  HANDLE value_{nullptr};
};

class InternetHandle {
 public:
  explicit InternetHandle(HINTERNET value = nullptr) : value_(value) {}
  ~InternetHandle() { if (value_ != nullptr) WinHttpCloseHandle(value_); }
  InternetHandle(const InternetHandle&) = delete;
  InternetHandle& operator=(const InternetHandle&) = delete;
  HINTERNET Get() const { return value_; }
  explicit operator bool() const { return value_ != nullptr; }

 private:
  HINTERNET value_;
};

std::wstring Quote(const std::wstring& value) {
  if (value.find_first_of(L" \t\"") == std::wstring::npos) return value;
  std::wstring result = L"\"";
  std::size_t backslashes = 0;
  for (const wchar_t character : value) {
    if (character == L'\\') {
      ++backslashes;
    } else if (character == L'\"') {
      result.append(backslashes * 2 + 1, L'\\');
      result.push_back(L'\"');
      backslashes = 0;
    } else {
      result.append(backslashes, L'\\');
      backslashes = 0;
      result.push_back(character);
    }
  }
  result.append(backslashes * 2, L'\\');
  result.push_back(L'\"');
  return result;
}

std::wstring BuildCommand(const ProcessRequest& request) {
  const auto extension = request.executable.extension().wstring();
  std::wstring command;
  if (_wcsicmp(extension.c_str(), L".cmd") == 0 || _wcsicmp(extension.c_str(), L".bat") == 0) {
    wchar_t system[MAX_PATH]{};
    GetSystemDirectoryW(system, MAX_PATH);
    command = Quote(std::filesystem::path(system) / L"cmd.exe") + L" /d /s /c \"" + Quote(request.executable.wstring());
    for (const auto& argument : request.arguments) command += L" " + Quote(Wide(argument));
    command += L"\"";
  } else if (_wcsicmp(extension.c_str(), L".ps1") == 0) {
    command = L"powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Quote(request.executable.wstring());
    for (const auto& argument : request.arguments) command += L" " + Quote(Wide(argument));
  } else {
    command = Quote(request.executable.wstring());
    for (const auto& argument : request.arguments) command += L" " + Quote(Wide(argument));
  }
  return command;
}

void ReadPipe(HANDLE pipe, std::string& destination) {
  std::array<char, 4096> buffer{};
  DWORD count = 0;
  while (ReadFile(pipe, buffer.data(), static_cast<DWORD>(buffer.size()), &count, nullptr) && count > 0) {
    destination.append(buffer.data(), count);
  }
}

class WindowsProcessRunner final : public IProcessRunner {
 public:
  ProcessResult Run(const ProcessRequest& request) override {
    SECURITY_ATTRIBUTES security{sizeof(SECURITY_ATTRIBUTES), nullptr, TRUE};
    Handle childOutRead;
    Handle childOutWrite;
    Handle childErrRead;
    Handle childErrWrite;
    Handle childInRead;
    Handle childInWrite;
    HANDLE rawRead = nullptr;
    HANDLE rawWrite = nullptr;
    if (!CreatePipe(&rawRead, &rawWrite, &security, 0)) throw std::runtime_error(WindowsError("CreatePipe stdout"));
    childOutRead.Reset(rawRead); childOutWrite.Reset(rawWrite);
    if (!SetHandleInformation(childOutRead.Get(), HANDLE_FLAG_INHERIT, 0)) throw std::runtime_error(WindowsError("SetHandleInformation stdout"));
    rawRead = nullptr; rawWrite = nullptr;
    if (!CreatePipe(&rawRead, &rawWrite, &security, 0)) throw std::runtime_error(WindowsError("CreatePipe stderr"));
    childErrRead.Reset(rawRead); childErrWrite.Reset(rawWrite);
    if (!SetHandleInformation(childErrRead.Get(), HANDLE_FLAG_INHERIT, 0)) throw std::runtime_error(WindowsError("SetHandleInformation stderr"));
    rawRead = nullptr; rawWrite = nullptr;
    if (!CreatePipe(&rawRead, &rawWrite, &security, 0)) throw std::runtime_error(WindowsError("CreatePipe stdin"));
    childInRead.Reset(rawRead); childInWrite.Reset(rawWrite);
    if (!SetHandleInformation(childInWrite.Get(), HANDLE_FLAG_INHERIT, 0)) throw std::runtime_error(WindowsError("SetHandleInformation stdin"));

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    startup.hStdInput = childInRead.Get();
    startup.hStdOutput = childOutWrite.Get();
    startup.hStdError = childErrWrite.Get();
    PROCESS_INFORMATION process{};
    auto command = BuildCommand(request);
    std::vector<wchar_t> mutableCommand(command.begin(), command.end());
    mutableCommand.push_back(L'\0');
    if (!CreateProcessW(nullptr, mutableCommand.data(), nullptr, nullptr, TRUE,
                        CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT, nullptr, nullptr, &startup, &process)) {
      throw std::runtime_error(WindowsError("CreateProcessW"));
    }
    Handle processHandle(process.hProcess);
    Handle threadHandle(process.hThread);
    Handle job(CreateJobObjectW(nullptr, nullptr));
    if (job) {
      JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
      limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
      SetInformationJobObject(job.Get(), JobObjectExtendedLimitInformation, &limits, sizeof(limits));
      AssignProcessToJobObject(job.Get(), processHandle.Get());
    }
    childInRead.Reset();
    childOutWrite.Reset();
    childErrWrite.Reset();

    ProcessResult result;
    std::jthread outputReader([&] { ReadPipe(childOutRead.Get(), result.standardOutput); });
    std::jthread errorReader([&] { ReadPipe(childErrRead.Get(), result.standardError); });
    if (!request.standardInput.empty()) {
      DWORD written = 0;
      const char* cursor = request.standardInput.data();
      std::size_t remaining = request.standardInput.size();
      while (remaining > 0) {
        const DWORD chunk = static_cast<DWORD>(std::min<std::size_t>(remaining, 64U * 1024U));
        if (!WriteFile(childInWrite.Get(), cursor, chunk, &written, nullptr)) break;
        cursor += written;
        remaining -= written;
      }
    }
    const auto deadline = std::chrono::steady_clock::now() + request.timeout;
    const auto inputCloseDeadline = std::chrono::steady_clock::now() + request.standardInputCloseDelay;
    bool inputOpen = !request.standardInput.empty() && request.standardInputCloseDelay > std::chrono::milliseconds{0};
    if (!inputOpen) childInWrite.Reset();
    DWORD wait = WAIT_TIMEOUT;
    while (true) {
      if (request.cancellationRequested && request.cancellationRequested()) {
        result.cancelled = true;
        break;
      }
      const auto now = std::chrono::steady_clock::now();
      if (inputOpen && now >= inputCloseDeadline) {
        childInWrite.Reset();
        inputOpen = false;
      }
      if (now >= deadline) {
        result.timedOut = true;
        break;
      }
      const auto nextDeadline = inputOpen ? std::min(deadline, inputCloseDeadline) : deadline;
      const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(nextDeadline - now);
      const auto slice = std::min(remaining, std::chrono::milliseconds{50});
      wait = WaitForSingleObject(processHandle.Get(), static_cast<DWORD>(std::max<std::int64_t>(1, slice.count())));
      if (wait == WAIT_OBJECT_0) break;
      if (wait == WAIT_FAILED) throw std::runtime_error(WindowsError("WaitForSingleObject"));
    }
    childInWrite.Reset();
    if (result.timedOut || result.cancelled) {
      if (job) {
        TerminateJobObject(job.Get(), result.cancelled ? 125 : 124);
      } else {
        TerminateProcess(processHandle.Get(), result.cancelled ? 125 : 124);
      }
      WaitForSingleObject(processHandle.Get(), 2000);
    }
    DWORD exitCode = 0;
    if (GetExitCodeProcess(processHandle.Get(), &exitCode)) result.exitCode = static_cast<int>(exitCode);
    childOutRead.Reset();
    childErrRead.Reset();
    outputReader.join();
    errorReader.join();
    return result;
  }

};

class WindowsHttpClient final : public IHttpClient {
 public:
  HttpResponse Send(const HttpRequest& request) override {
    if (!IsSafeEndpointUrl(request.url, request.allowLoopbackHttp)) throw std::runtime_error("unsafe endpoint URL");
    const auto wideUrl = Wide(request.url);
    URL_COMPONENTSW components{};
    components.dwStructSize = sizeof(components);
    components.dwSchemeLength = static_cast<DWORD>(-1);
    components.dwHostNameLength = static_cast<DWORD>(-1);
    components.dwUrlPathLength = static_cast<DWORD>(-1);
    components.dwExtraInfoLength = static_cast<DWORD>(-1);
    if (!WinHttpCrackUrl(wideUrl.c_str(), 0, 0, &components)) throw std::runtime_error(WindowsError("WinHttpCrackUrl"));
    const std::wstring host(components.lpszHostName, components.dwHostNameLength);
    std::wstring path(components.lpszUrlPath, components.dwUrlPathLength);
    if (components.dwExtraInfoLength > 0) path.append(components.lpszExtraInfo, components.dwExtraInfoLength);
    if (path.empty()) path = L"/";

    InternetHandle session(WinHttpOpen(L"AIUsageMonitor/0.1", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                                       WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0));
    if (!session) throw std::runtime_error(WindowsError("WinHttpOpen"));
    const int timeout = static_cast<int>(request.timeout.count());
    WinHttpSetTimeouts(session.Get(), timeout, timeout, timeout, timeout);
    InternetHandle connection(WinHttpConnect(session.Get(), host.c_str(), components.nPort, 0));
    if (!connection) throw std::runtime_error(WindowsError("WinHttpConnect"));
    const DWORD flags = components.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0;
    InternetHandle requestHandle(WinHttpOpenRequest(connection.Get(), Wide(request.method).c_str(), path.c_str(), nullptr,
                                                    WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags));
    if (!requestHandle) throw std::runtime_error(WindowsError("WinHttpOpenRequest"));
    DWORD disable = WINHTTP_DISABLE_REDIRECTS;
    WinHttpSetOption(requestHandle.Get(), WINHTTP_OPTION_DISABLE_FEATURE, &disable, sizeof(disable));
    std::wstring headers;
    for (const auto& [name, value] : request.headers) headers += Wide(name + ": " + value + "\r\n");
    void* body = request.body.empty() ? WINHTTP_NO_REQUEST_DATA : const_cast<char*>(request.body.data());
    if (!WinHttpSendRequest(requestHandle.Get(), headers.empty() ? WINHTTP_NO_ADDITIONAL_HEADERS : headers.c_str(),
                            headers.empty() ? 0 : static_cast<DWORD>(headers.size()), body,
                            static_cast<DWORD>(request.body.size()), static_cast<DWORD>(request.body.size()), 0)) {
      throw std::runtime_error(WindowsError("WinHttpSendRequest"));
    }
    if (!WinHttpReceiveResponse(requestHandle.Get(), nullptr)) throw std::runtime_error(WindowsError("WinHttpReceiveResponse"));

    HttpResponse response;
    DWORD statusSize = sizeof(response.status);
    if (!WinHttpQueryHeaders(requestHandle.Get(), WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX, &response.status, &statusSize, WINHTTP_NO_HEADER_INDEX)) {
      throw std::runtime_error(WindowsError("WinHttpQueryHeaders status"));
    }
    DWORD rawSize = 0;
    WinHttpQueryHeaders(requestHandle.Get(), WINHTTP_QUERY_RAW_HEADERS_CRLF, WINHTTP_HEADER_NAME_BY_INDEX, nullptr, &rawSize,
                        WINHTTP_NO_HEADER_INDEX);
    if (GetLastError() == ERROR_INSUFFICIENT_BUFFER && rawSize > sizeof(wchar_t)) {
      std::wstring raw(rawSize / sizeof(wchar_t), L'\0');
      if (WinHttpQueryHeaders(requestHandle.Get(), WINHTTP_QUERY_RAW_HEADERS_CRLF, WINHTTP_HEADER_NAME_BY_INDEX, raw.data(),
                              &rawSize, WINHTTP_NO_HEADER_INDEX)) {
        std::wistringstream lines(raw);
        std::wstring line;
        while (std::getline(lines, line)) {
          if (!line.empty() && line.back() == L'\r') line.pop_back();
          const auto colon = line.find(L':');
          if (colon != std::wstring::npos) {
            auto name = Utf8(line.substr(0, colon));
            auto value = Utf8(line.substr(colon + 1));
            while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front()))) value.erase(value.begin());
            response.headers.emplace(std::move(name), std::move(value));
          }
        }
      }
    }
    while (true) {
      DWORD available = 0;
      if (!WinHttpQueryDataAvailable(requestHandle.Get(), &available)) throw std::runtime_error(WindowsError("WinHttpQueryDataAvailable"));
      if (available == 0) break;
      if (response.body.size() + available > request.maxResponseBytes) throw std::runtime_error("HTTP response exceeds 1 MiB limit");
      const auto previous = response.body.size();
      response.body.resize(previous + available);
      DWORD read = 0;
      if (!WinHttpReadData(requestHandle.Get(), response.body.data() + previous, available, &read)) {
        throw std::runtime_error(WindowsError("WinHttpReadData"));
      }
      response.body.resize(previous + read);
    }
    return response;
  }
};

std::string Base64(const BYTE* data, DWORD size) {
  DWORD outputSize = 0;
  if (!CryptBinaryToStringA(data, size, CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, nullptr, &outputSize)) {
    throw std::runtime_error(WindowsError("CryptBinaryToString"));
  }
  std::string output(outputSize, '\0');
  if (!CryptBinaryToStringA(data, size, CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, output.data(), &outputSize)) {
    throw std::runtime_error(WindowsError("CryptBinaryToString"));
  }
  if (!output.empty() && output.back() == '\0') output.pop_back();
  return output;
}

std::vector<BYTE> FromBase64(const std::string& value) {
  DWORD outputSize = 0;
  if (!CryptStringToBinaryA(value.c_str(), static_cast<DWORD>(value.size()), CRYPT_STRING_BASE64, nullptr, &outputSize, nullptr, nullptr)) {
    throw std::runtime_error("invalid protected secret encoding");
  }
  std::vector<BYTE> output(outputSize);
  if (!CryptStringToBinaryA(value.c_str(), static_cast<DWORD>(value.size()), CRYPT_STRING_BASE64, output.data(), &outputSize,
                            nullptr, nullptr)) {
    throw std::runtime_error("invalid protected secret encoding");
  }
  output.resize(outputSize);
  return output;
}

class DpapiSecretStore final : public ISecretStore {
 public:
  std::string Protect(const std::string& plainText) override {
    DATA_BLOB input{static_cast<DWORD>(plainText.size()), reinterpret_cast<BYTE*>(const_cast<char*>(plainText.data()))};
    DATA_BLOB output{};
    if (!CryptProtectData(&input, L"AI Usage Monitor", nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)) {
      throw std::runtime_error(WindowsError("CryptProtectData"));
    }
    const auto encoded = Base64(output.pbData, output.cbData);
    LocalFree(output.pbData);
    return "dpapi:" + encoded;
  }
  std::string ProtectSession(const std::string& plainText) override {
    const auto id = std::to_string(GetCurrentProcessId()) + "-" + std::to_string(nextSessionId_++);
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
    if (!opaque.starts_with("dpapi:")) throw std::runtime_error("secret is not protected with DPAPI");
    auto encrypted = FromBase64(opaque.substr(6));
    DATA_BLOB input{static_cast<DWORD>(encrypted.size()), encrypted.data()};
    DATA_BLOB output{};
    if (!CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)) {
      throw std::runtime_error("stored credential cannot be decrypted by this Windows user");
    }
    std::string plain(reinterpret_cast<char*>(output.pbData), output.cbData);
    SecureZeroMemory(output.pbData, output.cbData);
    LocalFree(output.pbData);
    return plain;
  }
  bool PersistentAvailable() const override { return true; }

 private:
  std::atomic<unsigned long long> nextSessionId_{1};
  std::mutex sessionMutex_;
  std::map<std::string, std::string> session_;
};

class SystemClockService final : public IClock {
 public:
  TimePoint Now() const override { return Clock::now(); }
};

class WindowsSingleInstanceSignal final : public ISingleInstanceSignal {
 public:
  explicit WindowsSingleInstanceSignal(const std::filesystem::path& dataRoot) {
    std::filesystem::create_directories(dataRoot);
    const auto suffix = std::to_wstring(std::hash<std::wstring>{}(dataRoot.wstring()));
    const auto mutexName = L"Local\\AIUsageMonitor-" + suffix;
    mutex_.Reset(CreateMutexW(nullptr, FALSE, mutexName.c_str()));
    if (!mutex_) throw std::runtime_error(WindowsError("CreateMutexW"));
    anotherRunning_ = GetLastError() == ERROR_ALREADY_EXISTS;
    const auto eventName = L"Local\\AIUsageMonitor-activation-" + suffix;
    activationEvent_.Reset(CreateEventW(nullptr, FALSE, FALSE, eventName.c_str()));
    if (!activationEvent_) throw std::runtime_error(WindowsError("CreateEventW"));
  }

  bool IsAnotherRunning() const override { return anotherRunning_; }
  void SignalActivation() override {
    if (!SetEvent(activationEvent_.Get())) throw std::runtime_error(WindowsError("SetEvent"));
  }
  bool ConsumeActivation() override {
    return WaitForSingleObject(activationEvent_.Get(), 0) == WAIT_OBJECT_0;
  }
  bool WaitForActivation(std::chrono::milliseconds timeout) override {
    const DWORD milliseconds = timeout == std::chrono::milliseconds::max()
                                   ? INFINITE
                                   : static_cast<DWORD>(std::clamp<std::int64_t>(timeout.count(), 0, MAXDWORD - 1LL));
    return WaitForSingleObject(activationEvent_.Get(), milliseconds) == WAIT_OBJECT_0;
  }

 private:
  Handle mutex_;
  Handle activationEvent_;
  bool anotherRunning_{false};
};

bool IsLoopbackHost(std::string host) {
  std::transform(host.begin(), host.end(), host.begin(), [](unsigned char character) { return static_cast<char>(std::tolower(character)); });
  return host == "localhost" || host == "127.0.0.1" || host == "[::1]" || host == "::1";
}

}  // namespace

std::unique_ptr<IHttpClient> CreatePlatformHttpClient() { return std::make_unique<WindowsHttpClient>(); }
std::unique_ptr<IProcessRunner> CreatePlatformProcessRunner() { return std::make_unique<WindowsProcessRunner>(); }
std::unique_ptr<ISecretStore> CreatePlatformSecretStore() { return std::make_unique<DpapiSecretStore>(); }
std::unique_ptr<IClock> CreatePlatformClock() { return std::make_unique<SystemClockService>(); }
std::unique_ptr<ISingleInstanceSignal> CreatePlatformSingleInstanceSignal(const std::filesystem::path& dataRoot) {
  return std::make_unique<WindowsSingleInstanceSignal>(dataRoot);
}

std::optional<std::filesystem::path> DiscoverExecutable(const std::string& name) {
  const auto wideName = Wide(name);
  for (const wchar_t* extension : {L".exe", L".cmd", L".bat", L".ps1"}) {
    std::array<wchar_t, 32768> buffer{};
    const DWORD size = SearchPathW(nullptr, wideName.c_str(), extension, static_cast<DWORD>(buffer.size()), buffer.data(), nullptr);
    if (size > 0 && size < buffer.size()) return std::filesystem::path(std::wstring(buffer.data(), size));
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
  } catch (...) {
    return {};
  }
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
