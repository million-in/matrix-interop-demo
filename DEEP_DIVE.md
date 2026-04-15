# DEEP_DIVE.md — Touching the Metal: A Systems Engineering Masterclass

> *"The gap between a working program and a fast program is the gap between a programmer who models the algorithm and a programmer who models the machine."*

This document will fundamentally change how you think about loops, memory, and compilers. We will work from first principles — starting at the physics of a DRAM cell and building up to SIMD vector instructions. Every claim is grounded in the benchmark data from this project.

Read this slowly. Challenge every claim. Re-read the code snippets until you can predict what the CPU is doing on each iteration. That is the goal.

---

## Part 1: The Lie Your Language Tells You

### 1.1 — What a Matrix "Is" in Your Mind vs. in RAM

When a mathematician writes a 3×3 matrix:

```
    Col 0   Col 1   Col 2
Row 0 [ 1,     2,     3  ]
Row 1 [ 4,     5,     6  ]
Row 2 [ 7,     8,     9  ]
```

This is a conceptual model. It describes relationships between numbers. The math is clean, grid-like, elegant.

Now ask yourself a harder question: **how does the RAM chip inside your laptop physically store this?**

RAM — Dynamic Random-Access Memory — is organized as a one-dimensional array of memory cells. Each cell is an address. Each address holds bytes. There are no "rows" or "columns" in RAM. There is only a linear sequence of addresses from `0x0000000000000000` to the highest address your CPU can address.

When Zig, Rust, or C++ allocates a 3×3 matrix of `f32` (4-byte floats), the compiler **flattens** it into **Row-Major Order**:

```
Physical RAM (each slot = 4 bytes = one f32):

Address: 0x000  0x004  0x008  0x00C  0x010  0x014  0x018  0x01C  0x020
Value:   [  1,     2,     3,     4,     5,     6,     7,     8,     9  ]
         ├── Row 0 ──────────┤├── Row 1 ──────────┤├── Row 2 ──────────┤
```

Row 0 is stored first: `1, 2, 3`. Then Row 1: `4, 5, 6`. Then Row 2: `7, 8, 9`. The rows are **contiguous** — they are packed next to each other in address space.

This is Row-Major Order. It is the default in C, C++, Rust, Zig, and most systems languages. (Fortran and some numerical libraries use Column-Major. NumPy lets you choose. This distinction will matter enormously.)

**The critical implication**: if you want to walk down **Column 0** (values `1, 4, 7`), you have to jump:
- `1` is at address `0x000`
- `4` is at address `0x00C` — a jump of 12 bytes (3 floats × 4 bytes)
- `7` is at address `0x018` — another jump of 12 bytes

For our 1024×1024 matrix, a column jump is not 12 bytes. It is **4,096 bytes** (1024 floats × 4 bytes/float). Every step down a column requires a 4 KB stride across memory.

This number — 4,096 bytes — will come back to haunt us shortly.

---

### 1.2 — The Memory Hierarchy: Why RAM Access Takes Forever

Here is something that surprises most programmers when they first encounter it: your CPU can execute an arithmetic operation (an addition, a multiplication) in about **1 clock cycle**. At 2.4 GHz, that's 0.4 nanoseconds.

Accessing a value from RAM, on the other hand, takes **~100 clock cycles** or more. That's 40–100 nanoseconds of waiting.

The CPU is literally 100× faster at computing than at fetching data from RAM. This is called the **Memory Wall** — the ever-widening gap between processor speed and memory bandwidth. If your code constantly needs data from RAM, the CPU spends 99% of its time waiting and 1% of its time computing. That is what we saw in Stage 1.

To bridge this gap, CPU architects added a **cache hierarchy** — multiple layers of increasingly fast (and increasingly small) storage between the processing cores and the main RAM:

