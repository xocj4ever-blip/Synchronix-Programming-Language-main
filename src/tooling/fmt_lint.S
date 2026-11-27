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
 * SYNCHRONIX ECOSYSTEM — Linter & Formatter (src/tooling/fmt_lint.S)
 * ============================================================================
 * Implements Developer Ecosystem -> Linter & Formatter (`synchronix fmt`):
 *   - sx_cmd_fmt(file)  : tokenizes & canonically formats .synchronix code
 *   - sx_cmd_lint(file) : runs static safety/style/Phi-contract lint rules
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(fmt_indent_4, "    ")
SX_STR(fmt_tok_s,    "%.*s")
SX_STR(fmt_tok_q,    "\"%.*s\"")
SX_STR(fmt_sp,       " ")
SX_STR(fmt_nl,       "\n")
SX_STR(fmt_lbr_nl,   " {\n")
SX_STR(fmt_rbr_nl,   "}\n")

SX_STR(lint_hdr,     "[Synchronix Linter] Checking %s...\n")
SX_STR(lint_div_w,   "Lint [PHI-001]: division operator '/' detected — consider adding a `requires denom != 0` Phi contract")
SX_STR(lint_ok,      "[Synchronix Linter] Done: %lld error(s), %lld warning(s).\n")
SX_STR(err_fl_open,  "[Synchronix] Cannot open file: %s\n")

SX_TEXT

/* Helper: print indent_level * 4 spaces */
SX_FUNC(sx_print_indent)
    SX_PROLOGUE 16
    MOVR(S0, A0)
.L_pi_loop:
    CMPI(S0, 0) ; JLE(.L_pi_done)
    LEA_SYM(A0, fmt_indent_4) ; SX_VCALL(printf)
    SUBI(S0, 1)
    JMP(.L_pi_loop)
.L_pi_done:
    MOVI(R0, 0) ; SX_EPILOGUE
SX_ENDFUNC(sx_print_indent)

/* ----------------------------------------------------------------------------
 * sx_cmd_fmt(A0 = file_path) -> Canonical Synchronix Formatter (`synchronix fmt`)
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_cmd_fmt)
    SX_PROLOGUE 32
    MOVR(S0, A0)
    SX_CALL(sx_compiler_reset)
    MOVR(A0, S0) ; LEA_SYM(A1, g_src_len) ; SX_CALL(sx_read_file)
    CMPI(R0, 0) ; JNE(.L_fmt_ok)
    LEA_SYM(A0, err_fl_open) ; MOVR(A1, S0) ; SX_VCALL(printf)
    MOVI(R0, 1) ; SX_EPILOGUE
.L_fmt_ok:
    MOVR(A0, R0) ; LEA_SYM(T0, g_src_len) ; LD64(A1, T0, 0)
    SX_CALL(sx_lex)

    LEA_SYM(T0, g_tok_count) ; LD64(S0, T0, 0)  /* S0 = count */
    MOVI(S1, 0)                                  /* S1 = i */
    MOVI(S2, 0)                                  /* S2 = indent */
    MOVI(S3, 1)                                  /* S3 = at_line_start */
    MOVI(S4, 1)                                  /* S4 = prev_line */

.L_fmt_loop:
    CMP(S1, S0) ; JGE(.L_fmt_done)
    MOVR(T0, S1) ; MULI(T0, TOK_SIZE) ; LEA_SYM(T1, g_tokens) ; ADD(T0, T1)
    ST_LOCAL(T0, 0)             /* local[0] = tok_ptr */
    LD64(T1, T0, TOK_KIND)
    CMPI(T1, TK_EOF) ; JEQ(.L_fmt_done)

    /* Handle '}' dedent before printing */
    CMPI(T1, TK_RBRACE) ; JNE(.L_fmt_chk_nl)
    CMPI(S3, 0) ; JNE(.L_fmt_rbr_ded)
    LEA_SYM(A0, fmt_nl) ; SX_VCALL(printf)
.L_fmt_rbr_ded:
    CMPI(S2, 0) ; JLE(.L_fmt_rbr_pr)
    SUBI(S2, 1)
.L_fmt_rbr_pr:
    MOVR(A0, S2) ; SX_CALL(sx_print_indent)
    LEA_SYM(A0, fmt_rbr_nl) ; SX_VCALL(printf)
    MOVI(S3, 1)
    LD_LOCAL(T0, 0) ; LD64(S4, T0, TOK_LINE)
    JMP(.L_fmt_next)

.L_fmt_chk_nl:
    LD64(R0, T0, TOK_LINE)
    CMP(R0, S4) ; JLE(.L_fmt_chk_lbr)
    MOVR(S4, R0)
    CMPI(S3, 0) ; JNE(.L_fmt_chk_lbr)
    LEA_SYM(A0, fmt_nl) ; SX_VCALL(printf)
    MOVI(S3, 1)

.L_fmt_chk_lbr:
    LD_LOCAL(T0, 0) ; LD64(T1, T0, TOK_KIND)
    CMPI(T1, TK_LBRACE) ; JNE(.L_fmt_norm)
    LEA_SYM(A0, fmt_lbr_nl) ; SX_VCALL(printf)
    ADDI(S2, 1)
    MOVI(S3, 1)
    JMP(.L_fmt_next)

