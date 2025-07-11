// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/globals.h"
#if defined(DART_HOST_OS_MACOS)

#include "vm/os.h"

#include <dlfcn.h>           // NOLINT
#include <errno.h>           // NOLINT
#include <limits.h>          // NOLINT
#include <mach-o/loader.h>   // NOLINT
#include <mach/clock.h>      // NOLINT
#include <mach/mach.h>       // NOLINT
#include <mach/mach_time.h>  // NOLINT
#include <sys/resource.h>    // NOLINT
#include <sys/time.h>        // NOLINT
#include <unistd.h>          // NOLINT
#if DART_HOST_OS_IOS
#include <syslog.h>  // NOLINT
#endif

#include "platform/utils.h"
#include "vm/image_snapshot.h"
#include "vm/isolate.h"
#include "vm/timeline.h"
#include "vm/zone.h"

namespace dart {

intptr_t OS::ProcessId() {
  return static_cast<intptr_t>(getpid());
}

static bool LocalTime(int64_t seconds_since_epoch, tm* tm_result) {
  time_t seconds = static_cast<time_t>(seconds_since_epoch);
  if (seconds != seconds_since_epoch) return false;
  struct tm* error_code = localtime_r(&seconds, tm_result);
  return error_code != nullptr;
}

const char* OS::GetTimeZoneName(int64_t seconds_since_epoch) {
  tm decomposed;
  bool succeeded = LocalTime(seconds_since_epoch, &decomposed);
  // If unsuccessful, return an empty string like V8 does.
  return (succeeded && (decomposed.tm_zone != nullptr)) ? decomposed.tm_zone
                                                        : "";
}

int OS::GetTimeZoneOffsetInSeconds(int64_t seconds_since_epoch) {
  tm decomposed;
  bool succeeded = LocalTime(seconds_since_epoch, &decomposed);
  // Even if the offset was 24 hours it would still easily fit into 32 bits.
  // If unsuccessful, return zero like V8 does.
  return succeeded ? static_cast<int>(decomposed.tm_gmtoff) : 0;
}

int64_t OS::GetCurrentTimeMillis() {
  return GetCurrentTimeMicros() / 1000;
}

int64_t OS::GetCurrentTimeMicros() {
  // gettimeofday has microsecond resolution.
  struct timeval tv;
  if (gettimeofday(&tv, nullptr) < 0) {
    UNREACHABLE();
    return 0;
  }
  return (static_cast<int64_t>(tv.tv_sec) * 1000000) + tv.tv_usec;
}

int64_t OS::GetCurrentMonotonicTicks() {
  return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
}

int64_t OS::GetCurrentMonotonicFrequency() {
  return kNanosecondsPerSecond;
}

int64_t OS::GetCurrentMonotonicMicros() {
  ASSERT(GetCurrentMonotonicFrequency() == kNanosecondsPerSecond);
  return GetCurrentMonotonicTicks() / kNanosecondsPerMicrosecond;
}

int64_t OS::GetCurrentThreadCPUMicros() {
  return clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) /
         kNanosecondsPerMicrosecond;
}

int64_t OS::GetCurrentMonotonicMicrosForTimeline() {
#if defined(SUPPORT_TIMELINE)
  if (Timeline::recorder_discards_clock_values()) return -1;
  return GetCurrentMonotonicMicros();
#else
  return -1;
#endif
}

intptr_t OS::ActivationFrameAlignment() {
#if DART_HOST_OS_IOS
#if TARGET_ARCH_ARM
  // Even if we generate code that maintains a stronger alignment, we cannot
  // assert the stronger stack alignment because C++ code will not maintain it.
  return 8;
#elif TARGET_ARCH_ARM64
  return 16;
#elif TARGET_ARCH_IA32
  return 16;  // iOS simulator
#elif TARGET_ARCH_X64
  return 16;  // iOS simulator
#else
#error Unimplemented
#endif
#else   // DART_HOST_OS_IOS
  // OS X activation frames must be 16 byte-aligned; see "Mac OS X ABI
  // Function Call Guide".
  return 16;
#endif  // DART_HOST_OS_IOS
}

int OS::NumberOfAvailableProcessors() {
  return sysconf(_SC_NPROCESSORS_ONLN);
}

uintptr_t OS::CurrentRSS() {
  struct mach_task_basic_info info;
  mach_msg_type_number_t infoCount = MACH_TASK_BASIC_INFO_COUNT;
  kern_return_t result =
      task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                reinterpret_cast<task_info_t>(&info), &infoCount);
  if (result != KERN_SUCCESS) {
    return 0;
  }
  return info.resident_size;
}

void OS::Sleep(int64_t millis) {
  int64_t micros = millis * kMicrosecondsPerMillisecond;
  SleepMicros(micros);
}

void OS::SleepMicros(int64_t micros) {
  struct timespec req;  // requested.
  struct timespec rem;  // remainder.
  int64_t seconds = micros / kMicrosecondsPerSecond;
  if (seconds > kMaxInt32) {
    // Avoid truncation of overly large sleep values.
    seconds = kMaxInt32;
  }
  micros = micros - seconds * kMicrosecondsPerSecond;
  int64_t nanos = micros * kNanosecondsPerMicrosecond;
  req.tv_sec = static_cast<int32_t>(seconds);
  req.tv_nsec = static_cast<long>(nanos);  // NOLINT (long used in timespec).
  while (true) {
    int r = nanosleep(&req, &rem);
    if (r == 0) {
      break;
    }
    // We should only ever see an interrupt error.
    ASSERT(errno == EINTR);
    // Copy remainder into requested and repeat.
    req = rem;
  }
}

