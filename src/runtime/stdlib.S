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
 * SYNCHRONIX RUNTIME — Standard Library (std) (src/runtime/stdlib.S)
 * ============================================================================
 * Implements Foundation -> Synchronix Standard Library (std) & Zero-Cost Ops:
 *   - I/O: sx_print_int, sx_println_int, sx_print_str, sx_println_str
 *   - Math: sx_abs, sx_min, sx_max, sx_pow
 *   - Diagnostics/Timing: sx_runtime_report, sx_clock_ticks
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(fmt_int,     "%lld")
SX_STR(fmt_int_ln,  "%lld\n")
SX_STR(fmt_str,     "%s")
SX_STR(fmt_str_ln,  "%s\n")

SX_TEXT

SX_FUNC(sx_print_int)
    SX_PROLOGUE 16
    MOVR(A1, A0)
    LEA_SYM(A0, fmt_int)
    SX_VCALL(printf)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_print_int)

SX_FUNC(sx_println_int)
    SX_PROLOGUE 16
    MOVR(A1, A0)
    LEA_SYM(A0, fmt_int_ln)
    SX_VCALL(printf)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_println_int)

SX_FUNC(sx_print_str)
    SX_PROLOGUE 16
    MOVR(A1, A0)
    LEA_SYM(A0, fmt_str)
    SX_VCALL(printf)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_print_str)

SX_FUNC(sx_println_str)
    SX_PROLOGUE 16
    MOVR(A1, A0)
    LEA_SYM(A0, fmt_str_ln)
    SX_VCALL(printf)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_println_str)

SX_FUNC(sx_abs)
    SX_PROLOGUE 0
    MOVR(R0, A0)
    CMPI(R0, 0)
    JGE(.L_abs_pos)
    NEG(R0)
.L_abs_pos:
    SX_EPILOGUE
SX_ENDFUNC(sx_abs)

SX_FUNC(sx_min)
    SX_PROLOGUE 0
    MOVR(R0, A0)
    CMP(A0, A1)
    JLE(.L_min_done)
    MOVR(R0, A1)
.L_min_done:
    SX_EPILOGUE
SX_ENDFUNC(sx_min)

SX_FUNC(sx_max)
    SX_PROLOGUE 0
    MOVR(R0, A0)
    CMP(A0, A1)
    JGE(.L_max_done)
    MOVR(R0, A1)
.L_max_done:
    SX_EPILOGUE
SX_ENDFUNC(sx_max)

SX_FUNC(sx_pow)
    SX_PROLOGUE 0
    MOVR(S0, A0)        /* base */
    MOVR(S1, A1)        /* exp */
    MOVI(R0, 1)         /* result */
.L_pow_loop:
    CMPI(S1, 0)
    JLE(.L_pow_done)
    MUL(R0, S0)
    SUBI(S1, 1)
    JMP(.L_pow_loop)
.L_pow_done:
    SX_EPILOGUE
SX_ENDFUNC(sx_pow)

SX_FUNC(sx_clock_ticks)
    SX_PROLOGUE 16
    SX_CALL(clock)
    SX_EPILOGUE
SX_ENDFUNC(sx_clock_ticks)

SX_FUNC(sx_runtime_report)
    SX_PROLOGUE 16
    SX_CALL(sx_mem_stats)
    SX_CALL(sx_phi_stats)
    SX_CALL(sx_sched_stats)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_runtime_report)
