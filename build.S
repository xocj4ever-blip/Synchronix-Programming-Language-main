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
 * Full license text: LICENSE
 * End-User License Agreement: EULA.md
 */

/* ============================================================================
 * SYNCHRONIX — Pure Portable Assembly Build System & Cross-Target Verifier
 * ============================================================================
 * Replaces BOTH build.ps1 AND Makefile with 100% Pure Portable Assembly
 * (zero PowerShell, Make, or shell scripts). Uses the unified Synchronix
 * Portable Assembly ISA Layer (include/portable_asm.S) and works across:
 *   - x86_64  (Windows PE/COFF Win64 ABI, Linux ELF SysV ABI, macOS Mach-O)
 *   - ARM64   (Windows PE/COFF ARM64, Linux ELF AArch64, macOS Mach-O ARM64)
 *
 * Bootstrap & Run:
 *   Windows : clang -Iinclude -fuse-ld=lld build.S -o build/sx_build.exe
 *             .\build\sx_build.exe [all|build|runtime|compiler|verify|clean|help]
 *   Unix    : clang -Iinclude -fuse-ld=lld build.S -o build/sx_build
 *             ./build/sx_build [all|build|runtime|compiler|verify|clean|help]
 *
 * Environment Overrides (same as former Makefile):
 *   CC      (default: clang)
 *   AR      (default: llvm-ar)
 *   CFLAGS  (default: empty; -I "<root>/include" is always supplied)
 *   LDFLAGS (default: -fuse-ld=lld)
 * ============================================================================
 */

#include "portable_asm.S"

/* Target action bitmask flags */
#define ACT_RUNTIME   1
#define ACT_COMPILER  2
#define ACT_VERIFY    4
#define ACT_CLEAN     8
#define ACT_HELP      16

SX_RODATA

/* Double-NUL-terminated source tables (zero relocations -> 100% PIC-safe) */
SX_LABEL(tbl_rt_sources)
    .asciz "src/runtime/memory_rt.S"
    .asciz "src/runtime/async_rt.S"
    .asciz "src/runtime/phi_lambda_rt.S"
    .asciz "src/runtime/stdlib.S"
    .byte 0

SX_LABEL(tbl_compiler_sources)
    .asciz "src/frontend/utils.S"
    .asciz "src/frontend/lexer.S"
    .asciz "src/frontend/parser.S"
    .asciz "src/frontend/sema.S"
    .asciz "src/middle/ir_gen.S"
    .asciz "src/middle/mem_safety.S"
    .asciz "src/middle/phi_lambda_opt.S"
    .asciz "src/middle/lowering.S"
    .asciz "src/backend/target_opt.S"
    .asciz "src/backend/codegen.S"
    .asciz "src/backend/emitter.S"
    .asciz "src/tooling/cargo_pkg.S"
    .asciz "src/tooling/fmt_lint.S"
    .asciz "src/tooling/lsp.S"
    .asciz "src/tooling/debug_prof.S"
    .asciz "src/main.S"
    .byte 0

SX_LABEL(tbl_builder_sources)
    .asciz "build.S"
    .byte 0

SX_LABEL(tbl_verify_triples)
    .asciz "aarch64-w64-windows-gnu"
    .asciz "x86_64-pc-linux-gnu"
    .asciz "aarch64-apple-darwin"
    .byte 0

/* Environment variable names & defaults */
SX_STR(env_cc,             "CC")
SX_STR(env_ar,             "AR")
SX_STR(env_cflags,         "CFLAGS")
SX_STR(env_ldflags,        "LDFLAGS")

SX_STR(def_cc,             "clang")
SX_STR(def_ar,             "llvm-ar")
SX_STR(def_cflags,         "")
SX_STR(def_ldflags,        "-fuse-ld=lld")

/* CLI subcommands & flags */
SX_STR(cmd_all,            "all")
SX_STR(cmd_build,          "build")
SX_STR(cmd_runtime,        "runtime")
SX_STR(cmd_compiler,       "compiler")
SX_STR(cmd_verify,         "verify")
SX_STR(cmd_clean,          "clean")
SX_STR(cmd_help,           "help")
SX_STR(flag_help1,         "--help")
SX_STR(flag_help2,         "-h")
SX_STR(flag_noverify,      "--no-verify")

/* Path & command string fragments */
SX_STR(str_dot,            ".")
SX_STR(str_dotdot,         "..")
SX_STR(str_mode_rb,        "rb")
SX_STR(str_probe_rel,      "/include/portable_asm.S")
SX_STR(str_slash,          "/")
SX_STR(str_space,          " ")
SX_STR(str_underscore,     "_")
SX_STR(str_ext_o,          ".o")
SX_STR(str_dir_include,    "/include")
SX_STR(str_dir_build,      "/build")
SX_STR(str_dir_xverify,    "/build/cross_verify")
SX_STR(str_rt_lib_rel,     "/build/libsynchronix_rt.a")
#if defined(_WIN32) || defined(__MINGW32__) || defined(__MINGW64__)
SX_STR(str_exe_rel,        "/build/synchronix.exe")
#else
SX_STR(str_exe_rel,        "/build/synchronix")
#endif

