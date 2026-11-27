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
 * SYNCHRONIX COMPILER — Shared Utilities & Arena State (src/frontend/utils.S)
 * ============================================================================
 * Pure portable assembly utilities:
 *   - Global arenas for Tokens, AST Nodes, Symbols, SUMIR Instructions, Strings
 *   - File I/O helpers (sx_read_file, sx_write_file)
 *   - Slice & string comparison helpers (sx_slice_eq_cstr, sx_slice_eq_slice)
 *   - AST node bump allocator (sx_ast_new) & diagnostic reporter (sx_error)
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(mode_rb,     "rb")
SX_STR(mode_wb,     "wb")
SX_STR(fmt_err_ln,  "[Synchronix Error] line %lld: %s\n")
SX_STR(fmt_warn_ln, "[Synchronix Warning] line %lld: %s\n")
SX_STR(fmt_info_s,  "[Synchronix] %s\n")

SX_BSS
.p2align 4
/* Source code buffer pointer & length */
SX_GLOBAL(g_src_buf)
SX_LABEL(g_src_buf)
    .skip 8
SX_GLOBAL(g_src_len)
SX_LABEL(g_src_len)
    .skip 8

/* Phase 1: Token Arena */
SX_GLOBAL(g_tokens)
SX_LABEL(g_tokens)
    .skip (MAX_TOKENS * TOK_SIZE)
SX_GLOBAL(g_tok_count)
SX_LABEL(g_tok_count)
    .skip 8
SX_GLOBAL(g_tok_pos)
SX_LABEL(g_tok_pos)
    .skip 8

/* Phase 1: AST Arena */
SX_GLOBAL(g_ast_pool)
SX_LABEL(g_ast_pool)
    .skip (MAX_AST_NODES * AST_SIZE)
SX_GLOBAL(g_ast_count)
SX_LABEL(g_ast_count)
    .skip 8
SX_GLOBAL(g_ast_root)
SX_LABEL(g_ast_root)
    .skip 8

/* Phase 1: Symbol Table & Lambda Capture Registry */
SX_GLOBAL(g_symbols)
SX_LABEL(g_symbols)
    .skip (MAX_SYMBOLS * SYME_SIZE)
SX_GLOBAL(g_sym_count)
SX_LABEL(g_sym_count)
    .skip 8
SX_GLOBAL(g_scope_depth)
SX_LABEL(g_scope_depth)
    .skip 8

/* Lifted Lambda Descriptor Table (64 bytes each: ast_ptr, cap_name_ptr, cap_name_len, cap_vreg, param_ptr, param_len, id, reserved) */
SX_GLOBAL(g_lambdas)
SX_LABEL(g_lambdas)
    .skip (MAX_LAMBDAS * 64)
SX_GLOBAL(g_lambda_count)
SX_LABEL(g_lambda_count)
    .skip 8

/* String Literal Table (16 bytes each: ptr, len) */
SX_GLOBAL(g_strings)
SX_LABEL(g_strings)
    .skip (MAX_STRINGS * 16)
SX_GLOBAL(g_str_count)
SX_LABEL(g_str_count)
    .skip 8

/* Phase 2: SUMIR Instruction Buffer */
SX_GLOBAL(g_ir_buf)
SX_LABEL(g_ir_buf)
    .skip (MAX_IR_INSTS * IR_SIZE)
SX_GLOBAL(g_ir_count)
SX_LABEL(g_ir_count)
    .skip 8
SX_GLOBAL(g_next_vreg)
SX_LABEL(g_next_vreg)
    .skip 8
SX_GLOBAL(g_next_label)
SX_LABEL(g_next_label)
    .skip 8

/* Diagnostics & Compiler Options */
SX_GLOBAL(g_err_count)
SX_LABEL(g_err_count)
    .skip 8
SX_GLOBAL(g_warn_count)
SX_LABEL(g_warn_count)
    .skip 8
SX_GLOBAL(g_opt_target)
SX_LABEL(g_opt_target)
    .skip 8   /* TARGET_X86_64 / TARGET_ARM64 / TARGET_LLVM_IR */
SX_GLOBAL(g_opt_dump_ast)
SX_LABEL(g_opt_dump_ast)
    .skip 8
SX_GLOBAL(g_opt_dump_ir)
SX_LABEL(g_opt_dump_ir)
    .skip 8
SX_GLOBAL(g_opt_emit_asm)
SX_LABEL(g_opt_emit_asm)
    .skip 8
SX_GLOBAL(g_opt_debug)
SX_LABEL(g_opt_debug)
    .skip 8
SX_GLOBAL(g_opt_profile)
SX_LABEL(g_opt_profile)
    .skip 8
SX_GLOBAL(g_opt_ext_lib)
SX_LABEL(g_opt_ext_lib)
    .skip 8   /* optional external .a/.so/.lib path */

