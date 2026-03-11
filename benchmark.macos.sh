#!/bin/bash

# --- 1. Hardware Specification Retrieval ---
echo "Gathering System Specifications..."
MODEL=$(sysctl -n hw.model)
CPU_BRAND=$(sysctl -n machdep.cpu.brand_string)
PHYS_CORES=$(sysctl -n hw.physicalcpu)
LOGIC_CORES=$(sysctl -n hw.logicalcpu)
MEM_BYTES=$(sysctl -n hw.memsize)
MEM_GB=$(echo "$MEM_BYTES / 1024 / 1024 / 1024" | bc)

echo "-------------------------------------------------------"
echo "SYSTEM SPECIFICATIONS"
echo "Model:      $MODEL"
echo "CPU:        $CPU_BRAND"
echo "Cores:      $PHYS_CORES Physical / $LOGIC_CORES Logical"
echo "Memory:     $MEM_GB GB RAM"
echo "-------------------------------------------------------"

# --- 2. Configuration & Compilation ---
BINARY="./nqueen"
SEQ_FRACTION=0.05 
OMP_PATH=$(brew --prefix libomp)
CFLAGS="-Xpreprocessor -fopenmp -I${OMP_PATH}/include"
LDFLAGS="-L${OMP_PATH}/lib -lomp"

mpicc $CFLAGS main.c -o nqueen $LDFLAGS
if [ $? -ne 0 ]; then echo "Build Failed!"; exit 1; fi

# --- 3. Benchmarking Execution ---
echo "| Cores | Exp. Time (s) | Ideal Time | Amdahl Speedup | Analytical Spd | Exp. Speedup |"
echo "---------------------------------------------------------------------------------------"

export OMP_NUM_THREADS=1
T1=$(mpirun -np 1 $BINARY)

calc() { echo "scale=4; $1" | bc -l; }

for P in 1 2 4 8
do
    RAW_OUT=$(mpirun -np $P $BINARY)
    TP=$(echo "$RAW_OUT" | grep -oE '[0-9]+\.[0-9]+')
    
    if [ "$P" -eq 1 ]; then T1=$TP; fi

    IDEAL_T=$(echo "scale=4; $T1 / $P" | bc -l)
    AMDAHL_S=$(echo "scale=4; 1 / ($SEQ_FRACTION + (1 - $SEQ_FRACTION) / $P)" | bc -l)
    EXP_S=$(echo "scale=4; $T1 / $TP" | bc -l)
    ANALYTICAL_S=$(echo "scale=4; $AMDAHL_S * (1 - (0.015 * $P))" | bc -l)

    printf "| %-5s | %-13s | %-10s | %-14s | %-14s | %-12s |\n" \
           "$P" "$TP" "$IDEAL_T" "$AMDAHL_S" "$ANALYTICAL_S" "$EXP_S"
done