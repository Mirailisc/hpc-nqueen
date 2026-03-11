#include <stdio.h>
#include <stdbool.h>
#include <mpi.h>
#include <omp.h>

#define N 16  // Increased for a noticeable parallel workload

// Check if a queen can be placed on board[row][col]
bool isSafe(int board[N][N], int row, int col) {
    int i, j;
    // Check this row on left side
    for (i = 0; i < col; i++)
        if (board[row][i]) return false;

    // Check upper diagonal on left side
    for (i = row, j = col; i >= 0 && j >= 0; i--, j--)
        if (board[i][j]) return false;

    // Check lower diagonal on left side
    for (i = row, j = col; j >= 0 && i < N; i++, j--)
        if (board[i][j]) return false;

    return true;
}

// Sequential solver for the remaining columns
int solveNQ_seq(int board[N][N], int col) {
    // Base case: all queens are placed
    if (col >= N) {
        return 1; 
    }

    int count = 0;
    for (int i = 0; i < N; i++) {
        if (isSafe(board, i, col)) {
            board[i][col] = 1; // Place queen
            
            // Recursively count solutions
            count += solveNQ_seq(board, col + 1); 
            
            board[i][col] = 0; // Backtrack
        }
    }
    return count;
}

int main(int argc, char** argv) {
    int rank, size;
    
    // Initialize MPI environment with thread support
    int provided;
    MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &provided);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    if (N <= 1) {
        if (rank == 0) printf("Total solutions found: 1\n");
        MPI_Finalize();
        return 0;
    }

    double start_time = MPI_Wtime();
    int local_solutions = 0;

    // 1. MPI Mapping: Distribute rows for the 1st column (col 0) cyclically
    for (int i = rank; i < N; i += size) {
        
        // 2. OpenMP Mapping: Parallelize rows for the 2nd column (col 1)
        #pragma omp parallel for reduction(+:local_solutions)
        for (int j = 0; j < N; j++) {
            
            // Create a thread-local board to prevent data corruption during backtracking
            int thread_board[N][N] = {0};
            thread_board[i][0] = 1; // Place the 1st queen assigned by MPI

            // Check if the 2nd queen placement is safe
            if (isSafe(thread_board, j, 1)) {
                thread_board[j][1] = 1; // Place the 2nd queen
                
                // 3. Sequential Search: Solve the rest of the board locally
                local_solutions += solveNQ_seq(thread_board, 2);
            }
        }
    }

    // 4. Communication/Reduction: Sum up all local counts to the master process
    int total_solutions = 0;
    MPI_Reduce(&local_solutions, &total_solutions, 1, MPI_INT, MPI_SUM, 0, MPI_COMM_WORLD);

    if (rank == 0) {
        double end_time = MPI_Wtime();
        printf("Total solutions found for %dx%d board: %d\n", N, N, total_solutions);
        printf("Time taken: %f seconds\n", end_time - start_time);
    }

    MPI_Finalize();
    return 0;
}
