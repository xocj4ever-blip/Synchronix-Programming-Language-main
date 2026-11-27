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
 * SYNCHRONIX COMPILER — Phase 1: Semantic Analyzer & Formal Logic (sema.S)
 * ============================================================================
 * Implements:
 *   - Semantic Analyzer & Type Checker (Typed AST)
 *   - Type Inference
 *   - Generics Resolution
 *   - Scope Analysis
 *   - Math & Formal Logic & Subsystems:
 *       * Phi (Φ) Formal Logic & Formal Verification (static + runtime proofs)
 *       * Lambda (Λ) Functional Logic (free-variable capture analysis & lifting)
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(err_undef_var,   "Semantic Error: undefined identifier")
SX_STR(err_phi_refuted, "Phi Formal Verification FAILED: proposition statically refuted (false)")
SX_STR(err_div_zero,    "Phi Formal Verification FAILED: provable division by zero")
SX_STR(fmt_ast_hdr,     "[Phase 1: Typed AST] nodes=%lld phi_static=%lld phi_runtime=%lld lambdas=%lld\n")
SX_STR(fmt_ast_fn,      "  func %.*s (flags=%lld, ret_type=%lld)\n")

SX_TEXT

/* ----------------------------------------------------------------------------
 * Scope & Symbol Table Operations
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_scope_push)
    SX_PROLOGUE 0
    LEA_SYM(T0, g_scope_depth)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_scope_push)

SX_FUNC(sx_scope_pop)
    SX_PROLOGUE 0
    LEA_SYM(T0, g_scope_depth)
    LD64(S0, T0, 0)             /* S0 = current depth */
    LEA_SYM(S1, g_sym_count)
    LD64(S2, S1, 0)             /* S2 = count */
    LEA_SYM(S3, g_symbols)
.L_pop_loop:
    CMPI(S2, 0) ; JLE(.L_pop_done)
    MOVR(T1, S2) ; SUBI(T1, 1)
    SHLI(T1, 6)                 /* * 64 (SYME_SIZE) */
    ADD(T1, S3)
    LD64(R0, T1, SYME_SCOPE)
    CMP(R0, S0)
    JLT(.L_pop_done)
    SUBI(S2, 1)
    JMP(.L_pop_loop)
.L_pop_done:
    ST64(S2, S1, 0)
    SUBI(S0, 1)
    ST64(S0, T0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_scope_pop)

/* sx_sym_add(A0=name_ptr, A1=name_len, A2=type, A3=mem_kind) -> R0=sym_ptr */
SX_FUNC(sx_sym_add)
    SX_PROLOGUE 16
    MOVR(S0, A0) ; MOVR(S1, A1) ; MOVR(S2, A2) ; MOVR(S3, A3)
    LEA_SYM(T0, g_sym_count)
    LD64(S4, T0, 0)
    CMPI(S4, MAX_SYMBOLS) ; JGE(.L_sa_full)
    MOVR(T1, S4) ; ADDI(T1, 1) ; ST64(T1, T0, 0)

    SHLI(S4, 6)
    LEA_SYM(T0, g_symbols)
    ADD(S4, T0)
    ST64(S0, S4, SYME_NAME_PTR)
    ST64(S1, S4, SYME_NAME_LEN)
    ST64(S2, S4, SYME_TYPE)
    LEA_SYM(T0, g_scope_depth) ; LD64(T1, T0, 0)
    ST64(T1, S4, SYME_SCOPE)
    MOVI(T0, OWN_OWNED) ; ST64(T0, S4, SYME_OWN_STATE)
    ST64(S3, S4, SYME_MEM_KIND)
    MOVI(T0, 0)
    ST64(T0, S4, SYME_SLOT)
    ST64(T0, S4, SYME_CONST_VAL)
    MOVR(R0, S4)
    SX_EPILOGUE
.L_sa_full:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_sym_add)

/* sx_sym_lookup(A0=name_ptr, A1=name_len) -> R0=sym_ptr or 0 */
SX_FUNC(sx_sym_lookup)
    SX_PROLOGUE 16
    MOVR(S0, A0) ; MOVR(S1, A1)
    LEA_SYM(T0, g_sym_count)
    LD64(S2, T0, 0)
    LEA_SYM(S3, g_symbols)