/* Middle-End & Backend Optimization Counters */
SX_GLOBAL(g_stat_phi_static)
SX_LABEL(g_stat_phi_static)
    .skip 8
SX_GLOBAL(g_stat_phi_runtime)
SX_LABEL(g_stat_phi_runtime)
    .skip 8
SX_GLOBAL(g_stat_arc_inserted)
SX_LABEL(g_stat_arc_inserted)
    .skip 8
SX_GLOBAL(g_stat_gc_roots)
SX_LABEL(g_stat_gc_roots)
    .skip 8
SX_GLOBAL(g_stat_const_folded)
SX_LABEL(g_stat_const_folded)
    .skip 8
SX_GLOBAL(g_stat_dce_removed)
SX_LABEL(g_stat_dce_removed)
    .skip 8
SX_GLOBAL(g_stat_inlined)
SX_LABEL(g_stat_inlined)
    .skip 8
SX_GLOBAL(g_stat_reg_allocs)
SX_LABEL(g_stat_reg_allocs)
    .skip 8
SX_GLOBAL(g_stat_sched_opts)
SX_LABEL(g_stat_sched_opts)
    .skip 8

SX_TEXT

/* ----------------------------------------------------------------------------
 * sx_compiler_reset() — Zero all per-compilation counters
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_compiler_reset)
    SX_PROLOGUE 0
    MOVI(T1, 0)
    LEA_SYM(T0, g_tok_count)      ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_tok_pos)        ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_ast_count)      ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_ast_root)       ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_sym_count)      ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_scope_depth)    ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_lambda_count)   ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_str_count)      ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_ir_count)       ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_next_vreg)      ; MOVI(R0, 1) ; ST64(R0, T0, 0)
    LEA_SYM(T0, g_next_label)     ; MOVI(R0, 1) ; ST64(R0, T0, 0)
    LEA_SYM(T0, g_err_count)      ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_warn_count)     ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_stat_phi_static); ST64(T1, T0, 0)
    LEA_SYM(T0, g_stat_phi_runtime); ST64(T1, T0, 0)
    LEA_SYM(T0, g_stat_arc_inserted); ST64(T1, T0, 0)
    LEA_SYM(T0, g_stat_gc_roots)  ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_stat_const_folded); ST64(T1, T0, 0)
    LEA_SYM(T0, g_stat_dce_removed); ST64(T1, T0, 0)
    LEA_SYM(T0, g_stat_inlined)   ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_stat_reg_allocs); ST64(T1, T0, 0)
    LEA_SYM(T0, g_stat_sched_opts); ST64(T1, T0, 0)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_compiler_reset)

/* ----------------------------------------------------------------------------
 * sx_error(A0 = line, A1 = msg_cstr)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_error)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    MOVR(S1, A1)
    LEA_SYM(T0, g_err_count)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)
    MOVR(A2, S1)
    MOVR(A1, S0)
    LEA_SYM(A0, fmt_err_ln)
    SX_VCALL(printf)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_error)

/* ----------------------------------------------------------------------------
 * sx_warn(A0 = line, A1 = msg_cstr)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_warn)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    MOVR(S1, A1)
    LEA_SYM(T0, g_warn_count)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)
    MOVR(A2, S1)
    MOVR(A1, S0)
    LEA_SYM(A0, fmt_warn_ln)
    SX_VCALL(printf)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_warn)

/* ----------------------------------------------------------------------------
 * sx_ast_new(A0 = node_kind, A1 = line) -> R0 = ast_node_ptr
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_ast_new)
    SX_PROLOGUE 16
    MOVR(S0, A0)                /* kind */
    MOVR(S1, A1)                /* line */
    LEA_SYM(T0, g_ast_count)
    LD64(S2, T0, 0)
    CMPI(S2, MAX_AST_NODES)
    JGE(.L_ast_full)
    MOVR(T1, S2)
    ADDI(T1, 1)
    ST64(T1, T0, 0)

    /* addr = g_ast_pool + idx * 96 */
    MOVR(S3, S2)
    MULI(S3, AST_SIZE)
    LEA_SYM(T0, g_ast_pool)
    ADD(S3, T0)

    /* Zero 12 qwords (96 bytes) */
    MOVI(T0, 0)
    ST64(S0, S3, AST_KIND)
    ST64(T0, S3, AST_NAME_PTR)
    ST64(T0, S3, AST_NAME_LEN)
    ST64(T0, S3, AST_IVAL)
    ST64(T0, S3, AST_LEFT)
    ST64(T0, S3, AST_RIGHT)
    ST64(T0, S3, AST_EXTRA)
    ST64(T0, S3, AST_EXTRA2)
    ST64(T0, S3, AST_NEXT)
    ST64(T0, S3, AST_TYPE)
    ST64(S1, S3, AST_LINE)
    ST64(T0, S3, AST_META)

    MOVR(R0, S3)
    SX_EPILOGUE
.L_ast_full:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_ast_new)

