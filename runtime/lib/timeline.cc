// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/bootstrap_natives.h"

#include "include/dart_api.h"

#include "vm/native_entry.h"
#include "vm/object.h"
#include "vm/os.h"
#include "vm/timeline.h"

namespace dart {

// Native implementations for the dart:developer library.

DEFINE_NATIVE_ENTRY(Timeline_isDartStreamEnabled, 0, 0) {
#if defined(SUPPORT_TIMELINE)
  if (Timeline::GetDartStream()->enabled()) {
    return Bool::True().ptr();
  }
#endif
  return Bool::False().ptr();
}

DEFINE_NATIVE_ENTRY(Timeline_getNextTaskId, 0, 0) {
#if !defined(SUPPORT_TIMELINE)
  return Integer::New(0);
#else
  return Integer::New(thread->GetNextTaskId());
#endif
}

DEFINE_NATIVE_ENTRY(Timeline_getTraceClock, 0, 0) {
  return Integer::New(OS::GetCurrentMonotonicMicros(), Heap::kNew);
}

DEFINE_NATIVE_ENTRY(Timeline_reportTaskEvent, 0, 5) {
#if defined(SUPPORT_TIMELINE)
  GET_NON_NULL_NATIVE_ARGUMENT(Integer, id, arguments->NativeArgAt(0));
  GET_NON_NULL_NATIVE_ARGUMENT(Integer, flow_id, arguments->NativeArgAt(1));
  GET_NON_NULL_NATIVE_ARGUMENT(Smi, type, arguments->NativeArgAt(2));
  GET_NON_NULL_NATIVE_ARGUMENT(String, name, arguments->NativeArgAt(3));
  GET_NON_NULL_NATIVE_ARGUMENT(String, args, arguments->NativeArgAt(4));

  TimelineEventRecorder* recorder = Timeline::recorder();
  if (recorder == nullptr) {
    return Object::null();
  }

  TimelineEvent* event = Timeline::GetDartStream()->StartEvent();
  if (event == nullptr) {
    // Stream was turned off.
    return Object::null();
  }

  std::unique_ptr<const int64_t[]> flow_ids;
  if (flow_id.Value() != TimelineEvent::kNoFlowId) {
    int64_t* flow_ids_internal = new int64_t[1];
    flow_ids_internal[0] = flow_id.Value();
    flow_ids = std::unique_ptr<const int64_t[]>(flow_ids_internal);
  }
  intptr_t flow_id_count = flow_id.Value() == TimelineEvent::kNoFlowId ? 0 : 1;
  DartTimelineEventHelpers::ReportTaskEvent(
      event, id.Value(), flow_id_count, flow_ids, type.Value(),
      name.ToMallocCString(), args.ToMallocCString());
#endif  // SUPPORT_TIMELINE
  return Object::null();
}

}  // namespace dart
