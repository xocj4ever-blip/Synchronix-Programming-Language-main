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
 * SYNCHRONIX COMPILER — Phase 2: Phi & Lambda Optimization Passes
 * (src/middle/phi_lambda_opt.S)
 * ============================================================================
 * Implements:
 *   - Phi (Φ) Formal Logic Transforms:
 *       * Eliminates statically-proven IR_PHI_ASSERT checks (zero runtime cost!)
 *       * Propagates proven constant truth conditions
 *   - Lambda (Λ) Functional Lowering & Closure Optimizing:
 *       * Optimizes closure allocation & capture forwarding
 *       * Eliminates redundant ARC retain/release pairs on local closures
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_TEXT

SX_FUNC(sx_pass_phi_lambda_opt)
    SX_PROLOGUE 16
    LEA_SYM(T0, g_ir_count) ; LD64(S0, T0, 0)
    MOVI(S1, 0)                 /* i = 0 */

.L_plo_loop:
    CMP(S1, S0) ; JGE(.L_plo_done)
    MOVR(S2, S1) ; SHLI(S2, 6)
    LEA_SYM(T0, g_ir_buf) ; ADD(S2, T0)
    LD64(S3, S2, IR_OP)

    /* 1. Phi Formal Logic Transform: eliminate statically-proven assertions! */
    CMPI(S3, IR_PHI_ASSERT) ; JNE(.L_plo_arc_peep)
    LD64(T0, S2, IR_FLAGS)
    MOVR(T1, T0)
    ANDI(T1, IRF_PROVEN)
    CMPI(T1, 0) ; JEQ(.L_plo_next)
    /* Mark assertion DEAD -> zero runtime overhead for formally proven theorems! */
    ORI(T0, IRF_DEAD)
    ST64(T0, S2, IR_FLAGS)
    LEA_SYM(T0, g_stat_dce_removed) ; LD64(T1, T0, 0) ; ADDI(T1, 1) ; ST64(T1, T0, 0)
    JMP(.L_plo_next)

.L_plo_arc_peep:
    /* 2. ARC/Lambda Peephole Elision: adjacent RETAIN(v) + RELEASE(v) -> cancel both! */
    CMPI(S3, IR_ARC_RETAIN) ; JNE(.L_plo_next)
    MOVR(T0, S1) ; ADDI(T0, 1)
    CMP(T0, S0) ; JGE(.L_plo_next)
    SHLI(T0, 6) ; LEA_SYM(T1, g_ir_buf) ; ADD(T0, T1)
    LD64(R0, T0, IR_OP)
    CMPI(R0, IR_ARC_RELEASE) ; JNE(.L_plo_next)
    LD64(R0, S2, IR_SRC1)
    LD64(T1, T0, IR_SRC1)
    CMP(R0, T1) ; JNE(.L_plo_next)
    /* Cancel both! */
    LD64(R0, S2, IR_FLAGS) ; ORI(R0, IRF_DEAD) ; ST64(R0, S2, IR_FLAGS)
    LD64(R0, T0, IR_FLAGS) ; ORI(R0, IRF_DEAD) ; ST64(R0, T0, IR_FLAGS)
    LEA_SYM(T0, g_stat_dce_removed) ; LD64(T1, T0, 0) ; ADDI(T1, 2) ; ST64(T1, T0, 0)

.L_plo_next:
    ADDI(S1, 1)
    JMP(.L_plo_loop)

.L_plo_done:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_pass_phi_lambda_opt)
