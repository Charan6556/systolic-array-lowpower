#!/bin/bash
# regression.sh - mm_full_test over many seeds, no coverage
# usage: ./regression.sh [num_seeds]      e.g.  ./regression.sh 20
N=${1:-10}
mkdir -p regression_logs
PASS=0; FAIL=0

for SEED in $(seq 1 $N); do
    xrun -64bit -sv -uvm -timescale 1ns/1ps \
         -f filelist.f -top tb_top \
         +UVM_TESTNAME=mm_full_test +UVM_VERBOSITY=UVM_NONE +UVM_NO_RELNOTES \
         -svseed $SEED -access +rwc \
         -l regression_logs/seed_$SEED.log > /dev/null 2>&1
    if grep -q "TEST PASSED" regression_logs/seed_$SEED.log; then
        echo "seed $SEED : PASS"; PASS=$((PASS+1))
    else
        echo "seed $SEED : FAIL"; FAIL=$((FAIL+1))
    fi
done

echo "----------------------------------------"
echo "Regression: $PASS passed, $FAIL failed out of $N seeds"
