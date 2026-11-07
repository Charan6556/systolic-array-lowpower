# Pictures 1 and 3: how Conv1 becomes a matrix multiply, and how it is tiled 4x4
# Run in the same Colab notebook (uses model, quant_input, im2col, int8_forward, W1_mat)

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

# Pick the first "3" among the 100 test images
n = int(np.where(test_labels[:100] == 3)[0][0])
x = quant_input(test_images[n:n+1])                 # (1,28,28) int8 pixels
ref = int8_forward(x)

# Conv1 as matrices: A = im2col (padded to K=12), B = weights (padded), C = A x B
patches, _, _ = im2col(x.reshape(1, 28, 28, 1))     # (1,676,9)
A = np.zeros((676, 12), np.int64); A[:, :9] = patches[0]
B = np.zeros((12, 8), np.int64);   B[:9] = W1_mat
C = A @ B
assert np.array_equal(C, ref["acc1"][0])            # same numbers the RTL matched (exp_acc1)

# Choose a patch on an edge of the stroke (most varied pixels)
stroke = A[:, :9].sum(1) > 0
p = int(np.argmax(np.where(stroke, A[:, :9].std(1), -1)))
py, px = divmod(p, 26)

def annotate(ax, M, dark_text_above=None, fs=9):
    for (i, j), v in np.ndenumerate(M):
        if dark_text_above is None:
            col = "black"
        else:
            col = "black" if v > dark_text_above else "white"
        ax.text(j, i, str(v), ha="center", va="center", fontsize=fs, color=col)

def clean(ax):
    ax.set_xticks([]); ax.set_yticks([])

def symbol(ax, s, fs=22):
    ax.axis("off"); ax.text(0.5, 0.5, s, ha="center", va="center", fontsize=fs)

ORANGE = "#EF9F27"

# ================= Picture 1: Conv1 as a matrix multiply =================
fig = plt.figure(figsize=(17, 8))
gs = fig.add_gridspec(2, 7, width_ratios=[3, 1.1, 1.6, 0.4, 1.6, 0.4, 1.6],
                      height_ratios=[4, 1], hspace=0.35)

ax = fig.add_subplot(gs[0, 0])
ax.imshow(x[0], cmap="gray", vmin=0, vmax=127)
ax.add_patch(Rectangle((px - 0.5, py - 0.5), 3, 3, edgecolor=ORANGE, lw=3, fill=False))
ax.set_title(f'Input digit "3"  (28×28, int8 0–127)\none 3×3 patch at y={py}, x={px}', fontsize=11)
clean(ax)

symbol(fig.add_subplot(gs[0, 1]), "im2col\n→", fs=16)

ax = fig.add_subplot(gs[0, 2])
ax.imshow(A, cmap="gray", vmin=0, vmax=127, aspect="auto", interpolation="nearest")
ax.axvline(8.5, color="red", ls="--", lw=1)
ax.add_patch(Rectangle((-0.5, p - 4), 12, 8, edgecolor=ORANGE, lw=3, fill=False))
ax.set_title("A: one row per patch\n676 × 12  (9 pixels + 3 zero pad)", fontsize=11)
ax.set_ylabel("patch p = y·26 + x", fontsize=9); ax.set_xticks([0, 8, 11]); ax.set_yticks([0, 675])

symbol(fig.add_subplot(gs[0, 3]), "×")

ax = fig.add_subplot(gs[0, 4])
ax.imshow(B, cmap="bwr", vmin=-127, vmax=127, aspect="auto")
annotate(ax, B, fs=8)
ax.axhline(8.5, color="red", ls="--", lw=1)
ax.set_title("B: Conv1 weights\n12 × 8  (8 filters, w1.hex)", fontsize=11)
ax.set_xlabel("filter"); ax.set_xticks(range(8)); ax.set_yticks([0, 8, 11])

symbol(fig.add_subplot(gs[0, 5]), "=")

ax = fig.add_subplot(gs[0, 6])
ax.imshow(C, cmap="viridis", aspect="auto", interpolation="nearest")
ax.add_patch(Rectangle((-0.5, p - 4), 8, 8, edgecolor=ORANGE, lw=3, fill=False))
ax.set_title("C = A × B: Conv1 output\n676 × 8  (exp_acc1)", fontsize=11)
ax.set_xlabel("filter"); ax.set_xticks(range(8)); ax.set_yticks([0, 675])

