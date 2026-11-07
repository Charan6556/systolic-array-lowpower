#!/usr/bin/env python3
# draw_digit.py
# Draw digits in the terminal with the mouse and export them for tb_mnist.sv.
#
# Run from the repo root:
#   python3 app/draw_digit.py              draw digits
#   python3 app/draw_digit.py --selftest 5  check the math against the Colab answer key
#
#   python3 app/draw_digit.py --one        draw one digit, save, exit (live demo)
#
# Keys: mouse drag = draw, 0-9 = label, s = save, c = clear, q = quit

import curses
import os
import re
import shutil
import sys

N         = 28                      # image size
RAMP      = " .:-=+*#%@"            # dark -> bright
MODEL_DIR = "app/mnist_cnn_data"    # trained weights from Colab
OUT_DIR   = "app/draw_data"         # drawn digits go here
ONE       = "--one" in sys.argv     # live demo: exit after one digit

# Hex files
def read_hex(path, bits):
    vals = []
    for line in open(path):
        if line.strip():
            v = int(line, 16)
            if v >= 1 << (bits - 1):
                v -= 1 << bits              # two's complement
            vals.append(v)
    return vals

def write_hex(path, vals, bits):
    with open(path, "w") as f:
        for v in vals:
            f.write("%0*x\n" % (bits // 4, v & ((1 << bits) - 1)))

# Model (same integer math as int8_forward in Colab)
w1 = read_hex(MODEL_DIR + "/w1.hex", 8)     # 12 x 8
b1 = read_hex(MODEL_DIR + "/b1.hex", 32)
w2 = read_hex(MODEL_DIR + "/w2.hex", 8)     # 72 x 8
b2 = read_hex(MODEL_DIR + "/b2.hex", 32)
w3 = read_hex(MODEL_DIR + "/w3.hex", 8)     # 200 x 12
b3 = read_hex(MODEL_DIR + "/b3.hex", 32)
params = dict(re.findall(r"(\w+)\s*=\s*(\d+);", open(MODEL_DIR + "/mnist_params.svh").read()))
SHIFT, M1, M2 = int(params["SHIFT"]), int(params["M1"]), int(params["M2"])

def requant(acc, M):
    v = (acc * M + (1 << (SHIFT - 1))) >> SHIFT
    return max(0, min(127, v))              # ReLU + int8 clamp

def maxpool(v, H, W):
    out = []
    for y in range(H // 2):
        for x in range(W // 2):
            for c in range(8):
                out.append(max(v[((2*y + dy) * W + 2*x + dx) * 8 + c]
                               for dy in range(2) for dx in range(2)))
    return out

def forward(img):
    # Conv1: 26x26 patches of 3x3
    acc1, r1 = [], []
    for y in range(26):
        for x in range(26):
            patch = [img[(y + kh) * N + x + kw] for kh in range(3) for kw in range(3)]
            for n in range(8):
                a = sum(patch[k] * w1[k*8 + n] for k in range(9))
                acc1.append(a)
                r1.append(requant(a + b1[n], M1))
    a1 = maxpool(r1, 26, 26)                # 13x13x8

    # Conv2: 11x11 patches of 3x3x8
    acc2, r2 = [], []
    for y in range(11):
        for x in range(11):
            patch = [a1[((y + kh) * 13 + x + kw) * 8 + c]
                     for kh in range(3) for kw in range(3) for c in range(8)]
            for n in range(8):
                a = sum(patch[k] * w2[k*8 + n] for k in range(72))
                acc2.append(a)
                r2.append(requant(a + b2[n], M2))
    a2 = maxpool(r2, 11, 11)                # 5x5x8 = 200

    # Dense: 200 -> 12 (10 real + 2 padding)
    scores = [sum(a2[k] * w3[k*12 + n] for k in range(200)) + b3[n] for n in range(12)]
    pred = max(range(10), key=lambda n: (scores[n], -n))   # first max wins
    return dict(acc1=acc1, a1=a1, acc2=acc2, a2=a2, scores=scores, pred=[pred])

# Center the drawing by its center of mass (like MNIST)
def center(img):
    total = sum(img)
    cy = sum(img[i] * (i // N) for i in range(N*N)) / total
    cx = sum(img[i] * (i % N) for i in range(N*N)) / total
    dy, dx = round(13.5 - cy), round(13.5 - cx)
    out = [0] * (N*N)
    for y in range(N):
        for x in range(N):
            if 0 <= y - dy < N and 0 <= x - dx < N:
                out[y*N + x] = img[(y - dy) * N + x - dx]
    return out

# Export (same files as app/mnist_cnn_data)
def export(images, labels):
    os.makedirs(OUT_DIR, exist_ok=True)
    for f in ("w1", "b1", "w2", "b2", "w3", "b3"):
        shutil.copy(MODEL_DIR + "/%s.hex" % f, OUT_DIR)
    res = [forward(img) for img in images]
    write_hex(OUT_DIR + "/img.hex", sum(images, []), 8)
    write_hex(OUT_DIR + "/labels.hex", labels, 8)
    for key, bits in (("acc1", 32), ("a1", 8), ("acc2", 32), ("a2", 8), ("scores", 32), ("pred", 8)):
        write_hex(OUT_DIR + "/exp_%s.hex" % key, sum((r[key] for r in res), []), bits)
    with open(OUT_DIR + "/mnist_params.svh", "w") as f:
        f.write("localparam int N_IMG = %d;\n" % len(images))
        f.write("localparam int SHIFT = %d;\n" % SHIFT)
        f.write("localparam longint M1 = %d;\n" % M1)
        f.write("localparam longint M2 = %d;\n" % M2)
    return res[-1]["pred"][0]

# Selftest: compare against the Colab answer key
def selftest(n_img):
    img = read_hex(MODEL_DIR + "/img.hex", 8)
    size = dict(acc1=676*8, a1=13*13*8, acc2=121*8, a2=200, scores=12, pred=1)
    exp = {k: read_hex(MODEL_DIR + "/exp_%s.hex" % k, 32 if k in ("acc1", "acc2", "scores") else 8)
           for k in size}
    bad = 0
    for i in range(n_img):
        r = forward(img[i*784:(i + 1)*784])
        for k, n in size.items():
            if r[k] != exp[k][i*n:(i + 1)*n]:
                print("image %d: %s MISMATCH" % (i, k))
                bad += 1
    print("selftest: %d image(s), %s" % (n_img, "ALL MATCH" if bad == 0 else "%d mismatches" % bad))

# Brush: thick center, soft edges
def paint(canvas, y, x):
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if 0 <= y + dy < N and 0 <= x + dx < N:
                i = (y + dy) * N + x + dx
                canvas[i] = max(canvas[i], 127 if dy == 0 or dx == 0 else 70)

# Drawing screen
def draw_ui(scr):
    curses.curs_set(0)
    curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
    curses.mouseinterval(0)
    print("\033[?1003h", end="", flush=True)      # report mouse drag

    canvas, images, labels = [0] * (N*N), [], []
    label, down = None, False
    msg = "Draw a big digit, press 0-9 for its label, then s to save."

    while True:
        scr.erase()
        try:
            scr.addstr(0, 0, "+" + "-" * 2*N + "+")
            for y in range(N):
                row = "".join(RAMP[canvas[y*N + x] * 9 // 127] * 2 for x in range(N))
                scr.addstr(y + 1, 0, "|" + row + "|")
            scr.addstr(N + 1, 0, "+" + "-" * 2*N + "+")
            scr.addstr(2, 2*N + 5, "label : %s" % ("-" if label is None else label))
            scr.addstr(3, 2*N + 5, "saved : %d" % len(images))
            scr.addstr(5, 2*N + 5, "drag : draw    0-9 : label")
            scr.addstr(6, 2*N + 5, "s : save   c : clear   q : quit")
            scr.addstr(N + 3, 0, msg[:curses.COLS - 1])
        except curses.error:
            pass                                       # window shrank: skip this frame
        scr.refresh()

        k = scr.getch()
        if k == curses.KEY_MOUSE:
            try:
                _, mx, my, _, b = curses.getmouse()
            except curses.error:
                continue
            if b & curses.BUTTON1_PRESSED:
                down = True
            if b & curses.BUTTON1_RELEASED:
                down = False
            if down or b & curses.BUTTON1_CLICKED:
                y, x = my - 1, (mx - 1) // 2
                if 0 <= y < N and 0 <= x < N:
                    paint(canvas, y, x)
        elif ord("0") <= k <= ord("9"):
            label = k - ord("0")
        elif k == ord("c"):
            canvas = [0] * (N*N)
        elif k == ord("s"):
            if sum(canvas) == 0 or label is None:
                msg = "Draw a digit and press 0-9 first."
                continue
            images.append(center(canvas))
            labels.append(label)
            msg = "Computing..."
            scr.addstr(N + 3, 0, msg)
            scr.refresh()
            pred = export(images, labels)
            msg = "Saved #%d (label %d). Python reference predicts %d." % (len(images), label, pred)
            canvas, label = [0] * (N*N), None
            if ONE:
                break                               # live demo: hand over to the simulator
        elif k == ord("q"):
            break

    print("\033[?1003l", end="", flush=True)
    return len(images)

# Main
if len(sys.argv) == 3 and sys.argv[1] == "--selftest":
    selftest(int(sys.argv[2]))
else:
    cols, rows = shutil.get_terminal_size()
    if cols < 2*N + 40 or rows < N + 5:
        print("Terminal too small: %dx%d. Make the window at least %dx%d and run again."
              % (cols, rows, 2*N + 40, N + 5))
        sys.exit(1)
    try:
        n = curses.wrapper(draw_ui)
        print("Saved %d digit(s) to %s" % (n, OUT_DIR))
        if n == 0:
            sys.exit(1)                             # nothing saved: stop the demo loop
    finally:
        print("\033[?1003l\033[?1000l", end="", flush=True)   # always turn mouse tracking off
