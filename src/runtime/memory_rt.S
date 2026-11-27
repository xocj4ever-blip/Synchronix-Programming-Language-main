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
 * SYNCHRONIX RUNTIME — Unified Memory Engine (src/runtime/memory_rt.S)
 * ============================================================================
 * Implements Foundation -> Unified Memory (ARC & GC) & Allocator/Arena Manager:
 *   - Fast Bump-Pointer Arena Allocator (Zero-Cost Escape-Promoted Allocs)
 *   - Swift-inspired ARC Engine (Deterministic Fast Reference Counting)
 *   - Kotlin-inspired GC Engine (Tracing Mark-and-Sweep + Root Stack)
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(str_mem_hdr,   "[Synchronix Runtime] Unified Memory Report:\n")
SX_STR(str_arc_stat,  "  ARC Engine  : allocs=%lld retains=%lld releases=%lld freed=%lld live=%lld\n")
SX_STR(str_gc_stat,   "  GC Engine   : allocs=%lld cycles=%lld swept=%lld live=%lld roots=%lld\n")
SX_STR(str_arena_stat,"  Arena Mgr   : used=%lld bytes / 65536 bytes\n")

SX_BSS
.p2align 4
SX_GLOBAL(g_sx_arena_buf)
SX_LABEL(g_sx_arena_buf)
    .skip 65536
SX_GLOBAL(g_sx_arena_pos)
SX_LABEL(g_sx_arena_pos)
    .skip 8

/* ARC Counters */
SX_GLOBAL(g_arc_allocs)
SX_LABEL(g_arc_allocs)
    .skip 8
SX_GLOBAL(g_arc_retains)
SX_LABEL(g_arc_retains)
    .skip 8
SX_GLOBAL(g_arc_releases)
SX_LABEL(g_arc_releases)
    .skip 8
SX_GLOBAL(g_arc_freed)
SX_LABEL(g_arc_freed)
    .skip 8
SX_GLOBAL(g_arc_live)
SX_LABEL(g_arc_live)
    .skip 8

/* GC Heap & Shadow Root Stack */
SX_GLOBAL(g_gc_head)
SX_LABEL(g_gc_head)
    .skip 8
SX_GLOBAL(g_gc_root_top)
SX_LABEL(g_gc_root_top)
    .skip 8
SX_GLOBAL(g_gc_roots)
SX_LABEL(g_gc_roots)
    .skip (MAX_GC_ROOTS * 8)
SX_GLOBAL(g_gc_allocs)
SX_LABEL(g_gc_allocs)
    .skip 8
SX_GLOBAL(g_gc_cycles)
SX_LABEL(g_gc_cycles)
    .skip 8
SX_GLOBAL(g_gc_swept)
SX_LABEL(g_gc_swept)
    .skip 8
SX_GLOBAL(g_gc_live)
SX_LABEL(g_gc_live)
    .skip 8

SX_TEXT

/* ----------------------------------------------------------------------------
 * sx_arena_alloc(A0 = size) -> R0 = ptr (8-byte aligned bump allocator)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_arena_alloc)
    SX_PROLOGUE 16
    MOVR(S0, A0)                /* S0 = size */
    ADDI(S0, 7)
    ANDI(S0, -8)                /* align up to 8 bytes */
    LEA_SYM(S1, g_sx_arena_pos)
    LD64(S2, S1, 0)             /* S2 = cur pos */
    MOVR(T0, S2)
    ADD(T0, S0)                 /* T0 = new pos */
    MOVI64(T1, 65536)
    CMP(T0, T1)
    JLE(.L_arena_ok)
    /* Fallback to calloc if arena full */
    MOVI(A0, 1)
    MOVR(A1, S0)
    SX_CALL(calloc)
    SX_EPILOGUE
.L_arena_ok:
    ST64(T0, S1, 0)
    LEA_SYM(R0, g_sx_arena_buf)
    ADD(R0, S2)
    SX_EPILOGUE
SX_ENDFUNC(sx_arena_alloc)

