#include <sstream>
#include <vector>

#include "util.h"

using namespace std;

// File read and write utils

/** Reads in a CSV file of ratings. The file needs to be structured in the format of
 * `userId,itemId,rating` and needs to have a header file. The userId and itemId must
 * be sequential and start from 1. It also assumes that the number of users and the
 * number of items are fixed, and are equal to the maximum user id and maximum
 * integer id respectively. Those, and the global bias (mean), are assigned to their
 * given pointers.
 */
std::vector<Rating> readCSV(std::string filename, int *rows, int *cols, float *global_bias) {
    int max_row = 0;
    int max_col = 0;
    double sum_ratings = 0;
    std::ifstream ratingsFile(filename);
    std::vector<Rating> ratings;

    if (ratingsFile.is_open()){
        int userID, itemID;
        float rating;
        char delimiter;
        // Read the file line by line and skip the header
        ratingsFile.ignore(1000, '\n');
        while(ratingsFile >> userID >> delimiter >> itemID >> delimiter >> rating) {
            ratings.push_back({userID - 1, itemID - 1, rating});
            max_row = std::max(userID, max_row);
            max_col = std::max(itemID, max_col);
            sum_ratings += rating;
        }
        *rows = max_row;
        *cols = max_col;
        *global_bias = sum_ratings / (1.0 * ratings.size());
        return ratings;
    }
    else{
        std::cerr<<"ERROR: The file isnt open.\n";
        return ratings;
    }
}

/** Reads in a 2D float array that is saved as a CSV file.
 * The 2D float array gets converted into a 1D array in row-major
 * format, and the number of rows and columns get put into their
 * respective pointers.
 */
float* read_array(const char *file_path, int *n_rows_ptr, int *n_cols_ptr) {
    std::ifstream array_file(file_path);
    vector<float> nums;
    int n_rows = 0;
    int n_cols = 0;
    if(array_file.is_open()) {
        std::string line;
        while(getline(array_file, line)) {
            std::stringstream line_stream(line);
            while(getline(line_stream, line, ',')) {
                float num = std::stof(line);
                nums.push_back(num);
                n_cols += 1;
            }
            n_rows += 1;
        }
    } else {
        return nullptr;
    }
    float *num_arr = new float[nums.size()];
    std::copy(nums.begin(), nums.end(), num_arr);
    *n_rows_ptr = n_rows;
    *n_cols_ptr = n_cols;
    return num_arr;
}

float* read_array(const char *file_path) {
    int n_rows, n_cols;
    return read_array(file_path, &n_rows, &n_cols);
}

/** Writes in a 2D float array (that is held as a 1D array in memory)
 * to a CSV file.
 */
void writeCSV(char *file_path, float *data, int rows, int cols) {
    FILE *fp;
    fp = fopen(file_path, "w");
    for(int i = 0; i < rows; i++) {
        for(int j = 0; j < cols - 1; j++) {
            fprintf(fp, "%f,", data[index(i, j, cols)]);
        }
        fprintf(fp, "%f", data[index(i, cols - 1, cols)]);
        fprintf(fp, "\n");
    }
    fclose(fp);
}

void writeToFile(string parent_dir, string base_filename, string extension, string component, float *data, int rows, int cols, int factors) {
    char filename [255];
    sprintf(filename, "%s/%s_f%d_%s.%s", parent_dir.c_str(), base_filename.c_str(), factors, component.c_str(), extension.c_str());
    writeCSV(filename, data, rows, cols);
}

// Print utils

void printRating(Rating r){
    std::cout << r.userID << "  "<< r.itemID <<"  "<< r.rating << "\n";
}

void printCSV(std::vector<Rating> *ratings) {
    // Print the vector
    std::cout  << "UserID" << "   ItemID" << "   Rating\n";
    for (int x(0); x < ratings->size(); ++x){
        printRating(ratings->at(x));
    }
}

// Array and matrix utils

/** Initializes a normally distributed array with the given mean and the
 * given standard deviation (scaled down by n_factors).
 */
float* initialize_normal_array(int size, int n_factors, float mean, float stddev, int seed) {
    mt19937 generator(seed);
    normal_distribution<float> distribution(mean, stddev / n_factors);
    float *array = new float[size];
    for(int i = 0; i < size; ++i) {
        array[i] = distribution(generator);
    }
    return array;
}

float* initialize_normal_array(int size, int n_factors, float mean, float stddev) {
    return initialize_normal_array(size, n_factors, mean, stddev, 42);
}

float* initialize_normal_array(int size, int n_factors, int seed) {
    return initialize_normal_array(size, n_factors, 0, 1, seed);
}

float *initialize_normal_array(int size, int n_factors) {
    return initialize_normal_array(size, n_factors, 0, 1);
}

/** Creates a CUDA sparse matrix from the given ratings.
 * It stores the data in a manner that makes it easily accessible by row (ie user)
 * https://en.wikipedia.org/wiki/Sparse_matrix#Compressed_sparse_row_(CSR,_CRS_or_Yale_format)
 * If there is a user with no ratings (ie, a missing userId), it will be included in the matrix
 * as repeated values in indptr.
 */
cu2rec::CudaCSRMatrix* createSparseMatrix(std::vector<Rating> *ratings, int rows, int cols) {
    std::vector<int> indptr_vec;
    int *indices = new int[ratings->size()];
    float *data = new float[ratings->size()];
    int lastUser = -1;
    for(int i = 0; i < ratings->size(); ++i) {
        Rating r = ratings->at(i);
        if(r.userID != lastUser) {
            while(lastUser != r.userID) {
                indptr_vec.push_back(i);
                lastUser++;
            }
        }
        indices[i] = r.itemID;
        data[i] = r.rating;
    }
    indptr_vec.push_back(ratings->size());
    int *indptr = indptr_vec.data();

    // Create the Sparse Matrix
    const int *indptr_c = const_cast<const int*>(indptr);
    const int *indices_c = const_cast<const int*>(indices);
    const float *data_c = const_cast<const float*>(data);
    cu2rec::CudaCSRMatrix* matrix = new cu2rec::CudaCSRMatrix(rows, cols, (int)(ratings->size()), indptr_c, indices_c, data_c);
    cudaDeviceSynchronize();

    return matrix;
}

/** Gets the total number of free bytes in the GPU memory.
 * Useful for debugging.
 */
size_t getFreeBytes(const int where, size_t *total_bytes) {
    size_t free_bytes;

    cudaError_t err = cudaMemGetInfo(&free_bytes, total_bytes);
    if (err != cudaSuccess)
    {
        cout << "getFreeBytes: call index " << where
            << ": cudaMemGetInfo returned the error: " << cudaGetErrorString(err) << endl;
        exit(1);
    }
    return free_bytes;
}

/** Convenience device function for calculating predictions.
 */
__device__ float get_prediction(int factors, const float *p, const float *q, float user_bias, float item_bias, float global_bias) {
        float pred = global_bias + user_bias + item_bias;
        for (int f = 0; f < factors; f++)
            pred += q[f]*p[f];
        return pred;
}

