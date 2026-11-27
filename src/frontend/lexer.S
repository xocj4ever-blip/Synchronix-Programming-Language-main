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
 * SYNCHRONIX COMPILER — Phase 1: Lexer / Tokenizer (src/frontend/lexer.S)
 * ============================================================================
 * Reads .synchronix source text -> produces Token stream in g_tokens[].
 * Supports Swift + Kotlin + Phi (Formal Logic) + Lambda (Functional) syntax.
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(kw_func,      "func")
SX_STR(kw_fun,       "fun")
SX_STR(kw_let,       "let")
SX_STR(kw_val,       "val")
SX_STR(kw_var,       "var")
SX_STR(kw_return,    "return")
SX_STR(kw_if,        "if")
SX_STR(kw_else,      "else")
SX_STR(kw_while,     "while")
SX_STR(kw_true,      "true")
SX_STR(kw_false,     "false")
SX_STR(kw_arc,       "arc")
SX_STR(kw_gc,        "gc")
SX_STR(kw_borrow,    "borrow")
SX_STR(kw_move,      "move")
SX_STR(kw_phi,       "phi")
SX_STR(kw_requires,  "requires")
SX_STR(kw_ensures,   "ensures")
SX_STR(kw_invariant, "invariant")
SX_STR(kw_prove,     "prove")
SX_STR(kw_lambda,    "lambda")
SX_STR(kw_async,     "async")
SX_STR(kw_spawn,     "spawn")
SX_STR(kw_await,     "await")
SX_STR(kw_struct,    "struct")
SX_STR(kw_extern,    "extern")
SX_STR(kw_import,    "import")

SX_TEXT

/* ----------------------------------------------------------------------------
 * Internal helper: sx_emit_tok(A0=kind, A1=ptr, A2=len, A3=ival)
 * Uses local state via g_lex_line / g_lex_col
 * ----------------------------------------------------------------------------
 */
SX_BSS
.p2align 3
SX_LABEL(g_lex_line)
    .skip 8
SX_LABEL(g_lex_col)
    .skip 8

SX_TEXT

SX_FUNC(sx_emit_tok)
    SX_PROLOGUE 16
    MOVR(S0, A0)        /* kind */
    MOVR(S1, A1)        /* ptr */
    MOVR(S2, A2)        /* len */
    MOVR(S3, A3)        /* ival */

    LEA_SYM(T0, g_tok_count)
    LD64(S4, T0, 0)
    CMPI(S4, MAX_TOKENS)
    JGE(.L_et_full)

    MOVR(T1, S4)
    ADDI(T1, 1)
    ST64(T1, T0, 0)

    /* slot = &g_tokens[idx] (TOK_SIZE = 48) */
    MULI(S4, TOK_SIZE)
    LEA_SYM(T0, g_tokens)
    ADD(S4, T0)

    ST64(S0, S4, TOK_KIND)
    ST64(S1, S4, TOK_PTR)
    ST64(S2, S4, TOK_LEN)
    ST64(S3, S4, TOK_IVAL)
    LEA_SYM(T0, g_lex_line) ; LD64(T1, T0, 0) ; ST64(T1, S4, TOK_LINE)
    LEA_SYM(T0, g_lex_col)  ; LD64(T1, T0, 0) ; ST64(T1, S4, TOK_COL)
.L_et_full:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_emit_tok)

/* ----------------------------------------------------------------------------
 * sx_classify_kw(A0 = ptr, A1 = len) -> R0 = TK_KW_* or TK_IDENT
 * ----------------------------------------------------------------------------
 */
.macro CHECK_KW kw_sym, tok_kind
    MOVR(A0, S0)
    MOVR(A1, S1)
    LEA_SYM(A2, \kw_sym)
    SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0)
    JNE(.L_kw_ret_\tok_kind)
    JMP(.L_kw_next_\kw_sym)
.L_kw_ret_\tok_kind:
    MOVI(R0, \tok_kind)
    SX_EPILOGUE
.L_kw_next_\kw_sym:
.endm