/* ----------------------------------------------------------------------------
 * sx_arena_reset()
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_arena_reset)
    SX_PROLOGUE 0
    LEA_SYM(T0, g_sx_arena_pos)
    MOVI(T1, 0)
    ST64(T1, T0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_arena_reset)

/* ----------------------------------------------------------------------------
 * sx_arc_alloc(A0 = payload_size, A1 = dtor_fn) -> R0 = payload_ptr
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_arc_alloc)
    SX_PROLOGUE 16
    MOVR(S0, A0)                /* S0 = payload_size */
    MOVR(S1, A1)                /* S1 = dtor_fn */
    MOVR(A1, S0)
    ADDI(A1, OBJ_HDR_SIZE)
    MOVI(A0, 1)
    SX_CALL(calloc)             /* R0 = hdr */
    CMPI(R0, 0)
    JEQ(.L_arc_alloc_oom)
    MOVI64(T0, SX_MAGIC_ARC)
    ST64(T0, R0, OBJ_MAGIC)
    MOVI(T0, OBJF_ARC)
    ST64(T0, R0, OBJ_FLAGS)
    MOVI(T0, 1)
    ST64(T0, R0, OBJ_RC)
    ST64(S0, R0, OBJ_SIZE)
    MOVI(T0, 0)
    ST64(T0, R0, OBJ_NEXT)
    ST64(S1, R0, OBJ_DTOR)

    /* Update stats */
    LEA_SYM(T0, g_arc_allocs)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)

    LEA_SYM(T0, g_arc_live)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)

    ADDI(R0, OBJ_HDR_SIZE)      /* return payload ptr */
.L_arc_alloc_oom:
    SX_EPILOGUE
SX_ENDFUNC(sx_arc_alloc)

/* ----------------------------------------------------------------------------
 * sx_arc_box_int(A0 = int64_val) -> R0 = arc_payload_ptr
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_arc_box_int)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    MOVI(A0, 8)
    MOVI(A1, 0)
    SX_CALL(sx_arc_alloc)
    CMPI(R0, 0)
    JEQ(.L_arc_box_done)
    ST64(S0, R0, 0)
.L_arc_box_done:
    SX_EPILOGUE
SX_ENDFUNC(sx_arc_box_int)

/* ----------------------------------------------------------------------------
 * sx_arc_unbox_int(A0 = arc_payload_ptr) -> R0 = int64_val
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_arc_unbox_int)
    SX_PROLOGUE 0
    CMPI(A0, 0)
    JEQ(.L_arc_unbox_null)
    LD64(R0, A0, 0)
    SX_EPILOGUE
.L_arc_unbox_null:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_arc_unbox_int)

/* ----------------------------------------------------------------------------
 * sx_arc_retain(A0 = payload_ptr) -> R0 = payload_ptr
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_arc_retain)
    SX_PROLOGUE 0
    MOVR(R0, A0)
    CMPI(R0, 0)
    JEQ(.L_arc_ret_done)
    MOVR(T0, R0)
    SUBI(T0, OBJ_HDR_SIZE)
    LD64(T1, T0, OBJ_MAGIC)
    MOVI64(S0, SX_MAGIC_ARC)
    CMP(T1, S0)
    JNE(.L_arc_ret_done)
    LD64(T1, T0, OBJ_RC)
    ADDI(T1, 1)
    ST64(T1, T0, OBJ_RC)

    LEA_SYM(T0, g_arc_retains)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)
.L_arc_ret_done:
    SX_EPILOGUE
SX_ENDFUNC(sx_arc_retain)

/* ----------------------------------------------------------------------------
 * sx_arc_release(A0 = payload_ptr) -> R0 = remaining_rc
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_arc_release)
    SX_PROLOGUE 16
    MOVR(S0, A0)                /* S0 = payload_ptr */
    CMPI(S0, 0)
    JEQ(.L_arc_rel_zero)
    MOVR(S1, S0)
    SUBI(S1, OBJ_HDR_SIZE)      /* S1 = hdr */
    LD64(T0, S1, OBJ_MAGIC)
    MOVI64(T1, SX_MAGIC_ARC)
    CMP(T0, T1)
    JNE(.L_arc_rel_zero)

    /* Increment release counter */
    LEA_SYM(T0, g_arc_releases)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)

    LD64(S2, S1, OBJ_RC)        /* S2 = rc */
    SUBI(S2, 1)
    ST64(S2, S1, OBJ_RC)
    CMPI(S2, 0)
    JGT(.L_arc_rel_alive)

    /* rc == 0: invoke optional destructor, then free header */
    LD64(T0, S1, OBJ_DTOR)
    CMPI(T0, 0)
    JEQ(.L_arc_no_dtor)
    MOVR(A0, S0)
    SX_CALL_REG(T0)
.L_arc_no_dtor:
    /* Clear magic to detect double-free */
    MOVI(T0, 0)
    ST64(T0, S1, OBJ_MAGIC)

    LEA_SYM(T0, g_arc_live)
    LD64(T1, T0, 0)
    SUBI(T1, 1)
    ST64(T1, T0, 0)

    LEA_SYM(T0, g_arc_freed)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)

    MOVR(A0, S1)
    SX_CALL(free)
    MOVI(R0, 0)
    SX_EPILOGUE
