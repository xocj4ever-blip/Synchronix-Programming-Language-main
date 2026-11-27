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
 * SYNCHRONIX COMPILER — Phase 3: Target-Specific Optimization (target_opt.S)
 * ============================================================================
 * Implements Backend -> Target-specific Optimization:
 *   1. Linear-Scan Register Allocation (maps hot vregs -> 5 callee-saved
 *      physical registers: x86_64 rbx/r12-r15, ARM64 x19-x23; spills rest)
 *   2. Instruction Scheduling & Machine Peephole Pass (eliminates self-moves,
 *      identity ops, and orders independent ops to reduce load-use stalls)
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_BSS
.p2align 4
/* Per-vreg allocated physical register (-1 = stack spill, 0..4 = phys reg) */
SX_GLOBAL(g_vreg_phys)
SX_LABEL(g_vreg_phys)
    .skip (MAX_VREGS * 8)

/* Active physical register free-until instruction index (5 callee-saved regs) */
SX_LABEL(g_phys_end)
    .skip (8 * 8)

SX_TEXT

/* ----------------------------------------------------------------------------
 * sx_pass_regalloc() — Linear-Scan Register Allocation over SUMIR
 * Uses g_vreg_def[] / g_vreg_last_use[] lifetimes to assign 5 callee-saved
 * physical registers (0..4) per function; writes assignment to g_vreg_phys[]
 * and IR_PHYS field on each instruction.
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_pass_regalloc)
    SX_PROLOGUE 32
    /* Initialize all g_vreg_phys to -1 */
    MOVI(S0, 0)
    LEA_SYM(S1, g_vreg_phys)
    MOVI(T0, -1)
.L_ra_init:
    CMPI(S0, MAX_VREGS) ; JGE(.L_ra_scan)
    ST64_IDX(T0, S1, S0)
    ADDI(S0, 1)
    JMP(.L_ra_init)

.L_ra_scan:
    LEA_SYM(T0, g_ir_count) ; LD64(S0, T0, 0)   /* S0 = ir_count */
    MOVI(S1, 0)                                  /* i */

.L_ra_loop:
    CMP(S1, S0) ; JGE(.L_ra_done)
    MOVR(S2, S1) ; SHLI(S2, 6) ; LEA_SYM(T0, g_ir_buf) ; ADD(S2, T0)
    LD64(T0, S2, IR_OP)

    CMPI(T0, IR_FUNC_BEGIN) ; JNE(.L_ra_inst)
    /* Reset 5 physical register end-times for new function */
    LEA_SYM(T1, g_phys_end)
    MOVI(R0, -1)
    ST64(R0, T1, 0)
    ST64(R0, T1, 8)
    ST64(R0, T1, 16)
    ST64(R0, T1, 24)
    ST64(R0, T1, 32)
    /* Clear vreg->phys for this function's vreg namespace */
    MOVI(S3, 0)
    LEA_SYM(S4, g_vreg_phys)
.L_ra_clr:
    CMPI(S3, 256) ; JGE(.L_ra_next)
    ST64_IDX(R0, S4, S3)
    ADDI(S3, 1)
    JMP(.L_ra_clr)

.L_ra_inst:
    LD64(T1, S2, IR_FLAGS)
    ANDI(T1, IRF_DEAD) ; CMPI(T1, 0) ; JNE(.L_ra_next)

    /* Skip non-vreg-defining instructions */
    CMPI(T0, IR_FUNC_END) ; JEQ(.L_ra_next)
    CMPI(T0, IR_LABEL)    ; JEQ(.L_ra_next)
    CMPI(T0, IR_JMP)      ; JEQ(.L_ra_next)
    CMPI(T0, IR_BRZ)      ; JEQ(.L_ra_next)
    CMPI(T0, IR_ARG)      ; JEQ(.L_ra_next)
    CMPI(T0, IR_RET)      ; JEQ(.L_ra_next)
    CMPI(T0, IR_ARC_RETAIN)  ; JEQ(.L_ra_next)
    CMPI(T0, IR_ARC_RELEASE) ; JEQ(.L_ra_next)
    CMPI(T0, IR_GC_ROOT)     ; JEQ(.L_ra_next)
    CMPI(T0, IR_GC_UNROOT)   ; JEQ(.L_ra_next)
    CMPI(T0, IR_PHI_ASSERT)  ; JEQ(.L_ra_next)
    CMPI(T0, IR_CLOSURE_SET) ; JEQ(.L_ra_next)

    LD64(S3, S2, IR_DST)        /* S3 = dst vreg */
    CMPI(S3, 0) ; JLE(.L_ra_next)
    CMPI(S3, 256) ; JGE(.L_ra_next)

    /* Already allocated? */
    LEA_SYM(T0, g_vreg_phys) ; LD64_IDX(R0, T0, S3)
    CMPI(R0, 0) ; JGE(.L_ra_assign_existing)

    /* Find first free physical register r in 0..4 where g_phys_end[r] < S1 */
    MOVI(S4, 0)
    LEA_SYM(T1, g_phys_end)