/* ----------------------------------------------------------------------------
 * sx_slice_eq_cstr(A0 = ptr, A1 = len, A2 = cstr) -> R0 = 1 if equal else 0
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_slice_eq_cstr)
    SX_PROLOGUE 0
    MOVR(S0, A0)                /* ptr */
    MOVR(S1, A1)                /* len */
    MOVR(S2, A2)                /* cstr */
    MOVI(S3, 0)                 /* i */
.L_sec_loop:
    CMP(S3, S1)
    JGE(.L_sec_end_check)
    LD8_IDX_T0(S0, S3)
    LD8_IDX_T1(S2, S3)
    CMP(T0, T1)
    JNE(.L_sec_no)
    CMPI(T1, 0)
    JEQ(.L_sec_no)
    ADDI(S3, 1)
    JMP(.L_sec_loop)
.L_sec_end_check:
    LD8_IDX_T1(S2, S3)
    CMPI(T1, 0)
    JNE(.L_sec_no)
    MOVI(R0, 1)
    SX_EPILOGUE
.L_sec_no:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_slice_eq_cstr)

/* ----------------------------------------------------------------------------
 * sx_slice_eq_slice(A0 = p1, A1 = l1, A2 = p2, A3 = l2) -> R0 = 1 if eq else 0
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_slice_eq_slice)
    SX_PROLOGUE 0
    CMP(A1, A3)
    JNE(.L_ses_no)
    MOVR(S0, A0)
    MOVR(S1, A1)
    MOVR(S2, A2)
    MOVI(S3, 0)
.L_ses_loop:
    CMP(S3, S1)
    JGE(.L_ses_yes)
    LD8_IDX_T0(S0, S3)
    LD8_IDX_T1(S2, S3)
    CMP(T0, T1)
    JNE(.L_ses_no)
    ADDI(S3, 1)
    JMP(.L_ses_loop)
.L_ses_yes:
    MOVI(R0, 1)
    SX_EPILOGUE
.L_ses_no:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_slice_eq_slice)

/* ----------------------------------------------------------------------------
 * sx_read_file(A0 = path_cstr, A1 = out_len_ptr) -> R0 = malloc'd NUL-term buf
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_read_file)
    SX_PROLOGUE 32
    MOVR(S0, A0)                /* path */
    MOVR(S1, A1)                /* out_len_ptr */

    MOVR(A0, S0)
    LEA_SYM(A1, mode_rb)
    SX_CALL(fopen)
    CMPI(R0, 0)
    JEQ(.L_rf_fail)
    MOVR(S2, R0)                /* S2 = FILE* */

    /* fseek(fp, 0, SEEK_END=2) */
    MOVR(A0, S2)
    MOVI(A1, 0)
    MOVI(A2, 2)
    SX_CALL(fseek)

    /* len = ftell(fp) */
    MOVR(A0, S2)
    SX_CALL(ftell)
    MOVR(S3, R0)                /* S3 = file_len */

    /* fseek(fp, 0, SEEK_SET=0) */
    MOVR(A0, S2)
    MOVI(A1, 0)
    MOVI(A2, 0)
    SX_CALL(fseek)

    /* buf = malloc(len + 2) */
    MOVR(A0, S3)
    ADDI(A0, 2)
    SX_CALL(malloc)
    MOVR(S4, R0)                /* S4 = buf */
    CMPI(S4, 0)
    JEQ(.L_rf_close_fail)

    /* fread(buf, 1, len, fp) */
    MOVR(A0, S4)
    MOVI(A1, 1)
    MOVR(A2, S3)
    MOVR(A3, S2)
    SX_CALL(fread)

    /* NUL terminate */
    MOVI(T0, 0)
    ST8_IDX_T0(S4, S3)

    MOVR(A0, S2)
    SX_CALL(fclose)

    CMPI(S1, 0)
    JEQ(.L_rf_ret)
    ST64(S3, S1, 0)
.L_rf_ret:
    MOVR(R0, S4)
    SX_EPILOGUE
.L_rf_close_fail:
    MOVR(A0, S2)
    SX_CALL(fclose)
.L_rf_fail:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_read_file)

/* ----------------------------------------------------------------------------
 * sx_intern_string(A0 = ptr, A1 = len) -> R0 = string_id
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_intern_string)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    MOVR(S1, A1)
    LEA_SYM(T0, g_str_count)
    LD64(S2, T0, 0)
    CMPI(S2, MAX_STRINGS)
    JGE(.L_istr_full)
    MOVR(T1, S2)
    ADDI(T1, 1)
    ST64(T1, T0, 0)

    MOVR(S3, S2)
    SHLI(S3, 4)                 /* * 16 */
    LEA_SYM(T0, g_strings)
    ADD(S3, T0)
    ST64(S0, S3, 0)
    ST64(S1, S3, 8)
    MOVR(R0, S2)
    SX_EPILOGUE
.L_istr_full:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_intern_string)
