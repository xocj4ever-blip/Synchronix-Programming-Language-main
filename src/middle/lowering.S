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
 * SYNCHRONIX COMPILER — Phase 2: Lowering & Optimizations (src/middle/lowering.S)
 * ============================================================================
 * Implements SUMIR -> Lowering -> Low-Level IR / LLVM IR:
 *   1. Constant Folding (propagates & folds arithmetic/comparisons at compile time)
 *   2. Inlining (identifies & marks/inlines small leaf functions)
 *   3. Dead Code Elimination (DCE: backward liveness from side-effect roots)
 *   4. Diagnostic IR Dumper (--dump-ir)
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(fmt_ir_hdr,   "[Phase 2: SUMIR/Lowering] insts=%lld const_folded=%lld dce_removed=%lld")
SX_STR(fmt_ir_hdr2,  " arc_ops=%lld gc_roots=%lld inlined=%lld\n")

SX_BSS
.p2align 4
SX_LABEL(g_cf_is_const)
    .skip (MAX_VREGS * 8)
SX_LABEL(g_cf_val)
    .skip (MAX_VREGS * 8)
SX_LABEL(g_dce_used)
    .skip (MAX_VREGS * 8)
SX_LABEL(g_cf_def_cnt)
    .skip (MAX_VREGS * 8)

SX_TEXT

/* ----------------------------------------------------------------------------
 * Pass 1: Constant Folding (with SSA single-def safety for loops!)
 * Only folds vregs that are defined exactly ONCE in their function!
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_pass_const_fold)
    SX_PROLOGUE 32
    LEA_SYM(T0, g_ir_count) ; LD64(S0, T0, 0)   /* S0 = count */
    MOVI(S1, 0)                                  /* i */

.L_cf_outer:
    CMP(S1, S0) ; JGE(.L_cf_done)
    MOVR(S2, S1) ; SHLI(S2, 6)
    LEA_SYM(T0, g_ir_buf) ; ADD(S2, T0)
    LD64(S3, S2, IR_OP)

    CMPI(S3, IR_FUNC_BEGIN) ; JNE(.L_cf_next_fn)
    /* Count definitions per vreg in this function [S1 .. func_end] */
    LEA_SYM(A0, g_cf_is_const) ; MOVI(A1, 0) ; MOVI64(A2, MAX_VREGS * 8) ; SX_CALL(memset)
    LEA_SYM(A0, g_cf_def_cnt)  ; MOVI(A1, 0) ; MOVI64(A2, MAX_VREGS * 8) ; SX_CALL(memset)

    MOVR(S4, S1) ; ADDI(S4, 1)
.L_cf_cnt_loop:
    CMP(S4, S0) ; JGE(.L_cf_fold_start)
    MOVR(T0, S4) ; SHLI(T0, 6) ; LEA_SYM(T1, g_ir_buf) ; ADD(T0, T1)
    LD64(R0, T0, IR_OP)
    CMPI(R0, IR_FUNC_END) ; JEQ(.L_cf_fold_start)
    CMPI(R0, IR_LABEL) ; JEQ(.L_cf_cnt_nxt)
    CMPI(R0, IR_JMP)   ; JEQ(.L_cf_cnt_nxt)
    CMPI(R0, IR_BRZ)   ; JEQ(.L_cf_cnt_nxt)
    LD64(R0, T0, IR_DST)
    CMPI(R0, 0) ; JLE(.L_cf_cnt_nxt)
    CMPI(R0, MAX_VREGS) ; JGE(.L_cf_cnt_nxt)
    LEA_SYM(T1, g_cf_def_cnt) ; LD64_IDX(T0, T1, R0) ; ADDI(T0, 1) ; ST64_IDX(T0, T1, R0)
.L_cf_cnt_nxt:
    ADDI(S4, 1)
    JMP(.L_cf_cnt_loop)

.L_cf_fold_start:
    MOVR(S4, S1) ; ADDI(S4, 1)