void OS::DebugBreak() {
  __builtin_trap();
}

DART_NOINLINE uintptr_t OS::GetProgramCounter() {
  return reinterpret_cast<uintptr_t>(
      __builtin_extract_return_addr(__builtin_return_address(0)));
}

void OS::Print(const char* format, ...) {
#if DART_HOST_OS_IOS
  va_list args;
  va_start(args, format);
  vsyslog(LOG_INFO, format, args);
  va_end(args);
#else
  va_list args;
  va_start(args, format);
  VFPrint(stdout, format, args);
  va_end(args);
#endif
}

void OS::VFPrint(FILE* stream, const char* format, va_list args) {
  vfprintf(stream, format, args);
  fflush(stream);
}

char* OS::SCreate(Zone* zone, const char* format, ...) {
  va_list args;
  va_start(args, format);
  char* buffer = VSCreate(zone, format, args);
  va_end(args);
  return buffer;
}

char* OS::VSCreate(Zone* zone, const char* format, va_list args) {
  // Measure.
  va_list measure_args;
  va_copy(measure_args, args);
  intptr_t len = Utils::VSNPrint(nullptr, 0, format, measure_args);
  va_end(measure_args);

  char* buffer;
  if (zone) {
    buffer = zone->Alloc<char>(len + 1);
  } else {
    buffer = reinterpret_cast<char*>(malloc(len + 1));
  }
  ASSERT(buffer != nullptr);

  // Print.
  va_list print_args;
  va_copy(print_args, args);
  Utils::VSNPrint(buffer, len + 1, format, print_args);
  va_end(print_args);
  return buffer;
}

bool OS::ParseInitialInt64(const char* str, int64_t* value, char** end) {
  ASSERT(str != nullptr && strlen(str) > 0 && value != nullptr &&
         end != nullptr);
  int32_t base = 10;
  int i = 0;
  if (str[0] == '-') {
    i = 1;
  } else if (str[0] == '+') {
    i = 1;
  }
  if ((str[i] == '0') && (str[i + 1] == 'x' || str[i + 1] == 'X') &&
      (str[i + 2] != '\0')) {
    base = 16;
  }
  errno = 0;
  if (base == 16) {
    // Unsigned 64-bit hexadecimal integer literals are allowed but
    // immediately interpreted as signed 64-bit integers.
    *value = static_cast<int64_t>(strtoull(str, end, base));
  } else {
    *value = strtoll(str, end, base);
  }
  return (errno == 0) && (*end != str);
}

void OS::RegisterCodeObservers() {}

void OS::PrintErr(const char* format, ...) {
#if DART_HOST_OS_IOS
  va_list args;
  va_start(args, format);
  vsyslog(LOG_ERR, format, args);
  va_end(args);
#else
  va_list args;
  va_start(args, format);
  VFPrint(stderr, format, args);
  va_end(args);
#endif
}

void OS::Init() {
  // See https://github.com/dart-lang/sdk/issues/29539
  // This is a workaround for a macos bug, we eagerly call localtime_r so that
  // libnotify is initialized early before any fork happens.
  struct timeval tv;
  if (gettimeofday(&tv, nullptr) < 0) {
    FATAL("gettimeofday returned an error (%s)\n", strerror(errno));
    return;
  }
  tm decomposed;
  struct tm* error_code = localtime_r(&(tv.tv_sec), &decomposed);
  if (error_code == nullptr) {
    FATAL("localtime_r returned an error (%s)\n", strerror(errno));
    return;
  }
}

void OS::Cleanup() {}

void OS::PrepareToAbort() {}

void OS::Abort() {
  PrepareToAbort();
  abort();
}

void OS::Exit(int code) {
  exit(code);
}

OS::BuildId OS::GetAppBuildId(const uint8_t* snapshot_instructions) {
  // First return the build ID information from the instructions image if
  // available.
  const Image instructions_image(snapshot_instructions);
  if (auto* const image_build_id = instructions_image.build_id()) {
    return {instructions_image.build_id_length(), image_build_id};
  }
  const uint8_t* dso_base = GetAppDSOBase(snapshot_instructions);
  const auto& macho_header =
      *reinterpret_cast<const struct mach_header*>(dso_base);
  // If the Mach-O file is not host endian, then we'd need to adjust the code
  // below (and also the snapshot loading code) to load multibyte integers
  // as reverse endian.
  if (macho_header.magic != MH_MAGIC && macho_header.magic != MH_MAGIC_64) {
    return {0, nullptr};
  }
  const size_t macho_header_size = macho_header.magic == MH_MAGIC
                                       ? sizeof(struct mach_header)
                                       : sizeof(struct mach_header_64);
  const uint8_t* it = dso_base + macho_header_size;
  const uint8_t* end = it + macho_header.sizeofcmds;
  while (it < end) {
    const auto& current_cmd = *reinterpret_cast<const struct load_command*>(it);
    if ((current_cmd.cmd & ~LC_REQ_DYLD) == LC_UUID) {
      const auto& uuid_cmd = *reinterpret_cast<const struct uuid_command*>(it);
      return {
          static_cast<intptr_t>(uuid_cmd.cmdsize - sizeof(struct load_command)),
          uuid_cmd.uuid};
    }
    it += current_cmd.cmdsize;
  }
  return {0, nullptr};
}

}  // namespace dart

#endif  // defined(DART_HOST_OS_MACOS)
