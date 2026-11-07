# Power-Gated 4×4 INT8 Systolic Matmul Accelerator

A 4×4 output-stationary systolic array (16 INT8 MAC units, 32-bit accumulators) behind an AXI4-Lite slave interface, with:

- **UVM verification environment**: AXI4-Lite agent, scoreboard with reference model, constrained-random stimulus
- **Low-power design**: IEEE 1801 (UPF) power intent that puts the PE array in a switchable power domain, with isolation and retention, plus an RTL power controller driven by an AXI register
- **Power-aware verification** in Cadence Xcelium (`-lps_1801`), with SVA checks on the power sequence and bug-injection tests
- **Logic synthesis** in Cadence Genus on SKY130 HD with a 4 ns clock constraint (250 MHz)
- **A real workload**: an INT8 MNIST CNN runs on the accelerator RTL in Xcelium, bit-exact with a Python INT8 reference on 100/100 test images, plus a live demo where hand-drawn digits are classified in simulation

![Hand-drawn power-domain architecture](docs/hand_drawn_architecture.png)

---

## Architecture

```
matmul_axil_top            AXI4-Lite slave (always on)
└── U_CORE  matmul_accelerator         <- UPF scope
    ├── U_BUFFER      input_buffer     A, B matrices          PD_AON
    ├── U_FEEDER      data_feeder      skews A/B into array   PD_AON
    ├── U_CONTROLLER  controller       IDLE/CLEAR/COMPUTE/DONE PD_AON
    ├── U_OUTPUT      output_buffer    C results              PD_AON
    ├── power controller FSM           lp_* control signals   PD_AON
    └── U_ARRAY       pe_array         16 PEs                 PD_ARRAY (switchable)
```

### Register map

| Address | Register | Access | Description |
|---|---|---|---|
| 0x00 | CTRL | R/W | bit0 START (pulse, reads 0), bit1 IRQ_EN, bit2 ACCUMULATE |
| 0x04 | STATUS | R | bit0 busy, bit1 done (sticky) |
| 0x08 | ID | R | 0x4D4D_0001 |
| 0x10–0x1C | A rows 0–3 | W | 4 × INT8 per row |
| 0x20–0x2C | B rows 0–3 | W | 4 × INT8 per row |
| 0x34 | PWR_CTRL | R/W | W: bit0 = 1 power down array, 0 power up. R: bit0 request, bit4 array ON, bit5 array OFF |
| 0x40–0x7C | C[i][j] | R | 32-bit results, address = 0x40 + 4·(4i + j) |

Unmapped addresses return SLVERR. A START issued while the array is not fully on is refused with SLVERR.

---

## Low-power design

### Power domains (`uvm/accel.upf`)

| Domain | Contents | Supply |
|---|---|---|
| PD_AON | Everything in the core except the array | VDD (always on) |
| PD_ARRAY | `U_ARRAY` (16 PEs) | VDD_ARR (output of the power switch) |

| Structure | Implementation |
|---|---|
| Power switch | Header switch, VDD → VDD_ARR, controlled by `lp_pwr_en` |
| Isolation | All PD_ARRAY outputs (`c_out`) clamped to 0 while `lp_iso_en` = 1, powered by SS_AON |
| Retention | PD_ARRAY registers saved on `lp_save`, restored on `lp_restore`, shadow on SS_AON. Needed for ACCUMULATE mode across a power cycle |
| Level shifters | Not needed (single voltage) |

The PE array accounts for 71.4% of the core cell area in the hierarchy-preserving synthesis run. It is the switchable domain; the input and output buffers remain powered. Stored C results can therefore be read while the array is off. Area share alone does not establish leakage-power savings.

### Power controller FSM (`rtl/matmul_accelerator.sv`)

```
Power down:  ON -> SAVE -> ISO -> OFF          (save, isolate, switch off)
Power up:    OFF -> UP (wait 3) -> RESTORE -> UNISO -> ON
```

- Power-down waits until the core is not busy.
- START reaches the compute controller only when the array is fully on and no power-down is requested.

---

## Verification

### UVM environment (`uvm/`)

