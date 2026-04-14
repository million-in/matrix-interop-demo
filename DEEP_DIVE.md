# Deep Dive: The Mechanics of Performance

This document explains the transition from 20,000ms to 400ms in our matrix multiplication benchmark.

## 1. The Cache Locality Problem
The performance of a CPU is often limited not by how fast it can calculate, but by how fast it can fetch data from memory.

### Row-Major Layout
In Zig, Rust, and C++, matrices are stored in **Row-Major Order**. This means that a 2D matrix is actually one long array in memory:
`[row1][row1][row1][row2][row2][row2]...`

### The "Naive" Loop (i, j, k)
In the `(i, j, k)` order, Matrix B is accessed by column. This results in an **L1 Cache Miss** on nearly every iteration of the inner loop, as the CPU must "jump" between rows in Matrix B.

---

## 2. The Solution: Hardware Sympathy (i, k, j)
By swapping the inner two loops, we access all matrices sequentially by row. This allows the CPU's **Hardware Prefetcher** to stream data through the L1 cache at peak throughput, resulting in a **~48x performance gain.**

---

## 3. The Power of `-ffast-math`
C++'s leadership at **~400ms** is largely due to aggressive floating-point optimizations. Standard IEEE 754 rules prevent certain reorderings that are essential for SIMD vectorization. By enabling `-ffast-math`, we allow the compiler to use **AVX2/AVX512** to process 8 or 16 floats simultaneously.

---

## 4. Stage 4: Cache Blocking (Tiling)
In Stage 4, we introduced a block-based loop structure:
```c
for (ii = 0; ii < m; ii += BLOCK)
  for (kk = 0; kk < n; kk += BLOCK)
    for (jj = 0; jj < p; jj += BLOCK)
      // Standard i, k, j loops within the block
```
### The "HPC" Advantage
While the `(i, k, j)` order is fast, for very large matrices, the rows of Matrix B may still overflow the L1 or L2 cache. By "tiling" the multiplication into 64x64 blocks, we ensure that the working set of data (A-block + B-block) remains entirely within the CPU's fastest cache levels throughout the entire inner calculation.

### Results Analysis: The "Compiler Interference" Paradox
*   **Rust (-17%)**: Tiling worked as expected, providing a significant gain over Stage 3. This indicates that Rust's LLVM backend found tiling to be a more efficient way to manage registers and cache.
*   **Zig (+58%)**: Zig's regression in Stage 4 is a classic example of **"Manual Optimization Conflict."** The extra complexity of the tiled loops (extra counters, `@min` calls) likely prevented LLVM from recognizing the pattern it previously successfully autovectorized in Stage 3. In systems engineering, sometimes the most "advanced" algorithm is slower if it confuses the compiler's heuristics.
*   **C++ (Stable)**: At **400ms**, C++ is likely **Compute-Bound**—meaning the CPU's arithmetic units are working as fast as possible, and memory bandwidth is no longer the bottleneck.
