// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef RUNTIME_VM_FLAG_LIST_H_
#define RUNTIME_VM_FLAG_LIST_H_

#include "platform/thread_sanitizer.h"
#include "vm/globals.h"

// Don't use USING_PRODUCT outside of this file.
#if defined(PRODUCT)
#define USING_PRODUCT true
#else
#define USING_PRODUCT false
#endif

#if defined(DART_PRECOMPILED_RUNTIME)
constexpr bool kDartPrecompiledRuntime = true;
#else
constexpr bool kDartPrecompiledRuntime = false;
#endif

constexpr intptr_t kDefaultOptimizationCounterThreshold = 30000;

// The disassembler might be force included even in product builds so we need
// to conditionally make these into product flags to make the disassembler
// usable in product mode.
#if defined(FORCE_INCLUDE_DISASSEMBLER)
#define DISASSEMBLE_FLAGS(P, R, C, D)                                          \
  P(disassemble, bool, false, "Disassemble dart code.")                        \
  P(disassemble_optimized, bool, false, "Disassemble optimized code.")         \
  P(disassemble_relative, bool, false, "Use offsets instead of absolute PCs")  \
  P(disassemble_stubs, bool, false, "Disassemble generated stubs.")            \
  P(support_disassembler, bool, true, "Support the disassembler.")
#else
#define DISASSEMBLE_FLAGS(P, R, C, D)                                          \
  R(disassemble, false, bool, false, "Disassemble dart code.")                 \
  R(disassemble_optimized, false, bool, false, "Disassemble optimized code.")  \
  R(disassemble_relative, false, bool, false,                                  \
    "Use offsets instead of absolute PCs")                                     \
  R(disassemble_stubs, false, bool, false, "Disassemble generated stubs.")     \
  R(support_disassembler, false, bool, true, "Support the disassembler.")
#endif

#if defined(INCLUDE_IL_PRINTER)
constexpr bool FLAG_support_il_printer = true;
#else
constexpr bool FLAG_support_il_printer = false;
#endif  // defined(INCLUDE_IL_PRINTER)

// List of VM-global (i.e. non-isolate specific) flags.
//
// The value used for those flags at snapshot generation time needs to be the
// same as during runtime. Currently, only boolean flags are supported.
//
// The syntax used is the same as that for FLAG_LIST below, as these flags are
// automatically included in FLAG_LIST.
#define VM_GLOBAL_FLAG_LIST(P, R, C, D)                                        \
  P(code_comments, bool, false, "Include comments into code and disassembly.") \
  P(dwarf_stack_traces_mode, bool, false,                                      \
    "Use --[no-]dwarf-stack-traces instead.")                                  \
  R(dedup_instructions, true, bool, false,                                     \
    "Canonicalize instructions when precompiling.")

