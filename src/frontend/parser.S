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
 * SYNCHRONIX COMPILER — Phase 1: Parser (src/frontend/parser.S)
 * ============================================================================
 * Recursive-descent + precedence parser: Tokens -> Abstract Syntax Tree (AST)
 * Supports Swift/Kotlin syntax, Generics <T>, Phi contracts (requires/ensures/
 * prove/invariant), Lambda closures, ARC/GC/Borrow/Move, and M:N Async fibers.
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(err_exp_tok,   "Parser: unexpected token")
SX_STR(err_exp_ident, "Parser: expected identifier")
SX_STR(err_exp_expr,  "Parser: expected expression")
SX_STR(err_exp_lbr,   "Parser: expected '{'")
SX_STR(err_exp_rbr,   "Parser: expected '}'")
SX_STR(err_exp_rp,    "Parser: expected ')'")
SX_STR(ty_int_s,      "Int")
SX_STR(ty_bool_s,     "Bool")
SX_STR(ty_str_s,      "String")
SX_STR(ty_void_s,     "Void")

SX_TEXT

/* ----------------------------------------------------------------------------
 * Token Stream Helpers:
 *   sx_cur_tok()  -> R0 = &g_tokens[g_tok_pos]
 *   sx_peek_kind()-> R0 = current token kind
 *   sx_peek_next()-> R0 = next token kind (lookahead 1)
 *   sx_advance()  -> R0 = previous token ptr, increments g_tok_pos
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_cur_tok)
    SX_PROLOGUE 0
    LEA_SYM(T0, g_tok_pos)
    LD64(R0, T0, 0)
    MULI(R0, TOK_SIZE)
    LEA_SYM(T1, g_tokens)
    ADD(R0, T1)
    SX_EPILOGUE
SX_ENDFUNC(sx_cur_tok)

SX_FUNC(sx_peek_kind)
    SX_PROLOGUE 16
    SX_CALL(sx_cur_tok)
    LD64(R0, R0, TOK_KIND)
    SX_EPILOGUE
SX_ENDFUNC(sx_peek_kind)

SX_FUNC(sx_peek_next_kind)
    SX_PROLOGUE 0
    LEA_SYM(T0, g_tok_pos)
    LD64(R0, T0, 0)
    ADDI(R0, 1)
    LEA_SYM(T1, g_tok_count)
    LD64(T1, T1, 0)
    CMP(R0, T1)
    JGE(.L_pn_eof)
    MULI(R0, TOK_SIZE)
    LEA_SYM(T1, g_tokens)
    ADD(R0, T1)
    LD64(R0, R0, TOK_KIND)
    SX_EPILOGUE
.L_pn_eof:
    MOVI(R0, TK_EOF)
    SX_EPILOGUE
SX_ENDFUNC(sx_peek_next_kind)

SX_FUNC(sx_advance)
    SX_PROLOGUE 16
    SX_CALL(sx_cur_tok)
    MOVR(S0, R0)
    LD64(T0, S0, TOK_KIND)
    CMPI(T0, TK_EOF)
    JEQ(.L_adv_done)
    LEA_SYM(T0, g_tok_pos)
    LD64(T1, T0, 0)
    ADDI(T1, 1)
    ST64(T1, T0, 0)
.L_adv_done:
    MOVR(R0, S0)
    SX_EPILOGUE
SX_ENDFUNC(sx_advance)

/* sx_match(A0 = expected_kind) -> R0 = 1 if consumed else 0 */
SX_FUNC(sx_match)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    SX_CALL(sx_peek_kind)
    CMP(R0, S0)
    JNE(.L_mat_no)
    SX_CALL(sx_advance)
    MOVI(R0, 1)
    SX_EPILOGUE
.L_mat_no:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_match)

/* sx_parse_type() -> R0 = TY_* (consumes one type identifier) */
SX_FUNC(sx_parse_type)
    SX_PROLOGUE 16
    SX_CALL(sx_advance)
    MOVR(S0, R0)
    LD64(S1, S0, TOK_PTR)
    LD64(S2, S0, TOK_LEN)

    MOVR(A0, S1) ; MOVR(A1, S2) ; LEA_SYM(A2, ty_int_s) ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JNE(.L_pt_int)
    MOVR(A0, S1) ; MOVR(A1, S2) ; LEA_SYM(A2, ty_bool_s) ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JNE(.L_pt_bool)
    MOVR(A0, S1) ; MOVR(A1, S2) ; LEA_SYM(A2, ty_str_s) ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JNE(.L_pt_str)
    MOVR(A0, S1) ; MOVR(A1, S2) ; LEA_SYM(A2, ty_void_s) ; SX_CALL(sx_slice_eq_cstr)
    CMPI(R0, 0) ; JNE(.L_pt_void)
    /* Generic type parameter like T */
    MOVI(R0, TY_GENERIC)
    SX_EPILOGUE
