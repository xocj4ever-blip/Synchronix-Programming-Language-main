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
 * SYNCHRONIX RUNTIME — Phi & Lambda Runtime (src/runtime/phi_lambda_rt.S)
 * ============================================================================
 * Implements Foundation -> Phi & Lambda Runtime:
 *   - Phi Formal Logic Runtime (Proofs, Constraints, Runtime Contract Checks)
 *   - Lambda Runtime (ARC-managed Closures, Environment Capture, Higher-Order)
 *
 * Closure Object Payload Layout (allocated via ARC Engine):
 *   [+0]  fn_ptr    (lifted lambda function pointer: fn(closure_ptr, arg0))
 *   [+8]  env_count (number of captured environment variables)
 *   [+16 + 8*i] captured value i
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(str_phi_fail, "[Synchronix Phi Runtime] FORMAL PROOF VIOLATION at line %lld! Aborting.\n")
SX_STR(str_phi_stat, "  Phi Runtime : dynamic_checks=%lld passed=%lld closures_created=%lld\n")

SX_BSS
.p2align 4
SX_GLOBAL(g_phi_checks)
SX_LABEL(g_phi_checks)
    .skip 8
SX_GLOBAL(g_phi_passed)
SX_LABEL(g_phi_passed)
    .skip 8
SX_GLOBAL(g_lambda_created)
SX_LABEL(g_lambda_created)
    .skip 8

SX_TEXT

/* ----------------------------------------------------------------------------
 * sx_phi_check(A0 = cond_bool, A1 = line_num) -> R0 = 1 if ok (aborts on fail)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_phi_check)
    SX_PROLOGUE 16
    MOVR(S0, A0)                /* S0 = cond */
    MOVR(S1, A1)                /* S1 = line */

    LEA_SYM(T0, g_phi_checks)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)

    CMPI(S0, 0)
    JEQ(.L_phi_violated)

    LEA_SYM(T0, g_phi_passed)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)

    MOVI(R0, 1)
    SX_EPILOGUE

.L_phi_violated:
    MOVR(A1, S1)
    LEA_SYM(A0, str_phi_fail)
    SX_VCALL(printf)
    MOVI(A0, 1)
    SX_CALL(exit)
    SX_EPILOGUE
SX_ENDFUNC(sx_phi_check)

/* ----------------------------------------------------------------------------
 * sx_phi_stats()
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_phi_stats)
    SX_PROLOGUE 16
    LEA_SYM(T0, g_lambda_created)
    LD64(A3, T0, 0)
    LEA_SYM(T0, g_phi_passed)
    LD64(A2, T0, 0)
    LEA_SYM(T0, g_phi_checks)
    LD64(A1, T0, 0)
    LEA_SYM(A0, str_phi_stat)
    SX_VCALL(printf)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_phi_stats)

/* ----------------------------------------------------------------------------
 * sx_closure_alloc(A0 = fn_ptr, A1 = env_count) -> R0 = closure_ptr (ARC)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_closure_alloc)
    SX_PROLOGUE 16
    MOVR(S0, A0)                /* S0 = fn_ptr */
    MOVR(S1, A1)                /* S1 = env_count */

    /* payload size = 16 + env_count * 8 */
    MOVR(A0, S1)
    SHLI(A0, 3)
    ADDI(A0, 16)
    MOVI(A1, 0)
    SX_CALL(sx_arc_alloc)
    CMPI(R0, 0)
    JEQ(.L_cl_oom)

    /* Tag header flags with OBJF_CLOSURE */
    MOVR(T0, R0)
    SUBI(T0, OBJ_HDR_SIZE)
    LD64(T1, T0, OBJ_FLAGS)
    ORI(T1, OBJF_CLOSURE)
    ST64(T1, T0, OBJ_FLAGS)

    ST64(S0, R0, 0)             /* fn_ptr */
    ST64(S1, R0, 8)             /* env_count */

    LEA_SYM(T0, g_lambda_created)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)
.L_cl_oom:
    SX_EPILOGUE
SX_ENDFUNC(sx_closure_alloc)

/* ----------------------------------------------------------------------------
 * sx_closure_set_env(A0 = closure_ptr, A1 = idx, A2 = val)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_closure_set_env)
    SX_PROLOGUE 0
    ADDI(A0, 16)
    ST64_IDX(A2, A0, A1)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_closure_set_env)

/* ----------------------------------------------------------------------------
 * sx_closure_get_env(A0 = closure_ptr, A1 = idx) -> R0 = val
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_closure_get_env)
    SX_PROLOGUE 0
    ADDI(A0, 16)
    LD64_IDX(R0, A0, A1)
    SX_EPILOGUE
SX_ENDFUNC(sx_closure_get_env)

/* ----------------------------------------------------------------------------
 * sx_closure_call1(A0 = closure_ptr, A1 = arg0) -> R0 = result
 * Invokes closure's lifted function: fn(closure_ptr, arg0)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_closure_call1)
    SX_PROLOGUE 16
    MOVR(S0, A0)                /* closure_ptr */
    MOVR(S1, A1)                /* arg0 */
    LD64(T0, S0, 0)             /* fn_ptr */
    MOVR(A1, S1)
    MOVR(A0, S0)
    SX_CALL_REG(T0)
    SX_EPILOGUE
SX_ENDFUNC(sx_closure_call1)