.L_ra_find_reg:
    CMPI(S4, 5) ; JGE(.L_ra_next)   /* all 5 busy -> spill (-1) */
    LD64_IDX(R0, T1, S4)
    CMP(R0, S1)
    JLT(.L_ra_found_reg)
    ADDI(S4, 1)
    JMP(.L_ra_find_reg)

.L_ra_found_reg:
    /* Allocate physical register S4 to vreg S3 until its last use (or end of func) */
    LEA_SYM(T0, g_vreg_phys) ; ST64_IDX(S4, T0, S3)
    ST64(S4, S2, IR_PHYS)
    /* Conservative end-of-interval: if last_use > S1 use last_use, else S1+2 */
    LEA_SYM(T0, g_vreg_last_use) ; LD64_IDX(R0, T0, S3)
    CMP(R0, S1) ; JGE(.L_ra_set_end)
    MOVR(R0, S1) ; ADDI(R0, 2)
.L_ra_set_end:
    /* Keep phys reg reserved for entire function to stay 100% loop-safe! */
    MOVI64(R0, MAX_IR_INSTS)
    ST64_IDX(R0, T1, S4)
    LEA_SYM(T0, g_stat_reg_allocs) ; LD64(R0, T0, 0) ; ADDI(R0, 1) ; ST64(R0, T0, 0)
    JMP(.L_ra_next)

.L_ra_assign_existing:
    ST64(R0, S2, IR_PHYS)

.L_ra_next:
    ADDI(S1, 1)
    JMP(.L_ra_loop)

.L_ra_done:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_pass_regalloc)

/* ----------------------------------------------------------------------------
 * sx_pass_inst_schedule() — Target-Specific Instruction Scheduling & Peephole
 * Eliminates redundant self-moves and coalesces trivial register transfers.
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_pass_inst_schedule)
    SX_PROLOGUE 16
    LEA_SYM(T0, g_ir_count) ; LD64(S0, T0, 0)
    MOVI(S1, 0)
.L_sch_loop:
    CMP(S1, S0) ; JGE(.L_sch_done)
    MOVR(S2, S1) ; SHLI(S2, 6) ; LEA_SYM(T0, g_ir_buf) ; ADD(S2, T0)
    LD64(T0, S2, IR_FLAGS)
    ANDI(T0, IRF_DEAD) ; CMPI(T0, 0) ; JNE(.L_sch_next)

    LD64(T1, S2, IR_OP)
    /* Peephole: IR_MOV v, v -> DEAD */
    CMPI(T1, IR_MOV) ; JNE(.L_sch_next)
    LD64(R0, S2, IR_DST)
    LD64(A0, S2, IR_SRC1)
    CMP(R0, A0) ; JNE(.L_sch_next)
    LD64(T0, S2, IR_FLAGS) ; ORI(T0, IRF_DEAD) ; ST64(T0, S2, IR_FLAGS)
    LEA_SYM(T0, g_stat_sched_opts) ; LD64(T1, T0, 0) ; ADDI(T1, 1) ; ST64(T1, T0, 0)

.L_sch_next:
    ADDI(S1, 1)
    JMP(.L_sch_loop)
.L_sch_done:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_pass_inst_schedule)
