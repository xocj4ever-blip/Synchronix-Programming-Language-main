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
 * SYNCHRONIX — Shared Compiler, IR & Runtime Definitions (include/sx_defs.S)
 * ============================================================================
 * Strict 1-to-1 structural definitions for all 5 architectural domains:
 *   Phase 1: Frontend (Lexer, Parser, Semantic Analyzer, Phi & Lambda)
 *   Phase 2: Middle-End (SUMIR, Ownership/Borrow, ARC, GC, Lifetime, Lowering)
 *   Phase 3: Backend (x86_64 & ARM64 Codegen, RegAlloc, Scheduling, LLVM IR)
 *   Foundation: Runtime & Stdlib (Unified ARC+GC, Arena, M:N Fibers, Phi/Lambda)
 *   Ecosystem: Cargo Build/Pkg, LSP, Formatter/Linter, Debugger/Profiler
 * ============================================================================
 */

#ifndef SYNCHRONIX_DEFS_S
#define SYNCHRONIX_DEFS_S

/* ----------------------------------------------------------------------------
 * Token Kinds (Phase 1: Lexer / Tokenizer)
 * ----------------------------------------------------------------------------
 */
#define TK_EOF          0
#define TK_IDENT        1
#define TK_INT          2
#define TK_STR          3

/* Keywords (Swift + Kotlin + Phi + Lambda) */
#define TK_KW_FUNC      10   /* func / fun */
#define TK_KW_LET       11   /* let / val */
#define TK_KW_VAR       12   /* var */
#define TK_KW_RETURN    13   /* return */
#define TK_KW_IF        14   /* if */
#define TK_KW_ELSE      15   /* else */
#define TK_KW_WHILE     16   /* while */
#define TK_KW_TRUE      17   /* true */
#define TK_KW_FALSE     18   /* false */
#define TK_KW_ARC       19   /* arc (Swift ARC allocation) */
#define TK_KW_GC        20   /* gc (Kotlin tracing GC allocation) */
#define TK_KW_BORROW    21   /* borrow (immutable/mutable borrow) */
#define TK_KW_MOVE      22   /* move (ownership transfer) */
#define TK_KW_PHI       23   /* phi (Formal Logic axiom/predicate) */
#define TK_KW_REQUIRES  24   /* requires (Phi precondition) */
#define TK_KW_ENSURES   25   /* ensures (Phi postcondition) */
#define TK_KW_INVARIANT 26   /* invariant (Phi loop/type invariant) */
#define TK_KW_PROVE     27   /* prove (Phi formal proof obligation) */
#define TK_KW_LAMBDA    28   /* lambda (Lambda functional closure) */
#define TK_KW_ASYNC     29   /* async (M:N coroutine/fiber func) */
#define TK_KW_SPAWN     30   /* spawn (M:N task launch) */
#define TK_KW_AWAIT     31   /* await (M:N task join) */
#define TK_KW_STRUCT    32   /* struct */
#define TK_KW_EXTERN    33   /* extern */
#define TK_KW_IMPORT    34   /* import */

/* Delimiters & Punctuation */
#define TK_LPAREN       40   /* ( */
#define TK_RPAREN       41   /* ) */
#define TK_LBRACE       42   /* { */
#define TK_RBRACE       43   /* } */
#define TK_LBRACKET     44   /* [ */
#define TK_RBRACKET     45   /* ] */
#define TK_COMMA        46   /* , */
#define TK_COLON        47   /* : */
#define TK_SEMI         48   /* ; */
#define TK_DOT          49   /* . */

/* Operators */
#define TK_PLUS         50   /* + */
#define TK_MINUS        51   /* - */
#define TK_STAR         52   /* * */
#define TK_SLASH        53   /* / */
#define TK_PERCENT      54   /* % */
#define TK_ASSIGN       55   /* = */
#define TK_EQ           56   /* == */
#define TK_NE           57   /* != */
#define TK_LT           58   /* < */
#define TK_LE           59   /* <= */
#define TK_GT           60   /* > */
#define TK_GE           61   /* >= */
#define TK_AND          62   /* && */
#define TK_OR           63   /* || */
#define TK_BANG         64   /* ! */
#define TK_ARROW        65   /* -> */
#define TK_FATARROW     66   /* => */
#define TK_PIPE         67   /* |> */
#define TK_AMP          68   /* & */

/* Token Struct Layout (48 bytes) */
#define TOK_KIND        0
#define TOK_PTR         8
#define TOK_LEN         16
#define TOK_IVAL        24
#define TOK_LINE        32
#define TOK_COL         40
#define TOK_SIZE        48