.L_arc_rel_alive:
    MOVR(R0, S2)
    SX_EPILOGUE
.L_arc_rel_zero:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_arc_release)

/* ----------------------------------------------------------------------------
 * sx_gc_alloc(A0 = payload_size) -> R0 = payload_ptr
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_gc_alloc)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    MOVR(A1, S0)
    ADDI(A1, OBJ_HDR_SIZE)
    MOVI(A0, 1)
    SX_CALL(calloc)
    CMPI(R0, 0)
    JEQ(.L_gc_alloc_oom)

    MOVI64(T0, SX_MAGIC_GC)
    ST64(T0, R0, OBJ_MAGIC)
    MOVI(T0, OBJF_GC)
    ST64(T0, R0, OBJ_FLAGS)
    MOVI(T0, 0)
    ST64(T0, R0, OBJ_RC)
    ST64(S0, R0, OBJ_SIZE)
    ST64(T0, R0, OBJ_DTOR)

    /* Link onto g_gc_head */
    LEA_SYM(T0, g_gc_head)
    LD64(T1, T0, 0)
    ST64(T1, R0, OBJ_NEXT)
    ST64(R0, T0, 0)

    LEA_SYM(T0, g_gc_allocs)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)

    LEA_SYM(T0, g_gc_live)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)

    ADDI(R0, OBJ_HDR_SIZE)
.L_gc_alloc_oom:
    SX_EPILOGUE
SX_ENDFUNC(sx_gc_alloc)

/* ----------------------------------------------------------------------------
 * sx_gc_box_int(A0 = val) -> R0 = gc_payload_ptr
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_gc_box_int)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    MOVI(A0, 8)
    SX_CALL(sx_gc_alloc)
    CMPI(R0, 0)
    JEQ(.L_gc_box_done)
    ST64(S0, R0, 0)
.L_gc_box_done:
    SX_EPILOGUE
SX_ENDFUNC(sx_gc_box_int)

/* ----------------------------------------------------------------------------
 * sx_gc_unbox_int(A0 = gc_payload_ptr) -> R0 = int64_val
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_gc_unbox_int)
    SX_PROLOGUE 0
    CMPI(A0, 0)
    JEQ(.L_gc_unbox_null)
    LD64(R0, A0, 0)
    SX_EPILOGUE
.L_gc_unbox_null:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_gc_unbox_int)

/* ----------------------------------------------------------------------------
 * sx_gc_push_root(A0 = payload_ptr)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_gc_push_root)
    SX_PROLOGUE 0
    LEA_SYM(T0, g_gc_root_top)
    LD64(T1, T0, 0)
    CMPI(T1, MAX_GC_ROOTS)
    JGE(.L_gc_push_full)
    LEA_SYM(S0, g_gc_roots)
    ST64_IDX(A0, S0, T1)
    ADDI(T1, 1)
    ST64(T1, T0, 0)
.L_gc_push_full:
    SX_EPILOGUE
SX_ENDFUNC(sx_gc_push_root)

/* ----------------------------------------------------------------------------
 * sx_gc_pop_root()
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_gc_pop_root)
    SX_PROLOGUE 0
    LEA_SYM(T0, g_gc_root_top)
    LD64(T1, T0, 0)
    CMPI(T1, 0)
    JLE(.L_gc_pop_empty)
    SUBI(T1, 1)
    ST64(T1, T0, 0)
.L_gc_pop_empty:
    SX_EPILOGUE
SX_ENDFUNC(sx_gc_pop_root)

/* ----------------------------------------------------------------------------
 * sx_gc_collect() -> R0 = swept_count (Tracing Mark-and-Sweep GC)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_gc_collect)
    SX_PROLOGUE 16
    /* Increment cycle count */
    LEA_SYM(T0, g_gc_cycles)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)

    /* --- MARK PHASE: mark all objects referenced by g_gc_roots --- */
    LEA_SYM(S0, g_gc_roots)
    LEA_SYM(T0, g_gc_root_top)
    LD64(S1, T0, 0)             /* S1 = root_count */
    MOVI(S2, 0)                 /* S2 = i */
.L_gc_mark_loop:
    CMP(S2, S1)
    JGE(.L_gc_sweep_start)
    LD64_IDX(T0, S0, S2)        /* T0 = payload_ptr */
    CMPI(T0, 0)
    JEQ(.L_gc_mark_next)
    SUBI(T0, OBJ_HDR_SIZE)      /* T0 = hdr */
    LD64(T1, T0, OBJ_MAGIC)
    MOVI64(S3, SX_MAGIC_GC)
    CMP(T1, S3)
    JNE(.L_gc_mark_next)
    LD64(T1, T0, OBJ_FLAGS)
    ORI(T1, OBJF_GC_MARKED)
    ST64(T1, T0, OBJ_FLAGS)