| Component | Role |
|---|---|
| `axil_if` | AXI4-Lite interface |
| `axil_item` | One read/write, with randomized AW/W ordering and BREADY/RREADY backpressure |
| `axil_driver` / `axil_monitor` / `axil_agent` | Drive and observe the AXI4-Lite bus, with handshake timeouts |
| `mm_scoreboard` | Shadow model of A/B (honors WSTRB), reference matmul (normal and accumulate), checks every C read, response codes, ID, CTRL and PWR_CTRL readback, START refusal while powered off |
| `mm_seqs` | Register, matmul, WSTRB, write-while-busy, and power sequences (`power_down`, `power_up`, power-cycle, accumulate across power cycle, power-down request while busy) |
| `power_sva.sv` | 6 assertions on the power sequence, bound to `matmul_accelerator`, reported through `uvm_error` |

### Assertions (`uvm/power_sva.sv`)

| Assertion | Rule |
|---|---|
| `a_iso_when_off` | Array off → isolation on |
| `a_save_before_iso` | Save happens the cycle before isolation turns on |
| `a_iso_before_off` | Isolation is on before power turns off |
| `a_restore_when_on` | Restore only while the array is powered |
| `a_restore_before_uniso` | Isolation is removed only right after a restore |
| `a_no_save_while_busy` | No power-down in the middle of a computation |

### Results

All runs: Cadence Xcelium 26.03, seed 1.

| Run | Command | Result |
|---|---|---|
| Functional, no UPF | `./run.sh mm_full_test 1` | **PASS**: 960 writes, 2073 reads, 106 matmuls, 1696 C reads, 5103 checks, 0 errors |
| Functional, UPF loaded | `./run_lp.sh mm_full_test 1` | **PASS**: 5115 checks, 0 assertion failures |
| Low-power test | `./run_lp.sh mm_lp_test 1` | **PASS**: 46 power-control writes (23 power cycles), 51 matmuls, 4214 checks, 0 assertion failures |
| Bug: no isolation | `./run_lp.sh mm_lp_test 1 NO_ISO` | **FAIL as expected**: 3405 × `a_iso_when_off`, 23 × `a_iso_before_off`; scoreboard 0 errors |
| Bug: no restore | `./run_lp.sh mm_lp_test 1 NO_RESTORE` | **FAIL as expected**: 23 × `a_restore_before_uniso`; scoreboard 16 errors (accumulate-after-power-cycle results wrong) |

![Low-power results](docs/lowpower_test_results.png)

### AXI4-Lite waveform

SimVision capture showing matrix writes, the START write, computation, STATUS polling, and C-result reads.

![AXI4-Lite transactions and accelerator control signals in SimVision](docs/simvision_axi_waveform.png)

The two injected faults exercise different checks:
- With isolation missing, X from the powered-off array reached the always-on side, but no C result changed. The assertions detected the sequencing violation; the scoreboard reported no result mismatches.
- With restore missing, the accumulators came back as X. Both the assertions (protocol) and the scoreboard (data) caught it, demonstrating the need to restore accumulator state for this accumulate-after-power-cycle test.

