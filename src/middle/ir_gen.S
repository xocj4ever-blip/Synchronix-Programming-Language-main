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
 * SYNCHRONIX COMPILER — Phase 2: IR Generator -> SUMIR (src/middle/ir_gen.S)
 * ============================================================================
 * Lowers Typed AST -> High-Level IR -> SUMIR (Synchronix Unified Memory IR).
 * Handles Swift/Kotlin bindings, ARC/GC/Borrow/Move ops, Phi proof assertions,
 * Lambda closure lifting & capture binding, Generics, and M:N Async fibers.
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(bi_println,     "println")
SX_STR(bi_print,       "print")
SX_STR(bi_println_str, "println_str")
SX_STR(bi_print_str,   "print_str")
SX_STR(bi_abs,         "abs")
SX_STR(bi_min,         "min")
SX_STR(bi_max,         "max")
SX_STR(bi_pow,         "pow")
SX_STR(bi_mem_stats,   "mem_stats")
SX_STR(bi_gc_collect,  "gc_collect")
SX_STR(bi_phi_stats,   "phi_stats")

SX_STR(rt_println_int, "sx_println_int")
SX_STR(rt_print_int,   "sx_print_int")
SX_STR(rt_println_str, "sx_println_str")
SX_STR(rt_print_str,   "sx_print_str")
SX_STR(rt_abs,         "sx_abs")
SX_STR(rt_min,         "sx_min")
SX_STR(rt_max,         "sx_max")
SX_STR(rt_pow,         "sx_pow")
SX_STR(rt_report,      "sx_runtime_report")
SX_STR(rt_gc_collect,  "sx_gc_collect")
SX_STR(rt_phi_stats,   "sx_phi_stats")

SX_STR(fmt_lam_name,   "__sx_lambda_%lld")

SX_BSS
.p2align 4
/* Local IR symbol binding table (per function): 48 bytes each
 * [+0]=name_ptr, [+8]=name_len, [+16]=vreg, [+24]=type, [+32]=own_state, [+40]=reserved */
SX_GLOBAL(g_ir_vars)
SX_LABEL(g_ir_vars)
    .skip (256 * 48)
SX_GLOBAL(g_ir_var_cnt)
SX_LABEL(g_ir_var_cnt)
    .skip 8

/* Static storage for generated lambda function names (32 bytes each) */
SX_GLOBAL(g_lam_names)
SX_LABEL(g_lam_names)
    .skip (MAX_LAMBDAS * 32)

SX_GLOBAL(g_ir_func_cnt)
SX_LABEL(g_ir_func_cnt)
    .skip 8

/* Current lambda capture context when lowering a lifted lambda body */
SX_LABEL(g_cur_lam_closure_vreg)
    .skip 8
SX_LABEL(g_cur_lam_cap_ptr)
    .skip 8
SX_LABEL(g_cur_lam_cap_len)
    .skip 8

/* Temporary storage for call arg vregs (up to 4 portable args) */
SX_LABEL(g_call_arg_vregs)
    .skip (8 * 8)
SX_LABEL(g_call_arg_types)
    .skip (8 * 8)

SX_TEXT

/* ----------------------------------------------------------------------------
 * SUMIR Emission Helpers
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_new_vreg)
    SX_PROLOGUE 0
    LEA_SYM(T0, g_next_vreg)
    LD64(R0, T0, 0)
    MOVR(T1, R0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_new_vreg)

SX_FUNC(sx_new_label)
    SX_PROLOGUE 0
    LEA_SYM(T0, g_next_label)
    LD64(R0, T0, 0)
    MOVR(T1, R0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_new_label)

/* sx_ir_emit(A0=op, A1=dst, A2=src1, A3=src2) -> R0 = inst_ptr */
SX_FUNC(sx_ir_emit)
    SX_PROLOGUE 16
    MOVR(S0, A0) ; MOVR(S1, A1) ; MOVR(S2, A2) ; MOVR(S3, A3)
    LEA_SYM(T0, g_ir_count)
    LD64(S4, T0, 0)
    CMPI(S4, MAX_IR_INSTS) ; JGE(.L_ie_full)
    MOVR(T1, S4) ; ADDI(T1, 1) ; ST64(T1, T0, 0)

    SHLI(S4, 6)                 /* * 64 (IR_SIZE) */
    LEA_SYM(T0, g_ir_buf) ; ADD(S4, T0)
    ST64(S0, S4, IR_OP)
    ST64(S1, S4, IR_DST)
    ST64(S2, S4, IR_SRC1)
    ST64(S3, S4, IR_SRC2)
    MOVI(T0, 0)
    ST64(T0, S4, IR_IMM)
    ST64(T0, S4, IR_TYPE)
    ST64(T0, S4, IR_FLAGS)
    MOVI(T0, -1)
    ST64(T0, S4, IR_PHYS)
    MOVR(R0, S4)
    SX_EPILOGUE
.L_ie_full:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_ir_emit)

/* Variable table helpers inside a function */
/* sx_ir_var_bind(A0=ptr, A1=len, A2=vreg, A3=type) */
SX_FUNC(sx_ir_var_bind)
    SX_PROLOGUE 16
    MOVR(S0, A0) ; MOVR(S1, A1) ; MOVR(S2, A2) ; MOVR(S3, A3)
    LEA_SYM(T0, g_ir_var_cnt)
    LD64(S4, T0, 0)
    MOVR(T1, S4) ; ADDI(T1, 1) ; ST64(T1, T0, 0)
    MULI(S4, 48)
    LEA_SYM(T0, g_ir_vars) ; ADD(S4, T0)
    ST64(S0, S4, 0)
    ST64(S1, S4, 8)
    ST64(S2, S4, 16)
    ST64(S3, S4, 24)
    MOVI(T0, OWN_OWNED) ; ST64(T0, S4, 32)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_ir_var_bind)