SX_FUNC(sx_classify_kw)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    MOVR(S1, A1)

    /* Note: func and fun both map to TK_KW_FUNC (Swift + Kotlin!) */
    MOVR(A0, S0) ; MOVR(A1, S1) ; LEA_SYM(A2, kw_func) ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JNE(.L_ret_func)
    MOVR(A0, S0) ; MOVR(A1, S1) ; LEA_SYM(A2, kw_fun)  ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JNE(.L_ret_func)

    /* let and val both map to TK_KW_LET (Swift + Kotlin!) */
    MOVR(A0, S0) ; MOVR(A1, S1) ; LEA_SYM(A2, kw_let)  ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JNE(.L_ret_let)
    MOVR(A0, S0) ; MOVR(A1, S1) ; LEA_SYM(A2, kw_val)  ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JNE(.L_ret_let)

    CHECK_KW kw_var,       TK_KW_VAR
    CHECK_KW kw_return,    TK_KW_RETURN
    CHECK_KW kw_if,        TK_KW_IF
    CHECK_KW kw_else,      TK_KW_ELSE
    CHECK_KW kw_while,     TK_KW_WHILE
    CHECK_KW kw_true,      TK_KW_TRUE
    CHECK_KW kw_false,     TK_KW_FALSE
    CHECK_KW kw_arc,       TK_KW_ARC
    CHECK_KW kw_gc,        TK_KW_GC
    CHECK_KW kw_borrow,    TK_KW_BORROW
    CHECK_KW kw_move,      TK_KW_MOVE
    CHECK_KW kw_phi,       TK_KW_PHI
    CHECK_KW kw_requires,  TK_KW_REQUIRES
    CHECK_KW kw_ensures,   TK_KW_ENSURES
    CHECK_KW kw_invariant, TK_KW_INVARIANT
    CHECK_KW kw_prove,     TK_KW_PROVE
    CHECK_KW kw_lambda,    TK_KW_LAMBDA
    CHECK_KW kw_async,     TK_KW_ASYNC
    CHECK_KW kw_spawn,     TK_KW_SPAWN
    CHECK_KW kw_await,     TK_KW_AWAIT
    CHECK_KW kw_struct,    TK_KW_STRUCT
    CHECK_KW kw_extern,    TK_KW_EXTERN
    CHECK_KW kw_import,    TK_KW_IMPORT

    MOVI(R0, TK_IDENT)
    SX_EPILOGUE
.L_ret_func:
    MOVI(R0, TK_KW_FUNC)
    SX_EPILOGUE
.L_ret_let:
    MOVI(R0, TK_KW_LET)
    SX_EPILOGUE
SX_ENDFUNC(sx_classify_kw)

/* ----------------------------------------------------------------------------
 * sx_is_alpha(A0 = ch) -> R0 = 1 if [A-Za-z_] else 0
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_is_alpha)
    SX_PROLOGUE 0
    CMPI(A0, '_') ; JEQ(.L_ia_yes)
    CMPI(A0, 'a') ; JLT(.L_ia_upper)
    CMPI(A0, 'z') ; JLE(.L_ia_yes)
.L_ia_upper:
    CMPI(A0, 'A') ; JLT(.L_ia_no)
    CMPI(A0, 'Z') ; JLE(.L_ia_yes)
.L_ia_no:
    MOVI(R0, 0) ; SX_EPILOGUE
.L_ia_yes:
    MOVI(R0, 1) ; SX_EPILOGUE
SX_ENDFUNC(sx_is_alpha)

SX_FUNC(sx_is_digit)
    SX_PROLOGUE 0
    CMPI(A0, '0') ; JLT(.L_id_no)
    CMPI(A0, '9') ; JLE(.L_id_yes)
.L_id_no:
    MOVI(R0, 0) ; SX_EPILOGUE
.L_id_yes:
    MOVI(R0, 1) ; SX_EPILOGUE
SX_ENDFUNC(sx_is_digit)

/* ----------------------------------------------------------------------------
 * sx_lex(A0 = src_ptr, A1 = src_len) -> R0 = token_count
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_lex)
    SX_PROLOGUE 32
    MOVR(S0, A0)                /* S0 = src_ptr */
    MOVR(S1, A1)                /* S1 = src_len */
    MOVI(S2, 0)                 /* S2 = pos */

    LEA_SYM(T0, g_tok_count) ; MOVI(T1, 0) ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_tok_pos)   ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_lex_line)  ; MOVI(T1, 1) ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_lex_col)   ; ST64(T1, T0, 0)

