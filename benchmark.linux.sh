#!/bin/bash

# --- 1. Hardware Specification Retrieval (Arch Linux) ---
echo "Gathering System Specifications..."
CPU_MODEL=$(lscpu | grep "Model name:" | sed 's/Model name:[[:space:]]*//')
PHYS_CORES=$(lscpu -p | grep -v '^#' | sort -u -t, -k2,2 | wc -l)
LOGIC_CORES=$(lscpu -p | grep -v '^#' | wc -l)
MEM_GB=$(free -g | awk '/^Mem:/{print $2}')

echo "-------------------------------------------------------"
echo "SYSTEM SPECIFICATIONS"
echo "OS:         Arch Linux"
echo "CPU:        $CPU_MODEL"
echo "Cores:      $PHYS_CORES Physical / $LOGIC_CORES Logical"
echo "Memory:     $MEM_GB GB RAM"
echo "-------------------------------------------------------"

# --- 2. Configuration & Compilation ---
BINARY="./nqueen"
SEQ_FRACTION=0.05 

# Standard GCC/MPI flags for Linux
echo "Compiling..."
mpicc -O3 -fopenmp main.c -o nqueen -lm

if [ $? -ne 0 ]; then
    echo "Compilation failed. Make sure 'openmpi' and 'base-devel' are installed."
    exit 1
fi

# --- 3. Benchmarking Execution ---
echo "---------------------------------------------------------------------------------------"
echo "| Cores | Exp. Time (s) | Ideal Time | Amdahl Speedup | Analytical Spd | Exp. Speedup |"
echo "---------------------------------------------------------------------------------------"

# 1. Get Sequential Baseline (1 thread)
export OMP_NUM_THREADS=1
T1=$(mpirun --allow-run-as-root -np 1 $BINARY)

# Helper function for math
calc() { echo "scale=4; $1" | bc -l; }

for P in 1 2 4 8
do
    # Run Experimental (P MPI ranks)
    TP=$(mpirun --allow-run-as-root -np $P $BINARY)
    
    # Mathematical Models
    IDEAL_T=$(calc "$T1 / $P")
    AMDAHL_S=$(calc "1 / ($SEQ_FRACTION + (1 - $SEQ_FRACTION) / $P)")
    EXP_S=$(calc "$T1 / $TP")
    
    # Analytical: Amdahl minus a simplified communication penalty
    # T_comm increases slightly with more ranks (0.015 is an estimated penalty factor)
    ANALYTICAL_S=$(calc "$AMDAHL_S * (1 - (0.015 * $P))")

    printf "| %-5s | %-13s | %-10s | %-14s | %-14s | %-12s |\n" \
           "$P" "$TP" "$IDEAL_T" "$AMDAHL_S" "$ANALYTICAL_S" "$EXP_S"
done

echo "---------------------------------------------------------------------------------------"