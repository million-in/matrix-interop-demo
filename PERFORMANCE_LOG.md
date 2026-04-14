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
| Implementation | Execution Time | Context |
| :--- | :--- | :--- |
| **Zig** | 10,414 ms | Default `ReleaseFast`. |
| **C++** | 12,820 ms | Standard `-O3`. |
| **Rust** | 12,826 ms | Standard `--release`. |

---

## Stage 2: Toolchain Standardization
| Implementation | Execution Time | Context |
| :--- | :--- | :--- |
| **C++** | 10,671 ms | `-march=native -ffast-math`. |
| **Rust** | 12,685 ms | `target-cpu=native`. |
| **Zig** | 13,466 ms | Explicit `-Dtarget=native`. |

---

## Stage 3: Hardware Sympathy (i, k, j order)
| Implementation | Execution Time | Context |
| :--- | :--- | :--- |
| **C++** | 419 ms | Sequential row access. |
| **Rust** | 785 ms | Raw pointers + sequential access. |
| **Zig** | 865 ms | Sequential row access. |

---

## Stage 4: Cache Blocking / Tiling (64x64 Blocks)
| Implementation | Execution Time | Delta vs Stage 3 |
| :--- | :--- | :--- |
| **C++** | **401 ms** | -4% |
| **Rust** | **647 ms** | -17% |
| **Zig** | **1367 ms** | +58% |

**Observation**: Rust achieved its lowest time yet, nearing the C++ baseline. Zig's regression highlights the risk of "manual optimization" interfering with LLVM's auto-vectorization heuristics. C++ remains the gold standard for raw compute-bound throughput in this environment.