/* sx_ir_var_find(A0=ptr, A1=len) -> R0 = entry_ptr or 0 */
SX_FUNC(sx_ir_var_find)
    SX_PROLOGUE 16
    MOVR(S0, A0) ; MOVR(S1, A1)
    LEA_SYM(T0, g_ir_var_cnt)
    LD64(S2, T0, 0)
    LEA_SYM(S3, g_ir_vars)
.L_vf_loop:
    CMPI(S2, 0) ; JLE(.L_vf_none)
    SUBI(S2, 1)
    MOVR(S4, S2) ; MULI(S4, 48) ; ADD(S4, S3)
    MOVR(A0, S0) ; MOVR(A1, S1)
    LD64(A2, S4, 0) ; LD64(A3, S4, 8)
    SX_CALL(sx_slice_eq_slice)
    CMPI(R0, 0) ; JNE(.L_vf_found)
    JMP(.L_vf_loop)
.L_vf_found:
    MOVR(R0, S4) ; SX_EPILOGUE
.L_vf_none:
    MOVI(R0, 0) ; SX_EPILOGUE
SX_ENDFUNC(sx_ir_var_find)

/* Unbox ARC/GC value to raw int if needed: sx_unbox_if_managed(A0=vreg, A1=type) -> R0=vreg */
SX_FUNC(sx_unbox_if_managed)
    SX_PROLOGUE 16
    MOVR(S0, A0) ; MOVR(S1, A1)
    CMPI(S1, TY_ARC) ; JEQ(.L_ub_arc)
    CMPI(S1, TY_GC)  ; JEQ(.L_ub_gc)
    MOVR(R0, S0) ; SX_EPILOGUE