.L_gc_mark_next:
    ADDI(S2, 1)
    JMP(.L_gc_mark_loop)

    /* --- SWEEP PHASE: walk g_gc_head, free unmarked objects --- */
.L_gc_sweep_start:
    MOVI(S4, 0)                 /* S4 = swept_this_cycle */
    LEA_SYM(S0, g_gc_head)      /* S0 = &prev_next_ptr (pointer to pointer) */
    LD64(S1, S0, 0)             /* S1 = cur hdr */
.L_gc_sweep_loop:
    CMPI(S1, 0)
    JEQ(.L_gc_sweep_done)
    LD64(S2, S1, OBJ_NEXT)      /* S2 = next hdr */
    LD64(T0, S1, OBJ_FLAGS)
    MOVR(T1, T0)
    ANDI(T1, OBJF_GC_MARKED)
    CMPI(T1, 0)
    JEQ(.L_gc_sweep_free)

    /* Marked: clear mark bit and advance prev_ptr = &cur->next */
    ANDI(T0, ~OBJF_GC_MARKED)
    ST64(T0, S1, OBJ_FLAGS)
    MOVR(S0, S1)
    ADDI(S0, OBJ_NEXT)
    MOVR(S1, S2)
    JMP(.L_gc_sweep_loop)

.L_gc_sweep_free:
    /* Unmarked: unlink (*prev_ptr = next) and free(cur) */
    ST64(S2, S0, 0)
    MOVI(T0, 0)
    ST64(T0, S1, OBJ_MAGIC)
    MOVR(A0, S1)
    SX_CALL(free)

    ADDI(S4, 1)
    LEA_SYM(T0, g_gc_live)
    LD64(T1, T0, 0)
    SUBI(T1, 1)
    ST64(T1, T0, 0)

    LEA_SYM(T0, g_gc_swept)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)

    MOVR(S1, S2)
    JMP(.L_gc_sweep_loop)

.L_gc_sweep_done:
    MOVR(R0, S4)
    SX_EPILOGUE
SX_ENDFUNC(sx_gc_collect)

/* ----------------------------------------------------------------------------
 * sx_mem_stats() — Print Unified Memory Runtime Report (ARC + GC + Arena)
 * Note: Uses 3-arg printf calls to stay strictly within portable A0..A3!
 * ----------------------------------------------------------------------------
 */
SX_RODATA
SX_STR(str_arc_p1, "  ARC Engine  : allocs=%lld retains=%lld releases=%lld")
SX_STR(str_arc_p2, " freed=%lld live=%lld\n")
SX_STR(str_gc_p1,  "  GC Engine   : allocs=%lld cycles=%lld swept=%lld")
SX_STR(str_gc_p2,  " live=%lld roots=%lld\n")

SX_TEXT
SX_FUNC(sx_mem_stats)
    SX_PROLOGUE 16
    LEA_SYM(A0, str_mem_hdr)
    SX_VCALL(printf)

    /* ARC Part 1 */
    LEA_SYM(T0, g_arc_releases)
    LD64(A3, T0, 0)
    LEA_SYM(T0, g_arc_retains)
    LD64(A2, T0, 0)
    LEA_SYM(T0, g_arc_allocs)
    LD64(A1, T0, 0)
    LEA_SYM(A0, str_arc_p1)
    SX_VCALL(printf)

    /* ARC Part 2 */
    LEA_SYM(T0, g_arc_live)
    LD64(A2, T0, 0)
    LEA_SYM(T0, g_arc_freed)
    LD64(A1, T0, 0)
    LEA_SYM(A0, str_arc_p2)
    SX_VCALL(printf)

    /* GC Part 1 */
    LEA_SYM(T0, g_gc_swept)
    LD64(A3, T0, 0)
    LEA_SYM(T0, g_gc_cycles)
    LD64(A2, T0, 0)
    LEA_SYM(T0, g_gc_allocs)
    LD64(A1, T0, 0)
    LEA_SYM(A0, str_gc_p1)
    SX_VCALL(printf)

    /* GC Part 2 */
    LEA_SYM(T0, g_gc_root_top)
    LD64(A2, T0, 0)
    LEA_SYM(T0, g_gc_live)
    LD64(A1, T0, 0)
    LEA_SYM(A0, str_gc_p2)
    SX_VCALL(printf)

    /* Arena */
    LEA_SYM(T0, g_sx_arena_pos)
    LD64(A1, T0, 0)
    LEA_SYM(A0, str_arena_stat)
    SX_VCALL(printf)

    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_mem_stats)