ax = fig.add_subplot(gs[1, 0:3])
ax.imshow(A[p:p+1], cmap="gray", vmin=0, vmax=127, aspect="auto")
annotate(ax, A[p:p+1], dark_text_above=63, fs=11)
ax.set_title(f"row {p} of A = the orange patch (last 3 = zero padding)", fontsize=11)
clean(ax)

ax = fig.add_subplot(gs[1, 4:7])
ax.imshow(C[p:p+1], cmap="viridis", aspect="auto")
annotate(ax, C[p:p+1], dark_text_above=np.percentile(C, 60), fs=10)
ax.set_title(f"row {p} of C = that patch's result for all 8 filters", fontsize=11)
clean(ax)

fig.suptitle("Conv1 as one matrix multiply: every 3×3 patch becomes a row of A", fontsize=14)
fig.savefig("cnn_conv1_as_matmul.png", dpi=150, bbox_inches="tight")
plt.show()

# ================= Picture 3: 4x4 tiling with ACCUMULATE =================
ti = p // 4                                         # tile holding the orange patch
At = A[4*ti:4*ti+4, :]                              # 4 x 12
Bt = B[:, 0:4]                                      # 12 x 4  (filters 0-3)
parts = [At[:, 4*k:4*k+4] @ Bt[4*k:4*k+4, :] for k in range(3)]
Ct = sum(parts)
assert np.array_equal(Ct, C[4*ti:4*ti+4, 0:4])

fig = plt.figure(figsize=(17, 11))
gs = fig.add_gridspec(3, 8, width_ratios=[1, 0.3, 1, 0.3, 1.2, 0.5, 0.3, 1.4], hspace=0.45)
labels = ["run 1: START (accumulators cleared)",
          "run 2: START + ACCUMULATE",
          "run 3: START + ACCUMULATE  (includes zero padding)"]

for k in range(3):
    Ak = At[:, 4*k:4*k+4]; Bk = Bt[4*k:4*k+4, :]
    ax = fig.add_subplot(gs[k, 0]); ax.imshow(Ak, cmap="gray", vmin=0, vmax=127)
    annotate(ax, Ak, dark_text_above=63); clean(ax)
    ax.set_title(f"A tile, columns {4*k}–{4*k+3}", fontsize=10)
    ax.set_ylabel(labels[k], fontsize=10, rotation=0, ha="right", va="center", labelpad=20)
    symbol(fig.add_subplot(gs[k, 1]), "×")
    ax = fig.add_subplot(gs[k, 2]); ax.imshow(Bk, cmap="bwr", vmin=-127, vmax=127)
    annotate(ax, Bk); clean(ax); ax.set_title(f"B tile, rows {4*k}–{4*k+3}", fontsize=10)
    symbol(fig.add_subplot(gs[k, 3]), "=")
    ax = fig.add_subplot(gs[k, 4]); ax.imshow(parts[k], cmap="viridis")
    annotate(ax, parts[k], dark_text_above=np.median(parts[k]), fs=9); clean(ax)
    ax.set_title(f"partial sum {k+1} (12 cycles)", fontsize=10)
    symbol(fig.add_subplot(gs[k, 5]), "+" if k < 2 else "→")

ax = fig.add_subplot(gs[:, 7])
ax.imshow(Ct, cmap="viridis")
annotate(ax, Ct, dark_text_above=np.median(Ct), fs=11); clean(ax)
ax.set_title("C tile = sum of 3 runs\nkept inside the PEs (ACCUMULATE)\nread once: 16 AXI reads", fontsize=11)

fig.suptitle(f"4×4 tiling: one output tile (patches {4*ti}–{4*ti+3}, filters 0–3) "
             f"= 3 accelerator runs\nConv1 needs 169 × 2 tiles × 3 runs = 1,014 runs", fontsize=14)
fig.savefig("cnn_tiling_4x4.png", dpi=150, bbox_inches="tight")
plt.show()

from google.colab import files
files.download("cnn_conv1_as_matmul.png")
files.download("cnn_tiling_4x4.png")