/* ----------------------------------------------------------------------------
 * AST Node Kinds & Layout (Phase 1: Parser & Semantic Analyzer)
 * ----------------------------------------------------------------------------
 */
#define NK_PROGRAM      1
#define NK_FUNC         2
#define NK_PARAM        3
#define NK_BLOCK        4
#define NK_LET          5
#define NK_ASSIGN       6
#define NK_RETURN       7
#define NK_IF           8
#define NK_WHILE        9
#define NK_PROVE        10
#define NK_EXPR_STMT    11
#define NK_INT          12
#define NK_STR          13
#define NK_IDENT        14
#define NK_BINOP        15
#define NK_UNOP         16
#define NK_CALL         17
#define NK_ARC_NEW      18
#define NK_GC_NEW       19
#define NK_BORROW       20
#define NK_MOVE         21
#define NK_LAMBDA       22
#define NK_SPAWN        23
#define NK_AWAIT        24
#define NK_PHI_DECL     25
#define NK_STRUCT       26

/* AST Node Struct Layout (96 bytes) */
#define AST_KIND        0
#define AST_NAME_PTR    8
#define AST_NAME_LEN    16
#define AST_IVAL        24
#define AST_LEFT        32
#define AST_RIGHT       40
#define AST_EXTRA       48
#define AST_EXTRA2      56
#define AST_NEXT        64
#define AST_TYPE        72
#define AST_LINE        80
#define AST_META        88
#define AST_SIZE        96

/* AST Node Flags (stored in AST_IVAL for funcs/vars) */
#define FL_ASYNC        1
#define FL_MUT          2
#define FL_GENERIC      4
#define FL_ARC          8
#define FL_GC           16
#define FL_EXTERN       32

/* Type IDs (Phase 1: Type Inference & Generics Resolution) */
#define TY_UNKNOWN      0
#define TY_INT          1
#define TY_BOOL         2
#define TY_STR          3
#define TY_VOID         4
#define TY_ARC          5
#define TY_GC           6
#define TY_CLOSURE      7
#define TY_TASK         8
#define TY_GENERIC      9
#define TY_BORROW       10

/* Phi Proof Verification Status (stored in AST_META) */
#define PHI_UNVERIFIED      0
#define PHI_PROVEN_STATIC   1
#define PHI_RUNTIME_CHECK   2
#define PHI_REFUTED         3

/* ----------------------------------------------------------------------------
 * Symbol Table Entry Layout (64 bytes)
 * ----------------------------------------------------------------------------
 */
#define SYME_NAME_PTR   0
#define SYME_NAME_LEN   8
#define SYME_TYPE       16
#define SYME_SCOPE      24
#define SYME_OWN_STATE  32
#define SYME_MEM_KIND   40
#define SYME_SLOT       48
#define SYME_CONST_VAL  56
#define SYME_SIZE       64

#define OWN_OWNED       0
#define OWN_MOVED       1
#define OWN_BORROWED    2
#define OWN_DROPPED     3

#define MEM_STACK       0
#define MEM_ARC         1
#define MEM_GC          2
#define MEM_CLOSURE     3

/* ----------------------------------------------------------------------------
 * SUMIR Opcodes & Instruction Layout (Phase 2: Middle-End)
 * ----------------------------------------------------------------------------
 */
#define IR_NOP          0
#define IR_FUNC_BEGIN   1   /* dst=func_idx, src1=name_ptr, src2=name_len, imm=param_cnt */
#define IR_FUNC_END     2   /* dst=func_idx */
#define IR_PARAM        3   /* dst=vreg, imm=param_index */
#define IR_CONST        4   /* dst=vreg, imm=int64_val */
#define IR_STR_CONST    5   /* dst=vreg, src1=str_ptr, src2=str_len, imm=str_id */
#define IR_MOV          6   /* dst=vreg, src1=vreg */
#define IR_ADD          7   /* dst=vreg, src1=vreg, src2=vreg */
#define IR_SUB          8
#define IR_MUL          9
#define IR_DIV          10
#define IR_MOD          11
#define IR_NEG          12  /* dst=vreg, src1=vreg */
#define IR_CMP_EQ       13  /* dst=vreg, src1=vreg, src2=vreg */
#define IR_CMP_NE       14
#define IR_CMP_LT       15
#define IR_CMP_LE       16
#define IR_CMP_GT       17
#define IR_CMP_GE       18
#define IR_AND          19
#define IR_OR           20
#define IR_NOT          21
#define IR_LABEL        22  /* dst=label_id */
#define IR_JMP          23  /* dst=label_id */
#define IR_BRZ          24  /* dst=label_id, src1=cond_vreg (branch if 0) */
#define IR_ARG          25  /* src1=vreg, imm=arg_idx */
#define IR_CALL         26  /* dst=vreg, src1=name_ptr, src2=name_len, imm=argc */
#define IR_RET          27  /* src1=vreg */