.L_pt_int:  MOVI(R0, TY_INT)  ; SX_EPILOGUE
.L_pt_bool: MOVI(R0, TY_BOOL) ; SX_EPILOGUE
.L_pt_str:  MOVI(R0, TY_STR)  ; SX_EPILOGUE
.L_pt_void: MOVI(R0, TY_VOID) ; SX_EPILOGUE
SX_ENDFUNC(sx_parse_type)

/* ============================================================================
 * Expression Parser (Precedence Climbing / Recursive Descent)
 * ============================================================================
 */

/* sx_parse_primary() -> R0 = ast_node */
SX_FUNC(sx_parse_primary)
    SX_PROLOGUE 48
    SX_CALL(sx_cur_tok)
    MOVR(S0, R0)                /* S0 = cur tok */
    LD64(S1, S0, TOK_KIND)      /* S1 = kind */
    LD64(S2, S0, TOK_LINE)      /* S2 = line */

    /* Integer Literal */
    CMPI(S1, TK_INT) ; JNE(.L_pr_true)
    SX_CALL(sx_advance)
    MOVI(A0, NK_INT) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    LD64(T0, S0, TOK_IVAL)
    ST64(T0, R0, AST_IVAL)
    MOVI(T0, TY_INT)
    ST64(T0, R0, AST_TYPE)
    SX_EPILOGUE

.L_pr_true:
    CMPI(S1, TK_KW_TRUE) ; JNE(.L_pr_false)
    SX_CALL(sx_advance)
    MOVI(A0, NK_INT) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    MOVI(T0, 1) ; ST64(T0, R0, AST_IVAL)
    MOVI(T0, TY_BOOL) ; ST64(T0, R0, AST_TYPE)
    SX_EPILOGUE

.L_pr_false:
    CMPI(S1, TK_KW_FALSE) ; JNE(.L_pr_str)
    SX_CALL(sx_advance)
    MOVI(A0, NK_INT) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    MOVI(T0, 0) ; ST64(T0, R0, AST_IVAL)
    MOVI(T0, TY_BOOL) ; ST64(T0, R0, AST_TYPE)
    SX_EPILOGUE

.L_pr_str:
    CMPI(S1, TK_STR) ; JNE(.L_pr_lparen)
    SX_CALL(sx_advance)
    MOVI(A0, NK_STR) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    MOVR(S3, R0)
    LD64(T0, S0, TOK_PTR) ; ST64(T0, S3, AST_NAME_PTR)
    LD64(T0, S0, TOK_LEN) ; ST64(T0, S3, AST_NAME_LEN)
    MOVI(T0, TY_STR)      ; ST64(T0, S3, AST_TYPE)
    MOVR(R0, S3)
    SX_EPILOGUE

.L_pr_lparen:
    CMPI(S1, TK_LPAREN) ; JNE(.L_pr_arc)
    SX_CALL(sx_advance)
    SX_CALL(sx_parse_expr)
    MOVR(S3, R0)
    MOVI(A0, TK_RPAREN) ; SX_CALL(sx_match)
    MOVR(R0, S3)
    SX_EPILOGUE

.L_pr_arc:
    /* arc(expr) -> Swift-inspired ARC allocation */
    CMPI(S1, TK_KW_ARC) ; JNE(.L_pr_gc)
    SX_CALL(sx_advance)
    MOVI(A0, TK_LPAREN) ; SX_CALL(sx_match)
    SX_CALL(sx_parse_expr)
    MOVR(S3, R0)
    MOVI(A0, TK_RPAREN) ; SX_CALL(sx_match)
    MOVI(A0, NK_ARC_NEW) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    ST64(S3, R0, AST_LEFT)
    MOVI(T0, TY_ARC) ; ST64(T0, R0, AST_TYPE)
    SX_EPILOGUE

.L_pr_gc:
    /* gc(expr) -> Kotlin-inspired tracing GC allocation */
    CMPI(S1, TK_KW_GC) ; JNE(.L_pr_lambda)
    SX_CALL(sx_advance)
    MOVI(A0, TK_LPAREN) ; SX_CALL(sx_match)
    SX_CALL(sx_parse_expr)
    MOVR(S3, R0)
    MOVI(A0, TK_RPAREN) ; SX_CALL(sx_match)
    MOVI(A0, NK_GC_NEW) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    ST64(S3, R0, AST_LEFT)
    MOVI(T0, TY_GC) ; ST64(T0, R0, AST_TYPE)
    SX_EPILOGUE

.L_pr_lambda:
    /* lambda (x: Int) => expr */
    CMPI(S1, TK_KW_LAMBDA) ; JNE(.L_pr_spawn)
    SX_CALL(sx_advance)
    MOVI(A0, NK_LAMBDA) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    MOVR(S3, R0)                /* S3 = lambda node */
    MOVI(A0, TK_LPAREN) ; SX_CALL(sx_match)
    SX_CALL(sx_peek_kind)
    CMPI(R0, TK_IDENT) ; JNE(.L_lam_after_p)
    SX_CALL(sx_advance)
    LD64(T0, R0, TOK_PTR) ; ST64(T0, S3, AST_NAME_PTR) /* param name */
    LD64(T0, R0, TOK_LEN) ; ST64(T0, S3, AST_NAME_LEN)
    MOVI(A0, TK_COLON) ; SX_CALL(sx_match)
    CMPI(R0, 0) ; JEQ(.L_lam_after_p)
    SX_CALL(sx_parse_type)