```
┌─────────────────────────────────────────────────────────────────────┐
│  Storage Layer    │  Size (i5-6300U)  │  Latency  │  Speed          │
├───────────────────┼───────────────────┼───────────┼─────────────────┤
│  CPU Registers    │  ~1 KB per core   │  0 cycles │  Instantaneous  │
│  L1 Data Cache    │  32 KB per core   │  ~4 cycles│  Very fast      │
│  L2 Cache         │  256 KB per core  │  ~12 cycles│ Fast           │
│  L3 Cache (LLC)   │  3 MB shared      │  ~30 cycles│ Moderate       │
│  RAM (DRAM)       │  8–32 GB          │  ~100+ cycles│ Slow         │
│  NVMe SSD         │  256 GB+          │  ~100,000 cycles│ Very slow  │
└─────────────────────────────────────────────────────────────────────┘
```

The hierarchy works because of **temporal locality** (if you accessed data recently, you'll probably access it again soon) and **spatial locality** (if you accessed data at address X, you'll probably access data near address X soon). The caches exploit both.

But here's the key mechanism for our story: **the CPU does not fetch a single float from RAM**. That would be horribly inefficient. Instead, it fetches an entire **Cache Line**.

---

### 1.3 — The Cache Line: The Atomic Unit of Memory

A Cache Line is the smallest unit of data that the CPU can transfer between RAM and the L1 cache. On virtually all modern x86 processors, a cache line is **64 bytes**.

Since our floats are 4 bytes each, one cache line holds **16 floats**.

When your code accesses a value at address `0x000`, the CPU doesn't just fetch the float at `0x000`. It fetches the entire 64-byte cache line — the float at `0x000` **plus the 15 floats immediately following it** (at `0x004`, `0x008`, ... `0x03C`).

This is free. Fetching 16 adjacent floats costs the same as fetching 1. The cache line comes as a unit.

This is the hardware's bet: **if you need the float at address X, you will probably need the float at address X+4 very soon.** The cache line is the hardware's spatial locality optimization.

**When this bet pays off** (sequential access): every cache line you fetch gives you 15 free future accesses. You use all 16 floats. Cache efficiency = 100%.

**When this bet fails** (stride access): you fetch 16 floats, use 1, and jump 4,096 bytes to the next column value. The other 15 floats are evicted before you need them. Cache efficiency ≈ 6%.

That efficiency gap — 100% vs. 6% — is where our 48× speedup lives.

---

## Part 2: The Naive Loop Autopsy

### 2.1 — The Algorithm We Started With

Matrix multiplication $C = A \times B$ where $A$ is $m \times n$ and $B$ is $n \times p$ and $C$ is $m \times p$ is defined mathematically as:

$$C[i][j] = \sum_{k=0}^{n-1} A[i][k] \times B[k][j]$$

For every cell `(i, j)` in the result, you sum `n` products across a row of A and a column of B.

Transcribed directly into code, this gives us the canonical triple loop:

```zig
// zig/matrix.zig — Stage 1: Naive (i, j, k) order
export fn zig_matrix_multiply(
    a_ptr: [*]f32, a_rows: usize, a_cols: usize,
    b_ptr: [*]f32, _b_rows: usize, b_cols: usize,
    result_ptr: [*]f32
) void {
    const m = a_rows;
    const n = a_cols;
    const p = b_cols;

    for (0..m) |i| {           // ← outer: rows of A
        for (0..p) |j| {       // ← middle: columns of B
            var sum: f32 = 0.0;
            for (0..n) |k| {   // ← inner: the dot product
                sum += a_ptr[i * n + k] * b_ptr[k * p + j];
            }
            result_ptr[i * p + j] = sum;
        }
    }
}
```

This is a mathematically faithful implementation. It matches the formula. It produces the correct answer. And for a 1024×1024 matrix, it takes **~10,000–13,000 milliseconds** depending on the toolchain.

### 2.2 — Tracing the Cache Behavior of the Naive Loop

Let's freeze the outer two loops and analyze what happens in the innermost `k` loop. Assume `i = 0, j = 0`:

```
Inner loop iteration by iteration (i=0, j=0):

k=0:  A[0,0] at address 0x000  → sequential, likely in L1
      B[0,0] at address 0x000  → sequential, fetches cache line [B[0,0]..B[0,15]]

k=1:  A[0,1] at address 0x004  → in L1 (same cache line as k=0)
      B[1,0] at address 0x1000 → 4,096 bytes away! CACHE MISS — fetch new line

k=2:  A[0,2] at address 0x008  → in L1 ✓
      B[2,0] at address 0x2000 → another 4,096 byte jump! CACHE MISS

k=3:  A[0,3] at address 0x00C  → in L1 ✓
      B[3,0] at address 0x3000 → CACHE MISS
...
```

**Every single iteration of the k loop triggers a cache miss on Matrix B.**

When the L1 cache fills up (32 KB = ~8,192 floats), it starts evicting old cache lines to make room for new ones. Matrix B is 1024×1024 = 4,194,304 floats = 16 MB. The L3 cache is 3 MB. Matrix B **does not fit in any cache**. Every column access is a guaranteed RAM fetch.

The CPU response to each miss: it stalls all computation and waits ~100 cycles for RAM to deliver the data. With 1024 iterations of `k` and 1024×1024 cells in the result, we are triggering approximately **1,073,741,824 cache misses** for Matrix B alone.

At ~100 cycles per miss, at 2.4 GHz: `1,073,741,824 × 100 / 2,400,000,000 ≈ 44 seconds` of pure waiting. We measure ~13 seconds because the hardware has several prefetching mechanisms that help somewhat, but they cannot overcome this access pattern.

### 2.3 — Why Zig Led in Stage 1 Despite the Same Algorithm

Stage 1 results:
- Zig: 10,414ms
- C++: 12,820ms
- Rust: 12,826ms

Same algorithm. Same access pattern. Same cache misses. Why did Zig win by ~20%?

The answer is in the default optimization profiles:

**Zig `ReleaseFast`**: Zig's release build is explicitly designed for raw speed. It disables all runtime safety checks (bounds checking, overflow detection), enables aggressive inlining, and allows LLVM to apply its most aggressive optimization passes. Critically, Zig's `ReleaseFast` implicitly enables something equivalent to `-fno-strict-aliasing` and other aliasing relaxations that give LLVM more freedom.

**C++ with `-O3` (no `-march=native`)**: Without `-march=native`, the compiler targets a generic x86-64 baseline and cannot use the Skylake-specific AVX2 instructions. It must stay within the SSE2 instruction set, limiting SIMD vector width to 128 bits (4 floats at once) instead of 256 bits (8 floats).

**Rust `--release` (no `target-cpu=native`)**: Same issue as C++. The default Rust release build does not optimize for your specific CPU.

This is Stage 1's lesson in its purest form: **compiler defaults are not equal**. Zig's defaults happened to be more aggressive. That doesn't mean Zig is faster — it means Zig's out-of-box settings are configured differently.

---

## Part 3: The Loop Flip — Hardware Sympathy in Action

### 3.1 — The Insight: Change What the Innermost Loop Does

The naive `(i, j, k)` order has the innermost loop (`k`) walking down a **column** of B. This is the source of all our cache miss suffering.

The fix is to change the loop order so that the innermost loop walks along a **row**. We have exactly one option that achieves this while preserving the mathematical correctness of the computation: swap the `j` and `k` loops.

```zig
// zig/matrix.zig — Stage 3: Cache-Aware (i, k, j) order
export fn zig_matrix_multiply(
    a_ptr: [*]const f32, a_rows: usize, a_cols: usize,
    b_ptr: [*]const f32, _b_rows: usize, b_cols: usize,
    result_ptr: [*]f32
) void {
    _ = _b_rows;
    const m = a_rows;
    const n = a_cols;
    const p = b_cols;

    // Zero the result matrix before accumulation
    @memset(result_ptr[0 .. m * p], 0);

    for (0..m) |i| {           // ← outer: rows of A
        for (0..n) |k| {       // ← middle: shared dimension (was innermost!)
            const a_val = a_ptr[i * n + k]; // ← hoisted out of j loop
            for (0..p) |j| {   // ← inner: columns of result (was middle!)
                result_ptr[i * p + j] += a_val * b_ptr[k * p + j];
            }
        }
    }
}
```