SX_STR(str_sp_tgt_eq,      " --target=")
SX_STR(str_sp_inc_q,       " -I \"")
SX_STR(str_q_c_q,          "\" -c \"")
SX_STR(str_q_o_q,          "\" -o \"")
SX_STR(str_q,              "\"")
SX_STR(str_sp_q,           " \"")
SX_STR(str_sp_rcs_q,       " rcs \"")
SX_STR(str_sp_o_q,         " -o \"")

/* Help text */
SX_STR(msg_help,           "SYNCHRONIX Pure Portable Assembly Build System (build.S)\n\nUsage: sx_build [target]\n  (default)   Build runtime + compiler + cross-target verification\n  all         Build runtime (libsynchronix_rt.a) and compiler (synchronix)\n  build       Alias for 'all'\n  runtime     Assemble & archive build/libsynchronix_rt.a only\n  compiler    Assemble & link build/synchronix(.exe) only\n  verify      Build all & verify all 21 .S units across ARM64/x86_64/ELF/Mach-O\n  clean       Remove generated objects, archives, compiler, and cross_verify/\n  --no-verify Skip cross-target verification step\n  help        Show this message\n\nEnvironment overrides: CC (clang), AR (llvm-ar), CFLAGS, LDFLAGS (-fuse-ld=lld)")

/* Status & diagnostic messages */
SX_STR(msg_step1,          "[1/4] Assembling Synchronix Runtime (Pure Portable Assembly)...")
SX_STR(msg_step2,          "[2/4] Assembling Synchronix Compiler & Ecosystem Tooling (Pure Portable Assembly)...")
#if defined(_WIN32) || defined(__MINGW32__) || defined(__MINGW64__)
SX_STR(msg_step3,          "[3/4] Linking synchronix.exe with LLD...")
#else
SX_STR(msg_step3,          "[3/4] Linking synchronix with LLD...")
#endif
SX_STR(msg_step4,          "[4/4] Verifying Portable Assembly across ARM64 (Win64), x86_64 (Linux ELF), ARM64 (macOS Mach-O)...")
SX_STR(msg_verify_ok_pfx,  "  [OK] All 21 pure assembly units assembled cleanly for ")
SX_STR(msg_clean_pfx,      "[clean] Removed build artifacts from ")
SX_STR(msg_empty,          "")
SX_STR(msg_success,        "SUCCESS! Built:")
SX_STR(msg_compiler_pfx,   "  Compiler : ")
SX_STR(msg_runtime_pfx,    "  Runtime  : ")

SX_STR(err_asm_pfx,        "ERROR: Failed assembling ")
SX_STR(err_ar_fail,        "ERROR: Failed archiving libsynchronix_rt.a")
SX_STR(err_link_fail,      "ERROR: Failed linking synchronix")
SX_STR(err_port_pfx,       "ERROR: Portability check FAILED for ")
SX_STR(err_port_on,        " on ")
SX_STR(err_unknown_pfx,    "ERROR: Unknown target/option: ")

SX_BSS
.p2align 4
/* Toolchain pointers (resolved from env or defaults) */
SX_LABEL(g_cc_bin)
    .skip 8
SX_LABEL(g_ar_bin)
    .skip 8
SX_LABEL(g_extra_cflags)
    .skip 8
SX_LABEL(g_ldflags)
    .skip 8

/* Path & command buffers */
SX_LABEL(g_root_dir)
    .skip 1024
SX_LABEL(g_inc_dir)
    .skip 1024
SX_LABEL(g_bld_dir)
    .skip 1024
SX_LABEL(g_xverify_dir)
    .skip 1024
SX_LABEL(g_probe_path)
    .skip 1024
SX_LABEL(g_stem_buf)
    .skip 256
SX_LABEL(g_obj_path)
    .skip 1024
SX_LABEL(g_src_path)
    .skip 1024
SX_LABEL(g_exe_path)
    .skip 1024
SX_LABEL(g_rt_path)
    .skip 1024
SX_LABEL(g_msg_buf)
    .skip 1024
SX_LABEL(g_cmd_buf)
    .skip 4096
SX_LABEL(g_ar_cmd)
    .skip 8192
SX_LABEL(g_link_cmd)
    .skip 16384

SX_TEXT

/* ----------------------------------------------------------------------------
 * sx_env_or_default(A0 = env_name, A1 = default_cstr) -> R0 = cstr
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_env_or_default)
    SX_PROLOGUE 16
    MOVR(S0, A1)                /* S0 = default */
    SX_CALL(getenv)
    CMPI(R0, 0) ; JEQ(.L_eod_def)
    MOVR(S1, R0)
    LD8_R0(S1, 0)
    CMPI(R0, 0) ; JEQ(.L_eod_def)
    MOVR(R0, S1)
    SX_EPILOGUE
.L_eod_def:
    MOVR(R0, S0)
    SX_EPILOGUE
SX_ENDFUNC(sx_env_or_default)