.L_lam_after_p:
    MOVI(A0, TK_RPAREN)   ; SX_CALL(sx_match)
    MOVI(A0, TK_FATARROW) ; SX_CALL(sx_match)
    CMPI(R0, 0) ; JNE(.L_lam_body)
    MOVI(A0, TK_ARROW)    ; SX_CALL(sx_match)
.L_lam_body:
    SX_CALL(sx_parse_expr)
    ST64(R0, S3, AST_RIGHT)     /* body expr */
    MOVI(T0, TY_CLOSURE) ; ST64(T0, S3, AST_TYPE)
    MOVR(R0, S3)
    SX_EPILOGUE

.L_pr_spawn:
    /* spawn func_name(arg) -> M:N Async Fiber launch */
    CMPI(S1, TK_KW_SPAWN) ; JNE(.L_pr_ident)
    SX_CALL(sx_advance)
    SX_CALL(sx_advance)         /* func ident */
    MOVR(S4, R0)
    MOVI(A0, NK_SPAWN) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    MOVR(S3, R0)
    LD64(T0, S4, TOK_PTR) ; ST64(T0, S3, AST_NAME_PTR)
    LD64(T0, S4, TOK_LEN) ; ST64(T0, S3, AST_NAME_LEN)
    MOVI(A0, TK_LPAREN) ; SX_CALL(sx_match)
    SX_CALL(sx_peek_kind)
    CMPI(R0, TK_RPAREN) ; JEQ(.L_sp_noarg)
    SX_CALL(sx_parse_expr)
    ST64(R0, S3, AST_LEFT)
.L_sp_noarg:
    MOVI(A0, TK_RPAREN) ; SX_CALL(sx_match)
    MOVI(T0, TY_TASK) ; ST64(T0, S3, AST_TYPE)
    MOVR(R0, S3)
    SX_EPILOGUE

.L_pr_ident:
    CMPI(S1, TK_IDENT) ; JNE(.L_pr_err)
    SX_CALL(sx_advance)
    /* Check optional generic call syntax: ident<Type>(args) */
    MOVI(T0, 0)
    ST_LOCAL(T0, 0)             /* local[0] = generic_type_arg */
    SX_CALL(sx_peek_kind)
    CMPI(R0, TK_LT)
    JNE(.L_id_chk_call)
    /* Peek ahead: if next is IDENT and then GT and then LPAREN, it's a generic call! */
    LEA_SYM(T0, g_tok_pos)
    LD64(S4, T0, 0)             /* save pos S4 */
    SX_CALL(sx_advance)         /* consume < */
    SX_CALL(sx_peek_kind)
    CMPI(R0, TK_IDENT) ; JNE(.L_gen_restore)
    SX_CALL(sx_parse_type)
    ST_LOCAL(R0, 0)
    SX_CALL(sx_peek_kind)
    CMPI(R0, TK_GT) ; JNE(.L_gen_restore)
    SX_CALL(sx_advance)         /* consume > */
    SX_CALL(sx_peek_kind)
    CMPI(R0, TK_LPAREN) ; JEQ(.L_id_chk_call)
.L_gen_restore:
    LEA_SYM(T0, g_tok_pos)
    ST64(S4, T0, 0)
    MOVI(T0, 0)
    ST_LOCAL(T0, 0)

.L_id_chk_call:
    SX_CALL(sx_peek_kind)
    CMPI(R0, TK_LPAREN)
    JEQ(.L_pr_call)

    /* Plain identifier */
    MOVI(A0, NK_IDENT) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    LD64(T0, S0, TOK_PTR) ; ST64(T0, R0, AST_NAME_PTR)
    LD64(T0, S0, TOK_LEN) ; ST64(T0, R0, AST_NAME_LEN)
    SX_EPILOGUE

.L_pr_call:
    SX_CALL(sx_advance)         /* consume '(' */
    MOVI(A0, NK_CALL) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    MOVR(S3, R0)                /* S3 = call node */
    LD64(T0, S0, TOK_PTR) ; ST64(T0, S3, AST_NAME_PTR)
    LD64(T0, S0, TOK_LEN) ; ST64(T0, S3, AST_NAME_LEN)
    LD_LOCAL(T0, 0)       ; ST64(T0, S3, AST_EXTRA2) /* generic type arg if any */

    MOVI(S4, 0)                 /* S4 = tail of arg list */
    MOVI(T0, 0) ; ST_LOCAL(T0, 1) /* argc */
    SX_CALL(sx_peek_kind)
    CMPI(R0, TK_RPAREN) ; JEQ(.L_call_end)
