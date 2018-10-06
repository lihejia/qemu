// Copyright 2018 The Android Open Source Project
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
#include "Vsync.h"

#include "android/base/synchronization/ConditionVariable.h"
#include "android/base/synchronization/Lock.h"
#include "android/base/system/System.h"
#include "android/base/threads/FunctorThread.h"

#include <atomic>
#include <memory>

using android::base::AutoLock;
using android::base::ConditionVariable;
using android::base::FunctorThread;
using android::base::Lock;
using android::base::System;

namespace aemu {

class Vsync::Impl {
public:
    Impl(Callback&& callback, int refreshRate = 60)
        : mCallback(std::move(callback)),
          mRefreshRate(refreshRate),
          mRefreshIntervalUs(1000000ULL / mRefreshRate),
          mThread([this] {
              while (true) {
                  if (mShouldStop.load(std::memory_order_relaxed))
                      return 0;
                  System::get()->sleepUs(mRefreshIntervalUs);
                  AutoLock lock(mLock);
                  mSync = 1;
                  mCv.signal();
                  mCallback();
              }
              return 0;
          }) {
        mThread.start();
    }

    void join() {
        mShouldStop.store(true, std::memory_order_relaxed);
        mThread.wait();
    }

    ~Impl() { join(); }

    void waitUntilNextVsync() {
        AutoLock lock(mLock);
        mSync = 0;
        while (!mSync) {
            mCv.wait(&mLock);
        }
    }

private:
    std::atomic<bool> mShouldStop { false };
    int mSync = 0;
    Lock mLock;
    ConditionVariable mCv;

    Callback mCallback;
    int mRefreshRate = 60;
    uint64_t mRefreshIntervalUs;
    FunctorThread mThread;
};

Vsync::Vsync(Vsync::Callback&& callback)
    : mImpl(new Vsync::Impl(std::move(callback))) {}

Vsync::~Vsync() = default;

void Vsync::join() {
    mImpl->join();
}

void Vsync::waitUntilNextVsync() {
    mImpl->waitUntilNextVsync();
}

} // namespace aemu