**The mathematical equivalence**: We changed the *order* of accumulation, not the *set* of operations. The result matrix must be zeroed first (because we now accumulate into it across multiple `k` iterations), but the final answer is identical.

### 3.2 — Tracing the Cache Behavior of the Optimized Loop

Same analysis, same freeze — but now trace the innermost `j` loop with `i=0, k=0`:

```
Inner loop iteration by iteration (i=0, k=0):
a_val = A[0,0] → loaded once, held in a register for the entire j loop

j=0:  result[0,0] at address 0x000  → sequential ✓
      B[0,0]      at address 0x000  → fetches cache line [B[0,0]..B[0,15]] ✓

j=1:  result[0,1] at address 0x004  → in L1 (same line) ✓
      B[0,1]      at address 0x004  → in L1 (same line fetched at j=0) ✓

j=2:  result[0,2] at address 0x008  → in L1 ✓
      B[0,2]      at address 0x008  → in L1 ✓

j=3...j=15: all in L1, zero new fetches from RAM

j=16: result[0,16] at address 0x040 → new cache line, but prefetcher loaded it already
      B[0,16]     at address 0x040  → new cache line, prefetcher loaded it already
```

**Zero cache misses in the innermost loop.** The hardware prefetcher is feeding the L1 cache with new cache lines ahead of the j loop's progress.

The comparison:
| Loop Order | Cache Behavior for B | RAM Fetches for 1024×1024 |
|:---|:---|:---|
| `(i, j, k)` | One miss per `k` iteration | ~1 billion |
| `(i, k, j)` | One miss per 16 `j` iterations | ~67 million |

That's a **15× reduction in RAM traffic** just from reordering the loops. The rest of the speedup comes from the hardware prefetcher working perfectly, and from the compiler now being able to autovectorize.

### 3.3 — The Register Hoisting Trick

Notice this line in the Stage 3 code:

```zig
const a_val = a_ptr[i * n + k]; // ← hoisted out of j loop
```

`a_val` is a single float that is constant for the entire innermost `j` loop. By loading it once into a variable (which the compiler will map to a CPU register), we avoid re-loading it from the array on every iteration.

CPU registers are the fastest storage in the entire hierarchy — 0 cycles of latency. By hoisting this load, we've converted a potentially cached memory access into a pure register access.

The compiler would likely do this automatically through a pass called **Loop-Invariant Code Motion (LICM)**, but explicitly writing it out makes the intent clear and guarantees it in all optimization levels.

---

## Part 4: SIMD — When the CPU Does Math in Packs

### 4.1 — What SIMD Actually Is

SIMD stands for **Single Instruction, Multiple Data**. It is a class of CPU instructions that operate on multiple values simultaneously using wide registers.

Your CPU has normal registers (`rax`, `rbx`, etc.) that are 64 bits wide — they hold one `f64` or one `u64`. But modern CPUs also have **vector registers** that are much wider:

| Register Family | Width | Float Capacity |
|:---|:---|:---|
| SSE (`xmm0`–`xmm15`) | 128 bits | 4 × f32 |
| AVX/AVX2 (`ymm0`–`ymm15`) | 256 bits | 8 × f32 |
| AVX-512 (`zmm0`–`zmm31`) | 512 bits | 16 × f32 |

The Intel Skylake CPU in this benchmark supports **AVX2** (256-bit). This means it can execute one instruction that multiplies 8 floats simultaneously against 8 other floats.

For our inner loop:
```zig
for (0..p) |j| {
    result_ptr[i * p + j] += a_val * b_ptr[k * p + j];
}
```

