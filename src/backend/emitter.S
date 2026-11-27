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
 * SYNCHRONIX COMPILER — Phase 3: Assembler & Linker Driver (emitter.S)
 * ============================================================================
 * Drives the complete 3-Phase Diagram Pipeline:
 *   Phase 1 (Frontend) -> Phase 2 (Middle-End) -> Phase 3 (Backend Codegen
 *   + Target Optimization + Assembler & Linker ld/lld + External Libs)
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(mode_w,          "w")
SX_STR(err_open_src,    "[Synchronix Error] Cannot open source file: %s\n")
SX_STR(err_open_out,    "[Synchronix Error] Cannot open output file: %s\n")
SX_STR(err_comp_abort,  "[Synchronix] Compilation aborted with %lld error(s).\n")
SX_STR(err_link_fail,   "[Synchronix Error] Assembler/Linker failed (exit=%lld).\n")

SX_STR(fmt_asm_path,    "%s.s")
SX_STR(fmt_ll_path,     "%s.ll")
SX_STR(fmt_cmd_x64,     "clang -fuse-ld=lld %s \"%s\" \"%s\" -o \"%s\"")
SX_STR(fmt_cmd_x64_ext, "clang -fuse-ld=lld %s \"%s\" \"%s\" \"%s\" -o \"%s\"")
SX_STR(fmt_cmd_arm64,   "clang --target=aarch64-w64-windows-gnu -c \"%s\" -o \"%s.o\"")
SX_STR(flag_debug,      "-g")
SX_STR(flag_empty,      "")
SX_STR(rt_lib_x64,      "build/libsynchronix_rt.a")
SX_STR(rt_lib_local,    "libsynchronix_rt.a")
SX_STR(mode_r_chk,      "rb")

SX_STR(msg_emitted_ll,  "[Synchronix Backend] Emitted LLVM IR: %s\n")
SX_STR(msg_emitted_a64, "[Synchronix Backend] Assembled ARM64 object: %s.o\n")
SX_STR(msg_emitted_bin, "[Synchronix Backend] Linked native executable: %s\n")

SX_BSS
.p2align 4
SX_LABEL(g_asm_path)
    .skip 512
SX_LABEL(g_link_cmd)
    .skip 2048
SX_LABEL(g_rt_path_buf)
    .skip 512

SX_TEXT

/* ----------------------------------------------------------------------------
 * Helper: sx_find_rt_lib() -> R0 = path_cstr to libsynchronix_rt.a
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_find_rt_lib)
    SX_PROLOGUE 16
    LEA_SYM(A0, rt_lib_x64)
    LEA_SYM(A1, mode_r_chk)
    SX_CALL(fopen)
    CMPI(R0, 0) ; JEQ(.L_frt_local)
    MOVR(A0, R0) ; SX_CALL(fclose)
    LEA_SYM(R0, rt_lib_x64)
    SX_EPILOGUE
.L_frt_local:
    LEA_SYM(R0, rt_lib_local)
    SX_EPILOGUE
SX_ENDFUNC(sx_find_rt_lib)

/* ----------------------------------------------------------------------------
 * sx_compile_file(A0 = src_path, A1 = out_path) -> R0 = 0 on success else 1
 * Executes ALL 3 Phases strictly adhering to the Synchronix Architecture Diagram!
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_compile_file)
    SX_PROLOGUE 48
    MOVR(S0, A0)                /* S0 = src_path */
    MOVR(S1, A1)                /* S1 = out_path */

    SX_CALL(sx_compiler_reset)

    /* --- PHASE 1: FRONTEND (ANALYSIS) --- */
    /* 1. Read .synchronix Source Code */
    MOVR(A0, S0)
    LEA_SYM(A1, g_src_len)
    SX_CALL(sx_read_file)
    CMPI(R0, 0) ; JNE(.L_cf_read_ok)
    LEA_SYM(A0, err_open_src) ; MOVR(A1, S0) ; SX_VCALL(printf)
    MOVI(R0, 1) ; SX_EPILOGUE

.L_cf_read_ok:
    LEA_SYM(T0, g_src_buf) ; ST64(R0, T0, 0)

    /* 2. Lexer / Tokenizer */
    MOVR(A0, R0)
    LEA_SYM(T0, g_src_len) ; LD64(A1, T0, 0)
    SX_CALL(sx_lex)

    /* 3. Parser -> Abstract Syntax Tree (AST) */
    SX_CALL(sx_parse_program)
    MOVR(S2, R0)                /* S2 = AST root */

    /* 4. Semantic Analyzer & Type Checker + Phi/Lambda Verification -> Typed AST */
    MOVR(A0, S2)
    SX_CALL(sx_sema_program)
    CMPI(R0, 0) ; JEQ(.L_cf_phase2)
    MOVR(A1, R0) ; LEA_SYM(A0, err_comp_abort) ; SX_VCALL(printf)
    MOVI(R0, 1) ; SX_EPILOGUE

    /* --- PHASE 2: MIDDLE-END (OPTIMIZATION & MEMORY) --- */
