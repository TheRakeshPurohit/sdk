// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "include/bin/dart_io_api.h"
#include "include/dart_api.h"
#include "include/dart_tools_api.h"

#include "platform/assert.h"

#include "bin/builtin.h"
#include "bin/dartutils.h"
#include "bin/file.h"
#include "bin/io_natives.h"
#include "bin/platform.h"

namespace dart {
namespace bin {

// Lists the native functions implementing basic functionality in
// standalone dart, such as printing, file I/O, and platform information.
// Advanced I/O classes like sockets and process management are implemented
// using functions listed in io_natives.cc.
#define BUILTIN_NATIVE_LIST(V) V(Builtin_PrintString, 1)

BUILTIN_NATIVE_LIST(DECLARE_FUNCTION);

static struct NativeEntries {
  const char* name_;
  Dart_NativeFunction function_;
  int argument_count_;
} BuiltinEntries[] = {BUILTIN_NATIVE_LIST(REGISTER_FUNCTION)};

void Builtin_DummyNative(Dart_NativeArguments args) {
  UNREACHABLE();
}

/**
 * Looks up native functions in both libdart_builtin and libdart_io.
 */
Dart_NativeFunction Builtin::NativeLookup(Dart_Handle name,
                                          int argument_count,
                                          bool* auto_setup_scope) {
  const char* function_name = nullptr;
  Dart_Handle err = Dart_StringToCString(name, &function_name);
  if (Dart_IsError(err)) {
    Dart_PropagateError(err);
  }
  ASSERT(function_name != nullptr);
  ASSERT(auto_setup_scope != nullptr);
  *auto_setup_scope = true;
  int num_entries = sizeof(BuiltinEntries) / sizeof(struct NativeEntries);
  for (int i = 0; i < num_entries; i++) {
    struct NativeEntries* entry = &(BuiltinEntries[i]);
    if ((strcmp(function_name, entry->name_) == 0) &&
        (entry->argument_count_ == argument_count)) {
      return reinterpret_cast<Dart_NativeFunction>(entry->function_);
    }
  }
  Dart_NativeFunction result =
      IONativeLookup(name, argument_count, auto_setup_scope);
  if (result == nullptr) {
    result = Builtin_DummyNative;
  }
  return result;
}

const uint8_t* Builtin::NativeSymbol(Dart_NativeFunction nf) {
  int num_entries = sizeof(BuiltinEntries) / sizeof(struct NativeEntries);
  for (int i = 0; i < num_entries; i++) {
    struct NativeEntries* entry = &(BuiltinEntries[i]);
    if (reinterpret_cast<Dart_NativeFunction>(entry->function_) == nf) {
      return reinterpret_cast<const uint8_t*>(entry->name_);
    }
  }
  return IONativeSymbol(nf);
}

// Implementation of native functions which are used for some
// test/debug functionality in standalone dart mode.
void FUNCTION_NAME(Builtin_PrintString)(Dart_NativeArguments args) {
  intptr_t length = 0;
  Dart_Handle str = Dart_GetNativeArgument(args, 0);
  Dart_Handle result = Dart_StringUTF8Length(str, &length);
  if (Dart_IsError(result)) {
    Dart_PropagateError(result);
  }
  intptr_t new_length = length + 1;
  uint8_t* chars = Dart_ScopeAllocate(new_length);
  ASSERT(chars != nullptr);
  result = Dart_CopyUTF8EncodingOfString(str, chars, length);
  if (Dart_IsError(result)) {
    Dart_PropagateError(result);
  }
  chars[length] = '\n';

  // Uses fwrite to support printing NUL bytes.
  const uint8_t* cursor = chars;
  intptr_t remaining = new_length;
  while (remaining > 0) {
    intptr_t written = fwrite(cursor, 1, remaining, stdout);
    if (written == 0) break;  // EOF or error: ignore
    cursor += written;
    remaining -= written;
  }
  fflush(stdout);
  if (ShouldCaptureStdout()) {
    // For now we report print output on the Stdout stream.
    const char* res =
        Dart_ServiceSendDataEvent("Stdout", "WriteEvent", chars, new_length);
    ASSERT(res == nullptr);
  }
}

}  // namespace bin
}  // namespace dart