/* ----------------------------------------------------------------------------
 * sx_load_toolchain_env()
 * Resolves CC, AR, CFLAGS, LDFLAGS from environment with Makefile defaults.
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_load_toolchain_env)
    SX_PROLOGUE 16
    LEA_SYM(A0, env_cc)      ; LEA_SYM(A1, def_cc)      ; SX_CALL(sx_env_or_default)
    LEA_SYM(T0, g_cc_bin)    ; ST64(R0, T0, 0)

    LEA_SYM(A0, env_ar)      ; LEA_SYM(A1, def_ar)      ; SX_CALL(sx_env_or_default)
    LEA_SYM(T0, g_ar_bin)    ; ST64(R0, T0, 0)

    LEA_SYM(A0, env_cflags)  ; LEA_SYM(A1, def_cflags)  ; SX_CALL(sx_env_or_default)
    LEA_SYM(T0, g_extra_cflags) ; ST64(R0, T0, 0)

    LEA_SYM(A0, env_ldflags) ; LEA_SYM(A1, def_ldflags) ; SX_CALL(sx_env_or_default)
    LEA_SYM(T0, g_ldflags)   ; ST64(R0, T0, 0)

    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_load_toolchain_env)

/* ----------------------------------------------------------------------------
 * sx_ensure_dir(A0 = dir_path) -> R0 = 0
 * Cross-platform native directory creation (_mkdir on Windows, mkdir on POSIX)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_ensure_dir)
    SX_PROLOGUE 16
#if defined(_WIN32) || defined(__MINGW32__) || defined(__MINGW64__)
    SX_CALL(_mkdir)
#else
    MOVI(A1, 493)               /* 0755 octal */
    SX_CALL(mkdir)
#endif
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_ensure_dir)

/* ----------------------------------------------------------------------------
 * sx_remove_dir(A0 = dir_path) -> R0 = 0
 * Cross-platform native empty directory removal (_rmdir on Windows, rmdir on POSIX)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_remove_dir)
    SX_PROLOGUE 16
#if defined(_WIN32) || defined(__MINGW32__) || defined(__MINGW64__)
    SX_CALL(_rmdir)
#else
    SX_CALL(rmdir)
#endif
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_remove_dir)

/* ----------------------------------------------------------------------------
 * sx_probe_root(A0 = candidate_dir) -> R0 = 1 if candidate/include/portable_asm.S exists
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_probe_root)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    LEA_SYM(A0, g_probe_path) ; MOVR(A1, S0) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_probe_path) ; LEA_SYM(A1, str_probe_rel) ; SX_CALL(strcat)
    LEA_SYM(A0, g_probe_path) ; LEA_SYM(A1, str_mode_rb) ; SX_CALL(fopen)
    CMPI(R0, 0) ; JEQ(.L_pr_no)
    MOVR(A0, R0) ; SX_CALL(fclose)
    MOVI(R0, 1)
    SX_EPILOGUE
.L_pr_no:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_probe_root)

/* ----------------------------------------------------------------------------
 * sx_strip_path_component(A0 = mutable_path_buf) -> R0 = 1 if stripped, 0 if no slash
 * Strips trailing basename (after last '/' or '\') in place.
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_strip_path_component)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    SX_CALL(strlen)
    MOVR(S1, R0)
.L_spc_loop:
    CMPI(S1, 0) ; JLE(.L_spc_none)
    SUBI(S1, 1)
    LD8_IDX_R0(S0, S1)
    CMPI(R0, 47) ; JEQ(.L_spc_found)   /* '/' */
    CMPI(R0, 92) ; JEQ(.L_spc_found)   /* '\' */
    JMP(.L_spc_loop)
.L_spc_found:
    MOVI(R0, 0)
    ST8_IDX_R0(S0, S1)
    MOVI(R0, 1)
    SX_EPILOGUE
.L_spc_none:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_strip_path_component)

/* ----------------------------------------------------------------------------
 * sx_detect_root(A0 = argv0_or_0)
 * Populates g_root_dir, g_inc_dir, g_bld_dir, g_xverify_dir, g_exe_path, g_rt_path
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_detect_root)
    SX_PROLOGUE 16
    MOVR(S0, A0)

    /* 1. Try current working directory "." */
    LEA_SYM(A0, str_dot) ; SX_CALL(sx_probe_root)
    CMPI(R0, 0) ; JEQ(.L_dr_try_parent)
    LEA_SYM(A0, g_root_dir) ; LEA_SYM(A1, str_dot) ; SX_CALL(strcpy)
    JMP(.L_dr_build_paths)

.L_dr_try_parent:
    /* 2. Try parent directory ".." */
    LEA_SYM(A0, str_dotdot) ; SX_CALL(sx_probe_root)
    CMPI(R0, 0) ; JEQ(.L_dr_try_argv0)
    LEA_SYM(A0, g_root_dir) ; LEA_SYM(A1, str_dotdot) ; SX_CALL(strcpy)
    JMP(.L_dr_build_paths)

.L_dr_try_argv0:
    /* 3. Derive directory from argv[0] (and its parent if inside build/) */
    CMPI(S0, 0) ; JEQ(.L_dr_fallback)
    LEA_SYM(A0, g_root_dir) ; MOVR(A1, S0) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_root_dir) ; SX_CALL(sx_strip_path_component)
    CMPI(R0, 0) ; JEQ(.L_dr_fallback)
    LEA_SYM(A0, g_root_dir) ; SX_CALL(sx_probe_root)
    CMPI(R0, 0) ; JNE(.L_dr_build_paths)
    LEA_SYM(A0, g_root_dir) ; SX_CALL(sx_strip_path_component)
    CMPI(R0, 0) ; JEQ(.L_dr_fallback)
    LEA_SYM(A0, g_root_dir) ; SX_CALL(sx_probe_root)
    CMPI(R0, 0) ; JNE(.L_dr_build_paths)

.L_dr_fallback:
    LEA_SYM(A0, g_root_dir) ; LEA_SYM(A1, str_dot) ; SX_CALL(strcpy)