.L_ub_arc:
    SX_CALL(sx_new_vreg) ; MOVR(S2, R0)
    MOVI(A0, IR_ARC_LOAD) ; MOVR(A1, S2) ; MOVR(A2, S0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    MOVR(R0, S2) ; SX_EPILOGUE
.L_ub_gc:
    SX_CALL(sx_new_vreg) ; MOVR(S2, R0)
    MOVI(A0, IR_GC_LOAD) ; MOVR(A1, S2) ; MOVR(A2, S0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    MOVR(R0, S2) ; SX_EPILOGUE
SX_ENDFUNC(sx_unbox_if_managed)

/* ----------------------------------------------------------------------------
 * Expression Lowering: sx_ir_gen_expr(A0 = expr_node, A1 = out_type_ptr) -> R0 = vreg
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_ir_gen_expr)
    SX_PROLOGUE 48
    MOVR(S0, A0)                /* expr */
    MOVR(S1, A1)                /* out_type_ptr (may be 0) */
    CMPI(S0, 0) ; JEQ(.L_ge_zero)
    LD64(S2, S0, AST_KIND)

    /* NK_INT */
    CMPI(S2, NK_INT) ; JNE(.L_ge_str)
    SX_CALL(sx_new_vreg) ; MOVR(S3, R0)
    MOVI(A0, IR_CONST) ; MOVR(A1, S3) ; MOVI(A2, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    LD64(T0, S0, AST_IVAL) ; ST64(T0, R0, IR_IMM)
    MOVI(T0, TY_INT) ; ST64(T0, R0, IR_TYPE)
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
    JMP(.L_ge_ret_s3)

.L_ge_str:
    CMPI(S2, NK_STR) ; JNE(.L_ge_ident)
    LD64(A0, S0, AST_NAME_PTR)
    LD64(A1, S0, AST_NAME_LEN)
    SX_CALL(sx_intern_string)
    MOVR(S4, R0)                /* str_id */
    SX_CALL(sx_new_vreg) ; MOVR(S3, R0)
    MOVI(A0, IR_STR_CONST) ; MOVR(A1, S3)
    LD64(A2, S0, AST_NAME_PTR) ; LD64(A3, S0, AST_NAME_LEN)
    SX_CALL(sx_ir_emit)
    ST64(S4, R0, IR_IMM)
    MOVI(T0, TY_STR) ; ST64(T0, R0, IR_TYPE)
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
    JMP(.L_ge_ret_s3)

.L_ge_ident:
    CMPI(S2, NK_IDENT) ; JNE(.L_ge_arc)
    /* Check if this is the captured variable inside a lifted lambda! */
    LEA_SYM(T0, g_cur_lam_cap_ptr) ; LD64(T1, T0, 0)
    CMPI(T1, 0) ; JEQ(.L_ge_id_local)
    LD64(A0, S0, AST_NAME_PTR) ; LD64(A1, S0, AST_NAME_LEN)
    MOVR(A2, T1)
    LEA_SYM(T0, g_cur_lam_cap_len) ; LD64(A3, T0, 0)
    SX_CALL(sx_slice_eq_slice)
    CMPI(R0, 0) ; JEQ(.L_ge_id_local)
    /* Emit IR_CLOSURE_GET from closure_ptr (env index 0)! */
    SX_CALL(sx_new_vreg) ; MOVR(S3, R0)
    MOVI(A0, IR_CLOSURE_GET) ; MOVR(A1, S3)
    LEA_SYM(T0, g_cur_lam_closure_vreg) ; LD64(A2, T0, 0)
    MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    MOVI(T0, 0) ; ST64(T0, R0, IR_IMM)
    MOVI(T0, TY_INT) ; ST64(T0, R0, IR_TYPE)
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
    JMP(.L_ge_ret_s3)

.L_ge_id_local:
    LD64(A0, S0, AST_NAME_PTR) ; LD64(A1, S0, AST_NAME_LEN)
    SX_CALL(sx_ir_var_find)
    CMPI(R0, 0) ; JEQ(.L_ge_zero)
    LD64(S3, R0, 16)            /* vreg */
    LD64(T0, R0, 24)            /* type */
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
    JMP(.L_ge_ret_s3)

.L_ge_arc:
    CMPI(S2, NK_ARC_NEW) ; JNE(.L_ge_gc)
    LD64(A0, S0, AST_LEFT) ; LEA_LOCAL(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVR(A0, R0) ; LD_LOCAL(A1, 0) ; SX_CALL(sx_unbox_if_managed)
    MOVR(S4, R0)
    SX_CALL(sx_new_vreg) ; MOVR(S3, R0)
    MOVI(A0, IR_ARC_NEW) ; MOVR(A1, S3) ; MOVR(A2, S4) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    MOVI(T0, TY_ARC) ; ST64(T0, R0, IR_TYPE)
    MOVI(T1, IRF_ARC) ; ST64(T1, R0, IR_FLAGS)
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
    JMP(.L_ge_ret_s3)

.L_ge_gc:
    CMPI(S2, NK_GC_NEW) ; JNE(.L_ge_borrow)
    LD64(A0, S0, AST_LEFT) ; LEA_LOCAL(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVR(A0, R0) ; LD_LOCAL(A1, 0) ; SX_CALL(sx_unbox_if_managed)
    MOVR(S4, R0)
    SX_CALL(sx_new_vreg) ; MOVR(S3, R0)
    MOVI(A0, IR_GC_NEW) ; MOVR(A1, S3) ; MOVR(A2, S4) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    MOVI(T0, TY_GC) ; ST64(T0, R0, IR_TYPE)
    MOVI(T1, IRF_GC) ; ST64(T1, R0, IR_FLAGS)
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
    JMP(.L_ge_ret_s3)

.L_ge_borrow:
    CMPI(S2, NK_BORROW) ; JNE(.L_ge_move)
    LD64(A0, S0, AST_LEFT) ; LEA_LOCAL(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVR(S4, R0)
    SX_CALL(sx_new_vreg) ; MOVR(S3, R0)
    MOVI(A0, IR_BORROW) ; MOVR(A1, S3) ; MOVR(A2, S4) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    LD_LOCAL(T0, 0) ; ST64(T0, R0, IR_TYPE)
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
    JMP(.L_ge_ret_s3)

.L_ge_move:
    CMPI(S2, NK_MOVE) ; JNE(.L_ge_lambda)
    LD64(A0, S0, AST_LEFT) ; LEA_LOCAL(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVR(S4, R0)
    SX_CALL(sx_new_vreg) ; MOVR(S3, R0)
    MOVI(A0, IR_MOVE) ; MOVR(A1, S3) ; MOVR(A2, S4) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    LD_LOCAL(T0, 0) ; ST64(T0, R0, IR_TYPE)
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
    JMP(.L_ge_ret_s3)

.L_ge_lambda:
    CMPI(S2, NK_LAMBDA) ; JNE(.L_ge_spawn)
    /* Emit IR_CLOSURE_NEW pointing to __sx_lambda_<id> + IR_CLOSURE_SET if capture exists */
    LD64(S4, S0, AST_META)      /* lambda id */
    MOVR(T0, S4) ; SHLI(T0, 5)  /* * 32 */
    LEA_SYM(T1, g_lam_names) ; ADD(T0, T1)
    ST_LOCAL(T0, 0)             /* name_ptr */

    MOVR(A0, T0) ; MOVI(A1, 32)
    LEA_SYM(A2, fmt_lam_name) ; MOVR(A3, S4)
    SX_VCALL(snprintf)
    ST_LOCAL(R0, 1)             /* name_len */

    /* Look up capture in g_lambdas[id] */
    MOVR(T0, S4) ; SHLI(T0, 6)
    LEA_SYM(T1, g_lambdas) ; ADD(T0, T1)
    ST_LOCAL(T0, 2)             /* lam_desc */
    LD64(T1, T0, 8)             /* cap_name_ptr */
    MOVI(T0, 0)
    CMPI(T1, 0) ; JEQ(.L_lam_nocap)
    MOVI(T0, 1)
.L_lam_nocap:
    ST_LOCAL(T0, 3)             /* cap_cnt (0 or 1) */

    SX_CALL(sx_new_vreg) ; MOVR(S3, R0)
    MOVI(A0, IR_CLOSURE_NEW) ; MOVR(A1, S3)
    LD_LOCAL(A2, 0) ; LD_LOCAL(A3, 1)
    SX_CALL(sx_ir_emit)
    LD_LOCAL(T0, 3) ; ST64(T0, R0, IR_IMM)
    MOVI(T0, TY_CLOSURE) ; ST64(T0, R0, IR_TYPE)
    MOVI(T1, IRF_ARC) ; ST64(T1, R0, IR_FLAGS)

    /* If captured variable exists, find its vreg and emit IR_CLOSURE_SET */
    LD_LOCAL(T0, 3) ; CMPI(T0, 0) ; JEQ(.L_lam_ret)
    LD_LOCAL(T1, 2)             /* lam_desc */
    LD64(A0, T1, 8) ; LD64(A1, T1, 16)
    SX_CALL(sx_ir_var_find)
    CMPI(R0, 0) ; JEQ(.L_lam_ret)
    LD64(A0, R0, 16) ; LD64(A1, R0, 24)
    SX_CALL(sx_unbox_if_managed)
    MOVR(A2, R0)
    MOVI(A0, IR_CLOSURE_SET) ; MOVR(A1, S3) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    MOVI(T0, 0) ; ST64(T0, R0, IR_IMM)
.L_lam_ret:
    MOVI(T0, TY_CLOSURE)
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
    JMP(.L_ge_ret_s3)

.L_ge_spawn:
    CMPI(S2, NK_SPAWN) ; JNE(.L_ge_await)
    LD64(A0, S0, AST_LEFT) ; LEA_LOCAL(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVR(A0, R0) ; LD_LOCAL(A1, 0) ; SX_CALL(sx_unbox_if_managed)
    MOVR(S4, R0)                /* arg vreg */
    SX_CALL(sx_new_vreg) ; MOVR(S3, R0)
    MOVI(A0, IR_SPAWN) ; MOVR(A1, S3)
    LD64(A2, S0, AST_NAME_PTR) ; LD64(A3, S0, AST_NAME_LEN)
    SX_CALL(sx_ir_emit)
    ST64(S4, R0, IR_IMM)
    MOVI(T0, TY_TASK) ; ST64(T0, R0, IR_TYPE)
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
    JMP(.L_ge_ret_s3)

.L_ge_await:
    CMPI(S2, NK_AWAIT) ; JNE(.L_ge_unop)
    LD64(A0, S0, AST_LEFT) ; MOVI(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVR(S4, R0)
    SX_CALL(sx_new_vreg) ; MOVR(S3, R0)
    MOVI(A0, IR_AWAIT) ; MOVR(A1, S3) ; MOVR(A2, S4) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    MOVI(T0, TY_INT) ; ST64(T0, R0, IR_TYPE)
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
    JMP(.L_ge_ret_s3)

.L_ge_unop:
    CMPI(S2, NK_UNOP) ; JNE(.L_ge_binop)
    LD64(A0, S0, AST_LEFT) ; LEA_LOCAL(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVR(A0, R0) ; LD_LOCAL(A1, 0) ; SX_CALL(sx_unbox_if_managed)
    MOVR(S4, R0)
    SX_CALL(sx_new_vreg) ; MOVR(S3, R0)
    LD64(T0, S0, AST_IVAL)
    MOVI(A0, IR_NEG)
    CMPI(T0, TK_MINUS) ; JEQ(.L_un_emit)
    MOVI(A0, IR_NOT)
.L_un_emit:
    MOVR(A1, S3) ; MOVR(A2, S4) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    MOVI(T0, TY_INT) ; ST64(T0, R0, IR_TYPE)
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
    JMP(.L_ge_ret_s3)

.L_ge_binop:
    CMPI(S2, NK_BINOP) ; JNE(.L_ge_call)
    LD64(A0, S0, AST_LEFT) ; LEA_LOCAL(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVR(A0, R0) ; LD_LOCAL(A1, 0) ; SX_CALL(sx_unbox_if_managed)
    ST_LOCAL(R0, 1)             /* lhs vreg */

    LD64(A0, S0, AST_RIGHT) ; LEA_LOCAL(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVR(A0, R0) ; LD_LOCAL(A1, 0) ; SX_CALL(sx_unbox_if_managed)
    ST_LOCAL(R0, 2)             /* rhs vreg */

    SX_CALL(sx_new_vreg) ; MOVR(S3, R0)
    LD64(T0, S0, AST_IVAL)
    MOVI(A0, IR_ADD)
    CMPI(T0, TK_PLUS)    ; JEQ(.L_bo_emit)
    CMPI(T0, TK_MINUS)   ; JNE(.L_b1) ; MOVI(A0, IR_SUB)    ; JMP(.L_bo_emit)
.L_b1: CMPI(T0, TK_STAR) ; JNE(.L_b2) ; MOVI(A0, IR_MUL)    ; JMP(.L_bo_emit)
.L_b2: CMPI(T0, TK_SLASH); JNE(.L_b3) ; MOVI(A0, IR_DIV)    ; JMP(.L_bo_emit)
.L_b3: CMPI(T0, TK_PERCENT);JNE(.L_b4); MOVI(A0, IR_MOD)    ; JMP(.L_bo_emit)
.L_b4: CMPI(T0, TK_EQ)   ; JNE(.L_b5) ; MOVI(A0, IR_CMP_EQ) ; JMP(.L_bo_emit)
.L_b5: CMPI(T0, TK_NE)   ; JNE(.L_b6) ; MOVI(A0, IR_CMP_NE) ; JMP(.L_bo_emit)
.L_b6: CMPI(T0, TK_LT)   ; JNE(.L_b7) ; MOVI(A0, IR_CMP_LT) ; JMP(.L_bo_emit)
.L_b7: CMPI(T0, TK_LE)   ; JNE(.L_b8) ; MOVI(A0, IR_CMP_LE) ; JMP(.L_bo_emit)
.L_b8: CMPI(T0, TK_GT)   ; JNE(.L_b9) ; MOVI(A0, IR_CMP_GT) ; JMP(.L_bo_emit)
.L_b9: CMPI(T0, TK_GE)   ; JNE(.L_b10); MOVI(A0, IR_CMP_GE) ; JMP(.L_bo_emit)
.L_b10:CMPI(T0, TK_AND)  ; JNE(.L_b11); MOVI(A0, IR_AND)    ; JMP(.L_bo_emit)
.L_b11:MOVI(A0, IR_OR)
.L_bo_emit:
    MOVR(A1, S3)
    LD_LOCAL(A2, 1)
    LD_LOCAL(A3, 2)
    SX_CALL(sx_ir_emit)
    MOVI(T0, TY_INT) ; ST64(T0, R0, IR_TYPE)
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
    JMP(.L_ge_ret_s3)

.L_ge_call:
    CMPI(S2, NK_CALL) ; JNE(.L_ge_zero)
    /* First evaluate all arguments into g_call_arg_vregs[] */
    LD64(S4, S0, AST_RIGHT)     /* arg list */
    MOVI(T0, 0) ; ST_LOCAL(T0, 0) /* argc */
.L_gc_args:
    CMPI(S4, 0) ; JEQ(.L_gc_args_done)
    MOVR(A0, S4) ; LEA_LOCAL(A1, 1) ; SX_CALL(sx_ir_gen_expr)
    /* Unbox ARC/GC values when passing to functions/println */
    MOVR(A0, R0) ; LD_LOCAL(A1, 1) ; SX_CALL(sx_unbox_if_managed)
    LD_LOCAL(T0, 0)             /* idx */
    LEA_SYM(T1, g_call_arg_vregs) ; ST64_IDX(R0, T1, T0)
    LD_LOCAL(R0, 1)
    LEA_SYM(T1, g_call_arg_types) ; ST64_IDX(R0, T1, T0)
    ADDI(T0, 1) ; ST_LOCAL(T0, 0)
    LD64(S4, S4, AST_NEXT)
    JMP(.L_gc_args)

.L_gc_args_done:
    /* Check if callee is a local TY_CLOSURE variable! */
    LD64(A0, S0, AST_NAME_PTR) ; LD64(A1, S0, AST_NAME_LEN)
    SX_CALL(sx_ir_var_find)
    CMPI(R0, 0) ; JEQ(.L_gc_direct)
    LD64(T0, R0, 24)            /* type */
    CMPI(T0, TY_CLOSURE) ; JNE(.L_gc_direct)
    LD64(S4, R0, 16)            /* closure_vreg */
    SX_CALL(sx_new_vreg) ; MOVR(S3, R0)
    MOVI(A0, IR_CLOSURE_CALL) ; MOVR(A1, S3) ; MOVR(A2, S4)
    LEA_SYM(T1, g_call_arg_vregs) ; LD64(A3, T1, 0)
    SX_CALL(sx_ir_emit)
    MOVI(T0, TY_INT) ; ST64(T0, R0, IR_TYPE)
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
    JMP(.L_ge_ret_s3)

.L_gc_direct:
    /* Emit IR_ARG for each evaluated argument */
    MOVI(S4, 0)
.L_gc_emit_arg:
    LD_LOCAL(T0, 0)
    CMP(S4, T0) ; JGE(.L_gc_resolve_bi)
    MOVI(A0, IR_ARG) ; MOVI(A1, 0)
    LEA_SYM(T1, g_call_arg_vregs) ; LD64_IDX(A2, T1, S4)
    MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    ST64(S4, R0, IR_IMM)
    ADDI(S4, 1)
    JMP(.L_gc_emit_arg)

.L_gc_resolve_bi:
    /* Map stdlib builtins -> runtime symbols */
    LD64(T0, S0, AST_NAME_PTR) ; ST_LOCAL(T0, 2) /* target_ptr */
    LD64(T0, S0, AST_NAME_LEN) ; ST_LOCAL(T0, 3) /* target_len */

    /* println(x) -> sx_println_str if TY_STR else sx_println_int */
    LD_LOCAL(A0, 2) ; LD_LOCAL(A1, 3) ; LEA_SYM(A2, bi_println) ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JEQ(.L_bi_chk_print)
    LEA_SYM(T1, g_call_arg_types) ; LD64(T0, T1, 0)
    CMPI(T0, TY_STR) ; JEQ(.L_map_plns)
    LEA_SYM(T0, rt_println_int) ; MOVI(T1, 14) ; JMP(.L_bi_set)
.L_map_plns:
    LEA_SYM(T0, rt_println_str) ; MOVI(T1, 14) ; JMP(.L_bi_set)

.L_bi_chk_print:
    LD_LOCAL(A0, 2) ; LD_LOCAL(A1, 3) ; LEA_SYM(A2, bi_print) ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JEQ(.L_bi_chk_abs)
    LEA_SYM(T1, g_call_arg_types) ; LD64(T0, T1, 0)
    CMPI(T0, TY_STR) ; JEQ(.L_map_ps)
    LEA_SYM(T0, rt_print_int) ; MOVI(T1, 12) ; JMP(.L_bi_set)
.L_map_ps:
    LEA_SYM(T0, rt_print_str) ; MOVI(T1, 12) ; JMP(.L_bi_set)

.L_bi_chk_abs:
    LD_LOCAL(A0, 2) ; LD_LOCAL(A1, 3) ; LEA_SYM(A2, bi_abs) ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JEQ(.L_bi_chk_min)
    LEA_SYM(T0, rt_abs) ; MOVI(T1, 6) ; JMP(.L_bi_set)

.L_bi_chk_min:
    LD_LOCAL(A0, 2) ; LD_LOCAL(A1, 3) ; LEA_SYM(A2, bi_min) ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JEQ(.L_bi_chk_max)
    LEA_SYM(T0, rt_min) ; MOVI(T1, 6) ; JMP(.L_bi_set)

.L_bi_chk_max:
    LD_LOCAL(A0, 2) ; LD_LOCAL(A1, 3) ; LEA_SYM(A2, bi_max) ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JEQ(.L_bi_chk_pow)
    LEA_SYM(T0, rt_max) ; MOVI(T1, 6) ; JMP(.L_bi_set)

.L_bi_chk_pow:
    LD_LOCAL(A0, 2) ; LD_LOCAL(A1, 3) ; LEA_SYM(A2, bi_pow) ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JEQ(.L_bi_chk_ms)
    LEA_SYM(T0, rt_pow) ; MOVI(T1, 6) ; JMP(.L_bi_set)

.L_bi_chk_ms:
    LD_LOCAL(A0, 2) ; LD_LOCAL(A1, 3) ; LEA_SYM(A2, bi_mem_stats) ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JEQ(.L_bi_chk_gc)
    LEA_SYM(T0, rt_report) ; MOVI(T1, 17) ; JMP(.L_bi_set)

.L_bi_chk_gc:
    LD_LOCAL(A0, 2) ; LD_LOCAL(A1, 3) ; LEA_SYM(A2, bi_gc_collect) ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JEQ(.L_bi_chk_phi)
    LEA_SYM(T0, rt_gc_collect) ; MOVI(T1, 13) ; JMP(.L_bi_set)

.L_bi_chk_phi:
    LD_LOCAL(A0, 2) ; LD_LOCAL(A1, 3) ; LEA_SYM(A2, bi_phi_stats) ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JEQ(.L_bi_emit)
    LEA_SYM(T0, rt_phi_stats) ; MOVI(T1, 12)

.L_bi_set:
    ST_LOCAL(T0, 2)
    ST_LOCAL(T1, 3)

.L_bi_emit:
    SX_CALL(sx_new_vreg) ; MOVR(S3, R0)
    MOVI(A0, IR_CALL) ; MOVR(A1, S3)
    LD_LOCAL(A2, 2) ; LD_LOCAL(A3, 3)
    SX_CALL(sx_ir_emit)
    LD_LOCAL(T0, 0) ; ST64(T0, R0, IR_IMM) /* argc */
    MOVI(T0, TY_INT) ; ST64(T0, R0, IR_TYPE)
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
    JMP(.L_ge_ret_s3)

.L_ge_zero:
    SX_CALL(sx_new_vreg) ; MOVR(S3, R0)
    MOVI(A0, IR_CONST) ; MOVR(A1, S3) ; MOVI(A2, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    MOVI(T0, TY_INT) ; ST64(T0, R0, IR_TYPE)
    CMPI(S1, 0) ; JEQ(.L_ge_ret_s3)
    ST64(T0, S1, 0)
.L_ge_ret_s3:
    MOVR(R0, S3)
    SX_EPILOGUE
SX_ENDFUNC(sx_ir_gen_expr)

/* ----------------------------------------------------------------------------
 * Statement Lowering: sx_ir_gen_stmt(A0 = stmt_node)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_ir_gen_stmt)
    SX_PROLOGUE 32
    MOVR(S0, A0)
    CMPI(S0, 0) ; JEQ(.L_gs_done)
    LD64(S1, S0, AST_KIND)

    CMPI(S1, NK_BLOCK) ; JNE(.L_gs_let)
    LD64(S2, S0, AST_LEFT)
.L_gs_blk:
    CMPI(S2, 0) ; JEQ(.L_gs_done)
    MOVR(A0, S2) ; SX_CALL(sx_ir_gen_stmt)
    LD64(S2, S2, AST_NEXT)
    JMP(.L_gs_blk)

.L_gs_let:
    CMPI(S1, NK_LET) ; JNE(.L_gs_assign)
    LD64(A0, S0, AST_LEFT) ; LEA_LOCAL(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVR(S2, R0)                /* rhs vreg */
    LD_LOCAL(S3, 0)             /* rhs type */
    /* Always allocate a fresh named vreg via IR_MOV so ARC aliasing / reassignment works cleanly! */
    SX_CALL(sx_new_vreg) ; MOVR(S4, R0)
    MOVI(A0, IR_MOV) ; MOVR(A1, S4) ; MOVR(A2, S2) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    ST64(S3, R0, IR_TYPE)
    /* Tag ARC flag on alias copy if RHS was an existing ARC/Closure identifier */
    CMPI(S3, TY_ARC) ; JNE(.L_let_chk_gc)
    LD64(T0, S0, AST_LEFT) ; LD64(T1, T0, AST_KIND)
    CMPI(T1, NK_IDENT) ; JNE(.L_let_bind)
    MOVI(T0, IRF_ARC) ; ST64(T0, R0, IR_FLAGS)
    JMP(.L_let_bind)
.L_let_chk_gc:
    CMPI(S3, TY_GC) ; JNE(.L_let_bind)
    MOVI(T0, IRF_GC) ; ST64(T0, R0, IR_FLAGS)
.L_let_bind:
    LD64(A0, S0, AST_NAME_PTR) ; LD64(A1, S0, AST_NAME_LEN)
    MOVR(A2, S4) ; MOVR(A3, S3)
    SX_CALL(sx_ir_var_bind)
    JMP(.L_gs_done)

.L_gs_assign:
    CMPI(S1, NK_ASSIGN) ; JNE(.L_gs_ret)
    LD64(A0, S0, AST_LEFT) ; LEA_LOCAL(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVR(A0, R0) ; LD_LOCAL(A1, 0) ; SX_CALL(sx_unbox_if_managed)
    MOVR(S2, R0)
    LD64(A0, S0, AST_NAME_PTR) ; LD64(A1, S0, AST_NAME_LEN)
    SX_CALL(sx_ir_var_find)
    CMPI(R0, 0) ; JEQ(.L_gs_done)
    LD64(A1, R0, 16)            /* existing var vreg */
    MOVI(A0, IR_MOV) ; MOVR(A2, S2) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    JMP(.L_gs_done)

.L_gs_ret:
    CMPI(S1, NK_RETURN) ; JNE(.L_gs_if)
    LD64(A0, S0, AST_LEFT)
    CMPI(A0, 0) ; JEQ(.L_ret_z)
    LEA_LOCAL(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVR(A0, R0) ; LD_LOCAL(A1, 0) ; SX_CALL(sx_unbox_if_managed)
    MOVR(A2, R0)
    JMP(.L_ret_emit)
.L_ret_z:
    SX_CALL(sx_new_vreg) ; MOVR(S2, R0)
    MOVI(A0, IR_CONST) ; MOVR(A1, S2) ; MOVI(A2, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    MOVR(A2, S2)
.L_ret_emit:
    MOVI(A0, IR_RET) ; MOVI(A1, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    JMP(.L_gs_done)

.L_gs_if:
    CMPI(S1, NK_IF) ; JNE(.L_gs_while)
    SX_CALL(sx_new_label) ; MOVR(S2, R0) /* else_lbl */
    SX_CALL(sx_new_label) ; MOVR(S3, R0) /* end_lbl */
    LD64(A0, S0, AST_LEFT) ; MOVI(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVI(A0, IR_BRZ) ; MOVR(A1, S2) ; MOVR(A2, R0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    LD64(A0, S0, AST_RIGHT) ; SX_CALL(sx_ir_gen_stmt)
    MOVI(A0, IR_JMP) ; MOVR(A1, S3) ; MOVI(A2, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    MOVI(A0, IR_LABEL) ; MOVR(A1, S2) ; MOVI(A2, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    LD64(A0, S0, AST_EXTRA) ; SX_CALL(sx_ir_gen_stmt)
    MOVI(A0, IR_LABEL) ; MOVR(A1, S3) ; MOVI(A2, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    JMP(.L_gs_done)

.L_gs_while:
    CMPI(S1, NK_WHILE) ; JNE(.L_gs_prove)
    SX_CALL(sx_new_label) ; MOVR(S2, R0) /* top_lbl */
    SX_CALL(sx_new_label) ; MOVR(S3, R0) /* end_lbl */
    MOVI(A0, IR_LABEL) ; MOVR(A1, S2) ; MOVI(A2, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    LD64(A0, S0, AST_LEFT) ; MOVI(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVI(A0, IR_BRZ) ; MOVR(A1, S3) ; MOVR(A2, R0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    LD64(A0, S0, AST_RIGHT) ; SX_CALL(sx_ir_gen_stmt)
    MOVI(A0, IR_JMP) ; MOVR(A1, S2) ; MOVI(A2, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    MOVI(A0, IR_LABEL) ; MOVR(A1, S3) ; MOVI(A2, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    JMP(.L_gs_done)

.L_gs_prove:
    CMPI(S1, NK_PROVE) ; JNE(.L_gs_expr)
    LD64(A0, S0, AST_LEFT) ; MOVI(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVR(A2, R0)
    MOVI(A0, IR_PHI_ASSERT) ; MOVI(A1, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    LD64(T0, S0, AST_LINE) ; ST64(T0, R0, IR_IMM)
    /* If Phase 1 statically proved this, set IRF_PROVEN so Phi Opt eliminates it! */
    LD64(T0, S0, AST_META)
    CMPI(T0, PHI_PROVEN_STATIC) ; JNE(.L_gs_done)
    MOVI(T1, IRF_PROVEN) ; ST64(T1, R0, IR_FLAGS)
    JMP(.L_gs_done)

.L_gs_expr:
    CMPI(S1, NK_EXPR_STMT) ; JNE(.L_gs_done)
    LD64(A0, S0, AST_LEFT) ; MOVI(A1, 0) ; SX_CALL(sx_ir_gen_expr)
.L_gs_done:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_ir_gen_stmt)

/* ----------------------------------------------------------------------------
 * sx_ir_gen_program(A0 = program_root) -> R0 = ir_inst_count
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_ir_gen_program)
    SX_PROLOGUE 32
    MOVR(S0, A0)
    LEA_SYM(T0, g_ir_func_cnt) ; MOVI(T1, 0) ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_cur_lam_cap_ptr) ; ST64(T1, T0, 0)

    /* 1. Lower all user functions */
    LD64(S1, S0, AST_LEFT)
.L_igp_loop:
    CMPI(S1, 0) ; JEQ(.L_igp_lambdas)
    LD64(T0, S1, AST_KIND)
    CMPI(T0, NK_FUNC) ; JNE(.L_igp_next)
    /* Skip extern declarations (no body) */
    LD64(T0, S1, AST_RIGHT)
    CMPI(T0, 0) ; JEQ(.L_igp_next)

    /* Reset per-function vreg & var table */
    LEA_SYM(T0, g_ir_var_cnt) ; MOVI(T1, 0) ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_next_vreg)  ; MOVI(T1, 1) ; ST64(T1, T0, 0)

    /* Count parameters */
    MOVI(S2, 0)
    LD64(S3, S1, AST_LEFT)
.L_igp_pcnt:
    CMPI(S3, 0) ; JEQ(.L_igp_fbegin)
    ADDI(S2, 1)
    LD64(S3, S3, AST_NEXT)
    JMP(.L_igp_pcnt)

.L_igp_fbegin:
    LEA_SYM(T0, g_ir_func_cnt) ; LD64(S4, T0, 0)
    MOVR(T1, S4) ; ADDI(T1, 1) ; ST64(T1, T0, 0)

    MOVI(A0, IR_FUNC_BEGIN) ; MOVR(A1, S4)
    LD64(A2, S1, AST_NAME_PTR) ; LD64(A3, S1, AST_NAME_LEN)
    SX_CALL(sx_ir_emit)
    ST64(S2, R0, IR_IMM)        /* param count */

    /* Emit IR_PARAM for each parameter */
    MOVI(S2, 0)
    LD64(S3, S1, AST_LEFT)
.L_igp_pbind:
    CMPI(S3, 0) ; JEQ(.L_igp_req)
    SX_CALL(sx_new_vreg) ; ST_LOCAL(R0, 0)
    MOVI(A0, IR_PARAM) ; MOVR(A1, R0) ; MOVI(A2, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    ST64(S2, R0, IR_IMM)
    LD64(A0, S3, AST_NAME_PTR) ; LD64(A1, S3, AST_NAME_LEN)
    LD_LOCAL(A2, 0) ; LD64(A3, S3, AST_TYPE)
    SX_CALL(sx_ir_var_bind)
    ADDI(S2, 1)
    LD64(S3, S3, AST_NEXT)
    JMP(.L_igp_pbind)

.L_igp_req:
    /* Lower Phi `requires` precondition contract if present */
    LD64(A0, S1, AST_EXTRA)
    CMPI(A0, 0) ; JEQ(.L_igp_body)
    MOVI(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVR(A2, R0)
    MOVI(A0, IR_PHI_ASSERT) ; MOVI(A1, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    LD64(T0, S1, AST_LINE) ; ST64(T0, R0, IR_IMM)
    LD64(T0, S1, AST_META)
    CMPI(T0, PHI_PROVEN_STATIC) ; JNE(.L_igp_body)
    MOVI(T1, IRF_PROVEN) ; ST64(T1, R0, IR_FLAGS)

.L_igp_body:
    LD64(A0, S1, AST_RIGHT)
    SX_CALL(sx_ir_gen_stmt)

    MOVI(A0, IR_FUNC_END) ; MOVR(A1, S4) ; MOVI(A2, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)

.L_igp_next:
    LD64(S1, S1, AST_NEXT)
    JMP(.L_igp_loop)

    /* 2. Lower all lifted Lambda (Λ) closure bodies as top-level SUMIR functions! */
.L_igp_lambdas:
    MOVI(S1, 0)                 /* lambda index */
.L_igp_lam_loop:
    LEA_SYM(T0, g_lambda_count) ; LD64(T1, T0, 0)
    CMP(S1, T1) ; JGE(.L_igp_done)

    MOVR(S2, S1) ; SHLI(S2, 6)
    LEA_SYM(T0, g_lambdas) ; ADD(S2, T0) /* S2 = lam_desc */
    LD64(S3, S2, 0)             /* S3 = NK_LAMBDA ast node */

    LEA_SYM(T0, g_ir_var_cnt) ; MOVI(T1, 0) ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_next_vreg)  ; MOVI(T1, 1) ; ST64(T1, T0, 0)

    /* Format name __sx_lambda_<id> */
    MOVR(T0, S1) ; SHLI(T0, 5)
    LEA_SYM(T1, g_lam_names) ; ADD(T0, T1)
    ST_LOCAL(T0, 0)
    MOVR(A0, T0) ; MOVI(A1, 32)
    LEA_SYM(A2, fmt_lam_name) ; MOVR(A3, S1)
    SX_VCALL(snprintf)
    ST_LOCAL(R0, 1)

    LEA_SYM(T0, g_ir_func_cnt) ; LD64(S4, T0, 0)
    MOVR(T1, S4) ; ADDI(T1, 1) ; ST64(T1, T0, 0)

    /* Signature: __sx_lambda_i(closure_ptr, param0) */
    MOVI(A0, IR_FUNC_BEGIN) ; MOVR(A1, S4)
    LD_LOCAL(A2, 0) ; LD_LOCAL(A3, 1)
    SX_CALL(sx_ir_emit)
    MOVI(T0, 2) ; ST64(T0, R0, IR_IMM)

    /* param 0 = closure_ptr */
    SX_CALL(sx_new_vreg) ; ST_LOCAL(R0, 2)
    LEA_SYM(T0, g_cur_lam_closure_vreg) ; ST64(R0, T0, 0)
    MOVI(A0, IR_PARAM) ; MOVR(A1, R0) ; MOVI(A2, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    MOVI(T0, 0) ; ST64(T0, R0, IR_IMM)

    /* param 1 = lambda's user parameter */
    SX_CALL(sx_new_vreg) ; ST_LOCAL(R0, 3)
    MOVI(A0, IR_PARAM) ; MOVR(A1, R0) ; MOVI(A2, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)
    MOVI(T0, 1) ; ST64(T0, R0, IR_IMM)

    LD64(A0, S3, AST_NAME_PTR) ; LD64(A1, S3, AST_NAME_LEN)
    LD_LOCAL(A2, 3) ; MOVI(A3, TY_INT)
    SX_CALL(sx_ir_var_bind)

    /* Set active capture name for sx_ir_gen_expr */
    LD64(T0, S2, 8)  ; LEA_SYM(T1, g_cur_lam_cap_ptr) ; ST64(T0, T1, 0)
    LD64(T0, S2, 16) ; LEA_SYM(T1, g_cur_lam_cap_len) ; ST64(T0, T1, 0)

    LD64(A0, S3, AST_RIGHT) ; MOVI(A1, 0) ; SX_CALL(sx_ir_gen_expr)
    MOVR(A2, R0)
    MOVI(A0, IR_RET) ; MOVI(A1, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)

    MOVI(A0, IR_FUNC_END) ; MOVR(A1, S4) ; MOVI(A2, 0) ; MOVI(A3, 0)
    SX_CALL(sx_ir_emit)

    LEA_SYM(T1, g_cur_lam_cap_ptr) ; MOVI(T0, 0) ; ST64(T0, T1, 0)
    ADDI(S1, 1)
    JMP(.L_igp_lam_loop)

.L_igp_done:
    LEA_SYM(T0, g_ir_count)
    LD64(R0, T0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_ir_gen_program)
