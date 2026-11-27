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
 * SYNCHRONIX COMPILER — Phase 2: Static Analysis & Memory Safety (mem_safety.S)
 * ============================================================================
 * Implements the bidirectional SUMIR <-> Static Analysis & Memory Safety passes:
 *   1. Ownership & Borrow Checker (detects use-after-move on moved vregs)
 *   2. Lifetime Analyzer (computes [def_idx, last_use_idx] per virtual reg)
 *   3. ARC (Automatic Reference Counting) Insertion & Elision
 *        - Inserts IR_ARC_RETAIN on ARC alias copies
 *        - Inserts IR_ARC_RELEASE at exact end-of-lifetime / scope exit
 *   4. GC (Garbage Collection) Optimization & Root Tracking
 *        - Inserts IR_GC_ROOT after IR_GC_NEW
 *        - Inserts IR_GC_UNROOT at exact end-of-lifetime / scope exit
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(err_use_after_move, "Ownership Checker Error: use of moved value")

SX_BSS
.p2align 4
/* Scratch SUMIR buffer for clean O(N) ARC/GC instruction insertion */
SX_GLOBAL(g_ir_scratch)
SX_LABEL(g_ir_scratch)
    .skip (MAX_IR_INSTS * IR_SIZE)

/* Lifetime & Ownership Tracking Arrays (per virtual register) */
SX_GLOBAL(g_vreg_def)
SX_LABEL(g_vreg_def)
    .skip (MAX_VREGS * 8)
SX_GLOBAL(g_vreg_last_use)
SX_LABEL(g_vreg_last_use)
    .skip (MAX_VREGS * 8)
SX_GLOBAL(g_vreg_memkind)
SX_LABEL(g_vreg_memkind)
    .skip (MAX_VREGS * 8)   /* 0=stack, 1=ARC, 2=GC */
SX_GLOBAL(g_vreg_moved)
SX_LABEL(g_vreg_moved)
    .skip (MAX_VREGS * 8)

/* Active managed vregs in current function to release/unroot at scope exit */
SX_LABEL(g_fn_arc_vregs)
    .skip (128 * 8)
SX_LABEL(g_fn_arc_cnt)
    .skip 8
SX_LABEL(g_fn_gc_vregs)
    .skip (128 * 8)
SX_LABEL(g_fn_gc_cnt)
    .skip 8

SX_TEXT

/* Helper: copy 64-byte IR inst from A0 (src) to g_ir_scratch[A1] */
SX_FUNC(sx_copy_ir_to_scratch)
    SX_PROLOGUE 0
    SHLI(A1, 6)
    LEA_SYM(T0, g_ir_scratch) ; ADD(A1, T0)
    LD64(T1, A0, 0)  ; ST64(T1, A1, 0)
    LD64(T1, A0, 8)  ; ST64(T1, A1, 8)
    LD64(T1, A0, 16) ; ST64(T1, A1, 16)
    LD64(T1, A0, 24) ; ST64(T1, A1, 24)
    LD64(T1, A0, 32) ; ST64(T1, A1, 32)
    LD64(T1, A0, 40) ; ST64(T1, A1, 40)
    LD64(T1, A0, 48) ; ST64(T1, A1, 48)
    LD64(T1, A0, 56) ; ST64(T1, A1, 56)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_copy_ir_to_scratch)

/* Helper: emit synthetic ARC/GC inst into g_ir_scratch[A0] with op=A1, src1=A2 */
SX_FUNC(sx_emit_scratch_mem)
    SX_PROLOGUE 0
    SHLI(A0, 6)
    LEA_SYM(T0, g_ir_scratch) ; ADD(A0, T0)
    ST64(A1, A0, IR_OP)
    MOVI(T1, 0)
    ST64(T1, A0, IR_DST)
    ST64(A2, A0, IR_SRC1)
    ST64(T1, A0, IR_SRC2)
    ST64(T1, A0, IR_IMM)
    ST64(T1, A0, IR_TYPE)
    ST64(T1, A0, IR_FLAGS)
    MOVI(T1, -1)
    ST64(T1, A0, IR_PHYS)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_emit_scratch_mem)