.L_cf_phase2:
    /* 1. IR Generator -> High-Level IR -> SUMIR */
    MOVR(A0, S2)
    SX_CALL(sx_ir_gen_program)

    /* 2. Static Analysis & Memory Safety (ARC/GC/Ownership/Lifetime)
     *    + Phi & Lambda Optimizations
     *    + Lowering (Constant Folding, Inlining, DCE) */
    SX_CALL(sx_middle_end_run)

    /* Check for Ownership / Memory Safety errors */
    LEA_SYM(T0, g_err_count) ; LD64(R0, T0, 0)
    CMPI(R0, 0) ; JEQ(.L_cf_phase3)
    MOVR(A1, R0) ; LEA_SYM(A0, err_comp_abort) ; SX_VCALL(printf)
    MOVI(R0, 1) ; SX_EPILOGUE

    /* --- PHASE 3: BACKEND (CODEGEN) --- */
.L_cf_phase3:
    /* 1. Target-Specific Optimization: Register Allocation + Instruction Scheduling */
    SX_CALL(sx_pass_regalloc)
    SX_CALL(sx_pass_inst_schedule)

    /* 2. Determine target & output intermediate filename */
    LEA_SYM(T0, g_opt_target) ; LD64(S3, T0, 0)
    CMPI(S3, TARGET_LLVM_IR) ; JEQ(.L_cf_emit_ll)

    /* Format <out_path>.s */
    LEA_SYM(A0, g_asm_path) ; MOVI(A1, 512)
    LEA_SYM(A2, fmt_asm_path) ; MOVR(A3, S1)
    SX_VCALL(snprintf)

    LEA_SYM(A0, g_asm_path) ; LEA_SYM(A1, mode_w) ; SX_CALL(fopen)
    CMPI(R0, 0) ; JNE(.L_cf_asm_open)
    LEA_SYM(A0, err_open_out) ; LEA_SYM(A1, g_asm_path) ; SX_VCALL(printf)
    MOVI(R0, 1) ; SX_EPILOGUE

.L_cf_asm_open:
    MOVR(S4, R0)                /* S4 = FILE* */
    CMPI(S3, TARGET_ARM64) ; JEQ(.L_cf_do_arm64)

    /* Custom x86_64 Code Generator */
    MOVR(A0, S4) ; SX_CALL(sx_codegen_x86_64)
    MOVR(A0, S4) ; SX_CALL(fclose)

    /* If --emit-asm only, stop here */
    LEA_SYM(T0, g_opt_emit_asm) ; LD64(T1, T0, 0)
    CMPI(T1, 0) ; JNE(.L_cf_ok)

    /* 3. Assembler & Linker (ld / lld) + Synchronix Runtime + External Libs */
    SX_CALL(sx_find_rt_lib)
    ST_LOCAL(R0, 0)             /* local[0] = rt_lib_path */

    LEA_SYM(T0, g_opt_debug) ; LD64(T1, T0, 0)
    LEA_SYM(T0, flag_empty)
    CMPI(T1, 0) ; JEQ(.L_cf_dbg_ok)
    LEA_SYM(T0, flag_debug)
.L_cf_dbg_ok:
    ST_LOCAL(T0, 1)             /* local[1] = debug_flag */

    /* Build command safely using snprintf + strcat (keeps within portable 4 args!) */
    LEA_SYM(A0, g_link_cmd) ; MOVI(A1, 2048)
    LEA_SYM(A2, fmt_lnk_p1) ; LD_LOCAL(A3, 1)
    SX_VCALL(snprintf)

    /* Append asm path, rt_lib, optional external lib, and -o out_path */
    LEA_SYM(A0, g_link_cmd) ; LEA_SYM(A1, sp_q) ; SX_CALL(strcat)
    LEA_SYM(A0, g_link_cmd) ; LEA_SYM(A1, g_asm_path) ; SX_CALL(strcat)
    LEA_SYM(A0, g_link_cmd) ; LEA_SYM(A1, q_sp_q) ; SX_CALL(strcat)
    LEA_SYM(A0, g_link_cmd) ; LD_LOCAL(A1, 0) ; SX_CALL(strcat)
    LEA_SYM(A0, g_link_cmd) ; LEA_SYM(A1, q_only) ; SX_CALL(strcat)

    /* Optional external library (.a / .so / .lib) */
    LEA_SYM(T0, g_opt_ext_lib) ; LD64(T1, T0, 0)
    CMPI(T1, 0) ; JEQ(.L_cf_no_ext)
    ST_LOCAL(T1, 2)
    LEA_SYM(A0, g_link_cmd) ; LEA_SYM(A1, sp_q) ; SX_CALL(strcat)
    LEA_SYM(A0, g_link_cmd) ; LD_LOCAL(A1, 2) ; SX_CALL(strcat)
    LEA_SYM(A0, g_link_cmd) ; LEA_SYM(A1, q_only) ; SX_CALL(strcat)

