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
 * Full license text: ../LICENSE
 * End-User License Agreement: ../EULA.md
 */

/* ============================================================================
 * SYNCHRONIX — Pure Portable Assembly ISA Layer (include/portable_asm.S)
 * ============================================================================
 * Targets:
 *   - x86_64  (Windows PE/COFF Win64 ABI, Linux ELF SysV ABI, macOS Mach-O)
 *   - ARM64   (Windows PE/COFF ARM64, Linux ELF AArch64, macOS Mach-O ARM64)
 *
 * Canonical Register Set (100% Portable Across All 6 OS/Arch Targets):
 *   R0          : Return value / primary accumulator
 *   A0..A3      : Argument registers (4 portable integer/pointer arguments)
 *   S0..S4      : 5 callee-saved registers (preserved across all SX_CALLs)
 *   T0, T1      : 2 caller-saved scratch registers (disjoint from R0 & A0..A3)
 *   FP, SP      : Frame pointer & stack pointer
 * ============================================================================
 */

#ifndef SYNCHRONIX_PORTABLE_ASM_S
#define SYNCHRONIX_PORTABLE_ASM_S

/* ----------------------------------------------------------------------------
 * 1. OS / Object Format Symbol & Section Portability
 * ----------------------------------------------------------------------------
 */
#if defined(__APPLE__)
  #define SYM(x) _##x
  #define SX_TEXT   .section __TEXT,__text,regular,pure_instructions
  #define SX_RODATA .section __TEXT,__const
  #define SX_DATA   .section __DATA,__data
  #define SX_BSS    .section __DATA,__bss
#elif defined(_WIN32) || defined(__MINGW32__) || defined(__MINGW64__)
  #define SYM(x) x
  #define SX_TEXT   .section .text
  #define SX_RODATA .section .rdata,"dr"
  #define SX_DATA   .section .data
  #define SX_BSS    .section .bss
#else
  #define SYM(x) x
  #define SX_TEXT   .section .text
  #define SX_RODATA .section .rodata
  #define SX_DATA   .section .data
  #define SX_BSS    .section .bss
#endif

#if defined(__ELF__)
  #define SX_FUNC(name) \
    .globl SYM(name) ; \
    .type SYM(name), @function ; \
    .p2align 4 ; \
    SYM(name):
  #define SX_ENDFUNC(name) \
    .size SYM(name), .-SYM(name)
#else
  #define SX_FUNC(name) \
    .globl SYM(name) ; \
    .p2align 4 ; \
    SYM(name):
  #define SX_ENDFUNC(name)
#endif

#define SX_GLOBAL(name) .globl SYM(name)
#define SX_LABEL(name)  SYM(name):
#define SX_STR(name, text) .p2align 3 ; SYM(name): .asciz text

/* ============================================================================
 * 2. Architecture-Specific Register Mapping & Portable Instruction Macros
 * ============================================================================
 */

#if defined(__x86_64__) || defined(_M_X64)
/* ----------------------------------------------------------------------------
 * x86_64 Implementation (Win64 ABI + System V ABI)
 * ----------------------------------------------------------------------------
 */
#define R0  %rax
#define S0  %rbx
#define S1  %r12
#define S2  %r13
#define S3  %r14
#define S4  %r15
#define T0  %r10
#define T1  %r11
#define FP  %rbp
#define SP  %rsp

#if defined(_WIN32) || defined(__MINGW64__)
  #define A0 %rcx
  #define A1 %rdx
  #define A2 %r8
  #define A3 %r9
#else
  #define A0 %rdi
  #define A1 %rsi
  #define A2 %rdx
  #define A3 %rcx
#endif

/* Stack frame:
 *   [rbp]           = saved rbp
 *   [rbp - 8..40]   = saved S0..S4 (5 regs = 40 bytes)
 *   [rbp - 48 - 8*i]= local slot i (i >= 0)
 *   [rsp + 0..31]   = 32-byte Win64 shadow space (+ 8-byte alignment pad)
 *   frame_bytes MUST be a multiple of 16.
 */
.macro SX_PROLOGUE frame_bytes=0
    pushq %rbp
    movq  %rsp, %rbp
    pushq %rbx
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    subq  $(\frame_bytes + 40), %rsp
.endm

.macro SX_EPILOGUE
    leaq  -40(%rbp), %rsp
    popq  %r15
    popq  %r14
    popq  %r13
    popq  %r12
    popq  %rbx
    popq  %rbp
    ret
.endm

/* Calls */
#define SX_CALL(sym)      call SYM(sym)
#define SX_CALL_REG(reg)  call *reg
#if defined(_WIN32) || defined(__MINGW64__)
  #define SX_VCALL(sym)   call SYM(sym)
#else
  #define SX_VCALL(sym)   xorl %eax, %eax ; call SYM(sym)
#endif

/* Moves & Immediates */
#define MOVR(dst, src)    movq src, dst
#define MOVI(dst, imm)    movq $(imm), dst
#define MOVI64(dst, imm)  movabsq $(imm), dst
#define LEA_SYM(dst, sym) leaq SYM(sym)(%rip), dst

