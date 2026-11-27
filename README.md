# SYNCHRONIX — Pure Portable Assembly Programming Language

**Synchronix** is a standalone, native programming language implemented in **100% pure portable assembly** (`.S` only — zero C, C++, Rust, Python, Go, Pawn, PowerShell, or Makefile files), strictly adhering to the **Synchronix Architecture Diagram**.

Influenced by **Swift** (ARC, safety, modern design) and **Kotlin** (tracing GC, M:N concurrency, functional ergonomics), with integrated **$\Phi$ (Phi) Formal Logic** verification and **$\Lambda$ (Lambda) Functional Logic** closures.

## Portability Proof

Every single one of the **21 pure assembly units** uses the unified Portable Assembly ISA Layer (`include/portable_asm.S`) and assembles cleanly across:
- `x86_64` — Windows PE/COFF (Win64 ABI), Linux ELF (SysV ABI), macOS Mach-O
- `ARM64` (`aarch64`) — Windows ARM64, Linux ELF AArch64, macOS Mach-O ARM64

## Strict 1-to-1 Architecture Mapping

| Diagram Phase | Subsystem | Pure Assembly Source |
|---|---|---|
| **Portable ISA** | Cross-Arch & Cross-OS Macro Layer & Definitions | `include/portable_asm.S`, `include/sx_defs.S` |
| **Build System** | Native Build, Clean & Cross-Target Verification (`all`/`runtime`/`compiler`/`verify`/`clean`) | `build.S` |
| **Phase 1: Frontend** | Lexer / Tokenizer (`.synchronix`) | `src/frontend/lexer.S`, `src/frontend/utils.S` |
| **Phase 1: Frontend** | Parser (AST) | `src/frontend/parser.S` |
| **Phase 1: Frontend** | Semantic Analyzer, Type Inference, Generics, Scope, $\Phi$ Formal Verification, $\Lambda$ Capture Analysis | `src/frontend/sema.S` |
| **Phase 2: Middle-End** | IR Generator -> High-Level IR -> SUMIR | `src/middle/ir_gen.S` |
| **Phase 2: Middle-End** | Static Analysis & Memory Safety (Ownership/Borrow Checker, ARC Insertion, GC Root Tracking, Lifetime Analyzer) | `src/middle/mem_safety.S` |
| **Phase 2: Middle-End** | $\Phi$ & $\Lambda$ Optimization Passes (Proof Elimination, ARC Peephole) | `src/middle/phi_lambda_opt.S` |
| **Phase 2: Middle-End** | Lowering (Constant Folding, Inlining, Fixed-Point DCE) | `src/middle/lowering.S` |
| **Phase 3: Backend** | Target-Specific Optimization (Linear-Scan Register Allocation & Instruction Scheduling) | `src/backend/target_opt.S` |
| **Phase 3: Backend** | LLVM IR / Custom `x86_64` & `ARM64` Code Generator | `src/backend/codegen.S` |
| **Phase 3: Backend** | Assembler & Linker (`ld`/`lld`) + External Libs (`.a`/`.so`/`.lib`) | `src/backend/emitter.S` |
| **Foundation: Runtime** | Unified Memory (ARC Engine, Tracing Mark-and-Sweep GC, Arena Manager) | `src/runtime/memory_rt.S` |
| **Foundation: Runtime** | M:N Async Scheduler & Fibers/Tasks | `src/runtime/async_rt.S` |
| **Foundation: Runtime** | $\Phi$ Formal Logic & $\Lambda$ Closure Runtime | `src/runtime/phi_lambda_rt.S` |
| **Foundation: Stdlib** | Synchronix Standard Library (`std`) | `src/runtime/stdlib.S` |
| **Ecosystem Tooling** | Cargo Package Manager & Build System (`new`/`build`/`run`/`test`) | `src/tooling/cargo_pkg.S` |
| **Ecosystem Tooling** | Formatter (`synchronix fmt`) & Linter (`synchronix lint`) | `src/tooling/fmt_lint.S` |
| **Ecosystem Tooling** | Synchronix LSP (JSON-RPC 2.0 Language Server) | `src/tooling/lsp.S` |
| **Ecosystem Tooling** | Debugger (LLDB/GDB `-g`) & Profiler (`synchronix profile`) | `src/tooling/debug_prof.S` |
| **CLI Entry** | Unified `synchronix` CLI Driver | `src/main.S` |

## Build & Quick Start

```sh
# Bootstrap the pure assembly build system (replaces Makefile & build.ps1)
clang -Iinclude -fuse-ld=lld build.S -o build/sx_build.exe
./build/sx_build.exe              # Build runtime + compiler + cross-verify all 21 .S units
./build/sx_build.exe all          # Build runtime + compiler only
./build/sx_build.exe clean        # Clean all generated build artifacts
./build/sx_build.exe help         # Show all targets & CC/AR/CFLAGS/LDFLAGS overrides

# (Linux / macOS)
clang -Iinclude -fuse-ld=lld build.S -o build/sx_build && ./build/sx_build

# Compile & run the full architecture showcase
./build/synchronix.exe profile examples/showcase.synchronix

# Cross-compile to ARM64 or emit LLVM IR
./build/synchronix.exe compile examples/showcase.synchronix --target arm64 -o build/showcase_arm64
./build/synchronix.exe compile examples/showcase.synchronix --emit-llvm -o build/showcase_llvm

# Ecosystem tooling
./build/synchronix.exe new my_app
./build/synchronix.exe fmt examples/showcase.synchronix
./build/synchronix.exe lint examples/showcase.synchronix
./build/synchronix.exe lsp
```

## License

Synchronix is licensed under the [Apache License, Version 2.0](./LICENSE). End-user terms are provided in [EULA.md](./EULA.md).