.L_sl_loop:
    CMPI(S2, 0) ; JLE(.L_sl_none)
    SUBI(S2, 1)
    MOVR(S4, S2) ; SHLI(S4, 6) ; ADD(S4, S3)
    MOVR(A0, S0) ; MOVR(A1, S1)
    LD64(A2, S4, SYME_NAME_PTR)
    LD64(A3, S4, SYME_NAME_LEN)
    SX_CALL(sx_slice_eq_slice)
    CMPI(R0, 0) ; JNE(.L_sl_found)
    JMP(.L_sl_loop)
.L_sl_found:
    MOVR(R0, S4)
    SX_EPILOGUE
.L_sl_none:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_sym_lookup)

/* ----------------------------------------------------------------------------
 * Phi (Φ) Static Formal Evaluator:
 * sx_phi_eval_const(A0 = expr_node, A1 = out_val_ptr) -> R0 = 1 if const else 0
 * Evaluates compile-time constant arithmetic & logical propositions!
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_phi_eval_const)
    SX_PROLOGUE 32
    MOVR(S0, A0)                /* expr */
    MOVR(S1, A1)                /* out_val_ptr */
    CMPI(S0, 0) ; JEQ(.L_pe_not)
    LD64(S2, S0, AST_KIND)

    CMPI(S2, NK_INT) ; JNE(.L_pe_bin)
    LD64(T0, S0, AST_IVAL)
    ST64(T0, S1, 0)
    MOVI(R0, 1) ; SX_EPILOGUE

.L_pe_bin:
    CMPI(S2, NK_BINOP) ; JNE(.L_pe_un)
    LD64(A0, S0, AST_LEFT)
    LEA_LOCAL(A1, 0)
    SX_CALL(sx_phi_eval_const)
    CMPI(R0, 0) ; JEQ(.L_pe_not)

    LD64(A0, S0, AST_RIGHT)
    LEA_LOCAL(A1, 1)
    SX_CALL(sx_phi_eval_const)
    CMPI(R0, 0) ; JEQ(.L_pe_not)

    LD_LOCAL(S3, 0)             /* lhs */
    LD_LOCAL(S4, 1)             /* rhs */
    LD64(T0, S0, AST_IVAL)      /* op */

    CMPI(T0, TK_PLUS)  ; JNE(.L_pe_sub)
    MOVR(R0, S3) ; ADD(R0, S4) ; JMP(.L_pe_ok)
.L_pe_sub:
    CMPI(T0, TK_MINUS) ; JNE(.L_pe_mul)
    MOVR(R0, S3) ; SUB(R0, S4) ; JMP(.L_pe_ok)
.L_pe_mul:
    CMPI(T0, TK_STAR)  ; JNE(.L_pe_div)
    MOVR(R0, S3) ; MUL(R0, S4) ; JMP(.L_pe_ok)
.L_pe_div:
    CMPI(T0, TK_SLASH) ; JNE(.L_pe_eq)
    CMPI(S4, 0) ; JEQ(.L_pe_not)
    MOVR(R0, S3) ; MOVR(T0, S4) ; SDIV_R0_T0 ; JMP(.L_pe_ok)
.L_pe_eq:
    CMPI(T0, TK_EQ) ; JNE(.L_pe_ne)
    MOVI(R0, 0) ; CMP(S3, S4) ; JNE(.L_pe_ok) ; MOVI(R0, 1) ; JMP(.L_pe_ok)
.L_pe_ne:
    CMPI(T0, TK_NE) ; JNE(.L_pe_lt)
    MOVI(R0, 0) ; CMP(S3, S4) ; JEQ(.L_pe_ok) ; MOVI(R0, 1) ; JMP(.L_pe_ok)
.L_pe_lt:
    CMPI(T0, TK_LT) ; JNE(.L_pe_le)
    MOVI(R0, 0) ; CMP(S3, S4) ; JGE(.L_pe_ok) ; MOVI(R0, 1) ; JMP(.L_pe_ok)
.L_pe_le:
    CMPI(T0, TK_LE) ; JNE(.L_pe_gt)
    MOVI(R0, 0) ; CMP(S3, S4) ; JGT(.L_pe_ok) ; MOVI(R0, 1) ; JMP(.L_pe_ok)