.L_lex_loop:
    CMP(S2, S1)
    JGE(.L_lex_eof)

    LD8_IDX_R0(S0, S2)          /* R0 = ch */
    /* Skip whitespace */
    CMPI(R0, ' ')  ; JEQ(.L_lex_ws)
    CMPI(R0, '\t') ; JEQ(.L_lex_ws)
    CMPI(R0, '\r') ; JEQ(.L_lex_ws)
    CMPI(R0, '\n') ; JEQ(.L_lex_nl)

    /* Comments: line or block */
    CMPI(R0, '/')
    JNE(.L_lex_not_comment)
    MOVR(T0, S2) ; ADDI(T0, 1)
    CMP(T0, S1) ; JGE(.L_lex_not_comment)
    LD8_IDX_T1(S0, T0)
    CMPI(T1, '/') ; JEQ(.L_lex_line_comment)
    CMPI(T1, '*') ; JEQ(.L_lex_block_comment)
.L_lex_not_comment:

    /* Save start pos S3 */
    MOVR(S3, S2)

    /* Identifier or Keyword? */
    MOVR(A0, R0)
    SX_CALL(sx_is_alpha)
    CMPI(R0, 0)
    JNE(.L_lex_ident)

    /* Number? */
    LD8_IDX_R0(S0, S2)
    MOVR(A0, R0)
    SX_CALL(sx_is_digit)
    CMPI(R0, 0)
    JNE(.L_lex_num)

    /* String literal? */
    LD8_IDX_R0(S0, S2)
    CMPI(R0, '"')
    JEQ(.L_lex_str)

    /* Operators & Punctuation */
    /* Compute next char in S4 (0 if at end) */
    MOVI(S4, 0)
    MOVR(T0, S2) ; ADDI(T0, 1)
    CMP(T0, S1) ; JGE(.L_lex_ops)
    LD8_IDX_T1(S0, T0)
    MOVR(S4, T1)

.L_lex_ops:
    LD8_IDX_R0(S0, S2)
    /* 2-char operators first */
    CMPI(R0, '=') ; JNE(.L_op_ne)
      CMPI(S4, '=') ; JEQ(.L_emit_eq)
      CMPI(S4, '>') ; JEQ(.L_emit_fatarrow)
      JMP(.L_emit_assign)
.L_op_ne:
    CMPI(R0, '!') ; JNE(.L_op_lt)
      CMPI(S4, '=') ; JEQ(.L_emit_ne)
      JMP(.L_emit_bang)
.L_op_lt:
    CMPI(R0, '<') ; JNE(.L_op_gt)
      CMPI(S4, '=') ; JEQ(.L_emit_le)
      JMP(.L_emit_lt)
.L_op_gt:
    CMPI(R0, '>') ; JNE(.L_op_minus)
      CMPI(S4, '=') ; JEQ(.L_emit_ge)
      JMP(.L_emit_gt)
.L_op_minus:
    CMPI(R0, '-') ; JNE(.L_op_amp)
      CMPI(S4, '>') ; JEQ(.L_emit_arrow)
      JMP(.L_emit_minus)
.L_op_amp:
    CMPI(R0, '&') ; JNE(.L_op_pipe)
      CMPI(S4, '&') ; JEQ(.L_emit_and)
      JMP(.L_emit_amp)
.L_op_pipe:
    CMPI(R0, '|') ; JNE(.L_op_single)
      CMPI(S4, '|') ; JEQ(.L_emit_or)
      CMPI(S4, '>') ; JEQ(.L_emit_pipe)
      JMP(.L_lex_skip_unknown)

.L_op_single:
    CMPI(R0, '(') ; JEQ(.L_emit_lparen)
    CMPI(R0, ')') ; JEQ(.L_emit_rparen)
    CMPI(R0, '{') ; JEQ(.L_emit_lbrace)
    CMPI(R0, '}') ; JEQ(.L_emit_rbrace)
    CMPI(R0, '[') ; JEQ(.L_emit_lbrack)
    CMPI(R0, ']') ; JEQ(.L_emit_rbrack)
    CMPI(R0, ',') ; JEQ(.L_emit_comma)
    CMPI(R0, ':') ; JEQ(.L_emit_colon)
    CMPI(R0, ';') ; JEQ(.L_emit_semi)
    CMPI(R0, '.') ; JEQ(.L_emit_dot)
    CMPI(R0, '+') ; JEQ(.L_emit_plus)
    CMPI(R0, '*') ; JEQ(.L_emit_star)
    CMPI(R0, '/') ; JEQ(.L_emit_slash)
    CMPI(R0, '%') ; JEQ(.L_emit_pct)

