# Performance Evolution Log

This document tracks the iterative optimization of the `matrix_lib` benchmark across Zig, Rust, and C++. It is an audit trail proving that performance is not an accident—it is an engineered outcome.

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
| **Zig** | 10,414 ms | Default `ReleaseFast`. |
| **C++** | 12,820 ms | Standard `-O3`. |
| **Rust** | 12,826 ms | Standard `--release`. |

**The Lesson:** Out of the box, Zig led the pack. Why? Because Zig's `ReleaseFast` defaults are highly aggressive with LLVM auto-vectorization, whereas C++ and Rust require explicit flags to unlock their full potential. Language speed is heavily influenced by default compiler configurations.

---

## Stage 2: Toolchain Standardization
**Change**: Added `-march=native` and `-ffast-math` to the C++ build via `build.zig`. Forced Rust to use `target-cpu=native`.

| Implementation | Execution Time | Delta |
| :--- | :--- | :--- |
| **C++** | **10,671 ms** | -17% (Leadership Flip) |
| **Rust** | 12,685 ms | -1% (Negligible) |
| **Zig** | 13,466 ms | +29% (Regression via explicit target) |

**The Lesson:** Standardizing the toolchains allowed C++ to leverage aggressive floating-point reordering (`-ffast-math`), proving that "language speed" is often just "compiler configuration." Zig's regression highlighted how brittle auto-vectorization heuristics can be when you explicitly override targets instead of trusting the compiler's defaults.

---

## Stage 3: The "Hardware Sympathy" Breakthrough (i, k, j order)
**Change**: Reordered the triple-nested loops from `(i, j, k)` to `(i, k, j)`. Switched Rust to use raw pointers to eliminate bounds-checking overhead.

| Implementation | Execution Time | Speedup vs Stage 1 |
| :--- | :--- | :--- |
| **C++** | **419 ms** | **30x** |
| **Rust** | **785 ms** | **16x** |
| **Zig** | **865 ms** | **12x** |

**The Lesson:** **Algorithm dictates performance; hardware dictates the algorithm.** By swapping two lines of code, we stopped jumping across memory columns (cache misses) and started scanning memory linearly (cache hits + hardware prefetching). This single change yielded a **~48x total cumulative speedup**. 

---

## Stage 4: Cache Blocking / Tiling (64x64 Blocks)
**Change**: Subdivided the `(i, k, j)` loops into 64x64 blocks to ensure the active data set fits entirely within the L1/L2 cache boundaries.

| Implementation | Execution Time | Delta vs Stage 3 |
| :--- | :--- | :--- |
| **C++** | **401 ms** | -4% |
| **Rust** | **647 ms** | -17% |
| **Zig** | **1367 ms** | +58% |

**The Lesson:** **The Compiler Interference Paradox.** 
*   Rust successfully parsed our manual tiling, achieving its fastest time yet (-17%). 
*   C++ remained stable, indicating it was already compute-bound (maxing out the CPU's arithmetic units). 
*   Zig **regressed heavily** (+58%). Why? The manual block boundaries (`@min(ii + BLOCK_SIZE, m)`) introduced branching complexity that confused the Zig compiler's vectorization pass. Sometimes, trying to be smarter than the compiler makes the compiler give up. True engineering is knowing when to let the machine do its job.
