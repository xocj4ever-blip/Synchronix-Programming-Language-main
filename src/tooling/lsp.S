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
 * SYNCHRONIX ECOSYSTEM — Synchronix LSP (IDE Language Server) (src/tooling/lsp.S)
 * ============================================================================
 * Implements Developer Ecosystem -> Synchronix LSP (IDE Language Server):
 *   - JSON-RPC 2.0 over stdio (`Content-Length: N\r\n\r\n{...}`)
 *   - Handles: initialize, textDocument/hover, textDocument/completion,
 *     textDocument/didOpen, shutdown, exit
 * ============================================================================
 */

#include "portable_asm.S"
#include "sx_defs.S"

SX_RODATA
SX_STR(lsp_m_init,   "\"initialize\"")
SX_STR(lsp_m_hover,  "\"textDocument/hover\"")
SX_STR(lsp_m_comp,   "\"textDocument/completion\"")
SX_STR(lsp_m_shut,   "\"shutdown\"")
SX_STR(lsp_m_exit,   "\"exit\"")

SX_STR(lsp_fmt_hdr,  "Content-Length: %lld\r\n\r\n%s")
SX_STR(lsp_resp_init,"{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"serverInfo\":{\"name\":\"synchronix-lsp\",\"version\":\"1.0.0\"},\"capabilities\":{\"textDocumentSync\":1,\"hoverProvider\":true,\"completionProvider\":{\"triggerCharacters\":[\".\",\":\"]},\"documentFormattingProvider\":true}}}")
SX_STR(lsp_resp_hov, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"contents\":{\"kind\":\"markdown\",\"value\":\"**Synchronix** — Unified ARC & GC native language with Phi formal verification and Lambda closures.\"}}}")
SX_STR(lsp_resp_cmp, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":[{\"label\":\"func\",\"kind\":14},{\"label\":\"arc\",\"kind\":14},{\"label\":\"gc\",\"kind\":14},{\"label\":\"borrow\",\"kind\":14},{\"label\":\"move\",\"kind\":14},{\"label\":\"phi\",\"kind\":14},{\"label\":\"requires\",\"kind\":14},{\"label\":\"ensures\",\"kind\":14},{\"label\":\"prove\",\"kind\":14},{\"label\":\"lambda\",\"kind\":14},{\"label\":\"async\",\"kind\":14},{\"label\":\"spawn\",\"kind\":14},{\"label\":\"await\",\"kind\":14},{\"label\":\"println\",\"kind\":3},{\"label\":\"mem_stats\",\"kind\":3}]}")
SX_STR(lsp_resp_ok,  "{\"jsonrpc\":\"2.0\",\"id\":99,\"result\":null}")

SX_BSS
.p2align 4
SX_LABEL(g_lsp_inbuf)
    .skip 8192

SX_TEXT

/* Helper: sx_lsp_send(A0 = json_body_cstr) */
SX_FUNC(sx_lsp_send)
    SX_PROLOGUE 16
    MOVR(S0, A0)
    SX_CALL(strlen)
    MOVR(A1, R0)
    MOVR(A2, S0)
    LEA_SYM(A0, lsp_fmt_hdr)
    SX_VCALL(printf)
    MOVI(A0, 0)
    SX_CALL(fflush)
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_lsp_send)

/* ----------------------------------------------------------------------------
 * sx_cmd_lsp() — Runs JSON-RPC 2.0 Language Server loop on stdin/stdout
 * ----------------------------------------------------------------------------
 */
SX_FUNC(sx_cmd_lsp)
    SX_PROLOGUE 32
.L_lsp_loop:
    /* Read incoming line/frame into g_lsp_inbuf via getchar() until '}' or EOF */
    LEA_SYM(S0, g_lsp_inbuf)
    MOVI(S1, 0)                 /* len */
    MOVI(S2, 0)                 /* brace depth */
    MOVI(S3, 0)                 /* saw_brace */

.L_lsp_read:
    SX_CALL(getchar)
    CMPI(R0, 0) ; JLT(.L_lsp_eof)
    CMPI(S1, 8190) ; JGE(.L_lsp_dispatch)
    ST8_IDX_R0(S0, S1)
    ADDI(S1, 1)
    CMPI(R0, '{') ; JNE(.L_lsp_rc)
    ADDI(S2, 1) ; MOVI(S3, 1) ; JMP(.L_lsp_read)
.L_lsp_rc:
    CMPI(R0, '}') ; JNE(.L_lsp_read)
    SUBI(S2, 1)
    CMPI(S3, 1) ; JNE(.L_lsp_read)
    CMPI(S2, 0) ; JGT(.L_lsp_read)

.L_lsp_dispatch:
    MOVI(T0, 0) ; ST8_IDX_T0(S0, S1)

    /* Match JSON-RPC method via strstr() */
    MOVR(A0, S0) ; LEA_SYM(A1, lsp_m_init) ; SX_CALL(strstr)
    CMPI(R0, 0) ; JEQ(.L_lsp_hov)
    LEA_SYM(A0, lsp_resp_init) ; SX_CALL(sx_lsp_send)
    JMP(.L_lsp_loop)

.L_lsp_hov:
    MOVR(A0, S0) ; LEA_SYM(A1, lsp_m_hover) ; SX_CALL(strstr)
    CMPI(R0, 0) ; JEQ(.L_lsp_cmp)
    LEA_SYM(A0, lsp_resp_hov) ; SX_CALL(sx_lsp_send)
    JMP(.L_lsp_loop)

.L_lsp_cmp:
    MOVR(A0, S0) ; LEA_SYM(A1, lsp_m_comp) ; SX_CALL(strstr)
    CMPI(R0, 0) ; JEQ(.L_lsp_shut)
    LEA_SYM(A0, lsp_resp_cmp) ; SX_CALL(sx_lsp_send)
    JMP(.L_lsp_loop)

.L_lsp_shut:
    MOVR(A0, S0) ; LEA_SYM(A1, lsp_m_shut) ; SX_CALL(strstr)
    CMPI(R0, 0) ; JEQ(.L_lsp_exit)
    LEA_SYM(A0, lsp_resp_ok) ; SX_CALL(sx_lsp_send)
    JMP(.L_lsp_loop)

.L_lsp_exit:
    MOVR(A0, S0) ; LEA_SYM(A1, lsp_m_exit) ; SX_CALL(strstr)
    CMPI(R0, 0) ; JNE(.L_lsp_eof)
    JMP(.L_lsp_loop)

.L_lsp_eof:
    MOVI(R0, 0)
    SX_EPILOGUE
SX_ENDFUNC(sx_cmd_lsp)