.L_cf_fold_loop:
    CMP(S4, S0) ; JGE(.L_cf_done)
    MOVR(S2, S4) ; SHLI(S2, 6) ; LEA_SYM(T0, g_ir_buf) ; ADD(S2, T0)
    LD64(S3, S2, IR_OP)
    CMPI(S3, IR_FUNC_END) ; JEQ(.L_cf_end_fn)

    LD64(T0, S2, IR_FLAGS)
    ANDI(T0, IRF_DEAD) ; CMPI(T0, 0) ; JNE(.L_cf_fold_nxt)

    /* Record single-def IR_CONST */
    CMPI(S3, IR_CONST) ; JNE(.L_cf_mov)
    LD64(T0, S2, IR_DST)
    CMPI(T0, MAX_VREGS) ; JGE(.L_cf_fold_nxt)
    LEA_SYM(T1, g_cf_def_cnt) ; LD64_IDX(R0, T1, T0)
    CMPI(R0, 1) ; JNE(.L_cf_fold_nxt)
    LEA_SYM(T1, g_cf_is_const) ; MOVI(R0, 1) ; ST64_IDX(R0, T1, T0)
    LD64(R0, S2, IR_IMM)
    LEA_SYM(T1, g_cf_val) ; ST64_IDX(R0, T1, T0)
    JMP(.L_cf_fold_nxt)

.L_cf_mov:
    /* Propagate constant through IR_MOV (only if not ARC/GC tagged) */
    CMPI(S3, IR_MOV) ; JNE(.L_cf_bin)
    LD64(T0, S2, IR_FLAGS) ; ANDI(T0, (IRF_ARC | IRF_GC))
    CMPI(T0, 0) ; JNE(.L_cf_fold_nxt)
    LD64(T0, S2, IR_DST)
    CMPI(T0, MAX_VREGS) ; JGE(.L_cf_fold_nxt)
    LEA_SYM(T1, g_cf_def_cnt) ; LD64_IDX(R0, T1, T0)
    CMPI(R0, 1) ; JNE(.L_cf_fold_nxt)
    LD64(T1, S2, IR_SRC1)
    CMPI(T1, MAX_VREGS) ; JGE(.L_cf_fold_nxt)
    LEA_SYM(R0, g_cf_is_const) ; LD64_IDX(R0, R0, T1)
    CMPI(R0, 0) ; JEQ(.L_cf_fold_nxt)
    LEA_SYM(R0, g_cf_val) ; LD64_IDX(R0, R0, T1)
    /* Rewrite IR_MOV -> IR_CONST */
    MOVI(T1, IR_CONST) ; ST64(T1, S2, IR_OP)
    ST64(R0, S2, IR_IMM)
    LEA_SYM(T1, g_cf_is_const) ; MOVI(A0, 1) ; ST64_IDX(A0, T1, T0)
    LEA_SYM(T1, g_cf_val)      ; ST64_IDX(R0, T1, T0)
    JMP(.L_cf_fold_nxt)

.L_cf_bin:
    CMPI(S3, IR_ADD) ; JLT(.L_cf_fold_nxt)
    CMPI(S3, IR_MOD) ; JGT(.L_cf_fold_nxt)
    LD64(T0, S2, IR_SRC1) ; LD64(T1, S2, IR_SRC2)
    CMPI(T0, MAX_VREGS) ; JGE(.L_cf_fold_nxt)
    CMPI(T1, MAX_VREGS) ; JGE(.L_cf_fold_nxt)
    LEA_SYM(R0, g_cf_is_const) ; LD64_IDX(A0, R0, T0) ; CMPI(A0, 0) ; JEQ(.L_cf_fold_nxt)
    LD64_IDX(A1, R0, T1) ; CMPI(A1, 0) ; JEQ(.L_cf_fold_nxt)

    LEA_SYM(A2, g_cf_val)
    LD64_IDX(R0, A2, T0)        /* lhs */
    LD64_IDX(A3, A2, T1)        /* rhs */

    CMPI(S3, IR_ADD) ; JNE(.L_cf_s) ; ADD(R0, A3) ; JMP(.L_cf_commit)