.L_pe_gt:
    CMPI(T0, TK_GT) ; JNE(.L_pe_ge)
    MOVI(R0, 0) ; CMP(S3, S4) ; JLE(.L_pe_ok) ; MOVI(R0, 1) ; JMP(.L_pe_ok)
.L_pe_ge:
    CMPI(T0, TK_GE) ; JNE(.L_pe_not)
    MOVI(R0, 0) ; CMP(S3, S4) ; JLT(.L_pe_ok) ; MOVI(R0, 1) ; JMP(.L_pe_ok)

.L_pe_un:
    CMPI(S2, NK_UNOP) ; JNE(.L_pe_not)
    LD64(A0, S0, AST_LEFT)
    LEA_LOCAL(A1, 0)
    SX_CALL(sx_phi_eval_const)
    CMPI(R0, 0) ; JEQ(.L_pe_not)
    LD_LOCAL(R0, 0)
    LD64(T0, S0, AST_IVAL)
    CMPI(T0, TK_MINUS) ; JNE(.L_pe_bang)
    NEG(R0) ; JMP(.L_pe_ok)
.L_pe_bang:
    CMPI(R0, 0) ; JNE(.L_pe_bang0)
    MOVI(R0, 1) ; JMP(.L_pe_ok)
.L_pe_bang0:
    MOVI(R0, 0)
.L_pe_ok:
    ST64(R0, S1, 0)
    MOVI(R0, 1)
    SX_EPILOGUE
.L_pe_not:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_phi_eval_const)

/* ----------------------------------------------------------------------------
 * Lambda (Λ) Capture Scanner:
 * sx_lambda_scan_cap(A0=expr, A1=param_ptr, A2=param_len, A3=lam_desc_ptr)
 * Finds free variable referenced inside lambda body that != param_name
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_lambda_scan_cap)
    SX_PROLOGUE 32
    MOVR(S0, A0) ; MOVR(S1, A1) ; MOVR(S2, A2) ; MOVR(S3, A3)
    CMPI(S0, 0) ; JEQ(.L_lsc_done)
    LD64(S4, S0, AST_KIND)

    CMPI(S4, NK_IDENT) ; JNE(.L_lsc_children)
    /* Check if ident == param */
    LD64(A0, S0, AST_NAME_PTR) ; LD64(A1, S0, AST_NAME_LEN)
    MOVR(A2, S1) ; MOVR(A3, S2)
    SX_CALL(sx_slice_eq_slice)
    CMPI(R0, 0) ; JNE(.L_lsc_done)
    /* Captured free variable! Record in lam_desc[+8] = ptr, [+16] = len */
    LD64(T0, S0, AST_NAME_PTR) ; ST64(T0, S3, 8)
    LD64(T0, S0, AST_NAME_LEN) ; ST64(T0, S3, 16)
    JMP(.L_lsc_done)

.L_lsc_children:
    LD64(A0, S0, AST_LEFT)  ; MOVR(A1, S1) ; MOVR(A2, S2) ; MOVR(A3, S3)
    SX_CALL(sx_lambda_scan_cap)
    LD64(A0, S0, AST_RIGHT) ; MOVR(A1, S1) ; MOVR(A2, S2) ; MOVR(A3, S3)
    SX_CALL(sx_lambda_scan_cap)
.L_lsc_done:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_lambda_scan_cap)