/* ----------------------------------------------------------------------------
 * sx_pass_mem_safety() — Full Static Analysis & Memory Safety Pass on SUMIR
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_pass_mem_safety)
    SX_PROLOGUE 48
    /* Pass A: Ownership & Borrow Check + Lifetime Analysis */
    LEA_SYM(A0, g_vreg_def)      ; MOVI(A1, 0) ; MOVI64(A2, MAX_VREGS * 8) ; SX_CALL(memset)
    LEA_SYM(A0, g_vreg_last_use) ; MOVI(A1, 0) ; MOVI64(A2, MAX_VREGS * 8) ; SX_CALL(memset)
    LEA_SYM(A0, g_vreg_memkind)  ; MOVI(A1, 0) ; MOVI64(A2, MAX_VREGS * 8) ; SX_CALL(memset)
    LEA_SYM(A0, g_vreg_moved)    ; MOVI(A1, 0) ; MOVI64(A2, MAX_VREGS * 8) ; SX_CALL(memset)

    LEA_SYM(T0, g_ir_count) ; LD64(S0, T0, 0)   /* S0 = ir_count */
    MOVI(S1, 0)                                  /* S1 = i */
.L_ms_scan:
    CMP(S1, S0) ; JGE(.L_ms_insert_start)
    MOVR(S2, S1) ; SHLI(S2, 6)
    LEA_SYM(T0, g_ir_buf) ; ADD(S2, T0)          /* S2 = &ir[i] */
    LD64(S3, S2, IR_OP)

    /* Reset per-function moved flags on IR_FUNC_BEGIN */
    CMPI(S3, IR_FUNC_BEGIN) ; JNE(.L_ms_chk_use)
    LEA_SYM(A0, g_vreg_moved) ; MOVI(A1, 0) ; MOVI64(A2, MAX_VREGS * 8) ; SX_CALL(memset)
    JMP(.L_ms_scan_next)

.L_ms_chk_use:
    /* Update last_use for src1/src2 (if opcode uses vregs) */
    CMPI(S3, IR_CONST)     ; JEQ(.L_ms_rec_def)
    CMPI(S3, IR_STR_CONST) ; JEQ(.L_ms_rec_def)
    CMPI(S3, IR_CALL)      ; JEQ(.L_ms_rec_def)
    CMPI(S3, IR_FUNC_END)  ; JEQ(.L_ms_scan_next)
    CMPI(S3, IR_LABEL)     ; JEQ(.L_ms_scan_next)
    CMPI(S3, IR_JMP)       ; JEQ(.L_ms_scan_next)
    CMPI(S3, IR_CLOSURE_NEW); JEQ(.L_ms_rec_def)
    CMPI(S3, IR_SPAWN)     ; JEQ(.L_ms_chk_spawn)

    LD64(T0, S2, IR_SRC1)
    CMPI(T0, 0) ; JLE(.L_ms_chk_s2)
    CMPI(T0, MAX_VREGS) ; JGE(.L_ms_chk_s2)
    /* Ownership check: was src1 previously moved? */
    LEA_SYM(T1, g_vreg_moved) ; LD64_IDX(R0, T1, T0)
    CMPI(R0, 0) ; JEQ(.L_ms_u1_ok)
    MOVI(A0, 0) ; LEA_SYM(A1, err_use_after_move) ; SX_CALL(sx_error)
    LD64(T0, S2, IR_SRC1)
.L_ms_u1_ok:
    LEA_SYM(T1, g_vreg_last_use) ; ST64_IDX(S1, T1, T0)

.L_ms_chk_s2:
    /* Check src2 for binary ops & closure_call */
    CMPI(S3, IR_ADD) ; JLT(.L_ms_chk_move)
    CMPI(S3, IR_OR)  ; JLE(.L_ms_u2)
    CMPI(S3, IR_CLOSURE_CALL) ; JNE(.L_ms_chk_move)
.L_ms_u2:
    LD64(T0, S2, IR_SRC2)
    CMPI(T0, 0) ; JLE(.L_ms_chk_move)
    CMPI(T0, MAX_VREGS) ; JGE(.L_ms_chk_move)
    LEA_SYM(T1, g_vreg_last_use) ; ST64_IDX(S1, T1, T0)
    JMP(.L_ms_chk_move)

.L_ms_chk_spawn:
    LD64(T0, S2, IR_IMM)
    CMPI(T0, 0) ; JLE(.L_ms_rec_def)
    CMPI(T0, MAX_VREGS) ; JGE(.L_ms_rec_def)
    LEA_SYM(T1, g_vreg_last_use) ; ST64_IDX(S1, T1, T0)
    JMP(.L_ms_rec_def)

