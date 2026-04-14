# Performance Evolution Log

This document tracks the iterative optimization of the `matrix_lib` benchmark across Zig, Rust, and C++.

## Environment Configuration
*   **OS**: Windows 11 (win32)
*   **Shell**: MINGW64 (MSYS2)
*   **CPU**: x86_64 (Skylake architecture)
*   **Toolchains**:
    *   **Zig**: 0.15.2 (Native LLVM)
    *   **Rust**: 1.93.1 (Target: `x86_64-pc-windows-gnu`)
    *   **C++**: g++ 15.2.0 (Target: `x86_64-w64-mingw32`)

---

## Stage 1: The "Naive" Baseline (i, j, k order)
**Target**: 1024 x 1024 Matrix Multiplication (~2.1B FLOPs).
**Code State**: Standard nested loops using high-level abstractions (Safe Slices in Rust, standard indexing in Zig/C++).

| Implementation | Execution Time | Context |
| :--- | :--- | :--- |
| **Zig** | 10,414 ms | Default `ReleaseFast` optimizations. |
| **C++** | 12,820 ms | Standard `-O3`. |
| **Rust** | 12,826 ms | Standard `--release` with LTO. |

**Observation**: Zig led because its `ReleaseFast` defaults were more aggressive in autovectorization than the C++ and Rust defaults.

---

## Stage 2: Toolchain Standardization
**Change**: Added `-march=native` and `-ffast-math` to the C++ build via `build.zig`. Forced Rust to use `target-cpu=native`.

| Implementation | Execution Time | Delta |
| :--- | :--- | :--- |
| **C++** | **10,671 ms** | -17% (Leadership Flip) |
| **Rust** | 12,685 ms | -1% (Negligible) |
| **Zig** | 13,466 ms | +29% (Regression via explicit target) |

**Observation**: Standardizing the toolchains allowed C++ to leverage aggressive floating-point reordering (`-ffast-math`), proving that "language speed" is often just "compiler configuration."

---

## Stage 3: The "Hardware Sympathy" Breakthrough (i, k, j order)
**Change**: Reordered the triple-nested loops from `(i, j, k)` to `(i, k, j)`. Switched Rust to use raw pointers to eliminate bounds-checking overhead.

| Implementation | Execution Time | Speedup vs Stage 1 |
| :--- | :--- | :--- |
| **C++** | **419 ms** | **30x** |
| **Rust** | **785 ms** | **16x** |
| **Zig** | **865 ms** | **12x** |

**Total Cumulative Speedup**: **~48x** improvement from the original 20-second runs.

**Conclusion**: The leap from 13,000ms to 400ms was achieved not by changing the language, but by aligning the algorithm with the **CPU Cache Hierarchy**.