.L_call_arg_loop:
    SX_CALL(sx_parse_expr)
    CMPI(S4, 0) ; JNE(.L_call_append)
    ST64(R0, S3, AST_RIGHT)     /* head = arg */
    JMP(.L_call_tail)
.L_call_append:
    ST64(R0, S4, AST_NEXT)
.L_call_tail:
    MOVR(S4, R0)
    LD_LOCAL(T0, 1) ; ADDI(T0, 1) ; ST_LOCAL(T0, 1)
    MOVI(A0, TK_COMMA) ; SX_CALL(sx_match)
    CMPI(R0, 0) ; JNE(.L_call_arg_loop)
.L_call_end:
    MOVI(A0, TK_RPAREN) ; SX_CALL(sx_match)
    LD_LOCAL(T0, 1) ; ST64(T0, S3, AST_IVAL) /* store argc */
    MOVR(R0, S3)
    SX_EPILOGUE

.L_pr_err:
    MOVR(A0, S2)
    LEA_SYM(A1, err_exp_expr)
    SX_CALL(sx_error)
    SX_CALL(sx_advance)
    MOVI(A0, NK_INT) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    SX_EPILOGUE
SX_ENDFUNC(sx_parse_primary)

/* sx_parse_unary() -> R0 = ast_node */
SX_FUNC(sx_parse_unary)
    SX_PROLOGUE 16
    SX_CALL(sx_cur_tok)
    MOVR(S0, R0)
    LD64(S1, S0, TOK_KIND)
    LD64(S2, S0, TOK_LINE)

    CMPI(S1, TK_MINUS) ; JEQ(.L_un_op)
    CMPI(S1, TK_BANG)  ; JEQ(.L_un_op)
    CMPI(S1, TK_KW_BORROW) ; JEQ(.L_un_borrow)
    CMPI(S1, TK_AMP)       ; JEQ(.L_un_borrow)
    CMPI(S1, TK_KW_MOVE)   ; JEQ(.L_un_move)
    CMPI(S1, TK_KW_AWAIT)  ; JEQ(.L_un_await)
    SX_CALL(sx_parse_primary)
    SX_EPILOGUE

.L_un_op:
    SX_CALL(sx_advance)
    SX_CALL(sx_parse_unary)
    MOVR(S3, R0)
    MOVI(A0, NK_UNOP) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    ST64(S1, R0, AST_IVAL)
    ST64(S3, R0, AST_LEFT)
    SX_EPILOGUE

.L_un_borrow:
    SX_CALL(sx_advance)
    SX_CALL(sx_parse_unary)
    MOVR(S3, R0)
    MOVI(A0, NK_BORROW) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    ST64(S3, R0, AST_LEFT)
    SX_EPILOGUE

.L_un_move:
    SX_CALL(sx_advance)
    SX_CALL(sx_parse_unary)
    MOVR(S3, R0)
    MOVI(A0, NK_MOVE) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    ST64(S3, R0, AST_LEFT)
    SX_EPILOGUE

.L_un_await:
    SX_CALL(sx_advance)
    SX_CALL(sx_parse_unary)
    MOVR(S3, R0)
    MOVI(A0, NK_AWAIT) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    ST64(S3, R0, AST_LEFT)
    SX_EPILOGUE
SX_ENDFUNC(sx_parse_unary)

/* Precedence helper macro for left-associative binary layers */
SX_FUNC(sx_parse_mul)
    SX_PROLOGUE 16
    SX_CALL(sx_parse_unary)
    MOVR(S0, R0)
.L_mul_loop:
    SX_CALL(sx_cur_tok)
    LD64(S1, R0, TOK_KIND)
    LD64(S2, R0, TOK_LINE)
    CMPI(S1, TK_STAR)    ; JEQ(.L_mul_take)
    CMPI(S1, TK_SLASH)   ; JEQ(.L_mul_take)
    CMPI(S1, TK_PERCENT) ; JEQ(.L_mul_take)
    MOVR(R0, S0) ; SX_EPILOGUE
.L_mul_take:
    SX_CALL(sx_advance)
    SX_CALL(sx_parse_unary)
    MOVR(S3, R0)
    MOVI(A0, NK_BINOP) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    ST64(S1, R0, AST_IVAL)
    ST64(S0, R0, AST_LEFT)
    ST64(S3, R0, AST_RIGHT)
    MOVR(S0, R0)
    JMP(.L_mul_loop)
SX_ENDFUNC(sx_parse_mul)

SX_FUNC(sx_parse_add)
    SX_PROLOGUE 16
    SX_CALL(sx_parse_mul)
    MOVR(S0, R0)
.L_add_loop:
    SX_CALL(sx_cur_tok)
    LD64(S1, R0, TOK_KIND)
    LD64(S2, R0, TOK_LINE)
    CMPI(S1, TK_PLUS)  ; JEQ(.L_add_take)
    CMPI(S1, TK_MINUS) ; JEQ(.L_add_take)
    MOVR(R0, S0) ; SX_EPILOGUE
