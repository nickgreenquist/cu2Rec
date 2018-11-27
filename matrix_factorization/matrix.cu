// Credit: https://github.com/benfred/implicit
#include <stdexcept>
#include <sstream>

#include <cuda_runtime.h>
#include "cublas_v2.h"

#include "matrix.h"

#define CHECK_CUDA(code) { checkCuda((code), __FILE__, __LINE__); }
inline void checkCuda(cudaError_t code, const char *file, int line) {
    if (code != cudaSuccess) {
        std::stringstream err;
        err << "Cuda Error: " << cudaGetErrorString(code) << " (" << file << ":" << line << ")";
        throw std::runtime_error(err.str());
    }
}

namespace cu2rec {
    CudaDenseMatrix::CudaDenseMatrix(int rows, int cols, const float * host_data)
        : rows(rows), cols(cols) {
        CHECK_CUDA(cudaMalloc(&data, rows * cols * sizeof(float)));
        if (host_data) {
            CHECK_CUDA(cudaMemcpy(data, host_data, rows * cols * sizeof(float), cudaMemcpyHostToDevice));
        }
    }

    void CudaDenseMatrix::to_host(float * out) const {
        CHECK_CUDA(cudaMemcpy(out, data, rows * cols * sizeof(float), cudaMemcpyDeviceToHost));
    }

    CudaDenseMatrix::~CudaDenseMatrix() {
        CHECK_CUDA(cudaFree(data));
    }

    CudaCSRMatrix::CudaCSRMatrix(int rows, int cols, int nonzeros,
                                const int * indptr_, const int * indices_, const float * data_)
        : rows(rows), cols(cols), nonzeros(nonzeros) {

        CHECK_CUDA(cudaMalloc(&indptr, (rows + 1) * sizeof(int)));
        CHECK_CUDA(cudaMemcpy(indptr, indptr_, (rows + 1)*sizeof(int), cudaMemcpyHostToDevice));

        CHECK_CUDA(cudaMalloc(&indices, nonzeros * sizeof(int)));
        CHECK_CUDA(cudaMemcpy(indices, indices_, nonzeros * sizeof(int), cudaMemcpyHostToDevice));

        CHECK_CUDA(cudaMalloc(&data, nonzeros * sizeof(float)));
        CHECK_CUDA(cudaMemcpy(data, data_, nonzeros * sizeof(int), cudaMemcpyHostToDevice));
    }

    CudaCSRMatrix::~CudaCSRMatrix() {
        CHECK_CUDA(cudaFree(indices));
        CHECK_CUDA(cudaFree(indptr));
        CHECK_CUDA(cudaFree(data));
    }
}  // namespace cu2rec
