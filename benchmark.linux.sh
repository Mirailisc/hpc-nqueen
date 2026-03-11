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

# 1. Get Sequential Baseline (1 thread) 
# We use tail -n 1 to capture only the last line (the raw time)
T1_RAW=$(mpirun --allow-run-as-root -np 1 $BINARY)
T1=$(echo "$T1_RAW" | tail -n 1)

for P in 1 2 4 8
do
    # Run and grab ONLY the last line (the numeric time)
    TP_RAW=$(mpirun --allow-run-as-root -np $P $BINARY)
    TP=$(echo "$TP_RAW" | tail -n 1)
    
    # Mathematical Models
    IDEAL_T=$(calc "$T1 / $P")
    AMDAHL_S=$(calc "1 / ($SEQ_FRACTION + (1 - $SEQ_FRACTION) / $P)")
    EXP_S=$(calc "$T1 / $TP")
    
    # Analytical: Amdahl minus a simplified communication penalty
    ANALYTICAL_S=$(calc "$AMDAHL_S * (1 - (0.015 * $P))")

    printf "| %-5s | %-13s | %-10s | %-14s | %-14s | %-12s |\n" \
           "$P" "$TP" "$IDEAL_T" "$AMDAHL_S" "$ANALYTICAL_S" "$EXP_S"
done

echo "---------------------------------------------------------------------------------------"