With scalar (non-SIMD) execution:
- Load `b_ptr[j]` — 1 float
- Multiply by `a_val` — 1 float
- Load `result_ptr[j]` — 1 float
- Add — 1 float
- Store `result_ptr[j]` — 1 float
- Repeat 1024 times

With AVX2 SIMD execution (conceptually):
- Load `b_ptr[j..j+7]` — **8 floats in one instruction**
- Multiply all 8 by `a_val` simultaneously — **8 multiplications in one instruction**
- Load `result_ptr[j..j+7]` — **8 floats in one instruction**
- Add all 8 pairs — **8 additions in one instruction**
- Store `result_ptr[j..j+7]` — **8 floats in one instruction**
- Repeat 128 times (1024 / 8)

**8× fewer iterations, 8× fewer instructions.** Combined with pipelining and out-of-order execution, this is where the 400ms results come from.

### 4.2 — Why `-ffast-math` Is the Key That Unlocks SIMD

Here is the subtle problem. The compiler wants to vectorize your loop, but IEEE 754 (the standard defining how floating-point arithmetic works) says that `(a + b) + c` is not necessarily equal to `a + (b + c)` due to floating-point rounding. These are different computations that may produce slightly different results.

For the compiler to vectorize the inner loop, it needs to process elements out of the "natural" sequential order — it processes elements 0-7 in one SIMD instruction, then elements 8-15, etc. This changes the order of floating-point operations. Under strict IEEE 754, this is **illegal** — the results might differ from the scalar computation.

