#!/bin/bash
# run.sh - single test with coverage
# usage: ./run.sh [test] [seed]     e.g.  ./run.sh mm_full_test 25
# tests: mm_smoke_test, mm_full_test
TEST=${1:-mm_smoke_test}
SEED=${2:-1}
mkdir -p logs

xrun -64bit -sv -uvm -uvmnocdnsextra -uvmhome CDNS-1.2 -timescale 1ns/1ps \
     -f filelist.f -top tb_top \
     +UVM_TESTNAME=$TEST +UVM_VERBOSITY=UVM_LOW +UVM_NO_RELNOTES \
     -svseed $SEED \
     -access +rwc \
     -coverage all -covworkdir cov_work -covtest ${TEST}_seed${SEED} -covoverwrite \
     -l logs/${TEST}_seed${SEED}.log > /dev/null 2>&1

grep -E "UVM_ERROR :|UVM_FATAL :|Transactions:|CHECKS|TEST PASSED|TEST FAILED|\*E,|\*F," logs/${TEST}_seed${SEED}.log