The bugs are enabled with `+define+LP_BUG_NO_ISO` / `LP_BUG_NO_RESTORE` (`` `ifndef `` blocks in the power FSM). Without a define, the RTL is unchanged.

**Power gating seen in simulation** (first power cycle, `c_out[0][0]` of the array and after isolation):

| Time (ps) | Event | Array output | After isolation |
|---|---|---|---|
| 827000 | save | 0x00005F65 | 0x00005F65 |
| 831000 | isolation on | 0x00005F65 | 0x00000000 |
| 835000 | power off | xxxxxxxx | 0x00000000 |
| 1283000 | restore (power back on) | xxxxxxxx | 0x00000000 |
| 1287000 | isolation off | 0x00005F65 | 0x00005F65 |

---

## Application: INT8 MNIST CNN (Xcelium RTL simulation)

A small CNN runs on the accelerator. The testbench (`tb/tb_mnist.sv`) acts as the CPU and drives the accelerator only through the AXI4-Lite register interface. Every multiply-accumulate runs on the RTL.

**Interactive explainers** (open in a browser):
- [Follow one number from the terminal, through the systolic array, and back](https://charan6556.github.io/systolic-array-lowpower/pipeline.html): drag left to right
- [Step-by-step walkthrough with real values](https://charan6556.github.io/systolic-array-lowpower/): one pixel to one prediction in 8 steps

**Demo video:** [hand-drawn digits classified by the accelerator RTL](https://charan6556.github.io/systolic-array-lowpower/media/mnist_live_demo.mp4)

![CNN to hardware flow](docs/media/cnn_to_hardware_flow.png)

### Model and quantization

| Item | Value |
|---|---|
| Network | Conv 3×3×8 → ReLU → MaxPool 2×2 → Conv 3×3×8 → ReLU → MaxPool 2×2 → Dense 200→10 |
| Parameters | 2,674 |
| MACs per image | ~120,400 (Conv1 48,672, Conv2 69,696, Dense 2,000) |
| Training | Keras with TensorFlow, Adam, sparse categorical cross-entropy from logits, 5 epochs, batch size 64, seed 42 |
| Quantization | Post-training INT8 with symmetric per-layer weight scales, INT32 biases, and activation scales calibrated on 2,000 training images |
| Requantization | Integer only: `clamp((acc · M + 2^23) >> 24, 0, 127)`; the clamp at 0 is the ReLU |
| Accuracy, 10K test set (Python) | Float 97.6%, INT8 97.57% |

The [training and export notebook](app/mnist_small.ipynb) trains on 60,000 MNIST images, evaluates the float and INT8 models on the 10,000-image test set, and exports weights and layer-by-layer reference outputs for the first 100 test images.

| Layer | Output shape (excluding batch) | Trainable parameters |
|---|---:|---:|
| Reshape | 28 × 28 × 1 | 0 |
| Conv2D, 8 valid 3 × 3 filters, ReLU | 26 × 26 × 8 | 80 |
| Max pooling, 2 × 2 | 13 × 13 × 8 | 0 |
| Conv2D, 8 valid 3 × 3 filters, ReLU | 11 × 11 × 8 | 584 |
| Max pooling, 2 × 2 | 5 × 5 × 8 | 0 |
| Flatten | 200 | 0 |
| Dense logits | 10 | 2,010 |
| **Total** | | **2,674** |

[Keras model summary](docs/media/mnist_model_summary.png) · [Model architecture diagram](docs/media/mnist_model_architecture.png)

### Who does what

| Step | Where |
|---|---|
| All multiply-accumulates (Conv1, Conv2, Dense) | Accelerator RTL |
| im2col, zero padding to multiples of 4 | Testbench |
| 4×4 tiling: one START per K-step, ACCUMULATE set after the first, interrupt on completion, C read once per output tile | Testbench, using the hardware accumulate mode |
| Bias, requantization, ReLU, max pooling, argmax | Testbench |

### Checking

Python exports the weights, the first 100 MNIST test images, and the integer reference output of every layer (`app/mnist_cnn_data/exp_*.hex`). The testbench compares the RTL result after each step: Conv1 accumulators, Conv1 after requant and pool, Conv2 accumulators, Conv2 after requant and pool, dense scores, and the predicted digit.

### Results: first 100 MNIST test images

| Metric | Result |
|---|---|
| Bit-exact vs Python INT8, every layer | 100 / 100 (0 mismatches) |
| Correct vs label | 100 / 100 |
| Accelerator runs per image | 2,280 (Conv1 1,014, Conv2 1,116, Dense 150) |
| Cycles per image | 126,503 (average) |

![100-image summary](docs/media/summary_100.png)

The first 100 test images are all classified correctly; the model's accuracy on the full test set is 97.57%.

### Hand-drawn digits

`app/draw_digit.py` lets you draw a digit in the terminal with the mouse. It centers the drawing like MNIST, computes the same integer reference in plain Python (checked against the Colab answer key with `--selftest`), and writes the hex files. `./live_demo.sh` then runs each drawing on the RTL.

| Correct: 3 | Misclassified: a 4 with a closed top is read as 9 |
|---|---|
| ![3 classified correctly](docs/media/demo_3_correct.png) | ![4 read as 9, still bit-exact](docs/media/demo_4_wrong.png) |

The misclassified 4 is still bit-exact with the Python reference: the RTL computed exactly what the model specifies, and the error comes from the 2,674-parameter model. Per-layer bit-exact checking separates hardware errors from model errors.

---

## Synthesis (Cadence Genus, SKY130 HD, tt 25 °C 1.8 V)

Core (`matmul_accelerator`, with the power controller), 4 ns clock (250 MHz). Script: `synth/synth_simple.tcl`.

| Metric | Value |
|---|---|
| Worst slack | 0.0 ps (timing met), TNS 0 |
| Cells | 8,408 (1,485 sequential, 6,923 combinational) |
| Cell area | 96,093 µm² |
| Power (vectorless estimate) | 40.8 mW |

Genus QoR report for the flat synthesis run:

![Genus timing, cell count, and area report](docs/genus_qor.png)

Area by block, from a hierarchy-preserving run (`synth/synth_hier.tcl`, total 99,668 µm²):

| Block | Area (µm²) | Share |
|---|---|---|
| U_ARRAY (16 PEs) | 71,178 | 71.4% |
| U_OUTPUT | 16,045 | 16.1% |
| U_BUFFER | 11,093 | 11.1% |
| U_FEEDER | 751 | 0.8% |
| U_CONTROLLER | 353 | 0.4% |
| Top-level logic (power FSM, START/write gating) | ~248 | ~0.25% |

![Genus hierarchical area report](docs/genus_area_by_block.png)

### Synthesis schematic

Core hierarchy as displayed in Genus:

![Accelerator core schematic in Genus](docs/genus_schematic_core.png)

[View the PE-array schematic](docs/genus_schematic_pe_array.png).

Critical path: compute controller state → data feeder → input buffer read → PE carry-save adder tree → accumulator.

The UPF is used in simulation only. The netlist does not contain power switches, isolation cells, or retention flops (see Limitations).

---

## How to run

```
cd uvm
./run.sh mm_smoke_test 1          # functional smoke test
./run.sh mm_full_test 1           # full functional regression
./run_lp.sh mm_lp_test 1          # power-aware simulation with accel.upf
./run_lp.sh mm_lp_test 1 NO_ISO   # bug injection (must fail)
./regression.sh 10                # mm_full_test over seeds 1-10

cd ../synth
genus -f synth_simple.tcl -log genus_lp

cd ..                                  # MNIST CNN, from the repo root
xrun -64bit -sv -timescale 1ns/1ps rtl/*.sv tb/tb_mnist.sv \
     +incdir+app/mnist_cnn_data -top tb_mnist +DATA=app/mnist_cnn_data
./live_demo.sh                         # draw digits and classify them on the RTL
```

`filelist.f` expects `rtl/` next to `uvm/`.

---

## Limitations

- **Power gating is verified in power-aware simulation only.** It is not implemented in silicon: the SKY130 HD library has no power-switch or retention cells, so synthesis does not use the UPF.
- No static low-power checks (e.g. Conformal Low Power) and no low-power coverage (`-lps_cov`).
- Retention covers the whole PD_ARRAY domain; only the 16 accumulators are actually needed (an area optimization not done here).
- Power numbers are vectorless estimates, not from simulation activity.
- No clock gating yet.
- The MNIST results are RTL simulation (Xcelium, without UPF), not silicon or FPGA. The testbench performs im2col, requantization, pooling and argmax that a CPU would do; the accelerator performs the MACs.
- MNIST throughput is limited by AXI4-Lite data movement: each 4×4 run needs 8 register writes, and each output tile 16 reads. No DMA.

## Repository layout

```
rtl/     8 RTL files (power controller in matmul_accelerator.sv, PWR_CTRL in matmul_axil_top.sv)
uvm/     UVM environment, power_sva.sv, accel.upf, run scripts
tb/      Directed testbenches (original AXI-Lite tests, PE unit test, tb_mnist.sv)
app/     MNIST data and model files (mnist_cnn_data/), draw_digit.py
synth/   Genus scripts and reports (flat and hierarchical)
docs/    Diagrams and result screenshots (MNIST media in docs/media/)
live_demo.sh   Draw a digit -> Xcelium simulation -> prediction
```
