#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <mpi.h>
#include <omp.h>

// Check if a queen can be placed on board[row][col]
bool isSafe(int N, int board[N][N], int row, int col)
{
    int i, j;
    // Check this row on left side
    for (i = 0; i < col; i++)
        if (board[row][i])
            return false;

    // Check upper diagonal on left side
    for (i = row, j = col; i >= 0 && j >= 0; i--, j--)
        if (board[i][j])
            return false;

    // Check lower diagonal on left side
    for (i = row, j = col; j >= 0 && i < N; i++, j--)
        if (board[i][j])
            return false;

    return true;
}

// Format the board and write to the temp file
void write_board_to_temp(int N, int board[N][N], FILE *temp_file)
{
    // Allocate buffer for a single solution formatted as: ["..Q.", "Q...", ...]
    int max_len = N * (N + 4) + 10;
    char *buffer = (char *)malloc(max_len);
    if (!buffer)
        return;

    int offset = 0;
    offset += sprintf(buffer + offset, "[");
    for (int i = 0; i < N; i++)
    {
        offset += sprintf(buffer + offset, "\"");
        for (int j = 0; j < N; j++)
        {
            offset += sprintf(buffer + offset, "%c", board[i][j] ? 'Q' : '.');
        }
        offset += sprintf(buffer + offset, "\"%s", (i == N - 1) ? "" : ",");
    }
    offset += sprintf(buffer + offset, "]\n");

// Thread-safe file write
#pragma omp critical
    {
        fprintf(temp_file, "%s", buffer);
    }

    free(buffer);
}

// Sequential solver for the remaining columns
int solveNQ_seq(int N, int board[N][N], int col, FILE *temp_file)
{
    // Base case: all queens are placed
    if (col >= N)
    {
        write_board_to_temp(N, board, temp_file);
        return 1;
    }

    int count = 0;
    for (int i = 0; i < N; i++)
    {
        if (isSafe(N, board, i, col))
        {
            board[i][col] = 1; // Place queen

            // Recursively count solutions
            count += solveNQ_seq(N, board, col + 1, temp_file);

            board[i][col] = 0; // Backtrack
        }
    }
    return count;
}

int main(int argc, char **argv)
{
    int rank, size;
    int N = 0;

    // Initialize MPI environment with thread support
    int provided;
    MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &provided);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    // 1. Read input from file (Rank 0 reads, then broadcasts to others)
    if (rank == 0)
    {
        FILE *in_file = fopen("input.txt", "r");
        if (!in_file)
        {
            printf("Error: Could not open input.txt. Please create it and write 'N = 4' inside.\n");
            N = -1;
        }
        else
        {
            // Try parsing "N = X"
            if (fscanf(in_file, "N = %d", &N) != 1)
            {
                rewind(in_file);
                // Fallback: try reading just the integer "X"
                if (fscanf(in_file, "%d", &N) != 1)
                {
                    N = -1;
                }
            }
            fclose(in_file);
        }
    }

    // Broadcast N to all processes
    MPI_Bcast(&N, 1, MPI_INT, 0, MPI_COMM_WORLD);

    if (N <= 0)
    {
        MPI_Finalize();
        return 1;
    }

    double start_time = MPI_Wtime();
    int local_solutions = 0;

    // Open a temporary file specific to this MPI process
    char temp_filename[256];
    sprintf(temp_filename, "temp_rank_%d.txt", rank);
    FILE *temp_file = fopen(temp_filename, "w");

    if (temp_file)
    {
        // MPI Mapping: Distribute rows for the 1st column (col 0) cyclically
        for (int i = rank; i < N; i += size)
        {

// OpenMP Mapping: Parallelize rows for the 2nd column (col 1)
#pragma omp parallel for reduction(+ : local_solutions)
            for (int j = 0; j < N; j++)
            {

                int thread_board[N][N];
                memset(thread_board, 0, sizeof(int) * N * N);

                thread_board[i][0] = 1; // Place the 1st queen

                if (isSafe(N, thread_board, j, 1))
                {
                    thread_board[j][1] = 1; // Place the 2nd queen

                    // Solve the rest of the board locally
                    local_solutions += solveNQ_seq(N, thread_board, 2, temp_file);
                }
            }
        }
        fclose(temp_file);
    }

    // Wait for all MPI processes to finish computing and writing their temp files
    MPI_Barrier(MPI_COMM_WORLD);

    int total_solutions = 0;
    MPI_Reduce(&local_solutions, &total_solutions, 1, MPI_INT, MPI_SUM, 0, MPI_COMM_WORLD);

    // Rank 0 merges all temporary files into the final format
    if (rank == 0)
    {
        FILE *out_file = fopen("output.txt", "w");
        if (out_file)
        {
            fprintf(out_file, "[");
            bool first_solution = true;

            // Read through each rank's temp file
            for (int r = 0; r < size; r++)
            {
                sprintf(temp_filename, "temp_rank_%d.txt", r);
                FILE *in_temp = fopen(temp_filename, "r");
                if (in_temp)
                {
                    char line[4096];
                    while (fgets(line, sizeof(line), in_temp))
                    {
                        // Remove the newline character added during temp write
                        line[strcspn(line, "\n")] = 0;
                        if (strlen(line) > 0)
                        {
                            if (!first_solution)
                            {
                                fprintf(out_file, ",");
                            }
                            fprintf(out_file, "%s", line);
                            first_solution = false;
                        }
                    }
                    fclose(in_temp);
                }
                // Clean up the temporary file
                remove(temp_filename);
            }
            fprintf(out_file, "]\n");
            fclose(out_file);

            double end_time = MPI_Wtime();
            printf("Total solutions found for %dx%d board: %d\n", N, N, total_solutions);
            printf("Time taken: %f seconds\n", end_time - start_time);
        }
        else
        {
            printf("Error: Could not create output.txt\n");
        }
    }

    MPI_Finalize();
    return 0;
}