.L_add_take:
    SX_CALL(sx_advance)
    SX_CALL(sx_parse_mul)
    MOVR(S3, R0)
    MOVI(A0, NK_BINOP) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    ST64(S1, R0, AST_IVAL)
    ST64(S0, R0, AST_LEFT)
    ST64(S3, R0, AST_RIGHT)
    MOVR(S0, R0)
    JMP(.L_add_loop)
SX_ENDFUNC(sx_parse_add)

SX_FUNC(sx_parse_cmp)
    SX_PROLOGUE 16
    SX_CALL(sx_parse_add)
    MOVR(S0, R0)
.L_cmp_loop:
    SX_CALL(sx_cur_tok)
    LD64(S1, R0, TOK_KIND)
    LD64(S2, R0, TOK_LINE)
    CMPI(S1, TK_LT) ; JEQ(.L_cmp_take)
    CMPI(S1, TK_LE) ; JEQ(.L_cmp_take)
    CMPI(S1, TK_GT) ; JEQ(.L_cmp_take)
    CMPI(S1, TK_GE) ; JEQ(.L_cmp_take)
    CMPI(S1, TK_EQ) ; JEQ(.L_cmp_take)
    CMPI(S1, TK_NE) ; JEQ(.L_cmp_take)
    MOVR(R0, S0) ; SX_EPILOGUE
.L_cmp_take:
    SX_CALL(sx_advance)
    SX_CALL(sx_parse_add)
    MOVR(S3, R0)
    MOVI(A0, NK_BINOP) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    ST64(S1, R0, AST_IVAL)
    ST64(S0, R0, AST_LEFT)
    ST64(S3, R0, AST_RIGHT)
    MOVR(S0, R0)
    JMP(.L_cmp_loop)
SX_ENDFUNC(sx_parse_cmp)

SX_FUNC(sx_parse_logic)
    SX_PROLOGUE 16
    SX_CALL(sx_parse_cmp)
    MOVR(S0, R0)
.L_log_loop:
    SX_CALL(sx_cur_tok)
    LD64(S1, R0, TOK_KIND)
    LD64(S2, R0, TOK_LINE)
    CMPI(S1, TK_AND) ; JEQ(.L_log_take)
    CMPI(S1, TK_OR)  ; JEQ(.L_log_take)
    MOVR(R0, S0) ; SX_EPILOGUE
.L_log_take:
    SX_CALL(sx_advance)
    SX_CALL(sx_parse_cmp)
    MOVR(S3, R0)
    MOVI(A0, NK_BINOP) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    ST64(S1, R0, AST_IVAL)
    ST64(S0, R0, AST_LEFT)
    ST64(S3, R0, AST_RIGHT)
    MOVR(S0, R0)
    JMP(.L_log_loop)
SX_ENDFUNC(sx_parse_logic)

/* sx_parse_expr() — handles Lambda pipe operator: lhs |> fn  ==>  fn(lhs) */
SX_FUNC(sx_parse_expr)
    SX_PROLOGUE 16
    SX_CALL(sx_parse_logic)
    MOVR(S0, R0)
.L_pipe_loop:
    SX_CALL(sx_cur_tok)
    LD64(S1, R0, TOK_KIND)
    LD64(S2, R0, TOK_LINE)
    CMPI(S1, TK_PIPE)
    JNE(.L_pipe_done)
    SX_CALL(sx_advance)
    /* RHS is function/closure identifier */
    SX_CALL(sx_advance)
    MOVR(S3, R0)
    MOVI(A0, NK_CALL) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    LD64(T0, S3, TOK_PTR) ; ST64(T0, R0, AST_NAME_PTR)
    LD64(T0, S3, TOK_LEN) ; ST64(T0, R0, AST_NAME_LEN)
    ST64(S0, R0, AST_RIGHT)     /* single arg = lhs */
    MOVI(T0, 1) ; ST64(T0, R0, AST_IVAL)
    MOVR(S0, R0)
    JMP(.L_pipe_loop)
.L_pipe_done:
    MOVR(R0, S0)
    SX_EPILOGUE
SX_ENDFUNC(sx_parse_expr)

/* ============================================================================
 * Statement & Block Parser
 * ============================================================================
 */
SX_FUNC(sx_parse_block)
    SX_PROLOGUE 16
    SX_CALL(sx_cur_tok)
    LD64(S2, R0, TOK_LINE)
    MOVI(A0, TK_LBRACE) ; SX_CALL(sx_match)
    MOVI(A0, NK_BLOCK) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    MOVR(S0, R0)                /* S0 = block node */
    MOVI(S1, 0)                 /* S1 = tail stmt */

.L_blk_loop:
    SX_CALL(sx_peek_kind)
    CMPI(R0, TK_RBRACE) ; JEQ(.L_blk_end)
    CMPI(R0, TK_EOF)    ; JEQ(.L_blk_end)
    SX_CALL(sx_parse_stmt)
    CMPI(R0, 0) ; JEQ(.L_blk_loop)
    CMPI(S1, 0) ; JNE(.L_blk_app)
    ST64(R0, S0, AST_LEFT)
    JMP(.L_blk_tail)