// List of all flags in the VM.
// Flags can be one of four categories:
// * P roduct flags: Can be set in any of the deployment modes, including in
//   production.
// * R elease flags: Generally available flags except when building product.
// * pre C ompile flags: Generally available flags except when building product
//   or precompiled runtime.
// * D ebug flags: Can only be set in debug VMs, which also have C++ assertions
//   enabled.
//
// Usage:
//   P(name, type, default_value, comment)
//   R(name, product_value, type, default_value, comment)
//   C(name, precompiled_value, product_value, type, default_value, comment)
//   D(name, type, default_value, comment)
#define FLAG_LIST(P, R, C, D)                                                  \
  VM_GLOBAL_FLAG_LIST(P, R, C, D)                                              \
  DISASSEMBLE_FLAGS(P, R, C, D)                                                \
  P(abort_on_oom, bool, false,                                                 \
    "Abort if memory allocation fails - use only with --old-gen-heap-size")    \
  P(add_readonly_data_symbols, bool, false,                                    \
    "Add static symbols for objects in snapshot read-only data")               \
  P(background_compilation, bool, true,                                        \
    "Run optimizing compilation in background")                                \
  P(check_token_positions, bool, false,                                        \
    "Check validity of token positions while compiling flow graphs")           \
  P(collect_dynamic_function_names, bool, true,                                \
    "Collects all dynamic function names to identify unique targets")          \
  P(compactor_tasks, int, 2,                                                   \
    "The number of tasks to use for parallel compaction.")                     \
  P(concurrent_mark, bool, true, "Concurrent mark for old generation.")        \
  P(concurrent_sweep, bool, true, "Concurrent sweep for old generation.")      \
  C(deoptimize_alot, false, false, bool, false,                                \
    "Deoptimizes we are about to return to Dart code from native entries.")    \
  C(deoptimize_every, 0, 0, int, 0,                                            \
    "Deoptimize on every N stack overflow checks")                             \
  P(deoptimize_on_runtime_call_every, int, 0,                                  \
    "Deoptimize functions on every runtime call.")                             \
  P(dontneed_on_sweep, bool, false,                                            \
    "madvise(DONTNEED) free areas in partially used heap regions")             \
  R(dump_megamorphic_stats, false, bool, false,                                \
    "Dump megamorphic cache statistics")                                       \
  R(dump_symbol_stats, false, bool, false, "Dump symbol table statistics")     \
  P(enable_asserts, bool, false, "Enable assert statements.")                  \
  P(inline_alloc, bool, true, "Whether to use inline allocation fast paths.")  \
  P(enable_mirrors, bool, true,                                                \
    "Disable to make importing dart:mirrors an error.")                        \
  P(enable_ffi, bool, true, "Disable to make importing dart:ffi an error.")    \
  P(force_clone_compiler_objects, bool, false,                                 \
    "Force cloning of objects needed in compiler (ICData and Field).")         \
  P(guess_icdata_cid, bool, true,                                              \
    "Artificially create type feedback for arithmetic etc. operations")        \
  P(huge_method_cutoff_in_ast_nodes, int, 10000,                               \
    "Huge method cutoff in AST nodes: Disables optimizations for huge "        \
    "methods.")                                                                \
  P(idle_timeout_micros, int, 61 * kMicrosecondsPerSecond,                     \
    "Consider thread pool isolates for idle tasks after this long.")           \
  P(idle_duration_micros, int, kMaxInt32,                                      \
    "Allow idle tasks to run for this long.")                                  \
  P(interpret_irregexp, bool, false, "Use irregexp bytecode interpreter")      \
  C(interpreter, false, false, bool, false, "Use bytecode interpreter")        \
  P(link_natives_lazily, bool, false, "Link native calls lazily")              \
  R(log_marker_tasks, false, bool, false,                                      \
    "Log debugging information for old gen GC marking tasks.")                 \
  P(scavenger_tasks, int, -1,                                                  \
    "The number of tasks to spawn during scavenging and incremental "          \
    "compaction (0 means perform all work on the main thread, -1 means "       \
    "select an amount based on the number of active isolates).")               \
  P(mark_when_idle, bool, false,                                               \
    "The Dart thread will assist in concurrent marking during idle time and "  \
    "is counted as one marker task")                                           \
  P(marker_tasks, int, 2,                                                      \
    "The number of tasks to spawn during old gen GC marking (0 means "         \
    "perform all marking on main thread).")                                    \
  P(hash_map_probes_limit, int, kMaxInt32,                                     \
    "Limit number of probes while doing lookups in hash maps.")                \
  P(max_polymorphic_checks, int, 4,                                            \
    "Maximum number of polymorphic check, otherwise it is megamorphic.")       \
  P(max_equality_polymorphic_checks, int, 32,                                  \
    "Maximum number of polymorphic checks in equality operator,")              \
  P(new_gen_semi_max_size, int, kDefaultNewGenSemiMaxSize,                     \
    "Max size of new gen semi space in MB")                                    \
  P(new_gen_semi_initial_size, int, (kWordSize <= 4) ? 1 : 2,                  \
    "Initial size of new gen semi space in MB")                                \
  P(optimization_counter_threshold, int, kDefaultOptimizationCounterThreshold, \
    "Function's usage-counter value before it is optimized, -1 means never")   \
  P(optimization_level, int, 2,                                                \
    "Optimization level: 1 (favor size), 2 (default), 3 (favor speed)")        \
  P(old_gen_heap_size, int, kDefaultMaxOldGenHeapSize,                         \
    "Max size of old gen heap size in MB, or 0 for unlimited,"                 \
    "e.g: --old_gen_heap_size=1024 allows up to 1024MB old gen heap")          \
  R(pause_isolates_on_start, false, bool, false,                               \
    "Pause isolates before starting.")                                         \
  R(pause_isolates_on_exit, false, bool, false, "Pause isolates exiting.")     \
  R(pause_isolates_on_unhandled_exceptions, false, bool, false,                \
    "Pause isolates on unhandled exceptions.")                                 \
  P(polymorphic_with_deopt, bool, true,                                        \
    "Polymorphic calls with deoptimization / megamorphic call")                \
  P(precompiled_mode, bool, false, "Precompilation compiler mode")             \
  D(print_scopes, bool, false,                                                 \
    "Print scopes after scope building. Filtered by "                          \
    "--print-flow-graph-filter.")                                              \
  P(print_snapshot_sizes, bool, false, "Print sizes of generated snapshots.")  \
  P(print_snapshot_sizes_verbose, bool, false,                                 \
    "Print cluster sizes of generated snapshots.")                             \
  R(print_ssa_liveranges, false, bool, false,                                  \
    "Print live ranges after allocation.")                                     \
  R(print_stacktrace_at_api_error, false, bool, false,                         \
    "Attempt to print a native stack trace when an API error is created.")     \
  D(print_variable_descriptors, bool, false,                                   \
    "Print variable descriptors in disassembly.")                              \
  R(profiler, false, bool, false, "Enable the profiler.")                      \
  R(profiler_native_memory, false, bool, false,                                \
    "Enable native memory statistic collection.")                              \
  P(reorder_basic_blocks, bool, true, "Reorder basic blocks")                  \
  C(stress_async_stacks, false, false, bool, false,                            \
    "Stress test async stack traces")                                          \
  P(retain_function_objects, bool, true,                                       \
    "Serialize function objects for all code objects even if not otherwise "   \
    "needed in the precompiled runtime.")                                      \
  P(retain_code_objects, bool, true,                                           \
    "Serialize all code objects even if not otherwise "                        \
    "needed in the precompiled runtime.")                                      \
  P(show_invisible_frames, bool, false,                                        \
    "Show invisible frames in stack traces.")                                  \
  P(target_unknown_cpu, bool, false,                                           \
    "Generate code for a generic CPU, unknown at compile time")                \
  D(trace_cha, bool, false, "Trace CHA operations")                            \
  R(trace_field_guards, false, bool, false, "Trace changes in field's cids.")  \
  D(trace_finalizers, bool, false, "Traces finalizers.")                       \
  D(trace_ic, bool, false, "Trace IC handling")                                \
  D(trace_ic_miss_in_optimized, bool, false,                                   \
    "Trace IC miss in optimized code")                                         \
  C(trace_irregexp, false, false, bool, false, "Trace irregexps.")             \
  D(trace_intrinsified_natives, bool, false,                                   \
    "Report if any of the intrinsified natives are called")                    \
  D(trace_isolates, bool, false, "Trace isolate creation and shut down.")      \
  D(trace_handles, bool, false, "Traces allocation of handles.")               \
  D(trace_kernel_binary, bool, false, "Trace Kernel reader/writer.")           \
  D(trace_natives, bool, false, "Trace invocation of natives")                 \
  D(trace_optimization, bool, false, "Print optimization details.")            \
  R(trace_profiler, false, bool, false, "Profiler trace")                      \
  D(trace_profiler_verbose, bool, false, "Verbose profiler trace")             \
  D(trace_runtime_calls, bool, false, "Trace runtime calls.")                  \
  R(trace_ssa_allocator, false, bool, false,                                   \
    "Trace register allocation over SSA.")                                     \
  P(trace_strong_mode_types, bool, false,                                      \
    "Trace optimizations based on strong mode types.")                         \
  D(trace_type_checks, bool, false, "Trace runtime type checks.")              \
  D(trace_type_checks_verbose, bool, false,                                    \
    "Enable verbose trace of runtime type checks.")                            \
  D(trace_patching, bool, false, "Trace patching of code.")                    \
  D(trace_zones, bool, false, "Traces allocation sizes in the zone.")          \
  P(truncating_left_shift, bool, true,                                         \
    "Optimize left shift to truncate if possible")                             \
  P(use_compactor, bool, false, "Compact the heap during old-space GC.")       \
  P(use_incremental_compactor, bool, true,                                     \
    "Compact the heap during old-space GC.")                                   \
  P(use_cha_deopt, bool, true,                                                 \
    "Use class hierarchy analysis even if it can cause deoptimization.")       \
  P(use_field_guards, bool, true, "Use field guards and track field types")    \
  C(use_osr, false, true, bool, true, "Use OSR")                               \
  P(use_slow_path, bool, false, "Whether to avoid inlined fast paths.")        \
  P(verbose_gc, bool, false, "Enables verbose GC.")                            \
  P(verbose_gc_hdr, int, 40, "Print verbose GC header interval.")              \
  R(verify_after_gc, false, bool, false,                                       \
    "Enables heap verification after GC.")                                     \
  R(verify_before_gc, false, bool, false,                                      \
    "Enables heap verification before GC.")                                    \
  R(verify_store_buffer, false, bool, false,                                   \
    "Enables store buffer verification before and after scavenges.")           \
  R(verify_after_marking, false, bool, false,                                  \
    "Enables heap verification after marking.")                                \
  P(enable_slow_path_sharing, bool, true, "Enable sharing of slow-path code.") \
  P(shared_slow_path_triggers_gc, bool, false,                                 \
    "TESTING: slow-path triggers a GC.")                                       \
  P(enable_multiple_entrypoints, bool, true,                                   \
    "Enable multiple entrypoints per-function and related optimizations.")     \
  P(enable_testing_pragmas, bool, false,                                       \
    "Enable magical pragmas for testing purposes. Use at your own risk!")      \
  R(eliminate_type_checks, true, bool, true,                                   \
    "Eliminate type checks when allowed by static type analysis.")             \
  D(support_rr, bool, false, "Support running within RR.")                     \
  P(verify_entry_points, bool, true,                                           \
    "Throw API error on invalid member access through native API. See "        \
    "entry_point_pragma.md")                                                   \
  C(branch_coverage, false, false, bool, true, "Enable branch coverage")       \
  C(coverage, false, false, bool, true, "Enable coverage")                     \
  P(use_simulator, bool, true, "Use simulator if available")

#endif  // RUNTIME_VM_FLAG_LIST_H_