.L_fmt_norm:
    CMPI(S3, 0) ; JEQ(.L_fmt_space)
    MOVR(A0, S2) ; SX_CALL(sx_print_indent)
    MOVI(S3, 0)
    JMP(.L_fmt_print_tok)
.L_fmt_space:
    /* Skip space before ), ,, :, ;, ( */
    LD_LOCAL(T0, 0) ; LD64(T1, T0, TOK_KIND)
    CMPI(T1, TK_RPAREN) ; JEQ(.L_fmt_print_tok)
    CMPI(T1, TK_COMMA)  ; JEQ(.L_fmt_print_tok)
    CMPI(T1, TK_COLON)  ; JEQ(.L_fmt_print_tok)
    CMPI(T1, TK_SEMI)   ; JEQ(.L_fmt_print_tok)
    CMPI(T1, TK_LPAREN) ; JEQ(.L_fmt_print_tok)
    LEA_SYM(A0, fmt_sp) ; SX_VCALL(printf)

.L_fmt_print_tok:
    LD_LOCAL(T0, 0) ; LD64(T1, T0, TOK_KIND)
    CMPI(T1, TK_STR) ; JEQ(.L_fmt_str)
    LEA_SYM(A0, fmt_tok_s)
    LD64(A1, T0, TOK_LEN)
    LD64(A2, T0, TOK_PTR)
    SX_VCALL(printf)
    JMP(.L_fmt_next)
.L_fmt_str:
    LEA_SYM(A0, fmt_tok_q)
    LD64(A1, T0, TOK_LEN)
    LD64(A2, T0, TOK_PTR)
    SX_VCALL(printf)

.L_fmt_next:
    ADDI(S1, 1)
    JMP(.L_fmt_loop)

.L_fmt_done:
    CMPI(S3, 0) ; JNE(.L_fmt_ret)
    LEA_SYM(A0, fmt_nl) ; SX_VCALL(printf)
.L_fmt_ret:
    MOVI(R0, 0) ; SX_EPILOGUE
SX_ENDFUNC(sx_cmd_fmt)

/* ----------------------------------------------------------------------------
 * sx_cmd_lint(A0 = file_path) — Static Linter & Formal Safety Checker
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_cmd_lint)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    LEA_SYM(A0, lint_hdr) ; MOVR(A1, S0) ; SX_VCALL(printf)

    SX_CALL(sx_compiler_reset)
    MOVR(A0, S0) ; LEA_SYM(A1, g_src_len) ; SX_CALL(sx_read_file)
    CMPI(R0, 0) ; JNE(.L_ln_ok)
    LEA_SYM(A0, err_fl_open) ; MOVR(A1, S0) ; SX_VCALL(printf)
    MOVI(R0, 1) ; SX_EPILOGUE
.L_ln_ok:
    MOVR(A0, R0) ; LEA_SYM(T0, g_src_len) ; LD64(A1, T0, 0)
    SX_CALL(sx_lex)
    SX_CALL(sx_parse_program)
    MOVR(A0, R0) ; SX_CALL(sx_sema_program)

    /* Lint rule PHI-001: check division tokens without `requires` in file */
    LEA_SYM(T0, g_tok_count) ; LD64(S1, T0, 0)
    MOVI(S2, 0)                 /* i */
    MOVI(S3, 0)                 /* has_requires */
.L_ln_scan1:
    CMP(S2, S1) ; JGE(.L_ln_scan2)
    MOVR(T0, S2) ; MULI(T0, TOK_SIZE) ; LEA_SYM(T1, g_tokens) ; ADD(T0, T1)
    LD64(R0, T0, TOK_KIND)
    CMPI(R0, TK_KW_REQUIRES) ; JNE(.L_ln_s1n)
    MOVI(S3, 1)
.L_ln_s1n:
    ADDI(S2, 1) ; JMP(.L_ln_scan1)

.L_ln_scan2:
    CMPI(S3, 0) ; JNE(.L_ln_report)
    MOVI(S2, 0)
.L_ln_dloop:
    CMP(S2, S1) ; JGE(.L_ln_report)
    MOVR(T0, S2) ; MULI(T0, TOK_SIZE) ; LEA_SYM(T1, g_tokens) ; ADD(T0, T1)
    LD64(R0, T0, TOK_KIND)
    CMPI(R0, TK_SLASH) ; JNE(.L_ln_dn)
    LD64(A0, T0, TOK_LINE) ; LEA_SYM(A1, lint_div_w) ; SX_CALL(sx_warn)
.L_ln_dn:
    ADDI(S2, 1) ; JMP(.L_ln_dloop)

.L_ln_report:
    LEA_SYM(T0, g_warn_count) ; LD64(A2, T0, 0)
    LEA_SYM(T0, g_err_count)  ; LD64(A1, T0, 0)
    LEA_SYM(A0, lint_ok)
    SX_VCALL(printf)
    LEA_SYM(T0, g_err_count) ; LD64(R0, T0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_cmd_lint)
