# Matrix-Lib: Systems-Level Interop & Performance Benchmark

A raw, polyglot exploration of modern systems programming, pushing **Zig**, **Rust**, and **C++** to their limits in a unified performance harness.

```text
    [ Infrastructure Layer ]
           |
    +------+------+------+
    |      |      |      |
  [Zig]  [Rust] [C++]  (Core Engines)
    |      |      |
    +------+------+
           |
    [ Unified Build System (Zig) ]
           |
    +------+------+------+
    |      |      |      |
 [Python] [Go]  [TS]   (Consumers)
```

## The Manifesto
In the world of high-performance infrastructure, language choice is a tactical decision. This project proves that we can harness the unique strengths of the three most powerful systems languages without sacrificing interoperability.

We use **Zig 0.15.2** not just as a language, but as a **next-generation build orchestrator** that treats C++ and Rust as first-class citizens.

---

## Performance Ratios: 1024x1024 Matrix Multiplication
Benchmarks performed on **x86_64-windows-gnu** (MSYS2/MinGW). Total operations: ~2.1 Billion FLOPs.

| Implementation | Execution Time | Performance | Notes |
| :--- | :--- | :--- | :--- |
| **Zig** | **10,414 ms** | **1.00x (Baseline)** | 🏆 Ultra-efficient autovectorization. |
| **C++** | **12,820 ms** | **1.23x slower** | Standard O3 optimizations with g++. |
| **Rust** | **12,826 ms** | **1.23x slower** | LTO enabled, no_mangle C-exports. |

### Why is Zig winning?
*   **Aliasing Semantics**: Zig's pointer model gives LLVM more aggressive optimization room than standard C++ or Rust's safe-slice abstractions.
*   **Comptime Specialization**: Zero-overhead generic dispatch.
*   **No Hidden Runtime**: Unlike many modern languages, Zig provides absolute transparency between source and machine code.

---

## Interoperability: The "Zero-Overhead" Bridge
Every implementation adheres to the **C ABI**, ensuring zero-copy, zero-overhead calls between components.

### 1. The Rust Static Engine
We compile Rust to a `staticlib` with `lto = "fat"` and `panic = "abort"` for the smallest, fastest possible binary footprint.
```bash
cargo build --release --target x86_64-pc-windows-gnu
```

### 2. The C++ Legacy Wrapper
Using standard `extern "C"` to bridge C++'s class-based logic into the global linker namespace.

### 3. The Zig Orchestrator
Zig acts as the "Glue Code" and the Build System. It handles the linking of complex Windows system libraries (`userenv`, `ntdll`, `shell32`) and manages the C++ include paths.

---

## Real-World Production Integration
This library isn't meant for a terminal; it's meant to be the heart of a high-throughput system:

*   **Financial Trading (Python)**: Use `cffi` to call this library for nanosecond-sensitive risk calculations while keeping the strategy logic in Python.
*   **Cloud Infrastructure (Go)**: Use `cgo` to offload CPU-intensive matrix math from Go's garbage-collected heap into the raw memory managed by our Zig engine.
*   **Real-time Visualization (TS/Node)**: Process massive datasets in a background thread via `node-ffi-napi` without blocking the V8 event loop.

---

## Build & Verify
```bash
# 1. Prepare the Rust Engine
cd rust && cargo build --release --target x86_64-pc-windows-gnu && cd ..

# 2. Run the High-Performance Harness
zig build run -Doptimize=ReleaseFast
```

---

## Architectural Insights
*   **Binary Size**: We prioritize LTO (Link Time Optimization) to strip unused symbols from the Rust standard library.
*   **Linking Logic**: We manually resolve `GetUserProfileDirectoryW` and other OS-level symbols in the Zig build script, demonstrating deep integration with the Windows environment.
*   **Memory Safety**: We balance Rust's safety with Zig's manual precision, ensuring no leaks in the high-performance path.
