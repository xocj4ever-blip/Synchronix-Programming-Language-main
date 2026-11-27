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
 * Full license text: ../LICENSE
 * End-User License Agreement: ../EULA.md
 */

/* ============================================================================
 * SYNCHRONIX — Unified Compiler & Ecosystem CLI Driver (src/main.S)
 * ============================================================================
 * Pure Portable Assembly (x86_64 & ARM64, Windows/Linux/macOS)
 * Strictly adheres to the complete SYNCHRONIX Architecture Diagram:
 *   Phase 1: Frontend (Lexer, Parser, Sema, Phi Formal Logic, Lambda)
 *   Phase 2: Middle-End (SUMIR, Ownership/Borrow, ARC, GC, Lifetime, Lowering)
 *   Phase 3: Backend (x86_64 / ARM64 / LLVM IR, RegAlloc, Sched, lld Linker)
 *   Foundation: Runtime & Stdlib (Unified ARC+GC, Arena, M:N Fibers, Phi/Lambda)
 *   Ecosystem: Cargo (new/build/run/test), LSP, Fmt/Lint, LLDB Debug & Profile
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(str_banner, "SYNCHRONIX v1.0.0 — High-Performance Native Language (Pure Portable Assembly)\nInfluenced by Swift (ARC & Safety) + Kotlin (GC & M:N Concurrency) + Phi/Lambda\n\nUsage:\n  synchronix compile <file.synchronix> [-o out] [--target x86_64|arm64|llvm]\n                                       [--emit-llvm] [--emit-asm] [--dump-ast]\n                                       [--dump-ir] [--link <ext.a|.lib>] [-g]\n  synchronix run [file.synchronix]     Build and execute native binary\n  synchronix new <project_name>        Scaffold Cargo-style Synchronix package\n  synchronix build [file.synchronix]   Build Synchronix package (Synchronix.toml)\n  synchronix test [file.synchronix]    Run Phi verification & test suite\n  synchronix fmt <file.synchronix>     Format .synchronix source canonically\n  synchronix lint <file.synchronix>    Run static safety & Phi linter\n  synchronix lsp                       Start Synchronix JSON-RPC Language Server\n  synchronix debug <file.synchronix>   Compile with DWARF -g & launch LLDB\n  synchronix profile <file.synchronix> Profile 3-phase compiler & native runtime\n  synchronix --version                 Show version & architecture info\n")

SX_STR(str_ver,       "synchronix 1.0.0 (pure-portable-assembly; backends: x86_64, arm64, llvm-ir)\n")
SX_STR(cmd_compile,   "compile")
SX_STR(cmd_run,       "run")
SX_STR(cmd_new,       "new")
SX_STR(cmd_build,     "build")
SX_STR(cmd_test,      "test")
SX_STR(cmd_fmt,       "fmt")
SX_STR(cmd_lint,      "lint")
SX_STR(cmd_lsp,       "lsp")
SX_STR(cmd_debug,     "debug")
SX_STR(cmd_profile,   "profile")
SX_STR(cmd_ver,       "--version")
SX_STR(cmd_help,      "--help")

SX_STR(opt_o,         "-o")
SX_STR(opt_target,    "--target")
SX_STR(opt_arm64,     "arm64")
SX_STR(opt_llvm,      "llvm")
SX_STR(opt_emit_llvm, "--emit-llvm")
SX_STR(opt_emit_asm,  "--emit-asm")
SX_STR(opt_dump_ast,  "--dump-ast")
SX_STR(opt_dump_ir,   "--dump-ir")
SX_STR(opt_link,      "--link")
SX_STR(opt_g,         "-g")

SX_STR(def_out_exe,   "a.exe")
SX_STR(err_miss_arg,  "[Synchronix] Error: missing required file or argument.\n")

SX_TEXT

/* ----------------------------------------------------------------------------
 * main(A0 = argc, A1 = argv) -> R0 = exit code
 * ----------------------------------------------------------------------------
 */
