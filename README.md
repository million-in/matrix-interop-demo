# Matrix-Lib: A Polyglot Systems Performance Journey

A high-performance exploration of **Zig**, **Rust**, and **C++** interoperability, documenting the evolution from naive implementation to hardware-synchronized optimization.

```text
    [ Infrastructure Layer ]
           |
    +------+------+------+
    |      |      |      |
  [Zig]  [Rust] [C++]  (Cache-Aware i,k,j Kernels)
    |      |      |
    +------+------+
           |
    [ Unified Build System (Zig) ]
```

## The Story
This project is not just about matrix multiplication. It's a recorded history of **Systems Thinking**. We started with a simple problem—multiplying 1024x1024 matrices across three languages—and iteratively stripped away abstractions to see how the hardware truly behaves.

We evolved from a naive 20,000ms implementation to a cache-optimized **400ms** engine, achieving a **~48x performance jump** through algorithm design rather than just "language choice."

### Project Highlights
*   **Polyglot Architecture**: Zig, Rust, and C++ sharing a single binary via the C ABI.
*   **Unified Orchestration**: Using **Zig 0.15.2** to compile C++ and link Rust `staticlib` targets.
*   **Performance Research**: Iterative benchmarking documenting the impact of SIMD, LTO, and Cache Locality.

---

## Performance Summary: 1024x1024 Workload
*Total operations: ~2.1 Billion FLOPs.*

| Step | Zig | Rust | C++ |
| :--- | :--- | :--- | :--- |
| **Initial (Naive)** | 10,414 ms | 12,826 ms | 12,820 ms |
| **Final (Cache Optimized)** | **865 ms** | **785 ms** | **419 ms** |
| **Total Speedup** | **12x** | **16x** | **30x** |

> 📜 **[Read the Full Performance History Log here](./PERFORMANCE_LOG.md)** for a step-by-step audit of how we achieved these results.

---

## Technical Masterclass: Why the 48x Jump?
We transitioned from an `(i, j, k)` loop to an `(i, k, j)` loop. This one change fundamentally altered how the CPU interacts with memory.

> 🎓 **[Read the Deep Dive: The Mechanics of Performance](./DEEP_DIVE.md)** to understand Cache Locality, SIMD Vectorization, and why the "naive" approach fails on modern hardware.

---

## Build & Replicate
### Prerequisites
*   **Zig 0.15.2**
*   **Rust** (Target: `x86_64-pc-windows-gnu`)
*   **G++ 15.2.0** (MSYS2/MinGW)

### 1. Build the Rust Engine
```bash
cd rust
# Use native CPU tuning for maximum optimization
RUSTFLAGS="-C target-cpu=native" cargo build --release --target x86_64-pc-windows-gnu
cd ..
```

### 2. Run the Benchmark
The Zig build system orchestrates the C++ compilation and the final linking phase.
```bash
# Clean artifacts
zig build clean

# Build and run the optimized harness
zig build run -Doptimize=ReleaseFast -Dtarget=native
```

---

## Conclusion: The "Hardware Sympathy" Model
This project demonstrates that in high-performance infrastructure, the "fastest language" is a myth. The fastest solution is the one that achieves **Hardware Sympathy**—aligning the logic with the CPU's prefetchers, cache lines, and vector units.

Zig serves as the perfect "Systems Glue," providing a modern, safe, and incredibly powerful way to orchestrate this level of performance across the entire systems ecosystem.
