// rust/matrix.rs
#[no_mangle]
pub unsafe extern "C" fn rust_matrix_multiply(
    a_ptr: *const f32,
    a_rows: usize,
    a_cols: usize,
    b_ptr: *const f32,
    _b_rows: usize,
    b_cols: usize,
    result_ptr: *mut f32,
) {
    // Zero result matrix
    std::ptr::write_bytes(result_ptr, 0, a_rows * b_cols);

    // Cache-friendly i, k, j loop order
    for i in 0..a_rows {
        for k in 0..a_cols {
            // Pre-fetch a_val to maximize SIMD optimization in inner loop
            let a_val = *a_ptr.add(i * a_cols + k);
            for j in 0..b_cols {
                *result_ptr.add(i * b_cols + j) += a_val * *b_ptr.add(k * b_cols + j);
            }
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn rust_matrix_add(
    a_ptr: *const f32,
    b_ptr: *const f32,
    result_ptr: *mut f32,
    len: usize,
) {
    for i in 0..len {
        *result_ptr.add(i) = *a_ptr.add(i) + *b_ptr.add(i);
    }
}