.L_ms_chk_move:
    /* If IR_MOVE, mark src1 as MOVED in Ownership Checker */
    CMPI(S3, IR_MOVE) ; JNE(.L_ms_rec_def)
    LD64(T0, S2, IR_SRC1)
    CMPI(T0, 0) ; JLE(.L_ms_rec_def)
    CMPI(T0, MAX_VREGS) ; JGE(.L_ms_rec_def)
    LEA_SYM(T1, g_vreg_moved) ; MOVI(R0, 1) ; ST64_IDX(R0, T1, T0)

.L_ms_rec_def:
    LD64(T0, S2, IR_DST)
    CMPI(T0, 0) ; JLE(.L_ms_scan_next)
    CMPI(T0, MAX_VREGS) ; JGE(.L_ms_scan_next)
    LEA_SYM(T1, g_vreg_def) ; ST64_IDX(S1, T1, T0)

.L_ms_scan_next:
    ADDI(S1, 1)
    JMP(.L_ms_scan)

    /* ------------------------------------------------------------------------
     * Pass B: ARC Insertion (RETAIN/RELEASE) & GC Root Tracking (ROOT/UNROOT)
     * Streams g_ir_buf -> g_ir_scratch with deterministic memory ops inserted!
     * ------------------------------------------------------------------------
     */
.L_ms_insert_start:
    MOVI(S1, 0)                 /* S1 = read index */
    MOVI(S4, 0)                 /* S4 = write index in scratch */
    LEA_SYM(T0, g_fn_arc_cnt) ; MOVI(T1, 0) ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_fn_gc_cnt)  ; ST64(T1, T0, 0)

.L_ms_ins_loop:
    CMP(S1, S0) ; JGE(.L_ms_copy_back)
    MOVR(S2, S1) ; SHLI(S2, 6)
    LEA_SYM(T0, g_ir_buf) ; ADD(S2, T0)          /* S2 = &ir[S1] */
    LD64(S3, S2, IR_OP)

    CMPI(S3, IR_FUNC_BEGIN) ; JNE(.L_ms_chk_ret)
    LEA_SYM(T0, g_fn_arc_cnt) ; MOVI(T1, 0) ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_fn_gc_cnt)  ; ST64(T1, T0, 0)
    JMP(.L_ms_emit_orig)

.L_ms_chk_ret:
    /* Before IR_RET, deterministically release all owned ARC objects & unroot GC objects! */
    CMPI(S3, IR_RET) ; JNE(.L_ms_emit_orig)
    /* Emit IR_ARC_RELEASE for every ARC vreg tracked in this function */
    LEA_SYM(T0, g_fn_arc_cnt) ; LD64(T1, T0, 0)
    ST_LOCAL(T1, 0)             /* count */
    MOVI(T0, 0) ; ST_LOCAL(T0, 1) /* idx */
.L_ms_rel_loop:
    LD_LOCAL(T0, 1) ; LD_LOCAL(T1, 0)
    CMP(T0, T1) ; JGE(.L_ms_unroot_start)
    LEA_SYM(R0, g_fn_arc_vregs) ; LD64_IDX(A2, R0, T0)
    MOVR(A0, S4) ; MOVI(A1, IR_ARC_RELEASE)
    SX_CALL(sx_emit_scratch_mem)
    ADDI(S4, 1)
    LEA_SYM(R0, g_stat_arc_inserted) ; LD64(T1, R0, 0) ; ADDI(T1, 1) ; ST64(T1, R0, 0)
    LD_LOCAL(T0, 1) ; ADDI(T0, 1) ; ST_LOCAL(T0, 1)
    JMP(.L_ms_rel_loop)

.L_ms_unroot_start:
    /* Emit IR_GC_UNROOT for every GC root tracked in this function */
    LEA_SYM(T0, g_fn_gc_cnt) ; LD64(T1, T0, 0)
    ST_LOCAL(T1, 0)
    MOVI(T0, 0) ; ST_LOCAL(T0, 1)
.L_ms_unr_loop:
    LD_LOCAL(T0, 1) ; LD_LOCAL(T1, 0)
    CMP(T0, T1) ; JGE(.L_ms_emit_orig)
    LEA_SYM(R0, g_fn_gc_vregs) ; LD64_IDX(A2, R0, T0)
    MOVR(A0, S4) ; MOVI(A1, IR_GC_UNROOT)
    SX_CALL(sx_emit_scratch_mem)
    ADDI(S4, 1)
    LEA_SYM(R0, g_stat_gc_roots) ; LD64(T1, R0, 0) ; ADDI(T1, 1) ; ST64(T1, R0, 0)
    LD_LOCAL(T0, 1) ; ADDI(T0, 1) ; ST_LOCAL(T0, 1)
    JMP(.L_ms_unr_loop)