.L_dr_build_paths:
    LEA_SYM(A0, g_inc_dir) ; LEA_SYM(A1, g_root_dir) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_inc_dir) ; LEA_SYM(A1, str_dir_include) ; SX_CALL(strcat)

    LEA_SYM(A0, g_bld_dir) ; LEA_SYM(A1, g_root_dir) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_bld_dir) ; LEA_SYM(A1, str_dir_build) ; SX_CALL(strcat)

    LEA_SYM(A0, g_xverify_dir) ; LEA_SYM(A1, g_root_dir) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_xverify_dir) ; LEA_SYM(A1, str_dir_xverify) ; SX_CALL(strcat)

    LEA_SYM(A0, g_exe_path) ; LEA_SYM(A1, g_root_dir) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_exe_path) ; LEA_SYM(A1, str_exe_rel) ; SX_CALL(strcat)

    LEA_SYM(A0, g_rt_path) ; LEA_SYM(A1, g_root_dir) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_rt_path) ; LEA_SYM(A1, str_rt_lib_rel) ; SX_CALL(strcat)

    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_detect_root)

/* ----------------------------------------------------------------------------
 * sx_path_stem(A0 = rel_src_path, A1 = out_stem_buf)
 * Extracts filename without directory prefix or extension (e.g. "src/main.S" -> "main")
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_path_stem)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    MOVR(S1, A1)
    MOVR(S2, S0)
    MOVI(S3, 0)

.L_ps_find_base:
    LD8_IDX_R0(S0, S3)
    CMPI(R0, 0) ; JEQ(.L_ps_copy_start)
    CMPI(R0, 47) ; JEQ(.L_ps_mark)     /* '/' */
    CMPI(R0, 92) ; JEQ(.L_ps_mark)     /* '\' */
    JMP(.L_ps_next)
.L_ps_mark:
    MOVR(S2, S0)
    ADD(S2, S3)
    ADDI(S2, 1)
.L_ps_next:
    ADDI(S3, 1)
    JMP(.L_ps_find_base)

.L_ps_copy_start:
    MOVI(S3, 0)
.L_ps_copy_loop:
    LD8_IDX_R0(S2, S3)
    CMPI(R0, 0)  ; JEQ(.L_ps_done)
    CMPI(R0, 46) ; JEQ(.L_ps_done)     /* '.' */
    ST8_IDX_R0(S1, S3)
    ADDI(S3, 1)
    JMP(.L_ps_copy_loop)

.L_ps_done:
    MOVI(R0, 0)
    ST8_IDX_R0(S1, S3)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_path_stem)

/* ----------------------------------------------------------------------------
 * sx_append_opt_flag(A0 = dst_cmd_buf, A1 = opt_flag_cstr)
 * Appends ` <opt_flag_cstr>` to dst_cmd_buf if opt_flag_cstr is non-empty.
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_append_opt_flag)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    MOVR(S1, A1)
    CMPI(S1, 0) ; JEQ(.L_aof_done)
    LD8_R0(S1, 0)
    CMPI(R0, 0) ; JEQ(.L_aof_done)
    MOVR(A0, S0) ; LEA_SYM(A1, str_space) ; SX_CALL(strcat)
    MOVR(A0, S0) ; MOVR(A1, S1)           ; SX_CALL(strcat)
.L_aof_done:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_append_opt_flag)

/* ----------------------------------------------------------------------------
 * sx_assemble_list(A0 = src_table, A1 = accum_cmd_buf) -> R0 = 0 on success, 1 on fail
 * Assembles every .S unit in src_table to <root>/build/<stem>.o using CC/CFLAGS
 * and appends ` "<obj>"` to accum_cmd_buf.
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_assemble_list)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    MOVR(S1, A1)

.L_al_loop:
    LD8_R0(S0, 0)
    CMPI(R0, 0) ; JEQ(.L_al_ok)

    MOVR(A0, S0) ; LEA_SYM(A1, g_stem_buf) ; SX_CALL(sx_path_stem)

    /* g_src_path = <root>/<src> */
    LEA_SYM(A0, g_src_path) ; LEA_SYM(A1, g_root_dir) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_src_path) ; LEA_SYM(A1, str_slash)  ; SX_CALL(strcat)
    LEA_SYM(A0, g_src_path) ; MOVR(A1, S0)            ; SX_CALL(strcat)

    /* g_obj_path = <root>/build/<stem>.o */
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, g_bld_dir)  ; SX_CALL(strcpy)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, str_slash)  ; SX_CALL(strcat)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, g_stem_buf) ; SX_CALL(strcat)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, str_ext_o)  ; SX_CALL(strcat)

    /* g_cmd_buf = <CC> [CFLAGS] -I "<inc>" -c "<src>" -o "<obj>" */
    LEA_SYM(T0, g_cc_bin) ; LD64(A1, T0, 0)
    LEA_SYM(A0, g_cmd_buf) ; SX_CALL(strcpy)
    LEA_SYM(T0, g_extra_cflags) ; LD64(A1, T0, 0)
    LEA_SYM(A0, g_cmd_buf) ; SX_CALL(sx_append_opt_flag)
    LEA_SYM(A0, g_cmd_buf) ; LEA_SYM(A1, str_sp_inc_q) ; SX_CALL(strcat)
    LEA_SYM(A0, g_cmd_buf) ; LEA_SYM(A1, g_inc_dir)    ; SX_CALL(strcat)
    LEA_SYM(A0, g_cmd_buf) ; LEA_SYM(A1, str_q_c_q)    ; SX_CALL(strcat)
    LEA_SYM(A0, g_cmd_buf) ; LEA_SYM(A1, g_src_path)   ; SX_CALL(strcat)
    LEA_SYM(A0, g_cmd_buf) ; LEA_SYM(A1, str_q_o_q)    ; SX_CALL(strcat)
    LEA_SYM(A0, g_cmd_buf) ; LEA_SYM(A1, g_obj_path)   ; SX_CALL(strcat)
    LEA_SYM(A0, g_cmd_buf) ; LEA_SYM(A1, str_q)        ; SX_CALL(strcat)

    LEA_SYM(A0, g_cmd_buf) ; SX_CALL(system)
    CMPI(R0, 0) ; JNE(.L_al_fail)

    /* Append ` "<obj>"` to accumulator command */
    MOVR(A0, S1) ; LEA_SYM(A1, str_sp_q)   ; SX_CALL(strcat)
    MOVR(A0, S1) ; LEA_SYM(A1, g_obj_path) ; SX_CALL(strcat)
    MOVR(A0, S1) ; LEA_SYM(A1, str_q)      ; SX_CALL(strcat)

    MOVR(A0, S0) ; SX_CALL(strlen)
    ADD(S0, R0)
    ADDI(S0, 1)
    JMP(.L_al_loop)