/* ----------------------------------------------------------------------------
 * sx_sema_expr(A0 = expr_node) -> R0 = inferred TY_*
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_sema_expr)
    SX_PROLOGUE 32
    MOVR(S0, A0)
    CMPI(S0, 0) ; JEQ(.L_se_void)
    LD64(S1, S0, AST_KIND)

    CMPI(S1, NK_INT) ; JNE(.L_se_str)
    LD64(R0, S0, AST_TYPE)
    CMPI(R0, TY_UNKNOWN) ; JNE(.L_se_ret)
    MOVI(R0, TY_INT) ; ST64(R0, S0, AST_TYPE) ; SX_EPILOGUE

.L_se_str:
    CMPI(S1, NK_STR) ; JNE(.L_se_ident)
    MOVI(R0, TY_STR) ; ST64(R0, S0, AST_TYPE) ; SX_EPILOGUE

.L_se_ident:
    CMPI(S1, NK_IDENT) ; JNE(.L_se_binop)
    LD64(A0, S0, AST_NAME_PTR)
    LD64(A1, S0, AST_NAME_LEN)
    SX_CALL(sx_sym_lookup)
    CMPI(R0, 0) ; JNE(.L_se_id_ok)
    LD64(A0, S0, AST_LINE)
    LEA_SYM(A1, err_undef_var)
    SX_CALL(sx_error)
    MOVI(R0, TY_INT) ; ST64(R0, S0, AST_TYPE) ; SX_EPILOGUE
.L_se_id_ok:
    LD64(R0, R0, SYME_TYPE)
    ST64(R0, S0, AST_TYPE)
    SX_EPILOGUE

.L_se_binop:
    CMPI(S1, NK_BINOP) ; JNE(.L_se_unop)
    LD64(A0, S0, AST_LEFT)  ; SX_CALL(sx_sema_expr)
    LD64(A0, S0, AST_RIGHT) ; SX_CALL(sx_sema_expr)
    /* Phi Formal Verification: statically check division by literal 0! */
    LD64(T0, S0, AST_IVAL)
    CMPI(T0, TK_SLASH) ; JNE(.L_se_bin_ty)
    LD64(A0, S0, AST_RIGHT)
    LEA_LOCAL(A1, 0)
    SX_CALL(sx_phi_eval_const)
    CMPI(R0, 0) ; JEQ(.L_se_bin_ty)
    LD_LOCAL(T0, 0)
    CMPI(T0, 0) ; JNE(.L_se_bin_ty)
    LD64(A0, S0, AST_LINE)
    LEA_SYM(A1, err_div_zero)
    SX_CALL(sx_error)
.L_se_bin_ty:
    MOVI(R0, TY_INT) ; ST64(R0, S0, AST_TYPE) ; SX_EPILOGUE

.L_se_unop:
    CMPI(S1, NK_UNOP) ; JNE(.L_se_arc)
    LD64(A0, S0, AST_LEFT) ; SX_CALL(sx_sema_expr)
    MOVI(R0, TY_INT) ; ST64(R0, S0, AST_TYPE) ; SX_EPILOGUE

.L_se_arc:
    CMPI(S1, NK_ARC_NEW) ; JNE(.L_se_gc)
    LD64(A0, S0, AST_LEFT) ; SX_CALL(sx_sema_expr)
    MOVI(R0, TY_ARC) ; ST64(R0, S0, AST_TYPE) ; SX_EPILOGUE

.L_se_gc:
    CMPI(S1, NK_GC_NEW) ; JNE(.L_se_borrow)
    LD64(A0, S0, AST_LEFT) ; SX_CALL(sx_sema_expr)
    MOVI(R0, TY_GC) ; ST64(R0, S0, AST_TYPE) ; SX_EPILOGUE

.L_se_borrow:
    CMPI(S1, NK_BORROW) ; JNE(.L_se_move)
    LD64(A0, S0, AST_LEFT) ; SX_CALL(sx_sema_expr)
    MOVI(R0, TY_BORROW) ; ST64(R0, S0, AST_TYPE) ; SX_EPILOGUE

.L_se_move:
    CMPI(S1, NK_MOVE) ; JNE(.L_se_lambda)
    LD64(A0, S0, AST_LEFT) ; SX_CALL(sx_sema_expr)
    ST64(R0, S0, AST_TYPE) ; SX_EPILOGUE

