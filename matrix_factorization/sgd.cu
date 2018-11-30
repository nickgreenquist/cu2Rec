#include <stdio.h>

#include "config.h"

/* To index element (i,j) of a 2D array stored as 1D */
#define index(i, j, N)  ((i)*(N)) + (j)

/*************************/
/* CURAND INITIALIZATION */
/*************************/
__global__ void initCurand(curandState *state, unsigned long seed, int n_rows){
    int x = blockDim.x * blockIdx.x + threadIdx.x;
    if(x < n_rows && x < 1000) {
        curand_init(seed, x, 0, &state[x]);
    }
}

__global__ void sgd_update(int *indptr, int *indices, float *P, float *Q, float *P_target, float *Q_target, 
                           float *errors, int n_rows, int n_cols, float *user_bias, float *item_bias,
                           float *user_bias_target, float *item_bias_target, curandState *my_curandstate) {
    // One thread per user
    int x = blockDim.x * blockIdx.x + threadIdx.x;
    if(x < n_rows) {
        
        // pick a random y_i
        int low = indptr[x];
        int high = indptr[x+1];
        float myrandf = curand_uniform(&my_curandstate[x % 1000]);
        myrandf *= (high - low + 0.999999);
        myrandf += low;
        int y_i = (int)truncf(myrandf);

        int y = indices[y_i];
        for(int f = 0; f < config::n_factors; ++f) {
            int p_index = index(x, f, config::n_factors);
            int q_index = index(y, f, config::n_factors);

            // Update P
            P_target[p_index] = P[p_index] + config::learning_rate * (errors[y_i] * Q[q_index] - config::P_reg * P[p_index]);

            // Only update Q if train flag is true
            if(config::is_train) {
                Q_target[q_index] = Q[q_index] + config::learning_rate * (errors[y_i] * P[p_index] - config::Q_reg * Q[q_index]);
            }
        }

        // update biases
        user_bias_target[x] = user_bias[x] + config::learning_rate * (errors[y_i] - config::user_bias_reg * user_bias[x]);
        if(config::is_train) {
            item_bias_target[y] = item_bias[y] + config::learning_rate * (errors[y_i] - config::item_bias_reg * item_bias[y]);
        }

        // TODO: remove old loop over all items once we agree on one item per user SGD
        // Loop over all the ratings of the user
        // for(int y_i = indptr[x]; y_i < indptr[x + 1]; ++y_i) {
        // }
    }
}