.L_lex_skip_unknown:
    ADDI(S2, 1)
    JMP(.L_lex_loop)

/* --- Whitespace & Comments --- */
.L_lex_ws:
    ADDI(S2, 1)
    LEA_SYM(T0, g_lex_col) ; LD64(T1, T0, 0) ; ADDI(T1, 1) ; ST64(T1, T0, 0)
    JMP(.L_lex_loop)

.L_lex_nl:
    ADDI(S2, 1)
    LEA_SYM(T0, g_lex_line) ; LD64(T1, T0, 0) ; ADDI(T1, 1) ; ST64(T1, T0, 0)
    LEA_SYM(T0, g_lex_col)  ; MOVI(T1, 1) ; ST64(T1, T0, 0)
    JMP(.L_lex_loop)

.L_lex_line_comment:
    ADDI(S2, 2)
.L_lc_loop:
    CMP(S2, S1) ; JGE(.L_lex_loop)
    LD8_IDX_R0(S0, S2)
    CMPI(R0, '\n') ; JEQ(.L_lex_loop)
    ADDI(S2, 1)
    JMP(.L_lc_loop)

.L_lex_block_comment:
    ADDI(S2, 2)
.L_bc_loop:
    CMP(S2, S1) ; JGE(.L_lex_loop)
    LD8_IDX_R0(S0, S2)
    CMPI(R0, '\n') ; JNE(.L_bc_chk)
    LEA_SYM(T0, g_lex_line) ; LD64(T1, T0, 0) ; ADDI(T1, 1) ; ST64(T1, T0, 0)
.L_bc_chk:
    CMPI(R0, '*') ; JNE(.L_bc_adv)
    MOVR(T0, S2) ; ADDI(T0, 1)
    CMP(T0, S1) ; JGE(.L_bc_adv)
    LD8_IDX_T1(S0, T0)
    CMPI(T1, '/') ; JNE(.L_bc_adv)
    ADDI(S2, 2)
    JMP(.L_lex_loop)
.L_bc_adv:
    ADDI(S2, 1)
    JMP(.L_bc_loop)

/* --- Identifier / Keyword --- */
.L_lex_ident:
    ADDI(S2, 1)
.L_id_scan:
    CMP(S2, S1) ; JGE(.L_id_done)
    LD8_IDX_R0(S0, S2)
    MOVR(A0, R0) ; SX_CALL(sx_is_alpha)
    CMPI(R0, 0) ; JNE(.L_id_next)
    LD8_IDX_R0(S0, S2)
    MOVR(A0, R0) ; SX_CALL(sx_is_digit)
    CMPI(R0, 0) ; JEQ(.L_id_done)
.L_id_next:
    ADDI(S2, 1)
    JMP(.L_id_scan)
.L_id_done:
    MOVR(S4, S0) ; ADD(S4, S3)          /* ptr = src + start */
    MOVR(T0, S2) ; SUB(T0, S3)          /* len = pos - start */
    ST_LOCAL(T0, 0)
    MOVR(A0, S4)
    MOVR(A1, T0)
    SX_CALL(sx_classify_kw)
    MOVR(A0, R0)                        /* kind */
    MOVR(A1, S4)                        /* ptr */
    LD_LOCAL(A2, 0)                     /* len */
    MOVI(A3, 0)
    SX_CALL(sx_emit_tok)
    JMP(.L_lex_loop)

/* --- Integer Literal --- */
.L_lex_num:
    MOVI(S4, 0)                         /* accumulator */
.L_num_scan:
    CMP(S2, S1) ; JGE(.L_num_done)
    LD8_IDX_R0(S0, S2)
    CMPI(R0, '0') ; JLT(.L_num_done)
    CMPI(R0, '9') ; JGT(.L_num_done)
    MULI(S4, 10)
    SUBI(R0, '0')
    ADD(S4, R0)
    ADDI(S2, 1)
    JMP(.L_num_scan)