.L_blk_app:
    ST64(R0, S1, AST_NEXT)
.L_blk_tail:
    MOVR(S1, R0)
    JMP(.L_blk_loop)
.L_blk_end:
    MOVI(A0, TK_RBRACE) ; SX_CALL(sx_match)
    MOVR(R0, S0)
    SX_EPILOGUE
SX_ENDFUNC(sx_parse_block)

SX_FUNC(sx_parse_stmt)
    SX_PROLOGUE 32
    SX_CALL(sx_cur_tok)
    MOVR(S0, R0)
    LD64(S1, S0, TOK_KIND)
    LD64(S2, S0, TOK_LINE)

    /* let / val / var */
    CMPI(S1, TK_KW_LET) ; JEQ(.L_st_let)
    CMPI(S1, TK_KW_VAR) ; JEQ(.L_st_var)
    CMPI(S1, TK_KW_RETURN) ; JEQ(.L_st_ret)
    CMPI(S1, TK_KW_IF)     ; JEQ(.L_st_if)
    CMPI(S1, TK_KW_WHILE)  ; JEQ(.L_st_while)
    CMPI(S1, TK_KW_PROVE)  ; JEQ(.L_st_prove)
    CMPI(S1, TK_KW_INVARIANT) ; JEQ(.L_st_prove)

    /* Check assignment: ident = expr */
    CMPI(S1, TK_IDENT) ; JNE(.L_st_expr)
    SX_CALL(sx_peek_next_kind)
    CMPI(R0, TK_ASSIGN) ; JEQ(.L_st_assign)
    JMP(.L_st_expr)

.L_st_let:
    MOVI(S4, 0)
    JMP(.L_st_let_common)
.L_st_var:
    MOVI(S4, FL_MUT)
.L_st_let_common:
    SX_CALL(sx_advance)         /* consume let/val/var */
    SX_CALL(sx_advance)         /* name ident */
    MOVR(S3, R0)
    MOVI(A0, NK_LET) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    ST_LOCAL(R0, 0)             /* local[0] = let node */
    LD64(T0, S3, TOK_PTR) ; ST64(T0, R0, AST_NAME_PTR)
    LD64(T0, S3, TOK_LEN) ; ST64(T0, R0, AST_NAME_LEN)
    ST64(S4, R0, AST_IVAL)      /* mutability flag */
    /* Optional : Type */
    MOVI(A0, TK_COLON) ; SX_CALL(sx_match)
    CMPI(R0, 0) ; JEQ(.L_let_eq)
    SX_CALL(sx_parse_type)
    LD_LOCAL(T0, 0)
    ST64(R0, T0, AST_TYPE)
.L_let_eq:
    MOVI(A0, TK_ASSIGN) ; SX_CALL(sx_match)
    SX_CALL(sx_parse_expr)
    LD_LOCAL(T0, 0)
    ST64(R0, T0, AST_LEFT)
    MOVI(A0, TK_SEMI) ; SX_CALL(sx_match)
    LD_LOCAL(R0, 0)
    SX_EPILOGUE

.L_st_assign:
    SX_CALL(sx_advance)         /* ident */
    MOVR(S3, R0)
    SX_CALL(sx_advance)         /* '=' */
    SX_CALL(sx_parse_expr)
    MOVR(S4, R0)
    MOVI(A0, NK_ASSIGN) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    LD64(T0, S3, TOK_PTR) ; ST64(T0, R0, AST_NAME_PTR)
    LD64(T0, S3, TOK_LEN) ; ST64(T0, R0, AST_NAME_LEN)
    ST64(S4, R0, AST_LEFT)
    MOVR(S3, R0)
    MOVI(A0, TK_SEMI) ; SX_CALL(sx_match)
    MOVR(R0, S3)
    SX_EPILOGUE

.L_st_ret:
    SX_CALL(sx_advance)
    MOVI(A0, NK_RETURN) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    MOVR(S3, R0)
    SX_CALL(sx_peek_kind)
    CMPI(R0, TK_RBRACE) ; JEQ(.L_ret_done)
    CMPI(R0, TK_SEMI)   ; JEQ(.L_ret_semi)
    SX_CALL(sx_parse_expr)
    ST64(R0, S3, AST_LEFT)
.L_ret_semi:
    MOVI(A0, TK_SEMI) ; SX_CALL(sx_match)
.L_ret_done:
    MOVR(R0, S3)
    SX_EPILOGUE

.L_st_if:
    SX_CALL(sx_advance)
    MOVI(A0, NK_IF) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    MOVR(S3, R0)
    SX_CALL(sx_parse_expr)
    ST64(R0, S3, AST_LEFT)      /* cond */
    SX_CALL(sx_parse_block)
    ST64(R0, S3, AST_RIGHT)     /* then block */
    MOVI(A0, TK_KW_ELSE) ; SX_CALL(sx_match)
    CMPI(R0, 0) ; JEQ(.L_if_done)
    SX_CALL(sx_parse_block)
    ST64(R0, S3, AST_EXTRA)     /* else block */