.L_cf_s:
    CMPI(S3, IR_SUB) ; JNE(.L_cf_m) ; SUB(R0, A3) ; JMP(.L_cf_commit)
.L_cf_m:
    CMPI(S3, IR_MUL) ; JNE(.L_cf_d) ; MUL(R0, A3) ; JMP(.L_cf_commit)
.L_cf_d:
    CMPI(S3, IR_DIV) ; JNE(.L_cf_r)
    CMPI(A3, 0) ; JEQ(.L_cf_fold_nxt)
    MOVR(T0, A3) ; SDIV_R0_T0 ; JMP(.L_cf_commit)
.L_cf_r:
    CMPI(A3, 0) ; JEQ(.L_cf_fold_nxt)
    MOVR(T0, A3) ; SMOD_R0_T0

.L_cf_commit:
    /* Replace binary instruction with folded IR_CONST! */
    MOVI(T0, IR_CONST) ; ST64(T0, S2, IR_OP)
    MOVI(T0, 0) ; ST64(T0, S2, IR_SRC1) ; ST64(T0, S2, IR_SRC2)
    ST64(R0, S2, IR_IMM)
    LD64(T0, S2, IR_DST)
    LEA_SYM(T1, g_cf_def_cnt) ; LD64_IDX(A0, T1, T0)
    CMPI(A0, 1) ; JNE(.L_cf_cnt_stat)
    LEA_SYM(T1, g_cf_is_const) ; MOVI(A0, 1) ; ST64_IDX(A0, T1, T0)
    LEA_SYM(T1, g_cf_val) ; ST64_IDX(R0, T1, T0)
.L_cf_cnt_stat:
    LEA_SYM(T0, g_stat_const_folded) ; LD64(T1, T0, 0) ; ADDI(T1, 1) ; ST64(T1, T0, 0)

.L_cf_fold_nxt:
    ADDI(S4, 1)
    JMP(.L_cf_fold_loop)

.L_cf_end_fn:
    MOVR(S1, S4)
.L_cf_next_fn:
    ADDI(S1, 1)
    JMP(.L_cf_outer)

.L_cf_done:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_pass_const_fold)

/* ----------------------------------------------------------------------------
 * Pass 2: Small Leaf Function Inlining Analysis
 * Identifies small single-return pure leaf functions (e.g. identity/square)
 * and marks eligible call sites / records inlining candidates.
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_pass_inline)
    SX_PROLOGUE 16
    /* Scan functions; mark small pure leaf functions (<= 8 insts, no calls) */
    LEA_SYM(T0, g_ir_count) ; LD64(S0, T0, 0)
    MOVI(S1, 0)
.L_inl_loop:
    CMP(S1, S0) ; JGE(.L_inl_done)
    MOVR(S2, S1) ; SHLI(S2, 6) ; LEA_SYM(T0, g_ir_buf) ; ADD(S2, T0)
    LD64(T0, S2, IR_OP)
    CMPI(T0, IR_FUNC_BEGIN) ; JNE(.L_inl_nxt)
    /* Measure body size and verify no inner IR_CALL */
    MOVR(S3, S1) ; ADDI(S3, 1)
    MOVI(S4, 0)                 /* inst count */
    MOVI(T1, 1)                 /* is_leaf = 1 */
.L_inl_body:
    CMP(S3, S0) ; JGE(.L_inl_nxt)
    MOVR(R0, S3) ; SHLI(R0, 6) ; LEA_SYM(A0, g_ir_buf) ; ADD(R0, A0)
    LD64(A1, R0, IR_OP)
    CMPI(A1, IR_FUNC_END) ; JEQ(.L_inl_eval)
    CMPI(A1, IR_CALL)     ; JNE(.L_inl_b2) ; MOVI(T1, 0)