.L_al_fail:
    LEA_SYM(A0, g_msg_buf) ; LEA_SYM(A1, err_asm_pfx) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_msg_buf) ; MOVR(A1, S0)             ; SX_CALL(strcat)
    LEA_SYM(A0, g_msg_buf) ; SX_CALL(puts)
    MOVI(R0, 1)
    SX_EPILOGUE

.L_al_ok:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_assemble_list)

/* ----------------------------------------------------------------------------
 * sx_verify_list(A0 = src_table, A1 = target_triple) -> R0 = 0 on success, 1 on fail
 * Cross-assembles every .S unit in src_table for target_triple into build/cross_verify/
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_verify_list)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    MOVR(S1, A1)

.L_vl_loop:
    LD8_R0(S0, 0)
    CMPI(R0, 0) ; JEQ(.L_vl_ok)

    MOVR(A0, S0) ; LEA_SYM(A1, g_stem_buf) ; SX_CALL(sx_path_stem)

    /* g_src_path = <root>/<src> */
    LEA_SYM(A0, g_src_path) ; LEA_SYM(A1, g_root_dir) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_src_path) ; LEA_SYM(A1, str_slash)  ; SX_CALL(strcat)
    LEA_SYM(A0, g_src_path) ; MOVR(A1, S0)            ; SX_CALL(strcat)

    /* g_obj_path = <root>/build/cross_verify/<stem>_<triple>.o */
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, g_xverify_dir)  ; SX_CALL(strcpy)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, str_slash)      ; SX_CALL(strcat)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, g_stem_buf)     ; SX_CALL(strcat)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, str_underscore) ; SX_CALL(strcat)
    LEA_SYM(A0, g_obj_path) ; MOVR(A1, S1)                ; SX_CALL(strcat)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, str_ext_o)      ; SX_CALL(strcat)

    /* g_cmd_buf = <CC> --target=<triple> [CFLAGS] -I "<inc>" -c "<src>" -o "<obj>" */
    LEA_SYM(T0, g_cc_bin) ; LD64(A1, T0, 0)
    LEA_SYM(A0, g_cmd_buf) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_cmd_buf) ; LEA_SYM(A1, str_sp_tgt_eq) ; SX_CALL(strcat)
    LEA_SYM(A0, g_cmd_buf) ; MOVR(A1, S1)               ; SX_CALL(strcat)
    LEA_SYM(T0, g_extra_cflags) ; LD64(A1, T0, 0)
    LEA_SYM(A0, g_cmd_buf) ; SX_CALL(sx_append_opt_flag)
    LEA_SYM(A0, g_cmd_buf) ; LEA_SYM(A1, str_sp_inc_q)  ; SX_CALL(strcat)
    LEA_SYM(A0, g_cmd_buf) ; LEA_SYM(A1, g_inc_dir)     ; SX_CALL(strcat)
    LEA_SYM(A0, g_cmd_buf) ; LEA_SYM(A1, str_q_c_q)     ; SX_CALL(strcat)
    LEA_SYM(A0, g_cmd_buf) ; LEA_SYM(A1, g_src_path)    ; SX_CALL(strcat)
    LEA_SYM(A0, g_cmd_buf) ; LEA_SYM(A1, str_q_o_q)     ; SX_CALL(strcat)
    LEA_SYM(A0, g_cmd_buf) ; LEA_SYM(A1, g_obj_path)    ; SX_CALL(strcat)
    LEA_SYM(A0, g_cmd_buf) ; LEA_SYM(A1, str_q)         ; SX_CALL(strcat)

    LEA_SYM(A0, g_cmd_buf) ; SX_CALL(system)
    CMPI(R0, 0) ; JNE(.L_vl_fail)

    MOVR(A0, S0) ; SX_CALL(strlen)
    ADD(S0, R0)
    ADDI(S0, 1)
    JMP(.L_vl_loop)