.L_if_done:
    MOVR(R0, S3)
    SX_EPILOGUE

.L_st_while:
    SX_CALL(sx_advance)
    MOVI(A0, NK_WHILE) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    MOVR(S3, R0)
    SX_CALL(sx_parse_expr)
    ST64(R0, S3, AST_LEFT)      /* cond */
    SX_CALL(sx_parse_block)
    ST64(R0, S3, AST_RIGHT)     /* body */
    MOVR(R0, S3)
    SX_EPILOGUE

.L_st_prove:
    SX_CALL(sx_advance)
    MOVI(A0, NK_PROVE) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    MOVR(S3, R0)
    SX_CALL(sx_parse_expr)
    ST64(R0, S3, AST_LEFT)
    MOVI(A0, TK_SEMI) ; SX_CALL(sx_match)
    MOVR(R0, S3)
    SX_EPILOGUE

.L_st_expr:
    SX_CALL(sx_parse_expr)
    MOVR(S3, R0)
    MOVI(A0, NK_EXPR_STMT) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    ST64(S3, R0, AST_LEFT)
    MOVR(S3, R0)
    MOVI(A0, TK_SEMI) ; SX_CALL(sx_match)
    MOVR(R0, S3)
    SX_EPILOGUE
SX_ENDFUNC(sx_parse_stmt)

/* ============================================================================
 * Top-Level Declarations & Program Parser
 * ============================================================================
 */
SX_FUNC(sx_parse_func)
    SX_PROLOGUE 48
    MOVR(S4, A0)                /* S4 = flags (FL_ASYNC, FL_EXTERN) */
    SX_CALL(sx_cur_tok)
    LD64(S2, R0, TOK_LINE)
    SX_CALL(sx_advance)         /* consume func/fun */

    /* Function name */
    SX_CALL(sx_advance)
    MOVR(S1, R0)
    MOVI(A0, NK_FUNC) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    MOVR(S0, R0)                /* S0 = func node */
    LD64(T0, S1, TOK_PTR) ; ST64(T0, S0, AST_NAME_PTR)
    LD64(T0, S1, TOK_LEN) ; ST64(T0, S0, AST_NAME_LEN)
    ST64(S4, S0, AST_IVAL)

    /* Optional Generic Parameter <T> */
    MOVI(A0, TK_LT) ; SX_CALL(sx_match)
    CMPI(R0, 0) ; JEQ(.L_fn_params)
    ORI(S4, FL_GENERIC)
    ST64(S4, S0, AST_IVAL)
    SX_CALL(sx_advance)         /* generic param T */
    MOVI(A0, TK_GT) ; SX_CALL(sx_match)

.L_fn_params:
    MOVI(A0, TK_LPAREN) ; SX_CALL(sx_match)
    MOVI(S3, 0)                 /* S3 = tail of param list */
    SX_CALL(sx_peek_kind)
    CMPI(R0, TK_RPAREN) ; JEQ(.L_fn_rparen)
.L_fn_ploop:
    SX_CALL(sx_advance)         /* param ident */
    MOVR(S1, R0)
    MOVI(A0, NK_PARAM) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    ST_LOCAL(R0, 0)
    LD64(T0, S1, TOK_PTR) ; ST64(T0, R0, AST_NAME_PTR)
    LD64(T0, S1, TOK_LEN) ; ST64(T0, R0, AST_NAME_LEN)
    MOVI(T0, TY_INT)      ; ST64(T0, R0, AST_TYPE)
    MOVI(A0, TK_COLON) ; SX_CALL(sx_match)
    CMPI(R0, 0) ; JEQ(.L_fn_padd)
    SX_CALL(sx_parse_type)
    LD_LOCAL(T0, 0)
    ST64(R0, T0, AST_TYPE)
.L_fn_padd:
    LD_LOCAL(R0, 0)
    CMPI(S3, 0) ; JNE(.L_fn_papp)
    ST64(R0, S0, AST_LEFT)      /* params head */
    JMP(.L_fn_ptail)
.L_fn_papp:
    ST64(R0, S3, AST_NEXT)
.L_fn_ptail:
    MOVR(S3, R0)
    MOVI(A0, TK_COMMA) ; SX_CALL(sx_match)
    CMPI(R0, 0) ; JNE(.L_fn_ploop)
.L_fn_rparen:
    MOVI(A0, TK_RPAREN) ; SX_CALL(sx_match)

    /* Optional -> ReturnType */
    MOVI(T0, TY_INT) ; ST64(T0, S0, AST_TYPE)
    MOVI(A0, TK_ARROW) ; SX_CALL(sx_match)
    CMPI(R0, 0) ; JEQ(.L_fn_contracts)
    SX_CALL(sx_parse_type)
    ST64(R0, S0, AST_TYPE)

    /* Optional Phi contracts: requires <expr> / ensures <expr> */
