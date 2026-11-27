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
 * SYNCHRONIX RUNTIME — M:N Async Scheduler & Fibers (src/runtime/async_rt.S)
 * ============================================================================
 * Implements Foundation -> M:N Async Schedule & OS (Fibers/Tasks)
 * Kotlin-inspired lightweight task/fiber scheduling:
 *   - sx_spawn(fn_ptr, arg) -> task_id (queues fiber onto M:N work queue)
 *   - sx_sched_step()       -> runs next READY fiber in round-robin order
 *   - sx_await(task_id)     -> drives M:N scheduler until task completes & returns result
 *   - sx_sched_stats()      -> prints scheduler telemetry
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(str_sched_stat, "  M:N Async   : spawned=%lld completed=%lld yields=%lld\n")

SX_BSS
.p2align 4
SX_GLOBAL(g_task_table)
SX_LABEL(g_task_table)
    .skip (MAX_TASKS * TASK_SIZE)
SX_GLOBAL(g_task_count)
SX_LABEL(g_task_count)
    .skip 8
SX_GLOBAL(g_tasks_completed)
SX_LABEL(g_tasks_completed)
    .skip 8
SX_GLOBAL(g_task_yields)
SX_LABEL(g_task_yields)
    .skip 8

SX_TEXT

/* ----------------------------------------------------------------------------
 * sx_spawn(A0 = fn_ptr, A1 = arg) -> R0 = task_id (1-based)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_spawn)
    SX_PROLOGUE 16
    MOVR(S0, A0)                /* S0 = fn_ptr */
    MOVR(S1, A1)                /* S1 = arg */

    LEA_SYM(T0, g_task_count)
    LD64(S2, T0, 0)             /* S2 = idx */
    CMPI(S2, MAX_TASKS)
    JGE(.L_spawn_full)

    MOVR(T1, S2)
    ADDI(T1, 1)
    ST64(T1, T0, 0)             /* g_task_count++ */

    /* Compute task entry address: &g_task_table[idx] (TASK_SIZE = 64) */
    MOVR(S3, S2)
    SHLI(S3, 6)                 /* * 64 */
    LEA_SYM(T0, g_task_table)
    ADD(S3, T0)

    MOVR(T1, S2)
    ADDI(T1, 1)                 /* task_id = idx + 1 */
    ST64(T1, S3, TASK_ID)
    MOVI(T0, TASK_READY)
    ST64(T0, S3, TASK_STATE)
    ST64(S0, S3, TASK_FN)
    ST64(S1, S3, TASK_ARG)
    MOVI(T0, 0)
    ST64(T0, S3, TASK_RESULT)

    MOVR(R0, T1)                /* return task_id */
    SX_EPILOGUE
.L_spawn_full:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_spawn)

/* ----------------------------------------------------------------------------
 * sx_sched_run_one() -> R0 = 1 if a fiber ran, 0 if queue idle
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_sched_run_one)
    SX_PROLOGUE 16
    LEA_SYM(T0, g_task_count)
    LD64(S0, T0, 0)             /* S0 = count */
    MOVI(S1, 0)                 /* S1 = i */
    LEA_SYM(S2, g_task_table)   /* S2 = base */
.L_sched_loop:
    CMP(S1, S0)
    JGE(.L_sched_none)
    MOVR(S3, S1)
    SHLI(S3, 6)
    ADD(S3, S2)                 /* S3 = &table[i] */
    LD64(T0, S3, TASK_STATE)
    CMPI(T0, TASK_READY)
    JNE(.L_sched_next)

    /* Mark RUNNING */
    MOVI(T0, TASK_RUNNING)
    ST64(T0, S3, TASK_STATE)

    /* Execute fiber: result = fn(arg) */
    LD64(T0, S3, TASK_FN)
    LD64(A0, S3, TASK_ARG)
    SX_CALL_REG(T0)

    /* Store result & mark DONE */
    ST64(R0, S3, TASK_RESULT)
    MOVI(T0, TASK_DONE)
    ST64(T0, S3, TASK_STATE)

    LEA_SYM(T0, g_tasks_completed)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)

    MOVI(R0, 1)
    SX_EPILOGUE
.L_sched_next:
    ADDI(S1, 1)
    JMP(.L_sched_loop)
.L_sched_none:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_sched_run_one)

/* ----------------------------------------------------------------------------
 * sx_await(A0 = task_id) -> R0 = fiber result
 * Drives the M:N cooperative scheduler until task_id reaches TASK_DONE
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_await)
    SX_PROLOGUE 16
    MOVR(S0, A0)                /* S0 = task_id (1-based) */
    CMPI(S0, 1)
    JLT(.L_await_invalid)
    SUBI(S0, 1)                 /* S0 = idx */
    SHLI(S0, 6)
    LEA_SYM(T0, g_task_table)
    ADD(S0, T0)                 /* S0 = &task */

.L_await_spin:
    LD64(T0, S0, TASK_STATE)
    CMPI(T0, TASK_DONE)
    JEQ(.L_await_done)
    /* Yield / dispatch next fiber in M:N scheduler */
    LEA_SYM(T0, g_task_yields)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)
    SX_CALL(sx_sched_run_one)
    CMPI(R0, 0)
    JNE(.L_await_spin)
.L_await_done:
    LD64(R0, S0, TASK_RESULT)
    SX_EPILOGUE
.L_await_invalid:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_await)

/* ----------------------------------------------------------------------------
 * sx_sched_stats()
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_sched_stats)
    SX_PROLOGUE 16
    LEA_SYM(T0, g_task_yields)
    LD64(A3, T0, 0)
    LEA_SYM(T0, g_tasks_completed)
    LD64(A2, T0, 0)
    LEA_SYM(T0, g_task_count)
    LD64(A1, T0, 0)
    LEA_SYM(A0, str_sched_stat)
    SX_VCALL(printf)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_sched_stats)