.L_vl_fail:
    LEA_SYM(A0, g_msg_buf) ; LEA_SYM(A1, err_port_pfx) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_msg_buf) ; MOVR(A1, S0)              ; SX_CALL(strcat)
    LEA_SYM(A0, g_msg_buf) ; LEA_SYM(A1, err_port_on)  ; SX_CALL(strcat)
    LEA_SYM(A0, g_msg_buf) ; MOVR(A1, S1)              ; SX_CALL(strcat)
    LEA_SYM(A0, g_msg_buf) ; SX_CALL(puts)
    MOVI(R0, 1)
    SX_EPILOGUE

.L_vl_ok:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_verify_list)

/* ----------------------------------------------------------------------------
 * sx_clean_objs(A0 = src_table)
 * Deletes <root>/build/<stem>.o for every entry in src_table.
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_clean_objs)
    SX_PROLOGUE 16
    MOVR(S0, A0)
.L_co_loop:
    LD8_R0(S0, 0)
    CMPI(R0, 0) ; JEQ(.L_co_done)
    MOVR(A0, S0) ; LEA_SYM(A1, g_stem_buf) ; SX_CALL(sx_path_stem)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, g_bld_dir)  ; SX_CALL(strcpy)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, str_slash)  ; SX_CALL(strcat)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, g_stem_buf) ; SX_CALL(strcat)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, str_ext_o)  ; SX_CALL(strcat)
    LEA_SYM(A0, g_obj_path) ; SX_CALL(remove)
    MOVR(A0, S0) ; SX_CALL(strlen)
    ADD(S0, R0)
    ADDI(S0, 1)
    JMP(.L_co_loop)
.L_co_done:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_clean_objs)

/* ----------------------------------------------------------------------------
 * sx_clean_verify_objs(A0 = src_table, A1 = target_triple)
 * Deletes <root>/build/cross_verify/<stem>_<triple>.o for every entry in src_table.
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_clean_verify_objs)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    MOVR(S1, A1)
.L_cvo_loop:
    LD8_R0(S0, 0)
    CMPI(R0, 0) ; JEQ(.L_cvo_done)
    MOVR(A0, S0) ; LEA_SYM(A1, g_stem_buf) ; SX_CALL(sx_path_stem)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, g_xverify_dir)  ; SX_CALL(strcpy)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, str_slash)      ; SX_CALL(strcat)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, g_stem_buf)     ; SX_CALL(strcat)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, str_underscore) ; SX_CALL(strcat)
    LEA_SYM(A0, g_obj_path) ; MOVR(A1, S1)                ; SX_CALL(strcat)
    LEA_SYM(A0, g_obj_path) ; LEA_SYM(A1, str_ext_o)      ; SX_CALL(strcat)
    LEA_SYM(A0, g_obj_path) ; SX_CALL(remove)
    MOVR(A0, S0) ; SX_CALL(strlen)
    ADD(S0, R0)
    ADDI(S0, 1)
    JMP(.L_cvo_loop)
.L_cvo_done:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_clean_verify_objs)

/* ----------------------------------------------------------------------------
 * sx_do_clean() -> R0 = 0
 * Native pure-assembly equivalent of `make clean` (no shell rm -rf).
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_do_clean)
    SX_PROLOGUE 16
    LEA_SYM(A0, tbl_rt_sources)       ; SX_CALL(sx_clean_objs)
    LEA_SYM(A0, tbl_compiler_sources) ; SX_CALL(sx_clean_objs)
    LEA_SYM(A0, tbl_builder_sources)  ; SX_CALL(sx_clean_objs)

    LEA_SYM(S0, tbl_verify_triples)
.L_cln_tr_loop:
    LD8_R0(S0, 0)
    CMPI(R0, 0) ; JEQ(.L_cln_tr_done)
    LEA_SYM(A0, tbl_rt_sources)       ; MOVR(A1, S0) ; SX_CALL(sx_clean_verify_objs)
    LEA_SYM(A0, tbl_compiler_sources) ; MOVR(A1, S0) ; SX_CALL(sx_clean_verify_objs)
    LEA_SYM(A0, tbl_builder_sources)  ; MOVR(A1, S0) ; SX_CALL(sx_clean_verify_objs)
    MOVR(A0, S0) ; SX_CALL(strlen)
    ADD(S0, R0)
    ADDI(S0, 1)
    JMP(.L_cln_tr_loop)

.L_cln_tr_done:
    LEA_SYM(A0, g_xverify_dir) ; SX_CALL(sx_remove_dir)
    LEA_SYM(A0, g_rt_path)     ; SX_CALL(remove)
    LEA_SYM(A0, g_exe_path)    ; SX_CALL(remove)

    LEA_SYM(A0, g_msg_buf) ; LEA_SYM(A1, msg_clean_pfx) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_msg_buf) ; LEA_SYM(A1, g_bld_dir)     ; SX_CALL(strcat)
    LEA_SYM(A0, g_msg_buf) ; SX_CALL(puts)

    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_do_clean)

/* ----------------------------------------------------------------------------
 * main(A0 = argc, A1 = argv) -> R0 = 0 on success, 1 on failure
 * ----------------------------------------------------------------------------
 */