.L_fn_contracts:
    MOVI(A0, TK_KW_REQUIRES) ; SX_CALL(sx_match)
    CMPI(R0, 0) ; JEQ(.L_fn_chk_ens)
    SX_CALL(sx_parse_expr)
    ST64(R0, S0, AST_EXTRA)     /* requires expr */
    JMP(.L_fn_contracts)
.L_fn_chk_ens:
    MOVI(A0, TK_KW_ENSURES) ; SX_CALL(sx_match)
    CMPI(R0, 0) ; JEQ(.L_fn_body)
    SX_CALL(sx_parse_expr)
    ST64(R0, S0, AST_EXTRA2)    /* ensures expr */
    JMP(.L_fn_contracts)

.L_fn_body:
    SX_CALL(sx_peek_kind)
    CMPI(R0, TK_LBRACE) ; JNE(.L_fn_extern_end)
    SX_CALL(sx_parse_block)
    ST64(R0, S0, AST_RIGHT)
    MOVR(R0, S0)
    SX_EPILOGUE
.L_fn_extern_end:
    MOVI(A0, TK_SEMI) ; SX_CALL(sx_match)
    MOVR(R0, S0)
    SX_EPILOGUE
SX_ENDFUNC(sx_parse_func)

/* sx_parse_program() -> R0 = NK_PROGRAM root AST node */
SX_FUNC(sx_parse_program)
    SX_PROLOGUE 32
    LEA_SYM(T0, g_tok_pos) ; MOVI(T1, 0) ; ST64(T1, T0, 0)
    MOVI(A0, NK_PROGRAM) ; MOVI(A1, 1) ; SX_CALL(sx_ast_new)
    MOVR(S0, R0)                /* S0 = program root */
    MOVI(S1, 0)                 /* S1 = tail decl */

.L_prog_loop:
    SX_CALL(sx_peek_kind)
    CMPI(R0, TK_EOF) ; JEQ(.L_prog_done)

    MOVI(S4, 0)                 /* flags */
    CMPI(R0, TK_KW_ASYNC) ; JNE(.L_prog_chk_ext)
    SX_CALL(sx_advance)
    ORI(S4, FL_ASYNC)
    SX_CALL(sx_peek_kind)

.L_prog_chk_ext:
    CMPI(R0, TK_KW_EXTERN) ; JNE(.L_prog_chk_fn)
    SX_CALL(sx_advance)
    ORI(S4, FL_EXTERN)
    SX_CALL(sx_peek_kind)

.L_prog_chk_fn:
    CMPI(R0, TK_KW_FUNC) ; JNE(.L_prog_chk_phi)
    MOVR(A0, S4)
    SX_CALL(sx_parse_func)
    JMP(.L_prog_append)

.L_prog_chk_phi:
    CMPI(R0, TK_KW_PHI) ; JNE(.L_prog_chk_imp)
    SX_CALL(sx_cur_tok) ; LD64(S2, R0, TOK_LINE)
    SX_CALL(sx_advance)         /* phi */
    SX_CALL(sx_advance)         /* axiom name */
    MOVR(S3, R0)
    MOVI(A0, TK_ASSIGN) ; SX_CALL(sx_match)
    SX_CALL(sx_parse_expr)
    ST_LOCAL(R0, 0)
    MOVI(A0, NK_PHI_DECL) ; MOVR(A1, S2) ; SX_CALL(sx_ast_new)
    LD64(T0, S3, TOK_PTR) ; ST64(T0, R0, AST_NAME_PTR)
    LD64(T0, S3, TOK_LEN) ; ST64(T0, R0, AST_NAME_LEN)
    LD_LOCAL(T0, 0) ; ST64(T0, R0, AST_LEFT)
    MOVR(S3, R0)
    MOVI(A0, TK_SEMI) ; SX_CALL(sx_match)
    MOVR(R0, S3)
    JMP(.L_prog_append)

.L_prog_chk_imp:
    CMPI(R0, TK_KW_IMPORT) ; JNE(.L_prog_skip)
    SX_CALL(sx_advance)
    SX_CALL(sx_advance)
    MOVI(A0, TK_SEMI) ; SX_CALL(sx_match)
    JMP(.L_prog_loop)

.L_prog_skip:
    SX_CALL(sx_advance)
    JMP(.L_prog_loop)

.L_prog_append:
    CMPI(S1, 0) ; JNE(.L_prog_link)
    ST64(R0, S0, AST_LEFT)
    JMP(.L_prog_tail)
.L_prog_link:
    ST64(R0, S1, AST_NEXT)
.L_prog_tail:
    MOVR(S1, R0)
    JMP(.L_prog_loop)

.L_prog_done:
    LEA_SYM(T0, g_ast_root)
    ST64(S0, T0, 0)
    MOVR(R0, S0)
    SX_EPILOGUE
SX_ENDFUNC(sx_parse_program)
