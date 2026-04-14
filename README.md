# Matrix-Lib: Systems-Level Interop & Cache-Aware Performance Analysis

An empirical exploration of modern systems programming, evaluating how **Zig**, **Rust**, and **C++** optimize high-compute workloads through cache-aware algorithm design.

```text
    [ Infrastructure Layer ]
           |
    +------+------+------+
    |      |      |      |
  [Zig]  [Rust] [C++]  (Cache-Optimized i,k,j Kernels)
    |      |      |
    +------+------+
           |
    [ Unified Build System (Zig) ]
```

## The "Cache Locality" Breakthrough
Algorithm choice is secondary to **hardware sympathy**. By transitioning from a naive $O(n^3)$ `(i, j, k)` loop order to a cache-friendly `(i, k, j)` order, we achieved a **~48x performance gain** across all toolchains.

---

## Comparative Performance: 1024x1024 Workload
Benchmarks performed on **x86_64-windows-gnu** (MSYS2/MinGW). Total operations: ~2.1 Billion FLOPs.

| Implementation | Execution Time | Performance Delta | Notes |
| :--- | :--- | :--- | :--- |
| **C++** | **419 ms** | **1.00x (Baseline)** | 🏆 Lead with `-ffast-math` & SIMD vectorization. |
| **Rust** | **785 ms** | **1.87x** | Raw pointers, LTO, `target-cpu=native`. |
| **Zig** | **865 ms** | **2.06x** | Pointer-based `i,k,j` accumulation. |

### Technical Analysis: Why the 48x Speedup?
*   **Naive (i, j, k)**: Accesses Matrix B by column. This results in an L1 cache miss on nearly every inner-loop iteration because memory is stored in row-major order.
*   **Optimized (i, k, j)**: Accesses Matrix A, B, and Result all by row. This allows the CPU to stream memory linearly, triggering the **hardware prefetcher** and enabling **SIMD (AVX/AVX512)** vectorization of the inner `j` loop.

### Why is C++ winning now?
*   **Compiler Heuristics**: `g++` 15.2.0 with `-ffast-math` is significantly more aggressive in unrolling linear scans than the default LLVM passes in Zig and Rust.
*   **Floating-Point Reassociation**: `-ffast-math` allows the compiler to reorder the accumulation of `sum += a * b`, which is the key to filling the SIMD pipelines.

---

## The Build System (The "Glue")
We use **Zig 0.15.2** to orchestrate the entire polyglot build. Zig manages the cross-language linking of Rust's `staticlib` and C++'s object files, resolving complex Windows system dependencies (`userenv`, `ntdll`) automatically.

---

## Conclusion: Hardware Sympathy > Language Choice
This project demonstrates that while Zig and Rust provide superior safety and ergonomics, the **ultimate performance limit** is dictated by how well the code aligns with the CPU's cache hierarchy and vector units. 

In systems engineering, the goal isn't just to write code that works—it's to write code that **vibrates with the hardware.**