SX_FUNC(main)
    SX_PROLOGUE 32
    MOVR(S0, A0)                /* S0 = argc */
    MOVR(S1, A1)                /* S1 = argv */
    MOVI(S2, 0)                 /* S2 = action bitmask */

    /* Default action (no args): runtime + compiler + verify */
    CMPI(S0, 2) ; JGE(.L_parse_args)
    MOVI(S2, ACT_RUNTIME + ACT_COMPILER + ACT_VERIFY)
    JMP(.L_args_done)

.L_parse_args:
    MOVI(S3, 1)
.L_arg_loop:
    CMP(S3, S0) ; JGE(.L_args_done)
    LD64_IDX(S4, S1, S3)        /* S4 = argv[S3] */

    MOVR(A0, S4) ; LEA_SYM(A1, cmd_help)     ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JEQ(.L_set_help)
    MOVR(A0, S4) ; LEA_SYM(A1, flag_help1)   ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JEQ(.L_set_help)
    MOVR(A0, S4) ; LEA_SYM(A1, flag_help2)   ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JEQ(.L_set_help)

    MOVR(A0, S4) ; LEA_SYM(A1, cmd_all)      ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JEQ(.L_set_all)
    MOVR(A0, S4) ; LEA_SYM(A1, cmd_build)    ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JEQ(.L_set_all)
    MOVR(A0, S4) ; LEA_SYM(A1, flag_noverify) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JEQ(.L_set_all)

    MOVR(A0, S4) ; LEA_SYM(A1, cmd_runtime)  ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JEQ(.L_set_rt)

    MOVR(A0, S4) ; LEA_SYM(A1, cmd_compiler) ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JEQ(.L_set_comp)

    MOVR(A0, S4) ; LEA_SYM(A1, cmd_verify)   ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JEQ(.L_set_verify)

    MOVR(A0, S4) ; LEA_SYM(A1, cmd_clean)    ; SX_CALL(strcmp)
    CMPI(R0, 0) ; JEQ(.L_set_clean)

    /* Unknown argument */
    LEA_SYM(A0, g_msg_buf) ; LEA_SYM(A1, err_unknown_pfx) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_msg_buf) ; MOVR(A1, S4)                 ; SX_CALL(strcat)
    LEA_SYM(A0, g_msg_buf) ; SX_CALL(puts)
    JMP(.L_fail)

.L_set_help:
    ORI(S2, ACT_HELP)
    JMP(.L_arg_next)
.L_set_all:
    ORI(S2, ACT_RUNTIME + ACT_COMPILER)
    JMP(.L_arg_next)
.L_set_rt:
    ORI(S2, ACT_RUNTIME)
    JMP(.L_arg_next)
.L_set_comp:
    ORI(S2, ACT_COMPILER)
    JMP(.L_arg_next)
.L_set_verify:
    ORI(S2, ACT_RUNTIME + ACT_COMPILER + ACT_VERIFY)
    JMP(.L_arg_next)
.L_set_clean:
    ORI(S2, ACT_CLEAN)
.L_arg_next:
    ADDI(S3, 1)
    JMP(.L_arg_loop)

.L_args_done:
    /* Handle help immediately */
    MOVR(T0, S2) ; ANDI(T0, ACT_HELP)
    CMPI(T0, 0) ; JEQ(.L_init_env)
    LEA_SYM(A0, msg_help) ; SX_CALL(puts)
    MOVI(R0, 0)
    SX_EPILOGUE

.L_init_env:
    /* Load CC / AR / CFLAGS / LDFLAGS & locate root directory */
    SX_CALL(sx_load_toolchain_env)

    MOVI(A0, 0)
    CMPI(S0, 1) ; JLT(.L_call_detect)
    LD64(A0, S1, 0)
.L_call_detect:
    SX_CALL(sx_detect_root)

    /* Run clean first if requested (supports `sx_build clean all` too!) */
    MOVR(T0, S2) ; ANDI(T0, ACT_CLEAN)
    CMPI(T0, 0) ; JEQ(.L_chk_build_needed)
    SX_CALL(sx_do_clean)

.L_chk_build_needed:
    MOVR(T0, S2) ; ANDI(T0, ACT_RUNTIME + ACT_COMPILER + ACT_VERIFY)
    CMPI(T0, 0) ; JNE(.L_start_build)
    MOVI(R0, 0)
    SX_EPILOGUE

.L_start_build:
    /* Ensure build/ directory exists */
    LEA_SYM(A0, g_bld_dir) ; SX_CALL(sx_ensure_dir)

    /* ------------------------------------------------------------------------
     * [1/4] Assemble Synchronix Runtime & Archive libsynchronix_rt.a
     * ------------------------------------------------------------------------
     */
    MOVR(T0, S2) ; ANDI(T0, ACT_RUNTIME)
    CMPI(T0, 0) ; JEQ(.L_step2)

    LEA_SYM(A0, msg_step1) ; SX_CALL(puts)

    LEA_SYM(T0, g_ar_bin) ; LD64(A1, T0, 0)
    LEA_SYM(A0, g_ar_cmd) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_ar_cmd) ; LEA_SYM(A1, str_sp_rcs_q) ; SX_CALL(strcat)
    LEA_SYM(A0, g_ar_cmd) ; LEA_SYM(A1, g_rt_path)    ; SX_CALL(strcat)
    LEA_SYM(A0, g_ar_cmd) ; LEA_SYM(A1, str_q)        ; SX_CALL(strcat)

    LEA_SYM(A0, tbl_rt_sources)
    LEA_SYM(A1, g_ar_cmd)
    SX_CALL(sx_assemble_list)
    CMPI(R0, 0) ; JNE(.L_fail)

    LEA_SYM(A0, g_ar_cmd) ; SX_CALL(system)
    CMPI(R0, 0) ; JEQ(.L_step2)
    LEA_SYM(A0, err_ar_fail) ; SX_CALL(puts)
    JMP(.L_fail)

    /* ------------------------------------------------------------------------
     * [2/4] Assemble Synchronix Compiler & Ecosystem Tooling
     * [3/4] Link synchronix(.exe) with LLD
     * ------------------------------------------------------------------------
     */