.L_num_done:
    MOVR(A1, S0) ; ADD(A1, S3)
    MOVR(A2, S2) ; SUB(A2, S3)
    MOVR(A3, S4)
    MOVI(A0, TK_INT)
    SX_CALL(sx_emit_tok)
    JMP(.L_lex_loop)

/* --- String Literal --- */
.L_lex_str:
    ADDI(S2, 1)                         /* skip opening " */
    MOVR(S3, S2)                        /* string content start */
.L_str_scan:
    CMP(S2, S1) ; JGE(.L_str_done)
    LD8_IDX_R0(S0, S2)
    CMPI(R0, '"') ; JEQ(.L_str_done)
    ADDI(S2, 1)
    JMP(.L_str_scan)
.L_str_done:
    MOVR(A1, S0) ; ADD(A1, S3)
    MOVR(A2, S2) ; SUB(A2, S3)
    MOVI(A3, 0)
    MOVI(A0, TK_STR)
    SX_CALL(sx_emit_tok)
    CMP(S2, S1) ; JGE(.L_lex_loop)
    ADDI(S2, 1)                         /* skip closing " */
    JMP(.L_lex_loop)

/* --- Single & Double Character Operator Emitters --- */
.macro EMIT_OP1 lbl, kind
\lbl:
    MOVR(A1, S0) ; ADD(A1, S2)
    MOVI(A2, 1)
    MOVI(A3, 0)
    MOVI(A0, \kind)
    SX_CALL(sx_emit_tok)
    ADDI(S2, 1)
    JMP(.L_lex_loop)
.endm

.macro EMIT_OP2 lbl, kind
\lbl:
    MOVR(A1, S0) ; ADD(A1, S2)
    MOVI(A2, 2)
    MOVI(A3, 0)
    MOVI(A0, \kind)
    SX_CALL(sx_emit_tok)
    ADDI(S2, 2)
    JMP(.L_lex_loop)
.endm

EMIT_OP2 .L_emit_eq,       TK_EQ
EMIT_OP2 .L_emit_ne,       TK_NE
EMIT_OP2 .L_emit_le,       TK_LE
EMIT_OP2 .L_emit_ge,       TK_GE
EMIT_OP2 .L_emit_and,      TK_AND
EMIT_OP2 .L_emit_or,       TK_OR
EMIT_OP2 .L_emit_arrow,    TK_ARROW
EMIT_OP2 .L_emit_fatarrow, TK_FATARROW
EMIT_OP2 .L_emit_pipe,     TK_PIPE

EMIT_OP1 .L_emit_assign,   TK_ASSIGN
EMIT_OP1 .L_emit_bang,     TK_BANG
EMIT_OP1 .L_emit_lt,       TK_LT
EMIT_OP1 .L_emit_gt,       TK_GT
EMIT_OP1 .L_emit_minus,    TK_MINUS
EMIT_OP1 .L_emit_amp,      TK_AMP
EMIT_OP1 .L_emit_lparen,   TK_LPAREN
EMIT_OP1 .L_emit_rparen,   TK_RPAREN
EMIT_OP1 .L_emit_lbrace,   TK_LBRACE
EMIT_OP1 .L_emit_rbrace,   TK_RBRACE
EMIT_OP1 .L_emit_lbrack,   TK_LBRACKET
EMIT_OP1 .L_emit_rbrack,   TK_RBRACKET
EMIT_OP1 .L_emit_comma,    TK_COMMA
EMIT_OP1 .L_emit_colon,    TK_COLON
EMIT_OP1 .L_emit_semi,     TK_SEMI
EMIT_OP1 .L_emit_dot,      TK_DOT
EMIT_OP1 .L_emit_plus,     TK_PLUS
EMIT_OP1 .L_emit_star,     TK_STAR
EMIT_OP1 .L_emit_slash,    TK_SLASH
EMIT_OP1 .L_emit_pct,      TK_PERCENT

.L_lex_eof:
    MOVI(A0, TK_EOF)
    MOVI(A1, 0)
    MOVI(A2, 0)
    MOVI(A3, 0)
    SX_CALL(sx_emit_tok)
    LEA_SYM(T0, g_tok_count)
    LD64(R0, T0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_lex)
