#include <stdio.h>
#include <stdbool.h>

#define N 16

void printBoard(int board[N][N])
{
    for (int i = 0; i < N; i++)
    {
        for (int j = 0; j < N; j++)
            printf(" %s ", board[i][j] ? "Q" : ".");
        printf("\n");
    }
    printf("\n");
}

// Check if a queen can be placed on board[row][col]
bool isSafe(int board[N][N], int row, int col)
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

bool solveNQ(int board[N][N], int col)
{
    // Base case: If all queens are placed
    if (col >= N)
        return true;

    for (int i = 0; i < N; i++)
    {
        if (isSafe(board, i, col))
        {
            board[i][col] = 1; // Place queen

            if (solveNQ(board, col + 1))
                return true;

            board[i][col] = 0; // Backtrack
        }
    }
    return false;
}

int main()
{
    int board[N][N] = {0};

    if (solveNQ(board, 0) == false)
    {
        printf("Solution does not exist");
        return 0;
    }

    printBoard(board);
    return 0;
}