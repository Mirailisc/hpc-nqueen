#include <stdio.h>
#include <stdbool.h>
#include <time.h>

#define N 16

// Check if a queen can be placed on board[row][col]
bool isSafe(int board[N][N], int row, int col)
{
    for (int i = 0; i < col; i++)
        if (board[row][i])
            return false;

    for (int i = row, j = col; i >= 0 && j >= 0; i--, j--)
        if (board[i][j])
            return false;

    for (int i = row, j = col; j >= 0 && i < N; i++, j--)
        if (board[i][j])
            return false;

    return true;
}

// Recursive function to count all solutions
long long countSolutions(int board[N][N], int col)
{
    if (col >= N)
        return 1;

    long long count = 0;
    for (int i = 0; i < N; i++)
    {
        if (isSafe(board, i, col))
        {
            board[i][col] = 1;
            count += countSolutions(board, col + 1);
            board[i][col] = 0;
        }
    }
    return count;
}

int main()
{
    int board[N][N] = {0};

    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    long long total = countSolutions(board, 0);

    clock_gettime(CLOCK_MONOTONIC, &end);

    double time_taken = (double)(end.tv_sec - start.tv_sec) +
                        (double)(end.tv_nsec - start.tv_nsec) / 1e9;

    fprintf(stderr, "N=%d | Solutions: %lld\n", N, total);
    printf("%f\n", time_taken);

    return 0;
}