.L_cf_no_ext:
    LEA_SYM(A0, g_link_cmd) ; LEA_SYM(A1, sp_o_q) ; SX_CALL(strcat)
    LEA_SYM(A0, g_link_cmd) ; MOVR(A1, S1) ; SX_CALL(strcat)
    LEA_SYM(A0, g_link_cmd) ; LEA_SYM(A1, q_only) ; SX_CALL(strcat)

    LEA_SYM(A0, g_link_cmd)
    SX_CALL(system)
    CMPI(R0, 0) ; JEQ(.L_cf_x64_ok)
    MOVR(A1, R0) ; LEA_SYM(A0, err_link_fail) ; SX_VCALL(printf)
    MOVI(R0, 1) ; SX_EPILOGUE
.L_cf_x64_ok:
    LEA_SYM(A0, msg_emitted_bin) ; MOVR(A1, S1) ; SX_VCALL(printf)
    MOVI(R0, 0) ; SX_EPILOGUE

SX_RODATA
SX_STR(fmt_lnk_p1,   "clang -fuse-ld=lld %s")
SX_STR(sp_q,         " \"")
SX_STR(q_sp_q,       "\" \"")
SX_STR(q_only,       "\"")
SX_STR(sp_o_q,       " -o \"")
SX_STR(arm64_p1,     "clang --target=aarch64-w64-windows-gnu -c \"")
SX_STR(arm64_p2,     "\" -o \"")
SX_STR(arm64_p3,     ".o\"")
SX_TEXT

.L_cf_do_arm64:
    /* Custom ARM64 (AArch64) Code Generator */
    MOVR(A0, S4) ; SX_CALL(sx_codegen_arm64)
    MOVR(A0, S4) ; SX_CALL(fclose)

    LEA_SYM(T0, g_opt_emit_asm) ; LD64(T1, T0, 0)
    CMPI(T1, 0) ; JNE(.L_cf_ok)

    /* Assemble ARM64 .s -> .o using clang --target=aarch64 */
    LEA_SYM(A0, g_link_cmd) ; LEA_SYM(A1, arm64_p1) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_link_cmd) ; LEA_SYM(A1, g_asm_path) ; SX_CALL(strcat)
    LEA_SYM(A0, g_link_cmd) ; LEA_SYM(A1, arm64_p2) ; SX_CALL(strcat)
    LEA_SYM(A0, g_link_cmd) ; MOVR(A1, S1) ; SX_CALL(strcat)
    LEA_SYM(A0, g_link_cmd) ; LEA_SYM(A1, arm64_p3) ; SX_CALL(strcat)

    LEA_SYM(A0, g_link_cmd) ; SX_CALL(system)
    CMPI(R0, 0) ; JNE(.L_cf_fail)
    LEA_SYM(A0, msg_emitted_a64) ; MOVR(A1, S1) ; SX_VCALL(printf)
    MOVI(R0, 0) ; SX_EPILOGUE

.L_cf_emit_ll:
    /* LLVM IR (.ll) Code Generator */
    LEA_SYM(A0, g_asm_path) ; MOVI(A1, 512)
    LEA_SYM(A2, fmt_ll_path) ; MOVR(A3, S1)
    SX_VCALL(snprintf)

    LEA_SYM(A0, g_asm_path) ; LEA_SYM(A1, mode_w) ; SX_CALL(fopen)
    CMPI(R0, 0) ; JEQ(.L_cf_fail)
    MOVR(S4, R0)
    MOVR(A0, S4) ; SX_CALL(sx_codegen_llvm)
    MOVR(A0, S4) ; SX_CALL(fclose)
    LEA_SYM(A0, msg_emitted_ll) ; LEA_SYM(A1, g_asm_path) ; SX_VCALL(printf)

.L_cf_ok:
    MOVI(R0, 0) ; SX_EPILOGUE
.L_cf_fail:
    MOVI(R0, 1) ; SX_EPILOGUE
SX_ENDFUNC(sx_compile_file)
