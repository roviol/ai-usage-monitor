#pragma once

#include "ai_usage/config.h"
#include "ai_usage/platform.h"

#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace ai_usage {

class ProviderException final : public std::runtime_error {
 public:
  explicit ProviderException(ProviderError error)
      : std::runtime_error(error.message), error_(std::move(error)) {}
  const ProviderError& Error() const noexcept { return error_; }

 private:
  ProviderError error_;
};

struct ProviderCapabilities {
  bool usage{false};
  bool remaining{false};
  bool balance{false};
  bool tokenActivity{false};
  std::string detail;
};

struct ConnectionTestResult {
  bool success{false};
  ProviderCapabilities capabilities;
  std::string message;
};

class IUsageProvider {
 public:
  virtual ~IUsageProvider() = default;
  virtual const ProviderConfig& Config() const = 0;
  virtual ProviderCapabilities Capabilities() const = 0;
  virtual ConnectionTestResult TestConnection() = 0;
  virtual ProviderSnapshot Refresh() = 0;
  virtual void Cancel() {}
};

std::unique_ptr<IUsageProvider> CreateProvider(
    ProviderConfig config, IHttpClient& http, IProcessRunner& process, ISecretStore& secrets);

ProviderSnapshot ParseCodexResponses(const ProviderConfig& config, const std::string& jsonLines, TimePoint observedAt);
ProviderSnapshot ParseDeepSeekBalance(const ProviderConfig& config, const std::string& json, TimePoint observedAt);
std::vector<Metric> ParseGenericMetrics(const ProviderConfig& config, const std::string& json);
std::optional<ProviderSnapshot> ParseClaudeUsageText(
    const ProviderConfig& config, const std::string& output, TimePoint observedAt);
ProviderSnapshot ParseOllamaStatus(
    const ProviderConfig& config, const std::string& json, TimePoint observedAt);
std::string ParseOllamaAccountLabel(const std::string& json);
std::vector<Metric> ParseOllamaCloudUsage(const std::string& json);

}  // namespace ai_usage
