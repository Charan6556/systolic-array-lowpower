#!/bin/bash
# Live demo: draw a digit -> Xcelium RTL simulation of the accelerator -> prediction
# Run from the repo root:  ./live_demo.sh

DATA=app/draw_data

# First digit (also creates app/draw_data)
python3 app/draw_digit.py --one || exit 1

# Compile once
echo "Compiling RTL + testbench..."
xrun -64bit -sv -timescale 1ns/1ps rtl/*.sv tb/tb_mnist.sv \
     +incdir+$DATA -top tb_mnist -elaborate -q -l compile.log || exit 1

# Loop: simulate, show result, draw next
while true; do
    clear
    echo "Running on the accelerator (Xcelium RTL simulation)..."
    xrun -R -q +DATA=$DATA -l demo.log | sed -n '/RTL simulation/,/Accelerator runs/p'
    echo
    read -p "Enter = draw next digit, q = quit: " key
    [ "$key" = "q" ] && break
    python3 app/draw_digit.py --one || break
done
