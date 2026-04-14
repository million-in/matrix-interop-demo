// rust/matrix.rs
#[no_mangle]
pub unsafe extern "C" fn rust_matrix_multiply(
    a_ptr: *const f32,
    _a_rows: usize,
    a_cols: usize,
    b_ptr: *const f32,
    _b_rows: usize,
    b_cols: usize,
    result_ptr: *mut f32,
) {
    let a_rows = _a_rows;
    let b_cols = b_cols;
    let a_cols = a_cols;

    for i in 0..a_rows {
        for j in 0..b_cols {
            let mut sum = 0.0;
            for k in 0..a_cols {
                // Using raw pointer offsets to eliminate all bounds checks
                // and give LLVM a direct path to vectorization.
                sum += *a_ptr.add(i * a_cols + k) * *b_ptr.add(k * b_cols + j);
            }
            *result_ptr.add(i * b_cols + j) = sum;
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
