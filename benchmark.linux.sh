#!/bin/bash

# Hardware Specification Retrieval
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

# Configuration & Compilation
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

# Helper function to extract ONLY the decimal/number from a string
extract_num() {
    echo "$1" | grep -oE '[0-9]+\.[0-9]+|[0-9]+' | head -n 1
}

# Benchmarking Execution
echo "---------------------------------------------------------------------------------------"
echo "| Cores | Exp. Time (s) | Ideal Time | Amdahl Speedup | Analytical Spd | Exp. Speedup |"
echo "---------------------------------------------------------------------------------------"

# Get Sequential Baseline (1 thread) 
# Using --use-hwthread-cpus to prevent MPI slot errors on logical cores
T1_RAW=$(mpirun --allow-run-as-root --use-hwthread-cpus -np 1 $BINARY | tail -n 1)
T1=$(extract_num "$T1_RAW")

# Check if T1 was captured correctly
if [ -z "$T1" ]; then
    echo "Error: Could not capture execution time for P=1. Check binary output."
    exit 1
fi

for P in 1 2 4 8
do
    # Run and grab the numeric time
    TP_RAW=$(mpirun --allow-run-as-root --use-hwthread-cpus -np $P $BINARY | tail -n 1)
    TP=$(extract_num "$TP_RAW")
    
    if [ -z "$TP" ]; then
        # Skip calculation if TP is empty
        printf "| %-5s | %-13s | %-10s | %-14s | %-14s | %-12s |\n" "$P" "FAILED" "-" "-" "-" "-"
        continue
    fi

    # Mathematical Models
    IDEAL_T=$(calc "$T1 / $P")
    AMDAHL_S=$(calc "1 / ($SEQ_FRACTION + (1 - $SEQ_FRACTION) / $P)")
    EXP_S=$(calc "$T1 / $TP")
    
    # Analytical: Amdahl minus a simplified communication/scaling penalty
    ANALYTICAL_S=$(calc "$AMDAHL_S * (1 - (0.015 * $P))")

    printf "| %-5s | %-13s | %-10s | %-14s | %-14s | %-12s |\n" \
           "$P" "$TP" "$IDEAL_T" "$AMDAHL_S" "$ANALYTICAL_S" "$EXP_S"
done

echo "---------------------------------------------------------------------------------------"