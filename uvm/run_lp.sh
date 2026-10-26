#!/bin/bash
# run_lp.sh - power-aware simulation with accel.upf
# usage: ./run_lp.sh [test] [seed] [bug]      bug = NO_ISO or NO_RESTORE
TEST=${1:-mm_lp_test}
SEED=${2:-1}
BUG=${3:-}
DEF=""; TAG=""
if [ -n "$BUG" ]; then DEF="-define LP_BUG_$BUG"; TAG="_$BUG"; fi
LOG=logs/${TEST}_seed${SEED}${TAG}.log
mkdir -p logs
rm -rf xcelium.d

xrun -64bit -sv -uvm -timescale 1ns/1ps \
     -f filelist.f -top tb_top $DEF \
     -lps_1801 accel.upf -lps_dut_top tb_top.DUT.U_CORE \
     -lps_supply_full_on -lps_relax_1801 -lps_logfile logs/lps_${TEST}${TAG}.log \
     +UVM_TESTNAME=$TEST +UVM_VERBOSITY=UVM_LOW +UVM_NO_RELNOTES \
     -svseed $SEED -access +rwc -l $LOG > /dev/null 2>&1

echo "=========================================="
echo " Test : $TEST   Seed : $SEED   Bug : ${BUG:-none}"
echo "=========================================="
grep "Transactions:" $LOG
grep -E "CHECKS PASSED|ERRORS in" $LOG
echo "Assertion failures:"
grep "reporter \[SVA\]" $LOG | grep -o "SVA: [a-z ,-]*" | sort | uniq -c
grep -q "reporter \[SVA\]" $LOG || echo "   none"
grep -E "UVM_ERROR :|UVM_FATAL :" $LOG
grep -E "TEST PASSED|TEST FAILED" $LOG
grep -E "\*E,|\*F," $LOG | head -3