.L_inl_b2:
    ADDI(S4, 1)
    ADDI(S3, 1)
    JMP(.L_inl_body)
.L_inl_eval:
    CMPI(T1, 1) ; JNE(.L_inl_skip)
    CMPI(S4, 1) ; JLE(.L_inl_skip)
    CMPI(S4, 8) ; JGT(.L_inl_skip)
    /* Mark function with IRF_INLINED hint for backend / fast-path */
    LD64(R0, S2, IR_FLAGS) ; ORI(R0, IRF_INLINED) ; ST64(R0, S2, IR_FLAGS)
    LEA_SYM(R0, g_stat_inlined) ; LD64(A0, R0, 0) ; ADDI(A0, 1) ; ST64(A0, R0, 0)
.L_inl_skip:
    MOVR(S1, S3)
.L_inl_nxt:
    ADDI(S1, 1)
    JMP(.L_inl_loop)
.L_inl_done:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_pass_inline)

/* ----------------------------------------------------------------------------
 * Pass 3: Dead Code Elimination (DCE) — Reverse Liveness Per Function
 * Removes pure unused definitions (IR_CONST, IR_MOV, IR_ADD..IR_OR, IR_NEG)
 * whose destination vreg is never read!
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_pass_dce)
    SX_PROLOGUE 32
    LEA_SYM(T0, g_ir_count) ; LD64(S0, T0, 0)
    MOVI(S1, 0)                 /* fn start scan */
.L_dce_outer:
    CMP(S1, S0) ; JGE(.L_dce_done)
    MOVR(S2, S1) ; SHLI(S2, 6) ; LEA_SYM(T0, g_ir_buf) ; ADD(S2, T0)
    LD64(T0, S2, IR_OP)
    CMPI(T0, IR_FUNC_BEGIN) ; JNE(.L_dce_outer_nxt)

    /* Find IR_FUNC_END -> S3 */
    MOVR(S3, S1) ; ADDI(S3, 1)
.L_dce_find_end:
    CMP(S3, S0) ; JGE(.L_dce_done)
    MOVR(T0, S3) ; SHLI(T0, 6) ; LEA_SYM(T1, g_ir_buf) ; ADD(T0, T1)
    LD64(R0, T0, IR_OP)
    CMPI(R0, IR_FUNC_END) ; JEQ(.L_dce_run_fn)
    ADDI(S3, 1)
    JMP(.L_dce_find_end)

.L_dce_run_fn:
    LEA_SYM(A0, g_dce_used) ; MOVI(A1, 0) ; MOVI64(A2, MAX_VREGS * 8) ; SX_CALL(memset)

    /* Fixed-point liveness propagation (handles while-loop back-edges accurately!) */
    MOVI(T0, 0) ; ST_LOCAL(T0, 0) /* iter = 0 */
.L_dce_fp_loop:
    LD_LOCAL(T0, 0) ; CMPI(T0, 8) ; JGE(.L_dce_sweep)
    ADDI(T0, 1) ; ST_LOCAL(T0, 0)

    MOVR(S4, S3) ; SUBI(S4, 1)
.L_dce_prop:
    CMP(S4, S1) ; JLE(.L_dce_fp_loop)
    MOVR(S2, S4) ; SHLI(S2, 6) ; LEA_SYM(T0, g_ir_buf) ; ADD(S2, T0)
    LD64(T0, S2, IR_FLAGS)
    ANDI(T0, IRF_DEAD) ; CMPI(T0, 0) ; JNE(.L_dce_prop_nxt)

    LD64(T0, S2, IR_OP)
    /* If pure op, only propagate its inputs if its dst is ALREADY live */
    CMPI(T0, IR_CONST) ; JEQ(.L_dce_prop_nxt)
    CMPI(T0, IR_MOV)   ; JEQ(.L_dce_p_chk_mov)
    CMPI(T0, IR_ADD)   ; JLT(.L_dce_mark_uses)
    CMPI(T0, IR_NOT)   ; JLE(.L_dce_p_chk_pure)
    JMP(.L_dce_mark_uses)