.L_se_lambda:
    CMPI(S1, NK_LAMBDA) ; JNE(.L_se_spawn)
    /* Lambda (Λ) Functional Logic: register lambda & analyze captures */
    LEA_SYM(T0, g_lambda_count)
    LD64(S2, T0, 0)
    MOVR(T1, S2) ; ADDI(T1, 1) ; ST64(T1, T0, 0)
    ST64(S2, S0, AST_META)      /* store lambda ID */

    MOVR(S3, S2) ; SHLI(S3, 6)  /* * 64 */
    LEA_SYM(T0, g_lambdas) ; ADD(S3, T0)
    ST64(S0, S3, 0)             /* [0] = ast_ptr */
    MOVI(T0, 0)
    ST64(T0, S3, 8)             /* [8] = cap_name_ptr */
    ST64(T0, S3, 16)            /* [16] = cap_name_len */
    ST64(T0, S3, 24)            /* [24] = cap_vreg */
    LD64(T0, S0, AST_NAME_PTR) ; ST64(T0, S3, 32)
    LD64(T0, S0, AST_NAME_LEN) ; ST64(T0, S3, 40)
    ST64(S2, S3, 48)            /* [48] = id */

    /* Scan body for captured free variables */
    LD64(A0, S0, AST_RIGHT)
    LD64(A1, S0, AST_NAME_PTR)
    LD64(A2, S0, AST_NAME_LEN)
    MOVR(A3, S3)
    SX_CALL(sx_lambda_scan_cap)

    /* Type-check lambda body in child scope with param bound */
    SX_CALL(sx_scope_push)
    LD64(A0, S0, AST_NAME_PTR)
    LD64(A1, S0, AST_NAME_LEN)
    MOVI(A2, TY_INT)
    MOVI(A3, MEM_STACK)
    SX_CALL(sx_sym_add)
    LD64(A0, S0, AST_RIGHT) ; SX_CALL(sx_sema_expr)
    SX_CALL(sx_scope_pop)

    MOVI(R0, TY_CLOSURE) ; ST64(R0, S0, AST_TYPE) ; SX_EPILOGUE

.L_se_spawn:
    CMPI(S1, NK_SPAWN) ; JNE(.L_se_await)
    LD64(A0, S0, AST_LEFT) ; SX_CALL(sx_sema_expr)
    MOVI(R0, TY_TASK) ; ST64(R0, S0, AST_TYPE) ; SX_EPILOGUE

.L_se_await:
    CMPI(S1, NK_AWAIT) ; JNE(.L_se_call)
    LD64(A0, S0, AST_LEFT) ; SX_CALL(sx_sema_expr)
    MOVI(R0, TY_INT) ; ST64(R0, S0, AST_TYPE) ; SX_EPILOGUE

.L_se_call:
    CMPI(S1, NK_CALL) ; JNE(.L_se_void)
    /* Check all arguments */
    LD64(S2, S0, AST_RIGHT)
.L_se_arg_loop:
    CMPI(S2, 0) ; JEQ(.L_se_call_ty)
    MOVR(A0, S2) ; SX_CALL(sx_sema_expr)
    LD64(S2, S2, AST_NEXT)
    JMP(.L_se_arg_loop)
.L_se_call_ty:
    /* Generics Resolution: if explicit generic type arg in AST_EXTRA2, adopt it! */
    LD64(R0, S0, AST_EXTRA2)
    CMPI(R0, TY_UNKNOWN) ; JNE(.L_se_call_set)
    MOVI(R0, TY_INT)
.L_se_call_set:
    ST64(R0, S0, AST_TYPE)
    SX_EPILOGUE

.L_se_void:
    MOVI(R0, TY_VOID)
.L_se_ret:
    SX_EPILOGUE
SX_ENDFUNC(sx_sema_expr)

/* ----------------------------------------------------------------------------
 * Phi Verification Helper: sx_verify_phi_node(A0 = expr_node, A1 = owner_node)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_verify_phi_node)
    SX_PROLOGUE 32
    MOVR(S0, A0)                /* expr */
    MOVR(S1, A1)                /* owner AST node to annotate */
    CMPI(S0, 0) ; JEQ(.L_vp_done)
    MOVR(A0, S0)
    SX_CALL(sx_sema_expr)

    MOVR(A0, S0)
    LEA_LOCAL(A1, 0)
    SX_CALL(sx_phi_eval_const)
    CMPI(R0, 0) ; JEQ(.L_vp_runtime)

    LD_LOCAL(T0, 0)
    CMPI(T0, 0) ; JEQ(.L_vp_refuted)

    /* Statically Proven! Zero runtime overhead! */
    MOVI(T0, PHI_PROVEN_STATIC)
    ST64(T0, S1, AST_META)
    LEA_SYM(T0, g_stat_phi_static) ; LD64(T1, T0, 0) ; ADDI(T1, 1) ; ST64(T1, T0, 0)
    JMP(.L_vp_done)