.L_ms_emit_orig:
    /* Copy original instruction */
    MOVR(A0, S2) ; MOVR(A1, S4)
    SX_CALL(sx_copy_ir_to_scratch)
    ADDI(S4, 1)

    /* Track newly allocated ARC or Closure objects for deterministic release */
    CMPI(S3, IR_ARC_NEW)     ; JEQ(.L_ms_track_arc)
    CMPI(S3, IR_CLOSURE_NEW) ; JEQ(.L_ms_track_arc)
    CMPI(S3, IR_MOV)         ; JEQ(.L_ms_chk_arc_alias)
    CMPI(S3, IR_GC_NEW)      ; JEQ(.L_ms_track_gc)
    JMP(.L_ms_ins_next)

.L_ms_track_arc:
    LD64(T0, S2, IR_DST)
    LEA_SYM(T1, g_fn_arc_cnt) ; LD64(R0, T1, 0)
    CMPI(R0, 128) ; JGE(.L_ms_ins_next)
    LEA_SYM(A0, g_fn_arc_vregs) ; ST64_IDX(T0, A0, R0)
    ADDI(R0, 1) ; ST64(R0, T1, 0)
    JMP(.L_ms_ins_next)

.L_ms_chk_arc_alias:
    /* If IR_MOV has IRF_ARC set (aliasing an ARC object), insert IR_ARC_RETAIN & track release! */
    LD64(T0, S2, IR_FLAGS)
    ANDI(T0, IRF_ARC)
    CMPI(T0, 0) ; JEQ(.L_ms_ins_next)
    LD64(A2, S2, IR_DST)
    MOVR(A0, S4) ; MOVI(A1, IR_ARC_RETAIN)
    SX_CALL(sx_emit_scratch_mem)
    ADDI(S4, 1)
    LEA_SYM(R0, g_stat_arc_inserted) ; LD64(T1, R0, 0) ; ADDI(T1, 1) ; ST64(T1, R0, 0)
    /* Also register alias for deterministic release at scope exit */
    LD64(T0, S2, IR_DST)
    LEA_SYM(T1, g_fn_arc_cnt) ; LD64(R0, T1, 0)
    CMPI(R0, 128) ; JGE(.L_ms_ins_next)
    LEA_SYM(A0, g_fn_arc_vregs) ; ST64_IDX(T0, A0, R0)
    ADDI(R0, 1) ; ST64(R0, T1, 0)
    JMP(.L_ms_ins_next)

.L_ms_track_gc:
    /* Insert IR_GC_ROOT right after IR_GC_NEW */
    LD64(A2, S2, IR_DST)
    MOVR(A0, S4) ; MOVI(A1, IR_GC_ROOT)
    SX_CALL(sx_emit_scratch_mem)
    ADDI(S4, 1)
    LEA_SYM(R0, g_stat_gc_roots) ; LD64(T1, R0, 0) ; ADDI(T1, 1) ; ST64(T1, R0, 0)
    LD64(T0, S2, IR_DST)
    LEA_SYM(T1, g_fn_gc_cnt) ; LD64(R0, T1, 0)
    CMPI(R0, 128) ; JGE(.L_ms_ins_next)
    LEA_SYM(A0, g_fn_gc_vregs) ; ST64_IDX(T0, A0, R0)
    ADDI(R0, 1) ; ST64(R0, T1, 0)

.L_ms_ins_next:
    ADDI(S1, 1)
    JMP(.L_ms_ins_loop)

.L_ms_copy_back:
    /* Copy g_ir_scratch[0..S4-1] back to g_ir_buf */
    LEA_SYM(A0, g_ir_buf)
    LEA_SYM(A1, g_ir_scratch)
    MOVR(A2, S4) ; SHLI(A2, 6)
    SX_CALL(memcpy)
    LEA_SYM(T0, g_ir_count) ; ST64(S4, T0, 0)
    MOVR(R0, S4)
    SX_EPILOGUE
SX_ENDFUNC(sx_pass_mem_safety)