/* Local Stack Slots (slot index 0, 1, 2, ...) */
#define LD_LOCAL(dst, idx)   movq -(48 + (idx)*8)(%rbp), dst
#define ST_LOCAL(src, idx)   movq src, -(48 + (idx)*8)(%rbp)
#define LEA_LOCAL(dst, idx)  leaq -(48 + (idx)*8)(%rbp), dst

/* Memory Load / Store with Immediate Offset */
#define LD64(dst, base, off)   movq (off)(base), dst
#define ST64(src, base, off)   movq src, (off)(base)
#define LD32(dst, base, off)   movl (off)(base), %e##dst
#define LD32_R0(base, off)     movl (off)(base), %eax
#define LD32S_R0(base, off)    movslq (off)(base), %rax
#define LD8_R0(base, off)      movzbq (off)(base), %rax
#define LD8_T0(base, off)      movzbq (off)(base), %r10
#define LD8_T1(base, off)      movzbq (off)(base), %r11
#define ST8_R0(base, off)      movb %al, (off)(base)
#define ST8_T0(base, off)      movb %r10b, (off)(base)
#define ST8_T1(base, off)      movb %r11b, (off)(base)
#define ST8_IMM(imm, base, off) movb $(imm), (off)(base)

/* Indexed Memory Access */
#define LD64_IDX(dst, base, idx)  movq (base, idx, 8), dst
#define ST64_IDX(src, base, idx)  movq src, (base, idx, 8)
#define LD8_IDX_R0(base, idx)     movzbq (base, idx, 1), %rax
#define LD8_IDX_T0(base, idx)     movzbq (base, idx, 1), %r10
#define LD8_IDX_T1(base, idx)     movzbq (base, idx, 1), %r11
#define ST8_IDX_R0(base, idx)     movb %al, (base, idx, 1)
#define ST8_IDX_T0(base, idx)     movb %r10b, (base, idx, 1)

/* Arithmetic & Bitwise (2-operand portable form: dst = dst op src/imm) */
#define ADD(dst, src)     addq src, dst
#define ADDI(dst, imm)    addq $(imm), dst
#define SUB(dst, src)     subq src, dst
#define SUBI(dst, imm)    subq $(imm), dst
#define MUL(dst, src)     imulq src, dst
#define MULI(dst, imm)    imulq $(imm), dst, dst
#define NEG(dst)          negq dst
#define AND(dst, src)     andq src, dst
#define ANDI(dst, imm)    andq $(imm), dst
#define OR(dst, src)      orq src, dst
#define ORI(dst, imm)     orq $(imm), dst
#define XOR(dst, src)     xorq src, dst
#define SHLI(dst, imm)    shlq $(imm), dst
#define SHRI(dst, imm)    shrq $(imm), dst
#define SARI(dst, imm)    sarq $(imm), dst

/* Signed 64-bit Division & Modulo: R0 = R0 / T0  or  R0 = R0 % T0 (preserves all other regs) */
.macro SDIV_R0_T0
    pushq %rdx
    cqto
    idivq %r10
    popq  %rdx
.endm

.macro SMOD_R0_T0
    pushq %rdx
    cqto
    idivq %r10
    movq  %rdx, %rax
    popq  %rdx
.endm

/* Comparisons & Branches */
#define CMP(a, b)         cmpq b, a
#define CMPI(a, imm)      cmpq $(imm), a
#define JMP(lbl)          jmp lbl
#define JEQ(lbl)          je lbl
#define JNE(lbl)          jne lbl
#define JLT(lbl)          jl lbl
#define JLE(lbl)          jle lbl
#define JGT(lbl)          jg lbl
#define JGE(lbl)          jge lbl
#define JULT(lbl)         jb lbl
#define JUGE(lbl)         jae lbl

/* Zero-extended byte load/store via generic register (R0/T0/T1 helpers above cover hot paths) */
#define NOP               nop

#elif defined(__aarch64__) || defined(_M_ARM64)
/* ----------------------------------------------------------------------------
 * ARM64 / AArch64 Implementation (Windows ARM64, Linux ELF, macOS Mach-O)
 * ----------------------------------------------------------------------------
 */
#define R0  x0
#define A0  x0
#define A1  x1
#define A2  x2
#define A3  x3
#define S0  x19
#define S1  x20
#define S2  x21
#define S3  x22
#define S4  x23
#define T0  x9
#define T1  x10
#define FP  x29
#define SP  sp

/* Note: x16 and x17 are intra-procedure-call scratch registers (IP0/IP1) used internally by macros. */

.macro SX_PROLOGUE frame_bytes=0
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    .if \frame_bytes > 0
      mov x16, #\frame_bytes
      sub sp, sp, x16
    .endif
.endm

.macro SX_EPILOGUE
    sub sp, x29, #48
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
.endm

/* Calls */
#define SX_CALL(sym)      bl SYM(sym)
#define SX_CALL_REG(reg)  blr reg
#define SX_VCALL(sym)     bl SYM(sym)