.L_step2:
    MOVR(T0, S2) ; ANDI(T0, ACT_COMPILER)
    CMPI(T0, 0) ; JEQ(.L_step4)

    LEA_SYM(A0, msg_step2) ; SX_CALL(puts)

    LEA_SYM(T0, g_cc_bin)  ; LD64(A1, T0, 0)
    LEA_SYM(A0, g_link_cmd) ; SX_CALL(strcpy)
    LEA_SYM(T0, g_ldflags) ; LD64(A1, T0, 0)
    LEA_SYM(A0, g_link_cmd) ; SX_CALL(sx_append_opt_flag)

    LEA_SYM(A0, tbl_compiler_sources)
    LEA_SYM(A1, g_link_cmd)
    SX_CALL(sx_assemble_list)
    CMPI(R0, 0) ; JNE(.L_fail)

    LEA_SYM(A0, msg_step3) ; SX_CALL(puts)

    LEA_SYM(A0, g_link_cmd) ; LEA_SYM(A1, str_sp_o_q) ; SX_CALL(strcat)
    LEA_SYM(A0, g_link_cmd) ; LEA_SYM(A1, g_exe_path) ; SX_CALL(strcat)
    LEA_SYM(A0, g_link_cmd) ; LEA_SYM(A1, str_q)      ; SX_CALL(strcat)

    LEA_SYM(A0, g_link_cmd) ; SX_CALL(system)
    CMPI(R0, 0) ; JEQ(.L_step4)
    LEA_SYM(A0, err_link_fail) ; SX_CALL(puts)
    JMP(.L_fail)

    /* ------------------------------------------------------------------------
     * [4/4] Cross-Target Portability Verification (All 21 Pure Assembly Units)
     * ------------------------------------------------------------------------
     */
.L_step4:
    MOVR(T0, S2) ; ANDI(T0, ACT_VERIFY)
    CMPI(T0, 0) ; JEQ(.L_success)

    LEA_SYM(A0, msg_step4) ; SX_CALL(puts)
    LEA_SYM(A0, g_xverify_dir) ; SX_CALL(sx_ensure_dir)

    LEA_SYM(S3, tbl_verify_triples)
.L_triple_loop:
    LD8_R0(S3, 0)
    CMPI(R0, 0) ; JEQ(.L_success)

    LEA_SYM(A0, tbl_rt_sources)       ; MOVR(A1, S3) ; SX_CALL(sx_verify_list)
    CMPI(R0, 0) ; JNE(.L_fail)

    LEA_SYM(A0, tbl_compiler_sources) ; MOVR(A1, S3) ; SX_CALL(sx_verify_list)
    CMPI(R0, 0) ; JNE(.L_fail)

    LEA_SYM(A0, tbl_builder_sources)  ; MOVR(A1, S3) ; SX_CALL(sx_verify_list)
    CMPI(R0, 0) ; JNE(.L_fail)

    LEA_SYM(A0, g_msg_buf) ; LEA_SYM(A1, msg_verify_ok_pfx) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_msg_buf) ; MOVR(A1, S3)                   ; SX_CALL(strcat)
    LEA_SYM(A0, g_msg_buf) ; SX_CALL(puts)

    MOVR(A0, S3) ; SX_CALL(strlen)
    ADD(S3, R0)
    ADDI(S3, 1)
    JMP(.L_triple_loop)

.L_success:
    LEA_SYM(A0, msg_empty)   ; SX_CALL(puts)
    LEA_SYM(A0, msg_success) ; SX_CALL(puts)

    MOVR(T0, S2) ; ANDI(T0, ACT_COMPILER)
    CMPI(T0, 0) ; JEQ(.L_print_rt)
    LEA_SYM(A0, g_msg_buf) ; LEA_SYM(A1, msg_compiler_pfx) ; SX_CALL(strcpy)
    LEA_SYM(A0, g_msg_buf) ; LEA_SYM(A1, g_exe_path)       ; SX_CALL(strcat)
    LEA_SYM(A0, g_msg_buf) ; SX_CALL(puts)

.L_print_rt:
    MOVR(T0, S2) ; ANDI(T0, ACT_RUNTIME)
    CMPI(T0, 0) ; JEQ(.L_done_ok)
    LEA_SYM(A0, g_msg_buf) ; LEA_SYM(A1, msg_runtime_pfx)  ; SX_CALL(strcpy)
    LEA_SYM(A0, g_msg_buf) ; LEA_SYM(A1, g_rt_path)        ; SX_CALL(strcat)
    LEA_SYM(A0, g_msg_buf) ; SX_CALL(puts)

.L_done_ok:
    MOVI(R0, 0)
    SX_EPILOGUE

.L_fail:
    MOVI(R0, 1)
    SX_EPILOGUE
SX_ENDFUNC(main)
