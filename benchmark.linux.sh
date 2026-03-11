#!/bin/bash

# --- 1. Dependency Check ---
# Ubuntu requires build-essential and the specific MPI development headers.
for cmd in mpicc mpirun bc; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is not installed."
        echo "Please run: sudo apt update && sudo apt install build-essential openmpi-bin libopenmpi-dev bc"
        exit 1
    fi
done

# --- 2. Hardware Specification Retrieval ---
echo "Gathering System Specifications..."
# Distro-agnostic core detection
CPU_MODEL=$(grep -m 1 "model name" /proc/cpuinfo | cut -d':' -f2 | xargs)
PHYS_CORES=$(grep -P '^core id' /proc/cpuinfo | sort -u | wc -l)
LOGIC_CORES=$(nproc)
MEM_GB=$(free -g | awk '/^Mem:/{print $2}')

# Check if Hyperthreading is active
HT_STATUS="Disabled"
[ "$PHYS_CORES" -lt "$LOGIC_CORES" ] && HT_STATUS="Enabled"

echo "-------------------------------------------------------"
echo "SYSTEM SPECIFICATIONS"
echo "OS:         Ubuntu (Linux)"
echo "CPU:        $CPU_MODEL"
echo "Cores:      $PHYS_CORES Physical / $LOGIC_CORES Logical"
echo "HT/SMT:     $HT_STATUS"
echo "Memory:     ${MEM_GB} GB RAM"
echo "-------------------------------------------------------"

# --- 3. Configuration & Compilation ---
BINARY="./nqueen"
SEQ_FRACTION=0.05

# Optimization: Ensure we are using 1 OpenMP thread per MPI process 
# to avoid CPU contention on your 8 cores.
export OMP_NUM_THREADS=1

echo "Compiling with OpenMP and Math support..."
if [ ! -f "main.c" ]; then
    echo "Error: main.c not found in the current directory!"
    exit 1
fi

mpicc -O3 -fopenmp main.c -o nqueen -lm

if [ $? -ne 0 ]; then
    echo "Compilation failed."
    exit 1
fi

calc() { echo "scale=4; $1" | bc -l; }

extract_num() {
    # Grabs the last numeric value (integer or decimal) from the output
    echo "$1" | grep -oE '[0-9]*\.?[0-9]+' | tail -n 1
}

# --- 4. Benchmarking Execution ---
# Flag explanation:
# --bind-to core: Ensures each MPI process stays on its own physical core.
# --oversubscribe: Safety flag to prevent crashes if testing P > 8.
MPI_FLAGS="--bind-to core --oversubscribe"

echo "---------------------------------------------------------------------------------------"
echo "| Cores | Exp. Time (s) | Ideal Time | Amdahl Speedup | Analytical Spd | Exp. Speedup |"
echo "---------------------------------------------------------------------------------------"

# Get Sequential Baseline
T1_RAW=$(mpirun $MPI_FLAGS -np 1 $BINARY | tail -n 1)
T1=$(extract_num "$T1_RAW")

if [ -z "$T1" ] || [ $(echo "$T1 == 0" | bc) -eq 1 ]; then
    echo "Error: Could not capture baseline execution time. Check your code output."
    exit 1
fi

for P in 1 2 4 8
do
    # Run Benchmark
    TP_RAW=$(mpirun $MPI_FLAGS -np $P $BINARY | tail -n 1)
    TP=$(extract_num "$TP_RAW")
    
    if [ -z "$TP" ]; then
        printf "| %-5s | %-13s | %-10s | %-14s | %-14s | %-12s |\n" "$P" "FAILED" "-" "-" "-" "-"
        continue
    fi

    # Mathematical Comparisons
    IDEAL_T=$(calc "$T1 / $P")
    AMDAHL_S=$(calc "1 / ($SEQ_FRACTION + (1 - $SEQ_FRACTION) / $P)")
    EXP_S=$(calc "$T1 / $TP")
    
    # Analytical: Factors in a ~1.5% overhead per added core for communication
    ANALYTICAL_S=$(calc "$AMDAHL_S * (1 - (0.015 * $P))")

    printf "| %-5s | %-13s | %-10s | %-14s | %-14s | %-12s |\n" \
           "$P" "$TP" "$IDEAL_T" "$AMDAHL_S" "$ANALYTICAL_S" "$EXP_S"
done

echo "---------------------------------------------------------------------------------------"
echo "Benchmark Complete."