.L_vp_refuted:
    MOVI(T0, PHI_REFUTED)
    ST64(T0, S1, AST_META)
    LD64(A0, S1, AST_LINE)
    LEA_SYM(A1, err_phi_refuted)
    SX_CALL(sx_error)
    JMP(.L_vp_done)

.L_vp_runtime:
    MOVI(T0, PHI_RUNTIME_CHECK)
    ST64(T0, S1, AST_META)
    LEA_SYM(T0, g_stat_phi_runtime) ; LD64(T1, T0, 0) ; ADDI(T1, 1) ; ST64(T1, T0, 0)
.L_vp_done:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_verify_phi_node)

/* ----------------------------------------------------------------------------
 * sx_sema_stmt(A0 = stmt_node)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_sema_stmt)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    CMPI(S0, 0) ; JEQ(.L_ss_done)
    LD64(S1, S0, AST_KIND)

    CMPI(S1, NK_BLOCK) ; JNE(.L_ss_let)
    SX_CALL(sx_scope_push)
    LD64(S2, S0, AST_LEFT)
.L_ss_blk_loop:
    CMPI(S2, 0) ; JEQ(.L_ss_blk_end)
    MOVR(A0, S2) ; SX_CALL(sx_sema_stmt)
    LD64(S2, S2, AST_NEXT)
    JMP(.L_ss_blk_loop)
.L_ss_blk_end:
    SX_CALL(sx_scope_pop)
    JMP(.L_ss_done)

.L_ss_let:
    CMPI(S1, NK_LET) ; JNE(.L_ss_assign)
    LD64(A0, S0, AST_LEFT) ; SX_CALL(sx_sema_expr)
    MOVR(S2, R0)                /* inferred type */
    LD64(T0, S0, AST_TYPE)
    CMPI(T0, TY_UNKNOWN) ; JNE(.L_ss_let_keep)
    ST64(S2, S0, AST_TYPE)
    JMP(.L_ss_let_mem)
.L_ss_let_keep:
    /* Keep explicit type, unless RHS is ARC/GC/Closure */
    CMPI(S2, TY_ARC)     ; JEQ(.L_ss_let_ov)
    CMPI(S2, TY_GC)      ; JEQ(.L_ss_let_ov)
    CMPI(S2, TY_CLOSURE) ; JEQ(.L_ss_let_ov)
    MOVR(S2, T0)
    JMP(.L_ss_let_mem)
.L_ss_let_ov:
    ST64(S2, S0, AST_TYPE)
.L_ss_let_mem:
    MOVI(A3, MEM_STACK)
    CMPI(S2, TY_ARC)     ; JNE(.L_lm1) ; MOVI(A3, MEM_ARC)
.L_lm1:
    CMPI(S2, TY_GC)      ; JNE(.L_lm2) ; MOVI(A3, MEM_GC)
.L_lm2:
    CMPI(S2, TY_CLOSURE) ; JNE(.L_lm3) ; MOVI(A3, MEM_CLOSURE)
.L_lm3:
    LD64(A0, S0, AST_NAME_PTR)
    LD64(A1, S0, AST_NAME_LEN)
    MOVR(A2, S2)
    SX_CALL(sx_sym_add)
    JMP(.L_ss_done)

.L_ss_assign:
    CMPI(S1, NK_ASSIGN) ; JNE(.L_ss_ret)
    LD64(A0, S0, AST_LEFT) ; SX_CALL(sx_sema_expr)
    JMP(.L_ss_done)

.L_ss_ret:
    CMPI(S1, NK_RETURN) ; JNE(.L_ss_if)
    LD64(A0, S0, AST_LEFT) ; SX_CALL(sx_sema_expr)
    JMP(.L_ss_done)

.L_ss_if:
    CMPI(S1, NK_IF) ; JNE(.L_ss_while)
    LD64(A0, S0, AST_LEFT)  ; SX_CALL(sx_sema_expr)
    LD64(A0, S0, AST_RIGHT) ; SX_CALL(sx_sema_stmt)
    LD64(A0, S0, AST_EXTRA) ; SX_CALL(sx_sema_stmt)
    JMP(.L_ss_done)

