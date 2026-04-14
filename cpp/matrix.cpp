// cpp/matrix.cpp
#include "matrix.h"
#include <cstring> // for memset

extern "C" {
    void cpp_matrix_multiply(
        const float* a_ptr, size_t a_rows, size_t a_cols,
        const float* b_ptr, size_t _b_rows, size_t b_cols,
        float* result_ptr
    ) {
        // Zero out the result matrix
        std::memset(result_ptr, 0, a_rows * b_cols * sizeof(float));

        // Optimized i, k, j loop order for cache efficiency
        for (size_t i = 0; i < a_rows; ++i) {
            for (size_t k = 0; k < a_cols; ++k) {
                float a_val = a_ptr[i * a_cols + k];
                for (size_t j = 0; j < b_cols; ++j) {
                    result_ptr[i * b_cols + j] += a_val * b_ptr[k * b_cols + j];
                }
            }
        }
    }
    
    void cpp_matrix_add(
        const float* a_ptr, const float* b_ptr,
        float* result_ptr, size_t len
    ) {
        for (size_t i = 0; i < len; ++i) {
            result_ptr[i] = a_ptr[i] + b_ptr[i];
        }
    }
}