.L_dce_p_chk_mov:
    LD64(T1, S2, IR_FLAGS) ; ANDI(T1, (IRF_ARC | IRF_GC))
    CMPI(T1, 0) ; JNE(.L_dce_mark_uses)
.L_dce_p_chk_pure:
    LD64(T1, S2, IR_DST)
    CMPI(T1, 0) ; JLE(.L_dce_prop_nxt)
    CMPI(T1, MAX_VREGS) ; JGE(.L_dce_prop_nxt)
    LEA_SYM(R0, g_dce_used) ; LD64_IDX(R0, R0, T1)
    CMPI(R0, 0) ; JEQ(.L_dce_prop_nxt)

.L_dce_mark_uses:
    CMPI(T0, IR_CONST)      ; JEQ(.L_dce_prop_nxt)
    CMPI(T0, IR_STR_CONST)  ; JEQ(.L_dce_prop_nxt)
    CMPI(T0, IR_CALL)       ; JEQ(.L_dce_prop_nxt)
    CMPI(T0, IR_LABEL)      ; JEQ(.L_dce_prop_nxt)
    CMPI(T0, IR_JMP)        ; JEQ(.L_dce_prop_nxt)
    CMPI(T0, IR_CLOSURE_NEW); JEQ(.L_dce_prop_nxt)
    CMPI(T0, IR_SPAWN)      ; JEQ(.L_dce_use_spawn)

    CMPI(T0, IR_CLOSURE_SET); JNE(.L_dce_u1)
    LD64(T1, S2, IR_DST)
    CMPI(T1, MAX_VREGS) ; JGE(.L_dce_u1)
    LEA_SYM(R0, g_dce_used) ; MOVI(A0, 1) ; ST64_IDX(A0, R0, T1)

.L_dce_u1:
    LD64(T1, S2, IR_SRC1)
    CMPI(T1, 0) ; JLE(.L_dce_u2_chk)
    CMPI(T1, MAX_VREGS) ; JGE(.L_dce_u2_chk)
    LEA_SYM(R0, g_dce_used) ; MOVI(A0, 1) ; ST64_IDX(A0, R0, T1)

.L_dce_u2_chk:
    CMPI(T0, IR_ADD) ; JLT(.L_dce_prop_nxt)
    CMPI(T0, IR_OR)  ; JLE(.L_dce_u2)
    CMPI(T0, IR_CLOSURE_CALL) ; JNE(.L_dce_prop_nxt)
.L_dce_u2:
    LD64(T1, S2, IR_SRC2)
    CMPI(T1, 0) ; JLE(.L_dce_prop_nxt)
    CMPI(T1, MAX_VREGS) ; JGE(.L_dce_prop_nxt)
    LEA_SYM(R0, g_dce_used) ; MOVI(A0, 1) ; ST64_IDX(A0, R0, T1)
    JMP(.L_dce_prop_nxt)

.L_dce_use_spawn:
    LD64(T1, S2, IR_IMM)
    CMPI(T1, 0) ; JLE(.L_dce_prop_nxt)
    CMPI(T1, MAX_VREGS) ; JGE(.L_dce_prop_nxt)
    LEA_SYM(R0, g_dce_used) ; MOVI(A0, 1) ; ST64_IDX(A0, R0, T1)

.L_dce_prop_nxt:
    SUBI(S4, 1)
    JMP(.L_dce_prop)

    /* Final Sweep: mark pure instructions whose dst is STILL unused as IRF_DEAD */
.L_dce_sweep:
    MOVR(S4, S1) ; ADDI(S4, 1)