`-ffast-math` (and Zig's `ReleaseFast` mode equivalently) tells the compiler: **"I give you permission to reorder floating-point operations for throughput. I don't require strict IEEE 754 reproducibility."**

With that permission granted:
- The compiler reorganizes the loop to process 8 elements per SIMD instruction
- It uses the `VFMADD231PS` instruction (Fused Multiply-Add, AVX2): `result[j:j+7] += a_val * B[k][j:j+7]`
- It unrolls the loop 2–4× to keep multiple SIMD units busy

Without `-ffast-math`, the compiler must assume you want strict IEEE 754 and emits slower, scalar instructions.

**The cost of `-ffast-math`**: The floating-point results may differ in the last significant bit or two from a strictly IEEE 754 computation. For our matrix multiply, this is invisible — our correctness check uses a `0.001` tolerance. For a physics simulation or financial calculation, this tolerance may be unacceptable.

### 4.3 — The FMA Instruction: Multiply and Add in One Shot

Fused Multiply-Add (FMA) is a specific optimization that the Stage 3 loop enables. Instead of:
1. Multiply `a_val` by `B[k][j]` → temporary result
2. Add temporary result to `result[i][j]`

FMA does both in a single instruction, and importantly, the intermediate result is held at full precision (without rounding to float precision between steps). This reduces rounding error *and* halves the instruction count for the core computation.

On Skylake, the `VFMADD231PS` instruction operates on 8 floats at once and has a throughput of 2 per clock cycle. Meaning, in one clock cycle, the CPU can execute 2 × 8 = **16 fused multiply-adds**. That's 32 floating-point operations per clock cycle, per core. At 2.4 GHz, the theoretical peak for single-precision FMAs is `32 × 2,400,000,000 = 76.8 GFLOPs/s`.

We measured C++ at 401ms for 2.1 billion FLOPs = ~5.2 GFLOPs/s. We're at about 7% of theoretical peak. The gap is real — perfect peak throughput requires zero memory latency and perfect pipeline saturation, which no real application achieves. But the point is that by enabling SIMD, we moved from ~0.16 GFLOPs/s (Stage 1 naive) to ~5.2 GFLOPs/s. That's a **32× FLOPs-per-second improvement** from algorithmic and toolchain choices alone.

---

## Part 5: Cache Blocking — When Sequential Isn't Enough

### 5.1 — The Problem That Tiling Solves

Stage 3 achieved excellent sequential access in the innermost loop. But there's a subtler issue that appears at larger matrix sizes.

Consider the working set for a single iteration of the `k` loop (where `k` is fixed):
- We read all of row `i` of A: `n` floats = 1024 × 4 = **4 KB**
- We read all of row `k` of B: `p` floats = 1024 × 4 = **4 KB**
- We read/write all of row `i` of Result: `p` floats = 1024 × 4 = **4 KB**

Total: **~12 KB per k-iteration**. The L1 cache is 32 KB, so this fits — barely.

But over the full `n = 1024` iterations of the `k` loop:
- We stream through all of B: 1024 × 4 KB = **4 MB**
- The L3 cache is 3 MB — B doesn't fit entirely

As we cycle through all values of `k`, we keep evicting B's rows from the cache and then re-fetching them later. We are reading B from L3/RAM multiple times per i-row.

Tiling (Cache Blocking) solves this by operating on smaller sub-matrices that *do* fit in L1/L2 cache throughout the computation:

```c
// cpp/matrix.cpp — Stage 4: Cache-Blocked (Tiled)
#define BLOCK_SIZE 64  // 64 × 64 × 4 bytes = 16 KB per block (fits in 32KB L1)

for (size_t ii = 0; ii < a_rows; ii += BLOCK_SIZE) {       // block rows of A
    for (size_t kk = 0; kk < a_cols; kk += BLOCK_SIZE) {   // block shared dim
        for (size_t jj = 0; jj < b_cols; jj += BLOCK_SIZE) { // block cols of B

            // Now process just the 64×64 sub-block
            for (size_t i = ii; i < min(ii + BLOCK_SIZE, a_rows); ++i) {
                for (size_t k = kk; k < min(kk + BLOCK_SIZE, a_cols); ++k) {
                    float a_val = a_ptr[i * a_cols + k];
                    for (size_t j = jj; j < min(jj + BLOCK_SIZE, b_cols); ++j) {
                        result_ptr[i * b_cols + j] += a_val * b_ptr[k * b_cols + j];
                    }
                }
            }
        }
    }
}
```

A 64×64 block of `f32` values: `64 × 64 × 4 = 16,384 bytes = 16 KB`. Three such blocks (A-block, B-block, C-block) = 48 KB. This is slightly larger than L1 (32 KB) but fits well in L2 (256 KB). The key is that the same 64×64 B-block is reused 64 times (for each row of the A-block) before moving to the next B-block.

### 5.2 — The Stage 4 Results Paradox

Here's what we measured:

| Language | Stage 3 (i,k,j) | Stage 4 (Tiled) | Delta |
|:---|:---:|:---:|:---:|
| C++ | 419ms | 401ms | **-4%** |
| Rust | 785ms | 647ms | **-17%** |
| Zig | 865ms | 1,367ms | **+58%** ← Regression! |

Three different outcomes for three different toolchains applying the same algorithmic change. This is a masterclass in compiler behavior.

**C++ (-4%)**: C++ was already near the compute-bound limit in Stage 3. The hardware prefetcher was working well for the `(i,k,j)` pattern. Tiling added some overhead (extra loop variables, `std::min()` calls) but the improvement in L1/L2 hit rate was approximately equal to that overhead. Net: nearly flat.

**Rust (-17%)**: Rust's LLVM backend benefited from tiling because it gave the optimizer clearer loop bounds to work with. When LLVM sees bounded loops over small, known-size arrays, it is more confident in applying vectorization and register promotion. The tile size (64×64) is small enough that LLVM could reason about it completely. Net: meaningful improvement.

**Zig (+58%)**: This is the most important result. Zig's Stage 3 `(i,k,j)` implementation was a single, clean, unbounded sequential loop. LLVM's auto-vectorizer identified it, proved it was safe, and generated AVX2 code. When we added the tiling code — the extra `while` loops, the `@min()` calls, the block boundary variables — we introduced **conditional branching and ambiguous loop bounds** that the auto-vectorizer could no longer reason through. The vectorizer fell back to scalar code. The algorithmic improvement (better cache reuse) was not enough to compensate for losing AVX2 vectorization.

### 5.3 — The Compiler Interference Principle

This is perhaps the most subtle and practically important lesson in the entire project:

> **An optimization that is correct in theory can be harmful in practice if it prevents the compiler from applying a more powerful optimization it was already applying.**

In Zig's case:
- Stage 3 scalar loop → compiler auto-vectorizes → ~8× throughput from SIMD
- Stage 4 tiled loop → compiler cannot auto-vectorize → falls back to scalar → SIMD benefit lost
- Net result: tiling's cache benefit (~2× for this matrix size) < SIMD's benefit (~8×)

The implication for production code: **always profile before and after manual optimizations**. Never assume that a "theoretically superior" algorithm will produce better real-world performance. The compiler's optimizer is doing work you cannot see, and your manual changes can undo it.

The correct fix for Zig would be to add explicit SIMD intrinsic calls that tell the compiler exactly what vector instructions to emit, bypassing the auto-vectorizer entirely. That is Stage 6 on the project roadmap.

---

## Part 6: The ABI — How Three Languages Share One Binary

### 6.1 — What the C ABI Is

The **Application Binary Interface (ABI)** defines the contract between compiled code from different sources: how function arguments are passed (in registers or on the stack), how return values are passed back, how the stack is managed, and how symbols are named in the compiled object file.

The **C ABI** (sometimes called the System V AMD64 ABI on Linux/macOS, or the Microsoft x64 ABI on Windows) is the lingua franca of compiled systems code. Every language that wants to interoperate with other languages must support calling and being called from the C ABI.

This project uses the C ABI as the bridge:

```zig
// Zig: export keyword makes this function callable from C ABI
export fn zig_matrix_multiply(
    a_ptr: [*]const f32, a_rows: usize, a_cols: usize,
    b_ptr: [*]const f32, _b_rows: usize, b_cols: usize,
    result_ptr: [*]f32
) void { ... }
```

```rust
// Rust: extern "C" + #[no_mangle] exports with C ABI and preserves symbol name
#[no_mangle]
pub unsafe extern "C" fn rust_matrix_multiply(
    a_ptr: *const f32, a_rows: usize, a_cols: usize,
    b_ptr: *const f32, _b_rows: usize, b_cols: usize,
    result_ptr: *mut f32,
) { ... }
```

```cpp
// C++: extern "C" disables C++ name mangling, exposes with C ABI
extern "C" {
    void cpp_matrix_multiply(
        const float* a_ptr, size_t a_rows, size_t a_cols,
        const float* b_ptr, size_t _b_rows, size_t b_cols,
        float* result_ptr
    ) { ... }
}
```

```zig
// bench/bench.zig: calling all three via C ABI
const c = @cImport({ @cInclude("matrix.h"); }); // C++ function via C header

extern fn rust_matrix_multiply(...) void;        // Rust function declaration
extern fn zig_matrix_multiply(...) void;         // Zig function declaration
```

At runtime, the benchmark harness calls all three functions with identical arguments. No data copying. No serialization. No IPC. Just a direct function call at the machine-code level. The benchmark measures pure compute time.

### 6.2 — Windows-Specific Linking Complexity

On Windows with MSYS2/MinGW, the Rust standard library (`std`) pulls in Windows platform APIs. Our `build.zig` had to explicitly link several system libraries that Rust's std depends on:

```zig
// From build.zig — Windows system library resolution
if (target.result.os.tag == .windows) {
    bench.linkSystemLibrary("user32");
    bench.linkSystemLibrary("kernel32");
    bench.linkSystemLibrary("ws2_32");
    bench.linkSystemLibrary("advapi32");
    bench.linkSystemLibrary("ntdll");
    bench.linkSystemLibrary("userenv");  // Provides GetUserProfileDirectoryW
    bench.linkSystemLibrary("shell32");
}
```

`userenv` in particular was the cause of a late-stage linker error:
```
error: lld-link: undefined symbol: GetUserProfileDirectoryW
    note: referenced by libmatrix_rs.a in std::env::home_dir
```

Rust's `std::env::home_dir()` calls `GetUserProfileDirectoryW` from `userenv.dll` to find the user's home directory — even though we never called `home_dir()` in our code. It is a transitive dependency, pulled in by the Rust standard library initialization code. Zig's linker (`lld`) reported the missing symbol at link time. The fix was to explicitly add `userenv` to the link step.

This is a microcosm of a real production problem: when you link a foreign binary (a `.a` static library from another language/toolchain), you inherit all of its transitive system dependencies. Zig's build system requires you to be explicit about them, which forces you to understand your full dependency graph.

---

## Part 7: Summary — The Mental Models You Now Own

After working through this document, you should be able to internalize these models:

### Model 1: RAM is a Tape
Memory is one-dimensional. Multi-dimensional arrays are a compiler abstraction over that tape. Every time you access memory "across" the natural storage order, you pay a cache miss penalty. Design your data structures and loops around the physical layout, not the mathematical abstraction.

### Model 2: The Cache Line is Currency
You spend 64 bytes of cache space every time you touch a new cache line. Spend it wisely. If you only use 4 of those 64 bytes, you wasted 94% of your bandwidth budget. Design your inner loops to march forward through memory and use every float in every cache line they load.

### Model 3: The Compiler is a Collaborator, Not a Servant
Your job is to write code that the compiler can reason about clearly. When the compiler sees a simple, bounded, sequential loop, it can apply auto-vectorization, loop unrolling, and FMA fusion. When you add complexity (conditionals, function calls, ambiguous bounds), the compiler's analysis becomes uncertain and it must fall back to conservative code generation. The relationship between you and the optimizer is collaborative.

### Model 4: Flags Are Architecture
`-march=native` is not a cosmetic flag. It determines which CPU instructions are available. `-ffast-math` is not cosmetic either. It determines whether SIMD vectorization is mathematically legal. These flags are part of your system architecture decision, with real tradeoffs (reproducibility, portability).

### Model 5: Measure, Then Optimize
The Stage 4 paradox — where a theoretically correct optimization caused a 58% regression — is the most important lesson from this entire project. Never assume. Always measure. The hardware is more complex than your mental model of it, and that gap is where incorrect optimization intuitions live.

## The "Stabilization" Phenomenon: OS Jitter & Thermals
When you see your benchmark results fluctuate between 150ms and 230ms across 10 runs, you are no longer seeing the performance of your **code**. You are seeing the performance of the **environment**.

### Key Factors in Benchmark Variance:
1.  **CPU Turbo Boost**: On the first few runs, your CPU might boost its frequency (e.g., from 3.0GHz to 4.2GHz). As the CPU heats up, it will throttle down to maintain a safe temperature.
2.  **L3 Cache State**: Subsequent runs might benefit from data that is still sitting in the L3 cache or even the OS's file buffers for the binary.
3.  **Interrupts**: The Windows OS kernel might interrupt your benchmark thousands of times per second to handle networking, mouse movements, or background services. At 150ms, a single interrupt can add 10ms to the total time.

---

## Conclusion: Toolchain Parity
The fact that Zig, Rust, and C++ all reached a ~160ms baseline is the ultimate proof of **Hardware Sympathy**.

At the beginning of this project, we asked: "Which language is fastest?"
The answer at the end of this project is: **"It doesn't matter."**

If you understand how to align your data with the CPU's caches and vector units, you can achieve world-class performance in any systems-level language. You have moved from a programmer who writes "software" to an engineer who understands the **Machine**.


---

*This document was written from first principles, grounded in benchmark data from real hardware. All numbers are reproducible. See PERFORMANCE_LOG.md for the full audit trail.*