.L_ss_while:
    CMPI(S1, NK_WHILE) ; JNE(.L_ss_prove)
    LD64(A0, S0, AST_LEFT)  ; SX_CALL(sx_sema_expr)
    LD64(A0, S0, AST_RIGHT) ; SX_CALL(sx_sema_stmt)
    JMP(.L_ss_done)

.L_ss_prove:
    CMPI(S1, NK_PROVE) ; JNE(.L_ss_expr)
    LD64(A0, S0, AST_LEFT)
    MOVR(A1, S0)
    SX_CALL(sx_verify_phi_node)
    JMP(.L_ss_done)

.L_ss_expr:
    CMPI(S1, NK_EXPR_STMT) ; JNE(.L_ss_done)
    LD64(A0, S0, AST_LEFT) ; SX_CALL(sx_sema_expr)
.L_ss_done:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_sema_stmt)

/* ----------------------------------------------------------------------------
 * sx_sema_program(A0 = program_root) -> R0 = error_count
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_sema_program)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    LD64(S1, S0, AST_LEFT)      /* decl list */
.L_sp_loop:
    CMPI(S1, 0) ; JEQ(.L_sp_done)
    LD64(S2, S1, AST_KIND)

    CMPI(S2, NK_PHI_DECL) ; JNE(.L_sp_func)
    LD64(A0, S1, AST_LEFT)
    MOVR(A1, S1)
    SX_CALL(sx_verify_phi_node)
    JMP(.L_sp_next)

.L_sp_func:
    CMPI(S2, NK_FUNC) ; JNE(.L_sp_next)
    SX_CALL(sx_scope_push)
    /* Bind parameters */
    LD64(S3, S1, AST_LEFT)
.L_sp_ploop:
    CMPI(S3, 0) ; JEQ(.L_sp_contracts)
    LD64(A0, S3, AST_NAME_PTR)
    LD64(A1, S3, AST_NAME_LEN)
    LD64(A2, S3, AST_TYPE)
    MOVI(A3, MEM_STACK)
    SX_CALL(sx_sym_add)
    LD64(S3, S3, AST_NEXT)
    JMP(.L_sp_ploop)

.L_sp_contracts:
    /* Verify requires contract */
    LD64(A0, S1, AST_EXTRA)
    CMPI(A0, 0) ; JEQ(.L_sp_body)
    MOVR(A1, S1)
    SX_CALL(sx_verify_phi_node)

.L_sp_body:
    LD64(A0, S1, AST_RIGHT)
    SX_CALL(sx_sema_stmt)
    SX_CALL(sx_scope_pop)

.L_sp_next:
    LD64(S1, S1, AST_NEXT)
    JMP(.L_sp_loop)

.L_sp_done:
    /* Optional AST dump */
    LEA_SYM(T0, g_opt_dump_ast) ; LD64(T1, T0, 0)
    CMPI(T1, 0) ; JEQ(.L_sp_ret)
    SX_CALL(sx_dump_ast)
.L_sp_ret:
    LEA_SYM(T0, g_err_count)
    LD64(R0, T0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_sema_program)

/* ----------------------------------------------------------------------------
 * sx_dump_ast() — Diagnostic dump of Typed AST
 * ----------------------------------------------------------------------------
 */
SX_RODATA
SX_STR(fmt_ast_p1, "[Phase 1: Typed AST] nodes=%lld phi_static=%lld phi_runtime=%lld")
SX_STR(fmt_ast_p2, " lambdas=%lld\n")

SX_TEXT
SX_FUNC(sx_dump_ast)
    SX_PROLOGUE 16
    LEA_SYM(T0, g_stat_phi_runtime) ; LD64(A3, T0, 0)
    LEA_SYM(T0, g_stat_phi_static)  ; LD64(A2, T0, 0)
    LEA_SYM(T0, g_ast_count)        ; LD64(A1, T0, 0)
    LEA_SYM(A0, fmt_ast_p1)
    SX_VCALL(printf)

    LEA_SYM(T0, g_lambda_count) ; LD64(A1, T0, 0)
    LEA_SYM(A0, fmt_ast_p2)
    SX_VCALL(printf)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_dump_ast)