.L_dce_sw_loop:
    CMP(S4, S3) ; JGE(.L_dce_fn_done)
    MOVR(S2, S4) ; SHLI(S2, 6) ; LEA_SYM(T0, g_ir_buf) ; ADD(S2, T0)
    LD64(T0, S2, IR_FLAGS) ; ANDI(T0, IRF_DEAD) ; CMPI(T0, 0) ; JNE(.L_dce_sw_nxt)
    LD64(T0, S2, IR_OP)
    CMPI(T0, IR_CONST) ; JEQ(.L_dce_sw_chk)
    CMPI(T0, IR_MOV)   ; JEQ(.L_dce_sw_mov)
    CMPI(T0, IR_ADD)   ; JLT(.L_dce_sw_nxt)
    CMPI(T0, IR_NOT)   ; JLE(.L_dce_sw_chk)
    JMP(.L_dce_sw_nxt)
.L_dce_sw_mov:
    LD64(T1, S2, IR_FLAGS) ; ANDI(T1, (IRF_ARC | IRF_GC))
    CMPI(T1, 0) ; JNE(.L_dce_sw_nxt)
.L_dce_sw_chk:
    LD64(T1, S2, IR_DST)
    CMPI(T1, 0) ; JLE(.L_dce_sw_nxt)
    CMPI(T1, MAX_VREGS) ; JGE(.L_dce_sw_nxt)
    LEA_SYM(R0, g_dce_used) ; LD64_IDX(R0, R0, T1)
    CMPI(R0, 0) ; JNE(.L_dce_sw_nxt)
    LD64(R0, S2, IR_FLAGS) ; ORI(R0, IRF_DEAD) ; ST64(R0, S2, IR_FLAGS)
    LEA_SYM(R0, g_stat_dce_removed) ; LD64(T1, R0, 0) ; ADDI(T1, 1) ; ST64(T1, R0, 0)
.L_dce_sw_nxt:
    ADDI(S4, 1)
    JMP(.L_dce_sw_loop)

.L_dce_fn_done:
    MOVR(S1, S3)
.L_dce_outer_nxt:
    ADDI(S1, 1)
    JMP(.L_dce_outer)

.L_dce_done:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_pass_dce)

/* ----------------------------------------------------------------------------
 * sx_middle_end_run() — Runs the full Phase 2 Pipeline from the Diagram:
 *   SUMIR -> Static Analysis & Memory Safety (ARC/GC/Ownership/Lifetime)
 *         -> Phi & Lambda Optimization Passes
 *         -> Lowering (Constant Folding -> Inlining -> DCE)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_middle_end_run)
    SX_PROLOGUE 16
    SX_CALL(sx_pass_mem_safety)
    SX_CALL(sx_pass_phi_lambda_opt)
    SX_CALL(sx_pass_const_fold)
    SX_CALL(sx_pass_inline)
    SX_CALL(sx_pass_dce)

    LEA_SYM(T0, g_opt_dump_ir) ; LD64(T1, T0, 0)
    CMPI(T1, 0) ; JEQ(.L_me_ret)
    SX_CALL(sx_dump_ir)
.L_me_ret:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_middle_end_run)

SX_FUNC(sx_dump_ir)
    SX_PROLOGUE 16
    LEA_SYM(T0, g_stat_dce_removed)  ; LD64(A3, T0, 0)
    LEA_SYM(T0, g_stat_const_folded) ; LD64(A2, T0, 0)
    LEA_SYM(T0, g_ir_count)          ; LD64(A1, T0, 0)
    LEA_SYM(A0, fmt_ir_hdr)
    SX_VCALL(printf)

    LEA_SYM(T0, g_stat_inlined)      ; LD64(A3, T0, 0)
    LEA_SYM(T0, g_stat_gc_roots)     ; LD64(A2, T0, 0)
    LEA_SYM(T0, g_stat_arc_inserted) ; LD64(A1, T0, 0)
    LEA_SYM(A0, fmt_ir_hdr2)
    SX_VCALL(printf)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_dump_ir)