/* Moves & Immediates */
#define MOVR(dst, src)    mov dst, src
#define MOVI(dst, imm)    mov dst, #(imm)
#define MOVI64(dst, imm)  ldr dst, =(imm)

#if defined(__APPLE__)
  #define LEA_SYM(dst, sym) \
    adrp dst, SYM(sym)@PAGE ; \
    add  dst, dst, SYM(sym)@PAGEOFF
#else
  #define LEA_SYM(dst, sym) \
    adrp dst, SYM(sym) ; \
    add  dst, dst, :lo12:SYM(sym)
#endif

/* Local Stack Slots (slot index 0, 1, 2, ... stored at x29 - 56 - 8*idx) */
#define LD_LOCAL(dst, idx) \
    mov x16, #(56 + (idx)*8) ; \
    sub x16, x29, x16 ; \
    ldr dst, [x16]

#define ST_LOCAL(src, idx) \
    mov x16, #(56 + (idx)*8) ; \
    sub x16, x29, x16 ; \
    str src, [x16]

#define LEA_LOCAL(dst, idx) \
    mov x16, #(56 + (idx)*8) ; \
    sub dst, x29, x16

/* Memory Load / Store with Immediate Offset (safe for arbitrary offsets via x16) */
#define LD64(dst, base, off) \
    mov x16, #(off) ; \
    ldr dst, [base, x16]

#define ST64(src, base, off) \
    mov x16, #(off) ; \
    str src, [base, x16]

#define LD32_R0(base, off) \
    mov x16, #(off) ; \
    ldr w0, [base, x16]

#define LD32S_R0(base, off) \
    mov x16, #(off) ; \
    ldrsw x0, [base, x16]

#define LD8_R0(base, off) \
    mov x16, #(off) ; \
    ldrb w0, [base, x16]

#define LD8_T0(base, off) \
    mov x16, #(off) ; \
    ldrb w9, [base, x16]

#define LD8_T1(base, off) \
    mov x16, #(off) ; \
    ldrb w10, [base, x16]

#define ST8_R0(base, off) \
    mov x16, #(off) ; \
    strb w0, [base, x16]

#define ST8_T0(base, off) \
    mov x16, #(off) ; \
    strb w9, [base, x16]

#define ST8_T1(base, off) \
    mov x16, #(off) ; \
    strb w10, [base, x16]

#define ST8_IMM(imm, base, off) \
    mov x16, #(off) ; \
    mov w17, #(imm) ; \
    strb w17, [base, x16]

/* Indexed Memory Access */
#define LD64_IDX(dst, base, idx)  ldr dst, [base, idx, lsl #3]
#define ST64_IDX(src, base, idx)  str src, [base, idx, lsl #3]
#define LD8_IDX_R0(base, idx)     ldrb w0, [base, idx]
#define LD8_IDX_T0(base, idx)     ldrb w9, [base, idx]
#define LD8_IDX_T1(base, idx)     ldrb w10, [base, idx]
#define ST8_IDX_R0(base, idx)     strb w0, [base, idx]
#define ST8_IDX_T0(base, idx)     strb w9, [base, idx]

/* Arithmetic & Bitwise */
#define ADD(dst, src)     add dst, dst, src
#define ADDI(dst, imm)    mov x16, #(imm) ; add dst, dst, x16
#define SUB(dst, src)     sub dst, dst, src
#define SUBI(dst, imm)    mov x16, #(imm) ; sub dst, dst, x16
#define MUL(dst, src)     mul dst, dst, src
#define MULI(dst, imm)    mov x16, #(imm) ; mul dst, dst, x16
#define NEG(dst)          neg dst, dst
#define AND(dst, src)     and dst, dst, src
#define ANDI(dst, imm)    mov x16, #(imm) ; and dst, dst, x16
#define OR(dst, src)      orr dst, dst, src
#define ORI(dst, imm)     mov x16, #(imm) ; orr dst, dst, x16
#define XOR(dst, src)     eor dst, dst, src
#define SHLI(dst, imm)    lsl dst, dst, #(imm)
#define SHRI(dst, imm)    lsr dst, dst, #(imm)
#define SARI(dst, imm)    asr dst, dst, #(imm)

.macro SDIV_R0_T0
    sdiv x0, x0, x9
.endm

.macro SMOD_R0_T0
    sdiv x16, x0, x9
    msub x0, x16, x9, x0
.endm

/* Comparisons & Branches */
#define CMP(a, b)         cmp a, b
#define CMPI(a, imm)      mov x16, #(imm) ; cmp a, x16
#define JMP(lbl)          b lbl
#define JEQ(lbl)          b.eq lbl
#define JNE(lbl)          b.ne lbl
#define JLT(lbl)          b.lt lbl
#define JLE(lbl)          b.le lbl
#define JGT(lbl)          b.gt lbl
#define JGE(lbl)          b.ge lbl
#define JULT(lbl)         b.lo lbl
#define JUGE(lbl)         b.hs lbl

#define NOP               nop

#else
  #error "Unsupported architecture: Synchronix Portable Assembly supports x86_64 and ARM64 (aarch64)."
#endif

#endif /* SYNCHRONIX_PORTABLE_ASM_S */
