#ifndef CU2REC_SGD
#define CU2REC_SGD

#include <cuda.h>

using namespace cu2rec;

__global__ void sgd_update(int *indptr, int *indices, float *P, float *Q, float *P_target, float *Q_target, 
                           float *errors, int n_rows, int n_cols, float *user_bias, float *item_bias,
                           float *user_bias_target, float *item_bias_target);

#endif
