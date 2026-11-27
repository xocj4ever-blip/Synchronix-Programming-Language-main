/* SPDX-License-Identifier: Apache-2.0
 *
 * Copyright 2026 Synchronix Contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Full license text: ../../LICENSE
 * End-User License Agreement: ../../EULA.md
 */

/* ============================================================================
 * SYNCHRONIX ECOSYSTEM — Debugger (LLDB/GDB) & Profiler (src/tooling/debug_prof.S)
 * ============================================================================
 * Implements Developer Ecosystem -> Debugger (LLDB/GDB) & Profiler:
 *   - sx_cmd_debug(file)   : compiles with -g DWARF info & launches LLDB
 *   - sx_cmd_profile(file) : times compile + native execution & prints full
 *     3-Phase compiler optimization & runtime profiling telemetry!
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(dbg_out_bin,   "synchronix_debug.exe")
SX_STR(prof_out_bin,  "synchronix_prof.exe")
SX_STR(fmt_lldb_cmd,  "lldb -b -o \"b main\" -o \"run\" \"%s\"")
SX_STR(msg_dbg_go,    "[Synchronix Debugger] Built debug binary with DWARF symbols -> %s\n")
SX_STR(msg_dbg_hint,  "[Synchronix Debugger] Launching LLDB session...\n")

SX_STR(prof_hdr,      "\n================ SYNCHRONIX PROFILER REPORT ================\n")
SX_STR(prof_time1,    "  Compile Time     : %lld ticks\n")
SX_STR(prof_time2,    "  Execution Time   : %lld ticks\n")
SX_STR(prof_p1,       "  Phase 1 Frontend : tokens=%lld ast_nodes=%lld lambdas=%lld\n")
SX_STR(prof_phi,      "  Phi Verification : static_proven=%lld runtime_checks=%lld\n")
SX_STR(prof_p2a,      "  Phase 2 Middle   : sumir_insts=%lld arc_ops=%lld gc_roots=%lld\n")
SX_STR(prof_p2b,      "  Phase 2 Lowering : const_folded=%lld dce_removed=%lld inlined=%lld\n")
SX_STR(prof_p3,       "  Phase 3 Backend  : reg_allocated=%lld sched_opts=%lld\n")
SX_STR(prof_ftr,      "============================================================\n")
SX_STR(fmt_exec_prof, "\"%s\"")

SX_BSS
.p2align 4
SX_LABEL(g_dp_cmd)
    .skip 512

SX_TEXT

/* ----------------------------------------------------------------------------
 * sx_cmd_debug(A0 = src_file) — Compile with -g & invoke LLDB
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_cmd_debug)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    LEA_SYM(T0, g_opt_debug) ; MOVI(T1, 1) ; ST64(T1, T0, 0)
    MOVR(A0, S0) ; LEA_SYM(A1, dbg_out_bin)
    SX_CALL(sx_compile_file)
    CMPI(R0, 0) ; JNE(.L_dbg_fail)

    LEA_SYM(A0, msg_dbg_go) ; LEA_SYM(A1, dbg_out_bin) ; SX_VCALL(printf)
    LEA_SYM(A0, msg_dbg_hint) ; SX_VCALL(printf)
    LEA_SYM(A0, g_dp_cmd) ; MOVI(A1, 512)
    LEA_SYM(A2, fmt_lldb_cmd) ; LEA_SYM(A3, dbg_out_bin)
    SX_VCALL(snprintf)
    LEA_SYM(A0, g_dp_cmd) ; SX_CALL(system)
    MOVI(R0, 0) ; SX_EPILOGUE
.L_dbg_fail:
    MOVI(R0, 1) ; SX_EPILOGUE
SX_ENDFUNC(sx_cmd_debug)

/* ----------------------------------------------------------------------------
 * sx_cmd_profile(A0 = src_file) — Full Compiler + Native Runtime Profiler
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_cmd_profile)
    SX_PROLOGUE 32
    MOVR(S0, A0)

    /* Measure compile time */
    SX_CALL(clock) ; MOVR(S1, R0)
    MOVR(A0, S0) ; LEA_SYM(A1, prof_out_bin)
    SX_CALL(sx_compile_file)
    CMPI(R0, 0) ; JNE(.L_prof_fail)
    SX_CALL(clock) ; SUB(R0, S1) ; MOVR(S2, R0) /* S2 = compile ticks */

    /* Measure native execution time */
    LEA_SYM(A0, g_dp_cmd) ; MOVI(A1, 512)
    LEA_SYM(A2, fmt_exec_prof) ; LEA_SYM(A3, prof_out_bin)
    SX_VCALL(snprintf)

    SX_CALL(clock) ; MOVR(S3, R0)
    LEA_SYM(A0, g_dp_cmd) ; SX_CALL(system)
    SX_CALL(clock) ; SUB(R0, S3) ; MOVR(S4, R0) /* S4 = exec ticks */

    /* Print Structured Profiler Report */
    LEA_SYM(A0, prof_hdr) ; SX_VCALL(printf)
    LEA_SYM(A0, prof_time1) ; MOVR(A1, S2) ; SX_VCALL(printf)
    LEA_SYM(A0, prof_time2) ; MOVR(A1, S4) ; SX_VCALL(printf)

    LEA_SYM(T0, g_lambda_count) ; LD64(A3, T0, 0)
    LEA_SYM(T0, g_ast_count)    ; LD64(A2, T0, 0)
    LEA_SYM(T0, g_tok_count)    ; LD64(A1, T0, 0)
    LEA_SYM(A0, prof_p1) ; SX_VCALL(printf)

    LEA_SYM(T0, g_stat_phi_runtime) ; LD64(A2, T0, 0)
    LEA_SYM(T0, g_stat_phi_static)  ; LD64(A1, T0, 0)
    LEA_SYM(A0, prof_phi) ; SX_VCALL(printf)

    LEA_SYM(T0, g_stat_gc_roots)     ; LD64(A3, T0, 0)
    LEA_SYM(T0, g_stat_arc_inserted) ; LD64(A2, T0, 0)
    LEA_SYM(T0, g_ir_count)          ; LD64(A1, T0, 0)
    LEA_SYM(A0, prof_p2a) ; SX_VCALL(printf)

    LEA_SYM(T0, g_stat_inlined)      ; LD64(A3, T0, 0)
    LEA_SYM(T0, g_stat_dce_removed)  ; LD64(A2, T0, 0)
    LEA_SYM(T0, g_stat_const_folded) ; LD64(A1, T0, 0)
    LEA_SYM(A0, prof_p2b) ; SX_VCALL(printf)

    LEA_SYM(T0, g_stat_sched_opts) ; LD64(A2, T0, 0)
    LEA_SYM(T0, g_stat_reg_allocs) ; LD64(A1, T0, 0)
    LEA_SYM(A0, prof_p3) ; SX_VCALL(printf)

    LEA_SYM(A0, prof_ftr) ; SX_VCALL(printf)
    MOVI(R0, 0) ; SX_EPILOGUE
.L_prof_fail:
    MOVI(R0, 1) ; SX_EPILOGUE
SX_ENDFUNC(sx_cmd_profile)