SX_FUNC(main)
    SX_PROLOGUE 48
    MOVR(S0, A0)                /* S0 = argc */
    MOVR(S1, A1)                /* S1 = argv */

    /* Reset global options */
    MOVI(T0, 0)
    LEA_SYM(T1, g_opt_target)   ; ST64(T0, T1, 0)
    LEA_SYM(T1, g_opt_dump_ast) ; ST64(T0, T1, 0)
    LEA_SYM(T1, g_opt_dump_ir)  ; ST64(T0, T1, 0)
    LEA_SYM(T1, g_opt_emit_asm) ; ST64(T0, T1, 0)
    LEA_SYM(T1, g_opt_debug)    ; ST64(T0, T1, 0)
    LEA_SYM(T1, g_opt_ext_lib)  ; ST64(T0, T1, 0)

    CMPI(S0, 2) ; JLT(.L_show_help)

    LD64(S2, S1, 8)             /* S2 = argv[1] (subcommand) */

    /* --version */
    MOVR(A0, S2) ; LEA_SYM(A1, cmd_ver) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_chk_help)
    LEA_SYM(A0, str_ver) ; SX_VCALL(printf)
    MOVI(R0, 0) ; SX_EPILOGUE

.L_chk_help:
    MOVR(A0, S2) ; LEA_SYM(A1, cmd_help) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JEQ(.L_show_help)

    /* lsp */
    MOVR(A0, S2) ; LEA_SYM(A1, cmd_lsp) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_chk_new)
    SX_CALL(sx_cmd_lsp)
    SX_EPILOGUE

.L_chk_new:
    MOVR(A0, S2) ; LEA_SYM(A1, cmd_new) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_chk_fmt)
    CMPI(S0, 3) ; JLT(.L_err_arg)
    LD64(A0, S1, 16)
    SX_CALL(sx_cmd_new)
    SX_EPILOGUE

.L_chk_fmt:
    MOVR(A0, S2) ; LEA_SYM(A1, cmd_fmt) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_chk_lint)
    CMPI(S0, 3) ; JLT(.L_err_arg)
    LD64(A0, S1, 16)
    SX_CALL(sx_cmd_fmt)
    SX_EPILOGUE

.L_chk_lint:
    MOVR(A0, S2) ; LEA_SYM(A1, cmd_lint) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_chk_dbg)
    CMPI(S0, 3) ; JLT(.L_err_arg)
    LD64(A0, S1, 16)
    SX_CALL(sx_cmd_lint)
    SX_EPILOGUE

.L_chk_dbg:
    MOVR(A0, S2) ; LEA_SYM(A1, cmd_debug) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_chk_prof)
    CMPI(S0, 3) ; JLT(.L_err_arg)
    LD64(A0, S1, 16)
    SX_CALL(sx_cmd_debug)
    SX_EPILOGUE

.L_chk_prof:
    MOVR(A0, S2) ; LEA_SYM(A1, cmd_profile) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_chk_run)
    CMPI(S0, 3) ; JLT(.L_err_arg)
    LD64(A0, S1, 16)
    SX_CALL(sx_cmd_profile)
    SX_EPILOGUE

.L_chk_run:
    MOVR(A0, S2) ; LEA_SYM(A1, cmd_run) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_chk_test)
    MOVI(A0, 0)
    CMPI(S0, 3) ; JLT(.L_do_run)
    LD64(A0, S1, 16)
.L_do_run:
    SX_CALL(sx_cmd_run)
    SX_EPILOGUE

.L_chk_test:
    MOVR(A0, S2) ; LEA_SYM(A1, cmd_test) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_chk_build)
    MOVI(A0, 0)
    CMPI(S0, 3) ; JLT(.L_do_test)
    LD64(A0, S1, 16)
.L_do_test:
    SX_CALL(sx_cmd_test)
    SX_EPILOGUE

.L_chk_build:
    MOVR(A0, S2) ; LEA_SYM(A1, cmd_build) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_chk_compile)
    MOVI(A0, 0) ; MOVI(A1, 0)
    CMPI(S0, 3) ; JLT(.L_do_build)
    LD64(A0, S1, 16)
.L_do_build:
    SX_CALL(sx_cmd_build)
    SX_EPILOGUE

.L_chk_compile:
    /* `synchronix compile <file> [flags...]` OR `synchronix <file> [flags...]` */
    MOVI(S3, 2)                 /* S3 = arg index to start scanning */
    MOVR(A0, S2) ; LEA_SYM(A1, cmd_compile) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JEQ(.L_parse_flags)
    MOVI(S3, 1)                 /* treat argv[1] directly as input file */

