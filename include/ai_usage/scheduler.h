#pragma once

#include "ai_usage/providers.h"

#include <atomic>
#include <condition_variable>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <thread>
#include <vector>

namespace ai_usage {

class RefreshScheduler {
 public:
  using SnapshotCallback = std::function<void(const ProviderSnapshot&)>;

  explicit RefreshScheduler(SnapshotCallback callback, std::unique_ptr<IClock> clock = {});
  ~RefreshScheduler();
  RefreshScheduler(const RefreshScheduler&) = delete;
  RefreshScheduler& operator=(const RefreshScheduler&) = delete;

  void SetProviders(std::vector<std::unique_ptr<IUsageProvider>> providers);
  void SetInterval(std::chrono::minutes interval);
  void Start();
  void Stop();
  void RefreshAll();
  void RefreshOne(const std::string& providerId);
  void NotifyClockChanged();

 private:
  struct State {
    std::unique_ptr<IUsageProvider> provider;
    TimePoint nextDue{};
    unsigned failures{0};
    bool queued{false};
    bool running{false};
  };

  void Run();
  void RunWorker();
  void Refresh(State& state, TimePoint now);
  std::chrono::seconds Backoff(unsigned failures, const std::string& providerId) const;

  SnapshotCallback callback_;
  std::unique_ptr<IClock> clock_;
  std::map<std::string, State> providers_;
  std::chrono::minutes interval_{5};
  std::atomic<bool> stopping_{false};
  bool started_{false};
  std::mutex mutex_;
  std::condition_variable condition_;
  std::jthread schedulerThread_;
  std::vector<std::jthread> workers_;
  std::deque<std::string> jobs_;
  std::size_t active_{0};
};

}  // namespace ai_usage
