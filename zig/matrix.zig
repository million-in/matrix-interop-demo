// zig/matrix.zig
const std = @import("std");

pub const BLOCK_SIZE = 64;

// Export C ABI for interop
export fn zig_matrix_multiply(
    a_ptr: [*]const f32, a_rows: usize, a_cols: usize,
    b_ptr: [*]const f32, _b_rows: usize, b_cols: usize,
    result_ptr: [*]f32
) void {
    _ = _b_rows;
    const m = a_rows;
    const n = a_cols;
    const p = b_cols;

    @memset(result_ptr[0 .. m * p], 0);

    // Stage 4: Cache Blocking (Tiling)
    var ii: usize = 0;
    while (ii < m) : (ii += BLOCK_SIZE) {
        var kk: usize = 0;
        while (kk < n) : (kk += BLOCK_SIZE) {
            var jj: usize = 0;
            while (jj < p) : (jj += BLOCK_SIZE) {
                
                // Process the block
                var i = ii;
                const i_end = @min(ii + BLOCK_SIZE, m);
                while (i < i_end) : (i += 1) {
                    var k = kk;
                    const k_end = @min(kk + BLOCK_SIZE, n);
                    while (k < k_end) : (k += 1) {
                        const a_val = a_ptr[i * n + k];
                        var j = jj;
                        const j_end = @min(jj + BLOCK_SIZE, p);
                        while (j < j_end) : (j += 1) {
                            result_ptr[i * p + j] += a_val * b_ptr[k * p + j];
                        }
                    }
                }
            }
        }
    }
}

export fn zig_matrix_add(
    a_ptr: [*]const f32, b_ptr: [*]const f32, 
    result_ptr: [*]f32, len: usize
) void {
    for (0..len) |i| {
        result_ptr[i] = a_ptr[i] + b_ptr[i];
    }
}
