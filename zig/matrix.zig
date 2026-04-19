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

    const m_limit = (m / BLOCK_SIZE) * BLOCK_SIZE;
    const n_limit = (n / BLOCK_SIZE) * BLOCK_SIZE;
    const p_limit = (p / BLOCK_SIZE) * BLOCK_SIZE;

    multiplyFullTiles(a_ptr, n, b_ptr, p, result_ptr, m_limit, n_limit, p_limit);

    if (p_limit < p) {
        multiplyRange(a_ptr, n, b_ptr, p, result_ptr, 0, m_limit, 0, n_limit, p_limit, p);
    }

    if (n_limit < n) {
        multiplyRange(a_ptr, n, b_ptr, p, result_ptr, 0, m_limit, n_limit, n, 0, p);
    }

    if (m_limit < m) {
        multiplyRange(a_ptr, n, b_ptr, p, result_ptr, m_limit, m, 0, n, 0, p);
    }
}

fn multiplyFullTiles(
    a_ptr: [*]const f32,
    n: usize,
    b_ptr: [*]const f32,
    p: usize,
    result_ptr: [*]f32,
    m_limit: usize,
    n_limit: usize,
    p_limit: usize,
) void {
    var ii: usize = 0;
    while (ii < m_limit) : (ii += BLOCK_SIZE) {
        var kk: usize = 0;
        while (kk < n_limit) : (kk += BLOCK_SIZE) {
            var jj: usize = 0;
            while (jj < p_limit) : (jj += BLOCK_SIZE) {
                var i: usize = 0;
                while (i < BLOCK_SIZE) : (i += 1) {
                    const row = ii + i;
                    const a_row = a_ptr + row * n;
                    const result_tile = result_ptr + row * p + jj;

                    var k: usize = 0;
                    while (k < BLOCK_SIZE) : (k += 1) {
                        const a_val = a_row[kk + k];
                        const b_tile = b_ptr + (kk + k) * p + jj;

                        for (0..BLOCK_SIZE) |j| {
                            result_tile[j] += a_val * b_tile[j];
                        }
                    }
                }
            }
        }
    }
}

fn multiplyRange(
    a_ptr: [*]const f32,
    n: usize,
    b_ptr: [*]const f32,
    p: usize,
    result_ptr: [*]f32,
    row_start: usize,
    row_end: usize,
    k_start: usize,
    k_end: usize,
    col_start: usize,
    col_end: usize,
) void {
    var i = row_start;
    while (i < row_end) : (i += 1) {
        const a_row = a_ptr + i * n;
        const result_row = result_ptr + i * p;

        var k = k_start;
        while (k < k_end) : (k += 1) {
            const a_val = a_row[k];
            const b_row = b_ptr + k * p;

            var j = col_start;
            while (j < col_end) : (j += 1) {
                result_row[j] += a_val * b_row[j];
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