.L_parse_flags:
    MOVI(T0, 0) ; ST_LOCAL(T0, 0) /* local[0] = src_file */
    LEA_SYM(T0, def_out_exe) ; ST_LOCAL(T0, 1) /* local[1] = out_file */

.L_flg_loop:
    CMP(S3, S0) ; JGE(.L_flg_done)
    LD64_IDX(S4, S1, S3)        /* S4 = argv[S3] */

    /* -o <out> */
    MOVR(A0, S4) ; LEA_SYM(A1, opt_o) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_f_tgt)
    ADDI(S3, 1) ; CMP(S3, S0) ; JGE(.L_flg_done)
    LD64_IDX(T0, S1, S3) ; ST_LOCAL(T0, 1)
    JMP(.L_flg_next)

.L_f_tgt:
    /* --target x86_64|arm64|llvm */
    MOVR(A0, S4) ; LEA_SYM(A1, opt_target) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_f_ell)
    ADDI(S3, 1) ; CMP(S3, S0) ; JGE(.L_flg_done)
    LD64_IDX(S4, S1, S3)
    MOVR(A0, S4) ; LEA_SYM(A1, opt_arm64) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_f_tll)
    LEA_SYM(T0, g_opt_target) ; MOVI(T1, TARGET_ARM64) ; ST64(T1, T0, 0)
    JMP(.L_flg_next)
.L_f_tll:
    MOVR(A0, S4) ; LEA_SYM(A1, opt_llvm) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_flg_next)
    LEA_SYM(T0, g_opt_target) ; MOVI(T1, TARGET_LLVM_IR) ; ST64(T1, T0, 0)
    JMP(.L_flg_next)

.L_f_ell:
    MOVR(A0, S4) ; LEA_SYM(A1, opt_emit_llvm) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_f_easm)
    LEA_SYM(T0, g_opt_target) ; MOVI(T1, TARGET_LLVM_IR) ; ST64(T1, T0, 0)
    JMP(.L_flg_next)

.L_f_easm:
    MOVR(A0, S4) ; LEA_SYM(A1, opt_emit_asm) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_f_dast)
    LEA_SYM(T0, g_opt_emit_asm) ; MOVI(T1, 1) ; ST64(T1, T0, 0)
    JMP(.L_flg_next)

.L_f_dast:
    MOVR(A0, S4) ; LEA_SYM(A1, opt_dump_ast) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_f_dir)
    LEA_SYM(T0, g_opt_dump_ast) ; MOVI(T1, 1) ; ST64(T1, T0, 0)
    JMP(.L_flg_next)

.L_f_dir:
    MOVR(A0, S4) ; LEA_SYM(A1, opt_dump_ir) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_f_lnk)
    LEA_SYM(T0, g_opt_dump_ir) ; MOVI(T1, 1) ; ST64(T1, T0, 0)
    JMP(.L_flg_next)

.L_f_lnk:
    MOVR(A0, S4) ; LEA_SYM(A1, opt_link) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_f_dbg)
    ADDI(S3, 1) ; CMP(S3, S0) ; JGE(.L_flg_done)
    LD64_IDX(T0, S1, S3)
    LEA_SYM(T1, g_opt_ext_lib) ; ST64(T0, T1, 0)
    JMP(.L_flg_next)

.L_f_dbg:
    MOVR(A0, S4) ; LEA_SYM(A1, opt_g) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JNE(.L_f_src)
    LEA_SYM(T0, g_opt_debug) ; MOVI(T1, 1) ; ST64(T1, T0, 0)
    JMP(.L_flg_next)

.L_f_src:
    ST_LOCAL(S4, 0)

.L_flg_next:
    ADDI(S3, 1)
    JMP(.L_flg_loop)

.L_flg_done:
    LD_LOCAL(A0, 0)
    CMPI(A0, 0) ; JEQ(.L_err_arg)
    LD_LOCAL(A1, 1)
    SX_CALL(sx_compile_file)
    SX_EPILOGUE

.L_err_arg:
    LEA_SYM(A0, err_miss_arg) ; SX_VCALL(printf)
    MOVI(R0, 1) ; SX_EPILOGUE

.L_show_help:
    LEA_SYM(A0, str_banner) ; SX_VCALL(printf)
    MOVI(R0, 0) ; SX_EPILOGUE
SX_ENDFUNC(main)
