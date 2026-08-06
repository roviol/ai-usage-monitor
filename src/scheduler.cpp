#include "ai_usage/scheduler.h"

#include <algorithm>
#include <exception>
#include <stdexcept>

namespace ai_usage {

RefreshScheduler::RefreshScheduler(SnapshotCallback callback, std::unique_ptr<IClock> clock)
    : callback_(std::move(callback)), clock_(std::move(clock)) {
  if (!clock_) clock_ = CreatePlatformClock();
}

RefreshScheduler::~RefreshScheduler() { Stop(); }

void RefreshScheduler::SetProviders(std::vector<std::unique_ptr<IUsageProvider>> providers) {
  std::lock_guard lock(mutex_);
  if (started_) throw std::logic_error("cannot replace providers while scheduler is running");
  providers_.clear();
  for (auto& provider : providers) {
    const auto id = provider->Config().id;
    providers_.emplace(id, State{std::move(provider), TimePoint{}, 0U, true, false});
  }
}

void RefreshScheduler::SetInterval(std::chrono::minutes interval) {
  if (interval < std::chrono::minutes{1} || interval > std::chrono::minutes{60}) {
    throw std::invalid_argument("refresh interval must be 1..60 minutes");
  }
  std::lock_guard lock(mutex_);
  interval_ = interval;
  condition_.notify_all();
}

void RefreshScheduler::Start() {
  std::lock_guard lock(mutex_);
  if (started_) return;
  stopping_ = false;
  started_ = true;
  workers_.clear();
  workers_.emplace_back([this] { RunWorker(); });
  workers_.emplace_back([this] { RunWorker(); });
  schedulerThread_ = std::jthread([this] { Run(); });
}

void RefreshScheduler::Stop() {
  {
    std::lock_guard lock(mutex_);
    if (!started_) return;
    stopping_ = true;
    for (auto& [id, state] : providers_) {
      (void)id;
      if (state.running) state.provider->Cancel();
    }
    condition_.notify_all();
  }
  if (schedulerThread_.joinable()) schedulerThread_.join();
  for (auto& worker : workers_) {
    if (worker.joinable()) worker.join();
  }
  std::lock_guard lock(mutex_);
  workers_.clear();
  jobs_.clear();
  active_ = 0;
  for (auto& [id, state] : providers_) {
    (void)id;
    state.running = false;
  }
  started_ = false;
}

void RefreshScheduler::RefreshAll() {
  std::lock_guard lock(mutex_);
  for (auto& [id, state] : providers_) {
    (void)id;
    state.queued = true;
  }
  condition_.notify_all();
}

void RefreshScheduler::RefreshOne(const std::string& providerId) {
  std::lock_guard lock(mutex_);
  const auto found = providers_.find(providerId);
  if (found != providers_.end()) found->second.queued = true;
  condition_.notify_all();
}

void RefreshScheduler::NotifyClockChanged() {
  std::lock_guard lock(mutex_);
  condition_.notify_all();
}

std::chrono::seconds RefreshScheduler::Backoff(unsigned failures, const std::string& providerId) const {
  const unsigned exponent = failures == 0U ? 0U : std::min(failures - 1U, 7U);
  const auto base = std::chrono::seconds{30LL * (1LL << exponent)};
  const auto capped = std::min(base, std::chrono::duration_cast<std::chrono::seconds>(std::chrono::minutes{60}));
  const auto jitterRange = std::max<std::int64_t>(1, capped.count() / 5);
  const auto jitter = static_cast<std::int64_t>(std::hash<std::string>{}(providerId) % static_cast<std::size_t>(jitterRange));
  return std::min(capped + std::chrono::seconds{jitter},
                  std::chrono::duration_cast<std::chrono::seconds>(std::chrono::minutes{60}));
}

void RefreshScheduler::Refresh(State& state, TimePoint now) {
  ProviderSnapshot snapshot;
  try {
    snapshot = state.provider->Refresh();
    const auto validation = ValidateSnapshot(snapshot);
    if (!validation.valid) throw std::runtime_error(validation.errors.front());
  } catch (const ProviderException& exception) {
    snapshot.providerId = state.provider->Config().id;
    snapshot.displayName = state.provider->Config().name;
    snapshot.kind = state.provider->Config().kind;
    snapshot.observedAt = now;
    snapshot.freshness = Freshness::NoData;
    snapshot.health = Health::Error;
    snapshot.error = exception.Error();
  } catch (const std::exception& error) {
    snapshot.providerId = state.provider->Config().id;
    snapshot.displayName = state.provider->Config().name;
    snapshot.kind = state.provider->Config().kind;
    snapshot.observedAt = now;
    snapshot.freshness = Freshness::NoData;
    snapshot.health = Health::Error;
    snapshot.error = ProviderError{"refresh-failed", error.what(), true, std::nullopt};
  }

  {
    std::lock_guard lock(mutex_);
    if (snapshot.health == Health::Error) {
      ++state.failures;
      auto delay = Backoff(state.failures, state.provider->Config().id);
      if (snapshot.error.has_value() && snapshot.error->retryAfter.has_value()) delay = std::max(delay, *snapshot.error->retryAfter);
      state.nextDue = now + delay;
    } else {
      state.failures = 0;
      state.nextDue = now + interval_;
    }
  }
  callback_(snapshot);
}

void RefreshScheduler::Run() {
  while (!stopping_) {
    TimePoint nextWake = TimePoint::max();
    {
      std::unique_lock lock(mutex_);
      const auto now = clock_->Now();
      while (active_ < 2U) {
        auto selected = providers_.end();
        for (auto candidate = providers_.begin(); candidate != providers_.end(); ++candidate) {
          if (!candidate->second.running && (candidate->second.queued || candidate->second.nextDue <= now)) {
            selected = candidate;
            break;
          }
        }
        if (selected == providers_.end()) break;
        selected->second.queued = false;
        selected->second.running = true;
        jobs_.push_back(selected->first);
        ++active_;
        condition_.notify_all();
      }
      for (const auto& [id, state] : providers_) {
        (void)id;
        if (!state.running) {
          if (state.queued && active_ < 2U) nextWake = now;
          else nextWake = std::min(nextWake, state.nextDue);
        }
      }
      if (nextWake == TimePoint::max()) {
        condition_.wait(lock);
      } else {
        condition_.wait_until(lock, nextWake);
      }
    }
  }
}

void RefreshScheduler::RunWorker() {
  while (true) {
    std::string selected;
    {
      std::unique_lock lock(mutex_);
      condition_.wait(lock, [this] { return stopping_ || !jobs_.empty(); });
      if (stopping_) return;
      selected = std::move(jobs_.front());
      jobs_.pop_front();
    }
    State* state = nullptr;
    {
      std::lock_guard lock(mutex_);
      const auto found = providers_.find(selected);
      if (found != providers_.end()) state = &found->second;
    }
    if (state != nullptr && !stopping_) Refresh(*state, clock_->Now());
    {
      std::lock_guard lock(mutex_);
      const auto found = providers_.find(selected);
      if (found != providers_.end()) found->second.running = false;
      if (active_ > 0U) --active_;
      condition_.notify_all();
    }
  }
}

}  // namespace ai_usage