/* Unified Memory (ARC + GC + Borrow) SUMIR Opcodes */
#define IR_ARC_NEW      30  /* dst=vreg, src1=init_vreg */
#define IR_ARC_RETAIN   31  /* src1=vreg */
#define IR_ARC_RELEASE  32  /* src1=vreg */
#define IR_ARC_LOAD     33  /* dst=vreg, src1=arc_vreg */
#define IR_GC_NEW       34  /* dst=vreg, src1=init_vreg */
#define IR_GC_ROOT      35  /* src1=vreg */
#define IR_GC_UNROOT    36  /* src1=vreg */
#define IR_GC_LOAD      37  /* dst=vreg, src1=gc_vreg */
#define IR_BORROW       38  /* dst=vreg, src1=vreg */
#define IR_MOVE         39  /* dst=vreg, src1=vreg */

/* Phi (Formal Logic) & Lambda (Functional Logic) & Async SUMIR Opcodes */
#define IR_PHI_ASSERT   40  /* src1=cond_vreg, imm=line */
#define IR_CLOSURE_NEW  41  /* dst=vreg, src1=fn_name_ptr, src2=fn_name_len, imm=cap_cnt */
#define IR_CLOSURE_SET  42  /* dst=closure_vreg, src1=val_vreg, imm=cap_idx */
#define IR_CLOSURE_GET  43  /* dst=vreg, src1=closure_vreg, imm=cap_idx */
#define IR_CLOSURE_CALL 44  /* dst=vreg, src1=closure_vreg, src2=arg_vreg */
#define IR_SPAWN        45  /* dst=task_vreg, src1=fn_name_ptr, src2=fn_name_len, imm=arg_vreg */
#define IR_AWAIT        46  /* dst=vreg, src1=task_vreg */

/* SUMIR Instruction Layout (64 bytes) */
#define IR_OP           0
#define IR_DST          8
#define IR_SRC1         16
#define IR_SRC2         24
#define IR_IMM          32
#define IR_TYPE         40
#define IR_FLAGS        48
#define IR_PHYS         56
#define IR_SIZE         64

/* SUMIR Flags */
#define IRF_DEAD        1
#define IRF_PROVEN      2
#define IRF_CONST       4
#define IRF_ARC         8
#define IRF_GC          16
#define IRF_INLINED     32

/* ----------------------------------------------------------------------------
 * Runtime Object Header & Async Task Constants (Foundation: Runtime)
 * ----------------------------------------------------------------------------
 */
#define SX_MAGIC_ARC    0x53584152  /* "SXAR" */
#define SX_MAGIC_GC     0x53584743  /* "SXGC" */

#define OBJ_MAGIC       0
#define OBJ_FLAGS       8
#define OBJ_RC          16
#define OBJ_SIZE        24
#define OBJ_NEXT        32
#define OBJ_DTOR        40
#define OBJ_HDR_SIZE    48

#define OBJF_GC_MARKED  1
#define OBJF_ARC        2
#define OBJF_GC         4
#define OBJF_CLOSURE    8

/* Async Fiber/Task Struct (64 bytes) */
#define TASK_ID         0
#define TASK_STATE      8   /* 0=READY, 1=RUNNING, 2=DONE */
#define TASK_FN         16
#define TASK_ARG        24
#define TASK_RESULT     32
#define TASK_RESERVED   40
#define TASK_SIZE       64

#define TASK_READY      0
#define TASK_RUNNING    1
#define TASK_DONE       2

/* Target Architecture IDs (Phase 3: Backend) */
#define TARGET_X86_64   0
#define TARGET_ARM64    1
#define TARGET_LLVM_IR  2

/* Limits */
#define MAX_TOKENS      8192
#define MAX_AST_NODES   8192
#define MAX_SYMBOLS     1024
#define MAX_IR_INSTS    16384
#define MAX_VREGS       2048
#define MAX_STRINGS     512
#define MAX_FUNCS       256
#define MAX_LAMBDAS     256
#define MAX_GC_ROOTS    1024
#define MAX_TASKS       256

#endif /* SYNCHRONIX_DEFS_S */
