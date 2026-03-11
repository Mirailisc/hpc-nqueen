#!/bin/bash

# --- 1. Hardware Specification Retrieval (Arch Linux) ---
echo "Gathering System Specifications..."
CPU_MODEL=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
PHYS_CORES=$(lscpu -p | grep -v '^#' | sort -u -t, -k2,2 | wc -l)
LOGIC_CORES=$(lscpu -p | grep -v '^#' | wc -l)
MEM_GB=$(free -m | awk '/^Mem:/{printf "%.1f", $2/1024}')

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

echo "Compiling..."
mpicc -O3 -fopenmp main.c -o nqueen -lm

if [ $? -ne 0 ]; then
    echo "Compilation failed. Make sure 'openmpi' and 'base-devel' are installed."
    exit 1
fi

# Helper function for math
calc() { echo "scale=4; $1" | bc -l; }

# --- 3. Benchmarking Execution ---
echo "---------------------------------------------------------------------------------------"
echo "| Cores | Exp. Time (s) | Ideal Time | Amdahl Speedup | Analytical Spd | Exp. Speedup |"
echo "---------------------------------------------------------------------------------------"

# 1. Get Sequential Baseline
# Added --use-hwthread-cpus and --oversubscribe for safety
# Use 'grep' or 'awk' to ensure we ONLY grab the numeric part of the output
T1=$(mpirun --allow-run-as-root --use-hwthread-cpus -np 1 $BINARY | grep -oE '^[0-9.]+' | tail -n 1)

for P in 1 2 4 8
do
    # Run with hwthread support to allow 8 cores
    TP=$(mpirun --allow-run-as-root --use-hwthread-cpus -np $P $BINARY | grep -oE '^[0-9.]+' | tail -n 1)
    
    # Check if TP is empty to prevent bc errors
    if [ -z "$TP" ]; then
        TP="0.00"
        EXP_S="N/A"
    else
        # Mathematical Models
        IDEAL_T=$(calc "$T1 / $P")
        AMDAHL_S=$(calc "1 / ($SEQ_FRACTION + (1 - $SEQ_FRACTION) / $P)")
        EXP_S=$(calc "$T1 / $TP")
        ANALYTICAL_S=$(calc "$AMDAHL_S * (1 - (0.015 * $P))")
    fi

    printf "| %-5s | %-13s | %-10s | %-14s | %-14s | %-12s |\n" \
           "$P" "$TP" "$IDEAL_T" "$AMDAHL_S" "$ANALYTICAL_S" "$EXP_S"
done

echo "---------------------------------------------------------------------------------------"