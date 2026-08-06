#pragma once

#include "ai_usage/domain.h"

#include <chrono>
#include <filesystem>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace ai_usage {

struct HttpRequest {
  std::string method{"GET"};
  std::string url;
  std::map<std::string, std::string> headers;
  std::string body;
  std::chrono::milliseconds timeout{10000};
  std::size_t maxResponseBytes{1024U * 1024U};
  bool allowLoopbackHttp{false};
};

struct HttpResponse {
  int status{0};
  std::map<std::string, std::string> headers;
  std::string body;
};

class IHttpClient {
 public:
  virtual ~IHttpClient() = default;
  virtual HttpResponse Send(const HttpRequest& request) = 0;
};

struct ProcessRequest {
  std::filesystem::path executable;
  std::vector<std::string> arguments;
  std::string standardInput;
  std::chrono::milliseconds timeout{10000};
  std::function<bool()> cancellationRequested;
  // Some stdio servers need stdin to remain open while they process JSONL requests.
  std::chrono::milliseconds standardInputCloseDelay{0};
};

struct ProcessResult {
  int exitCode{-1};
  std::string standardOutput;
  std::string standardError;
  bool timedOut{false};
  bool cancelled{false};
};

class IProcessRunner {
 public:
  virtual ~IProcessRunner() = default;
  virtual ProcessResult Run(const ProcessRequest& request) = 0;
};

class ISecretStore {
 public:
  virtual ~ISecretStore() = default;
  virtual std::string Protect(const std::string& plainText) = 0;
  virtual std::string ProtectSession(const std::string& plainText) = 0;
  virtual std::string Unprotect(const std::string& opaque) = 0;
  virtual bool PersistentAvailable() const = 0;
};

class IClock {
 public:
  virtual ~IClock() = default;
  virtual TimePoint Now() const = 0;
};

class ISingleInstanceSignal {
 public:
  virtual ~ISingleInstanceSignal() = default;
  virtual bool IsAnotherRunning() const = 0;
  virtual void SignalActivation() = 0;
  virtual bool ConsumeActivation() = 0;
  virtual bool WaitForActivation(std::chrono::milliseconds timeout) = 0;
};

std::unique_ptr<IHttpClient> CreatePlatformHttpClient();
std::unique_ptr<IProcessRunner> CreatePlatformProcessRunner();
std::unique_ptr<ISecretStore> CreatePlatformSecretStore();
std::unique_ptr<IClock> CreatePlatformClock();
std::unique_ptr<ISingleInstanceSignal> CreatePlatformSingleInstanceSignal(const std::filesystem::path& dataRoot);
std::optional<std::filesystem::path> DiscoverExecutable(const std::string& name);
std::string ProbeVersion(IProcessRunner& runner, const std::filesystem::path& executable);
bool IsSafeEndpointUrl(const std::string& url, bool allowLoopbackHttp);
std::string RedactSecrets(std::string text, const std::vector<std::string>& secrets);

}  // namespace ai_usage
