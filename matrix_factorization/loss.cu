#include <stdexcept>
#include <sstream>
#include <iostream>     // std::cout
#include <math.h>       /* pow */

#include <cuda_runtime.h>
#include "cublas_v2.h"

#include "matrix.h"

#define index(i, j, N)  ((i)*(N)) + (j)
#define warp_size 32 //TODO: we need to get device props

using namespace cu2rec;

// PARALLEL
extern __shared__ float biases[];
__global__ void loss_kernel(int factors, int user_count, int item_count, const float * P, const float * Q, const int * indptr, 
                            const int * indices, const float * data, float * error, float * user_bias, float * item_bias, float global_bias) {
    float* s_user_bias = (float*)biases;
    float* s_item_bias = (float*)&s_user_bias[user_count];

    // use first warp to load in user_biases
    if(threadIdx.x < warp_size) {
        for(int i = 0; i < user_count; i += warp_size) {
            s_user_bias[i] = user_bias[i];
        }
    }
    // use second warp to load in item_biases
    if(threadIdx.x >= warp_size && threadIdx.x < 2*warp_size) {
        for(int i = 0; i < item_count; i += warp_size) {
            s_item_bias[i] = item_bias[i];
        }
    }
    // sync all threads before accessing any shared memory
    __syncthreads();
    
    // One thread per user
    int u = blockDim.x * blockIdx.x + threadIdx.x;
    if(u < user_count) {
        // get this user's factors into closer memory
        const float * p = &P[u * factors];
        const float ub = s_user_bias[u];

        for (int i = indptr[u]; i < indptr[u + 1]; ++i) {
            // get this item's factors
            int item_id = indices[i];
            const float * Qi = &Q[item_id * factors];

            // calculate predicted rating
            float pred = global_bias + ub + s_item_bias[item_id];
            for (int f = 0; f < factors; f++)
                pred += Qi[f]*p[f];

            // set the error value for this rating: rating - pred
            error[i] = data[i] - pred;
        }
    }
}

__global__ void total_loss_kernel(float *errors, float *losses, int n_errors, int current_iter, float discount) {
    int x = blockDim.x * blockIdx.x + threadIdx.x;
    for(int i = n_errors / 2; i > 0; i >>= 1) {
        __syncthreads();
        if(x < i) {
            if(i == n_errors / 2) {
                // First iteration
                // Need to square the errors
                errors[x] = pow(errors[x], 2) + pow(errors[x + i], 2);
            } else {
                errors[x] += errors[x + i];
            }
        }
    }
    if(x == 0) {
        // Doing this atomic, in case we want to parallelize this calculation using streams
        atomicAdd(&losses[current_iter], discount * errors[0]);
    }
}

void calculate_loss_gpu(CudaDenseMatrix* P_d, CudaDenseMatrix* Q_d, int factors, int user_count, int item_count, int num_ratings, 
                        CudaCSRMatrix* matrix, float * error_d, float * user_bias,  float * item_bias, float global_bias) {
    int n_threads = 32;
    dim3 dimBlock(n_threads);
    dim3 dimGrid(user_count / n_threads + 1);
    float shared_mem_size = (user_count + item_count) * sizeof(float);
    loss_kernel<<<dimGrid, dimBlock, shared_mem_size>>>(
        factors, user_count, item_count, P_d->data, Q_d->data,
        matrix->indptr, matrix->indices, matrix->data, error_d,
        user_bias, item_bias, global_bias);
    cudaError_t lastError = cudaGetLastError();
    if(cudaSuccess != lastError) {
        printf("ERROR: %s\n", cudaGetErrorName(lastError));
    }
}
