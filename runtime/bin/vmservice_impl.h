// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef RUNTIME_BIN_VMSERVICE_IMPL_H_
#define RUNTIME_BIN_VMSERVICE_IMPL_H_

#include "include/dart_api.h"

#include "platform/globals.h"

namespace dart {
namespace bin {

class VmService {
 public:
#if defined(PRODUCT)
  static bool Setup(const char* server_ip,
                    intptr_t server_port,
                    bool dev_mode_server,
                    bool auth_codes_disabled,
                    const char* write_service_info_filename,
                    bool trace_loading,
                    bool deterministic,
                    bool enable_service_port_fallback,
                    bool wait_for_dds_to_advertise_service,
                    bool serve_devtools,
                    bool serve_observatory,
                    bool print_dtd,
                    bool should_use_resident_compiler,
                    const char* resident_compiler_info_file_path) {
    return false;
  }

  static void SetNativeResolver() {}

  // Error message if startup failed.
  static const char* GetErrorMessage() {
    return "VM Service not suppported in Product mode";
  }

  // HTTP Server's address.
  static const char* GetServerAddress() { return nullptr; }

 private:
#else   // defined(PRODUCT)
  static bool Setup(
      const char* server_ip,
      intptr_t server_port,
      bool dev_mode_server,
      bool auth_codes_disabled,
      const char* write_service_info_filename,
      bool trace_loading,
      bool deterministic,
      bool enable_service_port_fallback,
      bool wait_for_dds_to_advertise_service,
      bool serve_devtools,
      bool serve_observatory,
      bool print_dtd,
      bool should_use_resident_compiler,
      // If either --resident-compiler-info-file or --resident-server-info-file
      // was supplied on the command line, the CLI argument should be forwarded
      // as the argument to this parameter. If neither option was supplied, the
      // argument to this parameter should be null.
      const char* resident_compiler_info_file_path);

  static void SetNativeResolver();

  // Error message if startup failed.
  static const char* GetErrorMessage();

  // HTTP Server's address.
  static const char* GetServerAddress() { return &server_uri_[0]; }

 private:
  static constexpr intptr_t kServerUriStringBufferSize = 1024;
  friend void NotifyServerState(Dart_NativeArguments args);

  static void SetServerAddress(const char* server_uri_);

  static const char* error_msg_;
  static char server_uri_[kServerUriStringBufferSize];
#endif  // defined(PRODUCT)
  DISALLOW_ALLOCATION();
  DISALLOW_IMPLICIT_CONSTRUCTORS(VmService);
};

}  // namespace bin
}  // namespace dart

#endif  // RUNTIME_BIN_VMSERVICE_IMPL_H_
