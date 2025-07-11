// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "bin/main_options.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bin/dartdev_isolate.h"
#include "bin/error_exit.h"
#include "bin/file_system_watcher.h"
#if defined(DART_IO_SECURE_SOCKET_DISABLED)
#include "bin/io_service_no_ssl.h"
#else  // defined(DART_IO_SECURE_SOCKET_DISABLED)
#include "bin/io_service.h"
#endif  // defined(DART_IO_SECURE_SOCKET_DISABLED)
#include "bin/options.h"
#include "bin/platform.h"
#include "bin/utils.h"
#include "platform/syslog.h"
#if !defined(DART_IO_SECURE_SOCKET_DISABLED)
#include "bin/security_context.h"
#endif  // !defined(DART_IO_SECURE_SOCKET_DISABLED)
#include "bin/socket.h"
#include "include/dart_api.h"
#include "platform/assert.h"
#include "platform/globals.h"
#include "platform/hashmap.h"

namespace dart {
namespace bin {

// These strings must match the enum SnapshotKind in main_options.h.
static const char* const kSnapshotKindNames[] = {
    "none",
    "kernel",
    "app-jit",
    nullptr,
};

// These strings must match the enum VerbosityLevel in main_options.h.
static const char* const kVerbosityLevelNames[] = {
    "error", "warning", "info", "all", nullptr,
};

SnapshotKind Options::gen_snapshot_kind_ = kNone;
VerbosityLevel Options::verbosity_ = kAll;
bool Options::enable_vm_service_ = false;

#define OPTION_FIELD(variable) Options::variable##_

#define STRING_OPTION_DEFINITION(name, variable)                               \
  const char* OPTION_FIELD(variable) = nullptr;                                \
  DEFINE_STRING_OPTION(name, OPTION_FIELD(variable))
STRING_OPTIONS_LIST(STRING_OPTION_DEFINITION)
#undef STRING_OPTION_DEFINITION

#define BOOL_OPTION_DEFINITION(name, variable)                                 \
  bool OPTION_FIELD(variable) = false;                                         \
  DEFINE_BOOL_OPTION(name, OPTION_FIELD(variable))
BOOL_OPTIONS_LIST(BOOL_OPTION_DEFINITION)
#if defined(DEBUG)
DEBUG_BOOL_OPTIONS_LIST(BOOL_OPTION_DEFINITION)
#endif
#undef BOOL_OPTION_DEFINITION

#define SHORT_BOOL_OPTION_DEFINITION(short_name, long_name, variable)          \
  bool OPTION_FIELD(variable) = false;                                         \
  DEFINE_BOOL_OPTION_SHORT(short_name, long_name, OPTION_FIELD(variable))
SHORT_BOOL_OPTIONS_LIST(SHORT_BOOL_OPTION_DEFINITION)
#undef SHORT_BOOL_OPTION_DEFINITION

#define ENUM_OPTION_DEFINITION(name, type, variable)                           \
  DEFINE_ENUM_OPTION(name, type, OPTION_FIELD(variable))
ENUM_OPTIONS_LIST(ENUM_OPTION_DEFINITION)
#undef ENUM_OPTION_DEFINITION

#define CB_OPTION_DEFINITION(callback)                                         \
  static bool callback##Helper(const char* arg, CommandLineOptions* o) {       \
    return Options::callback(arg, o);                                          \
  }                                                                            \
  DEFINE_CB_OPTION(callback##Helper)
CB_OPTIONS_LIST(CB_OPTION_DEFINITION)
#undef CB_OPTION_DEFINITION

#if !defined(DART_PRECOMPILED_RUNTIME)
DFE* Options::dfe_ = nullptr;

DEFINE_STRING_OPTION_CB(dfe, { Options::dfe()->set_frontend_filename(value); });
#endif  // !defined(DART_PRECOMPILED_RUNTIME)

static void hot_reload_test_mode_callback(CommandLineOptions* vm_options) {
  // Identity reload.
  vm_options->AddArgument("--identity_reload");
  // Start reloading quickly.
  vm_options->AddArgument("--reload_every=4");
  // Reload from optimized and unoptimized code.
  vm_options->AddArgument("--reload_every_optimized=false");
  // Reload less frequently as time goes on.
  vm_options->AddArgument("--reload_every_back_off");
  // Ensure that every isolate has reloaded once before exiting.
  vm_options->AddArgument("--check_reloaded");
#if !defined(DART_PRECOMPILED_RUNTIME)
  Options::dfe()->set_use_incremental_compiler(true);
#endif  // !defined(DART_PRECOMPILED_RUNTIME)
}

DEFINE_BOOL_OPTION_CB(hot_reload_test_mode, hot_reload_test_mode_callback);

static void hot_reload_rollback_test_mode_callback(
    CommandLineOptions* vm_options) {
  // Identity reload.
  vm_options->AddArgument("--identity_reload");
  // Start reloading quickly.
  vm_options->AddArgument("--reload_every=4");
  // Reload from optimized and unoptimized code.
  vm_options->AddArgument("--reload_every_optimized=false");
  // Reload less frequently as time goes on.
  vm_options->AddArgument("--reload_every_back_off");
  // Ensure that every isolate has reloaded once before exiting.
  vm_options->AddArgument("--check_reloaded");
  // Force all reloads to fail and execute the rollback code.
  vm_options->AddArgument("--reload_force_rollback");
#if !defined(DART_PRECOMPILED_RUNTIME)
  Options::dfe()->set_use_incremental_compiler(true);
#endif  // !defined(DART_PRECOMPILED_RUNTIME)
}

DEFINE_BOOL_OPTION_CB(hot_reload_rollback_test_mode,
                      hot_reload_rollback_test_mode_callback);

void Options::PrintVersion() {
  Syslog::Print("Dart SDK version: %s\n", Dart_VersionString());
}

// clang-format off
void Options::PrintUsage() {
  Syslog::Print(
      "Usage: dart [<vm-flags>] <dart-script-file> [<script-arguments>]\n"
      "\n"
      "Executes the Dart script <dart-script-file> with "
      "the given list of <script-arguments>.\n"
      "\n");
  if (!Options::verbose_option()) {
    Syslog::Print(
"Common VM flags:\n"
#if !defined(PRODUCT)
"--enable-asserts\n"
"  Enable assert statements.\n"
#endif  // !defined(PRODUCT)
"--help or -h\n"
"  Display this message (add -v or --verbose for information about\n"
"  all VM options).\n"
"--packages=<path>\n"
"  Where to find a package spec file.\n"
"--define=<key>=<value> or -D<key>=<value>\n"
"  Define an environment declaration. To specify multiple declarations,\n"
"  use multiple instances of this option.\n"
#if !defined(PRODUCT)
"--observe[=<port>[/<bind-address>]]\n"
"  The observe flag is a convenience flag used to run a program with a\n"
"  set of options which are often useful for debugging under Dart DevTools.\n"
"  These options are currently:\n"
"      --enable-vm-service[=<port>[/<bind-address>]]\n"
"      --serve-devtools\n"
"      --pause-isolates-on-exit\n"
"      --pause-isolates-on-unhandled-exceptions\n"
"      --warn-on-pause-with-no-debugger\n"
"      --timeline-streams=\"Compiler, Dart, GC, Microtask\"\n"
"  This set is subject to change.\n"
"  Please see these options (--help --verbose) for further documentation.\n"
"--write-service-info=<file_uri>\n"
"  Outputs information necessary to connect to the VM service to the\n"
"  specified file in JSON format. Useful for clients which are unable to\n"
"  listen to stdout for the Dart VM service listening message.\n"
#endif  // !defined(PRODUCT)
"--snapshot-kind=<snapshot_kind>\n"
"--snapshot=<file_name>\n"
"  These snapshot options are used to generate a snapshot of the loaded\n"
"  Dart script:\n"
"    <snapshot-kind> controls the kind of snapshot, it could be\n"
"                    kernel(default) or app-jit\n"
"    <file_name> specifies the file into which the snapshot is written\n"
"--version\n"
"  Print the SDK version.\n");
  } else {
    Syslog::Print(
"Supported options:\n"
#if !defined(PRODUCT)
"--enable-asserts\n"
"  Enable assert statements.\n"
#endif  // !defined(PRODUCT)
"--help or -h\n"
"  Display this message (add -v or --verbose for information about\n"
"  all VM options).\n"
"--packages=<path>\n"
"  Where to find a package spec file.\n"
"--define=<key>=<value> or -D<key>=<value>\n"
"  Define an environment declaration. To specify multiple declarations,\n"
"  use multiple instances of this option.\n"
#if !defined(PRODUCT)
"--observe[=<port>[/<bind-address>]]\n"
"  The observe flag is a convenience flag used to run a program with a\n"
"  set of options which are often useful for debugging under Dart DevTools.\n"
"  These options are currently:\n"
"      --enable-vm-service[=<port>[/<bind-address>]]\n"
"      --serve-devtools\n"
"      --pause-isolates-on-exit\n"
"      --pause-isolates-on-unhandled-exceptions\n"
"      --warn-on-pause-with-no-debugger\n"
"      --timeline-streams=\"Compiler, Dart, GC, Microtask\"\n"
"  This set is subject to change.\n"
"  Please see these options for further documentation.\n"
"--profile-microtasks\n"
"  Record information about each microtask. Information about completed\n"
"  microtasks will be written to the \"Microtask\" timeline stream.\n"
#endif  // !defined(PRODUCT)
"--version\n"
"  Print the VM version.\n"
"\n"
"--trace-loading\n"
"  enables tracing of library and script loading\n"
"\n"
#if !defined(PRODUCT)
"--enable-vm-service[=<port>[/<bind-address>]]\n"
"  Enables the VM service and listens on specified port for connections\n"
"  (default port number is 8181, default bind address is localhost).\n"
"\n"
"--disable-service-auth-codes\n"
"  Disables the requirement for an authentication code to communicate with\n"
"  the VM service. Authentication codes help protect against CSRF attacks,\n"
"  so it is not recommended to disable them unless behind a firewall on a\n"
"  secure device.\n"
"\n"
"--enable-service-port-fallback\n"
"  When the VM service is told to bind to a particular port, fallback to 0 if\n"
"  it fails to bind instead of failing to start.\n"
"\n"
#endif  // !defined(PRODUCT)
"--root-certs-file=<path>\n"
"  The path to a file containing the trusted root certificates to use for\n"
"  secure socket connections.\n"
"--root-certs-cache=<path>\n"
"  The path to a cache directory containing the trusted root certificates to\n"
"  use for secure socket connections.\n"
#if defined(DART_HOST_OS_LINUX) || \
    defined(DART_HOST_OS_ANDROID) || \
    defined(DART_HOST_OS_FUCHSIA)
"--namespace=<path>\n"
"  The path to a directory that dart:io calls will treat as the root of the\n"
"  filesystem.\n"
#endif  // defined(DART_HOST_OS_LINUX) || defined(DART_HOST_OS_ANDROID)
"\n"
"The following options are only used for VM development and may\n"
"be changed in any future version:\n");
    const char* print_flags = "--print_flags";
    char* error = Dart_SetVMFlags(1, &print_flags);
    ASSERT(error == nullptr);
  }
}
// clang-format on

dart::SimpleHashMap* Options::environment_ = nullptr;
bool Options::ProcessEnvironmentOption(const char* arg,
                                       CommandLineOptions* vm_options) {
  return OptionProcessor::ProcessEnvironmentOption(arg, vm_options,
                                                   &Options::environment_);
}

void Options::Cleanup() {
#if defined(DART_PRECOMPILED_RUNTIME)
  DestroyEnvArgv();
#endif
  DestroyEnvironment();
}

void Options::DestroyEnvironment() {
  if (environment_ != nullptr) {
    for (SimpleHashMap::Entry* p = environment_->Start(); p != nullptr;
         p = environment_->Next(p)) {
      free(p->key);
      free(p->value);
    }
    delete environment_;
    environment_ = nullptr;
  }
}

#if defined(DART_PRECOMPILED_RUNTIME)
// Retrieves the set of arguments stored in the DART_VM_OPTIONS environment
// variable.
//
// DART_VM_OPTIONS should contain a list of comma-separated options and flags
// with no spaces. Options that support providing multiple values as
// comma-separated lists (e.g., --timeline-streams=Dart,GC,Compiler) are not
// supported and will cause argument parsing to fail.
char** Options::GetEnvArguments(int* argc) {
  ASSERT(argc != nullptr);
  const char* env_args_str = std::getenv("DART_VM_OPTIONS");
  if (env_args_str == nullptr) {
    *argc = 0;
    return nullptr;
  }

  intptr_t n = strlen(env_args_str);
  if (n == 0) {
    return nullptr;
  }

  // Find the number of arguments based on the number of ','s.
  //
  // WARNING: this won't work for arguments that support CSVs. There's less
  // than a handful of options that support multiple values. If we want to
  // support this case, we need to determine a way to specify groupings of CSVs
  // in environment variables.
  int arg_count = 1;
  for (int i = 0; i < n; ++i) {
    // Ignore the last comma if it's the last character in the string.
    if (env_args_str[i] == ',' && i + 1 != n) {
      arg_count++;
    }
  }

  env_argv_ = new char*[arg_count];
  env_argc_ = arg_count;
  *argc = arg_count;

  int current_arg = 0;
  char* token;
  char* rest = const_cast<char*>(env_args_str);

  // Split out the individual arguments.
  while ((token = strtok_r(rest, ",", &rest)) != nullptr) {
    // TODO(bkonyi): consider stripping leading/trailing whitespace from
    // arguments.
    env_argv_[current_arg++] = Utils::StrNDup(token, rest - token);
  }

  return env_argv_;
}

char** Options::env_argv_ = nullptr;
int Options::env_argc_ = 0;

void Options::DestroyEnvArgv() {
  for (int i = 0; i < env_argc_; ++i) {
    free(env_argv_[i]);
  }
  delete[] env_argv_;
  env_argv_ = nullptr;
}
#endif  // defined(DART_PRECOMPILED_RUNTIME)

bool Options::ExtractPortAndAddress(const char* option_value,
                                    int* out_port,
                                    const char** out_ip,
                                    int default_port,
                                    const char* default_ip) {
  // [option_value] has to be one of the following formats:
  //   - ""
  //   - ":8181"
  //   - "=8181"
  //   - ":8181/192.168.0.1"
  //   - "=8181/192.168.0.1"
  //   - "=8181/::1"

  if (*option_value == '\0') {
    *out_ip = default_ip;
    *out_port = default_port;
    return true;
  }

  if ((*option_value != '=') && (*option_value != ':')) {
    return false;
  }

  int port = atoi(option_value + 1);
  const char* slash = strstr(option_value, "/");
  if (slash == nullptr) {
    *out_ip = default_ip;
    *out_port = port;
    return true;
  }

  *out_ip = slash + 1;
  *out_port = port;
  return true;
}

// Returns true if arg starts with the characters "--" followed by option, but
// all '_' in the option name are treated as '-'.
static bool IsOption(const char* arg, const char* option) {
  if (arg[0] != '-' || arg[1] != '-') {
    // Special case first two characters to avoid recognizing __flag.
    return false;
  }
  for (int i = 0; option[i] != '\0'; i++) {
    auto c = arg[i + 2];
    if (c == '\0') {
      // Not long enough.
      return false;
    }
    if ((c == '_' ? '-' : c) != option[i]) {
      return false;
    }
  }
  return true;
}

const char* Options::vm_service_server_ip_ = DEFAULT_VM_SERVICE_SERVER_IP;
int Options::vm_service_server_port_ = INVALID_VM_SERVICE_SERVER_PORT;
bool Options::ProcessEnableVmServiceOption(const char* arg,
                                           CommandLineOptions* vm_options) {
#if !defined(PRODUCT)
  const char* value =
      OptionProcessor::ProcessOption(arg, "--enable-vm-service");
  if (value == nullptr) {
    return false;
  }
  if (!ExtractPortAndAddress(
          value, &vm_service_server_port_, &vm_service_server_ip_,
          DEFAULT_VM_SERVICE_SERVER_PORT, DEFAULT_VM_SERVICE_SERVER_IP)) {
    Syslog::PrintErr(
        "unrecognized --enable-vm-service option syntax. "
        "Use --enable-vm-service[=<port number>[/<bind address>]]\n");
    return false;
  }
#if !defined(DART_PRECOMPILED_RUNTIME)
  dfe()->set_use_incremental_compiler(true);
#endif  // !defined(DART_PRECOMPILED_RUNTIME)
  enable_vm_service_ = true;
  return true;
#else
  // VM service not available in product mode.
  return false;
#endif  // !defined(PRODUCT)
}

bool Options::ProcessObserveOption(const char* arg,
                                   CommandLineOptions* vm_options) {
#if !defined(PRODUCT)
  const char* value = OptionProcessor::ProcessOption(arg, "--observe");
  if (value == nullptr) {
    return false;
  }
  if (!ExtractPortAndAddress(
          value, &vm_service_server_port_, &vm_service_server_ip_,
          DEFAULT_VM_SERVICE_SERVER_PORT, DEFAULT_VM_SERVICE_SERVER_IP)) {
    Syslog::PrintErr(
        "unrecognized --observe option syntax. "
        "Use --observe[=<port number>[/<bind address>]]\n");
    return false;
  }

  // These options should also be documented in the help message.
  vm_options->AddArgument("--pause-isolates-on-exit");
  vm_options->AddArgument("--pause-isolates-on-unhandled-exceptions");
  vm_options->AddArgument("--profiler");
  vm_options->AddArgument("--warn-on-pause-with-no-debugger");
  vm_options->AddArgument("--timeline-streams=\"Compiler,Dart,GC,Microtask\"");
#if !defined(DART_PRECOMPILED_RUNTIME)
  dfe()->set_use_incremental_compiler(true);
#endif  // !defined(DART_PRECOMPILED_RUNTIME)
  enable_vm_service_ = true;
  return true;
#else
  // VM service not available in product mode.
  return false;
#endif  // !defined(PRODUCT)
}

bool Options::ProcessProfileMicrotasksOption(const char* arg,
                                             CommandLineOptions* vm_options) {
#if !defined(PRODUCT)
  constexpr const char* kProfileMicrotasksFlagAsCstr = "--profile-microtasks";
  constexpr const char* kAlternativeProfileMicrotasksFlagAsCstr =
      "--profile_microtasks";
  if (strncmp(kProfileMicrotasksFlagAsCstr, arg,
              strlen(kProfileMicrotasksFlagAsCstr)) == 0 ||
      strncmp(kAlternativeProfileMicrotasksFlagAsCstr, arg,
              strlen(kAlternativeProfileMicrotasksFlagAsCstr)) == 0) {
    profile_microtasks_ = true;
    vm_options->AddArgument(kProfileMicrotasksFlagAsCstr);
    return true;
  }
#endif  // !defined(PRODUCT)
  return false;
}

// Explicitly handle VM flags that can be parsed by DartDev's run command.
bool Options::ProcessVMDebuggingOptions(const char* arg,
                                        CommandLineOptions* vm_options) {
#define IS_DEBUG_OPTION(name, arg)                                             \
  if (strncmp(name, arg, strlen(name)) == 0) {                                 \
    vm_options->AddArgument(arg);                                              \
    return true;                                                               \
  }

// This is an exhaustive set of VM flags that are accepted by 'dart run'. Flags
// defined in main_options.h do not need to be handled here as they already
// have handlers generated.
//
// NOTE: When updating this list of VM flags, be sure to make the corresponding
// changes in pkg/dartdev/lib/src/commands/run.dart.
#define HANDLE_DARTDEV_VM_DEBUG_OPTIONS(V, arg)                                \
  V("--enable-asserts", arg)                                                   \
  V("--pause-isolates-on-exit", arg)                                           \
  V("--no-pause-isolates-on-exit", arg)                                        \
  V("--pause-isolates-on-start", arg)                                          \
  V("--no-pause-isolates-on-start", arg)                                       \
  V("--pause-isolates-on-unhandled-exception", arg)                            \
  V("--no-pause-isolates-on-unhandled-exception", arg)                         \
  V("--warn-on-pause-with-no-debugger", arg)                                   \
  V("--no-warn-on-pause-with-no-debugger", arg)                                \
  V("--timeline-streams", arg)                                                 \
  V("--timeline-recorder", arg)                                                \
  V("--enable-experiment", arg)
  HANDLE_DARTDEV_VM_DEBUG_OPTIONS(IS_DEBUG_OPTION, arg);

#undef IS_DEBUG_OPTION
#undef HANDLE_DARTDEV_VM_DEBUG_OPTIONS

  return false;
}

bool Options::ParseArguments(int argc,
                             char** argv,
                             bool vm_run_app_snapshot,
                             bool parsing_dart_vm_options,
                             CommandLineOptions* vm_options,
                             char** script_name,
                             CommandLineOptions* dart_options,
                             bool* print_flags_seen,
                             bool* verbose_debug_seen) {
  int i = 0;
#if !defined(DART_PRECOMPILED_RUNTIME)
  // DART_VM_OPTIONS is only implemented for compiled executables.
  ASSERT(!parsing_dart_vm_options);
#endif  // !defined(DART_PRECOMPILED_RUNTIME)
  if (!parsing_dart_vm_options) {
    // Store the executable name.
    Platform::SetExecutableName(argv[0]);

    // Start the rest after the executable name.
    i = 1;
  }

  CommandLineOptions temp_vm_options(vm_options->max_count());

  bool enable_dartdev_analytics = false;
  bool disable_dartdev_analytics = false;
  char* packages_argument = nullptr;

  // Parse out the vm options.
  while (i < argc) {
    bool skipVmOption = false;
    if (!OptionProcessor::TryProcess(argv[i], &temp_vm_options)) {
      // Check if this flag is a potentially valid VM flag.
      if (!OptionProcessor::IsValidFlag(argv[i])) {
        break;
      }
      // The following flags are processed as DartDev flags and are not to
      // be treated as if they are VM flags.
      if (IsOption(argv[i], "print-flags")) {
        *print_flags_seen = true;
      } else if (IsOption(argv[i], "verbose-debug")) {
        *verbose_debug_seen = true;
      } else if (IsOption(argv[i], "enable-analytics")) {
        enable_dartdev_analytics = true;
        skipVmOption = true;
      } else if (IsOption(argv[i], "disable-analytics")) {
        disable_dartdev_analytics = true;
        skipVmOption = true;
      } else if (IsOption(argv[i], "disable-telemetry")) {
        disable_dartdev_analytics = true;
        skipVmOption = true;
      } else if (IsOption(argv[i], "suppress-analytics")) {
        dart_options->AddArgument("--suppress-analytics");
        skipVmOption = true;
      } else if (IsOption(argv[i], "no-analytics")) {
        // Just add this option even if we don't go to dartdev.
        // It is irrelevant for the vm.
        dart_options->AddArgument("--no-analytics");
        skipVmOption = true;
      } else if (IsOption(argv[i], "dds")) {
        // This flag is set by default in dartdev, so we ignore it. --no-dds is
        // a VM flag as disabling DDS changes how we configure the VM service,
        // so we don't need to handle that case here.
        skipVmOption = true;
      } else if (IsOption(argv[i], "serve-observatory")) {
        // This flag is currently set by default in vmservice_io.dart, so we
        // ignore it. --no-serve-observatory is a VM flag so we don't need to
        // handle that case here.
        skipVmOption = true;
      } else if (IsOption(argv[i], "print-dtd-uri")) {
        skipVmOption = true;
      }
      if (!skipVmOption) {
        temp_vm_options.AddArgument(argv[i]);
      }
    }
    if (IsOption(argv[i], "packages")) {
      packages_argument = argv[i];
    }
    i++;
  }

#if !defined(DART_PRECOMPILED_RUNTIME)
  Options::dfe()->set_use_dfe();
#else
  // DartDev is not supported in AOT.
  Options::disable_dart_dev_ = true;
#endif  // !defined(DART_PRECOMPILED_RUNTIME)
  if (Options::deterministic()) {
    // Both an embedder and VM flag.
    temp_vm_options.AddArgument("--deterministic");
  }

  Socket::set_short_socket_read(Options::short_socket_read());
  Socket::set_short_socket_write(Options::short_socket_write());
#if !defined(DART_IO_SECURE_SOCKET_DISABLED)
  SSLCertContext::set_root_certs_file(Options::root_certs_file());
  SSLCertContext::set_root_certs_cache(Options::root_certs_cache());
  SSLCertContext::set_long_ssl_cert_evaluation(
      Options::long_ssl_cert_evaluation());
  SSLCertContext::set_bypass_trusting_system_roots(
      Options::bypass_trusting_system_roots());
#endif  // !defined(DART_IO_SECURE_SOCKET_DISABLED)

  FileSystemWatcher::set_delayed_filewatch_callback(
      Options::delayed_filewatch_callback());

  if (Options::deterministic()) {
    IOService::set_max_concurrency(1);
  }

  // The arguments to the VM are at positions 1 through i-1 in argv.
  Platform::SetExecutableArguments(i, argv);

#if !defined(DART_PRECOMPILED_RUNTIME)
  bool run_script = false;
#endif
  // Get the script name.
  if (i < argc) {
#if !defined(DART_PRECOMPILED_RUNTIME)
    // If the script name is a valid file or a URL, we'll run the script
    // directly. Otherwise, this might be a DartDev command and we need to try
    // to find the DartDev snapshot so we can forward the command and its
    // arguments.
    bool is_potential_file_path = !DartDevIsolate::ShouldParseCommand(argv[i]);
#else
    bool is_potential_file_path = true;
#endif  // !defined(DART_PRECOMPILED_RUNTIME)
    if (Options::disable_dart_dev() ||
        (Options::snapshot_filename() != nullptr) || is_potential_file_path) {
      *script_name = Utils::StrDup(argv[i]);
#if !defined(DART_PRECOMPILED_RUNTIME)
      run_script = true;
#endif
      i++;
    }
#if !defined(DART_PRECOMPILED_RUNTIME)
    else {  // NOLINT
      DartDevIsolate::set_should_run_dart_dev(true);
    }
#endif  // !defined(DART_PRECOMPILED_RUNTIME)
  }
#if !defined(DART_PRECOMPILED_RUNTIME)
  else if (!Options::disable_dart_dev()) {  // NOLINT
    // Handles following invocation arguments:
    //   - dart help
    //   - dart --help
    //   - dart
    if (((Options::help_option() && !Options::verbose_option()) ||
         (argc == 1))) {
      DartDevIsolate::set_should_run_dart_dev(true);
      // Let DartDev handle the default help message.
      dart_options->AddArgument("help");
      return true;
    }
    // Handles cases where only analytics flags are provided. We need to start
    // the DartDev isolate to set this state.
    else if (enable_dartdev_analytics || disable_dartdev_analytics) {  // NOLINT
      // The analytics flags are a special case as we don't have a target script
      // or DartDev command but we still want to launch DartDev.
      DartDevIsolate::set_should_run_dart_dev(true);
      dart_options->AddArgument(enable_dartdev_analytics
                                    ? "--enable-analytics"
                                    : "--disable-analytics");
      return true;
    }
    // Let the VM handle '--version' and '--help --disable-dart-dev'.
    // Otherwise, we'll launch the DartDev isolate to print its help message
    // and set an error exit code.
    else if (!Options::help_option() && !Options::version_option()) {  // NOLINT
      DartDevIsolate::PrintUsageErrorOnRun();
      return true;
    }
    return false;
  }
#endif  // !defined(DART_PRECOMPILED_RUNTIME)
  // Handle argument parsing errors and missing script / command name when not
  // processing options set via DART_VM_OPTIONS.
  else if (!parsing_dart_vm_options || Options::help_option() ||  // NOLINT
           Options::version_option()) {                           // NOLINT
    return false;
  }
  USE(enable_dartdev_analytics);
  USE(disable_dartdev_analytics);
  USE(packages_argument);

  const char** vm_argv = temp_vm_options.arguments();
  int vm_argc = temp_vm_options.count();

  vm_options->AddArguments(vm_argv, vm_argc);

#if !defined(DART_PRECOMPILED_RUNTIME)
  // If we're parsing DART_VM_OPTIONS, there shouldn't be any script set or
  // Dart arguments left to parse.
  if (parsing_dart_vm_options) {
    ASSERT(i == argc);
    return true;
  }

  // If running with dartdev, attempt to parse VM flags which are part of the
  // dartdev command (e.g., --enable-vm-service, --observe, etc).
  bool record_vm_options = false;
  if ((i < argc) && DartDevIsolate::ShouldParseVMOptions(argv[i])) {
    record_vm_options = true;
  }
  if (!run_script && record_vm_options) {
    // Skip the command.
    int tmp_i = i + 1;
    while (tmp_i < argc) {
      // Check if this flag is a potentially valid VM flag. If not, we've likely
      // hit a script name and are done parsing VM flags.
      if (!OptionProcessor::IsValidFlag(argv[tmp_i]) &&
          !OptionProcessor::IsValidShortFlag(argv[tmp_i])) {
        break;
      }
      OptionProcessor::TryProcess(argv[tmp_i], vm_options);
      tmp_i++;
    }
  }
#endif  // !defined(DART_PRECOMPILED_RUNTIME)

  bool first_option = true;
  // Parse out options to be passed to dart main.
  while (i < argc) {
    // dart run isn't able to parse these options properly. Since it doesn't
    // need to use the values from these options, just strip them from the
    // argument list passed to dart run.
    if (!IsOption(argv[i], "observe") &&
        !IsOption(argv[i], "enable-vm-service")) {
      dart_options->AddArgument(argv[i]);
    }
#if !defined(DART_PRECOMPILED_RUNTIME)
    if (IsOption(argv[i], "disable-dart-dev")) {
      Syslog::PrintErr(
          "Attempted to use --disable-dart-dev with a Dart CLI command.\n");
      Platform::Exit(kErrorExitCode);
    }
#endif  // !defined(DART_PRECOMIPLED_RUNTIME)
    i++;
    // Add DDS specific flags immediately after the dartdev command.
    if (first_option) {
      // DDS is only enabled for the run command. Make sure we don't pass DDS
      // specific flags along with other commands, otherwise argument parsing
      // will fail unexpectedly.
#if !defined(DART_PRECOMPILED_RUNTIME)
      // Bring any --packages option into the dartdev command
      if (DartDevIsolate::should_run_dart_dev() &&
          packages_argument != nullptr) {
        dart_options->AddArgument(packages_argument);
      }
#endif  // !defined(DART_PRECOMPILED_RUNTIME)
      first_option = false;
    }
  }

  // Verify consistency of arguments.

  // snapshot_depfile is an alias for depfile. Passing them both is an error.
  if ((snapshot_deps_filename_ != nullptr) && (depfile_ != nullptr)) {
    Syslog::PrintErr("Specify only one of --depfile and --snapshot_depfile\n");
    return false;
  }
  if (snapshot_deps_filename_ != nullptr) {
    depfile_ = snapshot_deps_filename_;
    snapshot_deps_filename_ = nullptr;
  }

  if ((packages_file_ != nullptr) && (strlen(packages_file_) == 0)) {
    Syslog::PrintErr("Empty package file name specified.\n");
    return false;
  }
  if ((gen_snapshot_kind_ != kNone) && (snapshot_filename_ == nullptr)) {
    Syslog::PrintErr(
        "Generating a snapshot requires a filename (--snapshot).\n");
    return false;
  }
  if ((gen_snapshot_kind_ == kNone) && (depfile_ != nullptr) &&
      (snapshot_filename_ == nullptr) &&
      (depfile_output_filename_ == nullptr)) {
    Syslog::PrintErr(
        "Generating a depfile requires an output filename"
        " (--depfile-output-filename or --snapshot).\n");
    return false;
  }
  if ((gen_snapshot_kind_ != kNone) && vm_run_app_snapshot) {
    Syslog::PrintErr(
        "Specifying an option to generate a snapshot and"
        " run using a snapshot is invalid.\n");
    return false;
  }

  // If --snapshot is given without --snapshot-kind, default to script snapshot.
  if ((snapshot_filename_ != nullptr) && (gen_snapshot_kind_ == kNone)) {
    gen_snapshot_kind_ = kKernel;
  }

  return true;
}

}  // namespace bin
}  // namespace dart
