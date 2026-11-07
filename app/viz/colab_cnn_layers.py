# Image 1: CNN layers on a "3", using the INT8 model (the same numbers the hardware computes)
# Run in the same Colab notebook (uses quant_input, im2col, int8_forward, requant_relu, b1_q, b2_q, M1, M2, SHIFT)

import numpy as np
import matplotlib.pyplot as plt

# First "3" among the 100 test images
n = int(np.where(test_labels[:100] == 3)[0][0])
x = quant_input(test_images[n:n+1])
ref = int8_forward(x)

# Feature maps after ReLU (before pooling), plus the pooled maps from the reference
r1 = requant_relu(ref["acc1"][0] + b1_q, M1, SHIFT).reshape(26, 26, 8)
r2 = requant_relu(ref["acc2"][0] + b2_q, M2, SHIFT).reshape(11, 11, 8)
a1 = ref["a1"][0]                     # 13 x 13 x 8
a2 = ref["a2"][0]                     #  5 x  5 x 8
scores = ref["scores"][0]
pred = int(ref["pred"][0])

HW = "#1D9E75"     # accelerator
SW = "#7F7F7F"     # testbench / CPU

fig = plt.figure(figsize=(22, 7))
outer = fig.add_gridspec(1, 11, width_ratios=[2.2, .45, 2.6, .45, 2.2, .45, 2.2, .45, 1.8, .45, 2.4], wspace=0.05)

def column_title(spec, title, sub, color):
    ax = fig.add_subplot(spec); ax.axis("off")
    ax.set_title(title, fontsize=13, pad=26)
    ax.text(0.5, 1.02, sub, transform=ax.transAxes, ha="center", fontsize=10.5, color=color, weight="bold")
    return ax

def maps(spec, data, title, sub, color):
    column_title(spec, title, sub, color)
    g = spec.subgridspec(12, 1)[1:].subgridspec(4, 2, hspace=0.18, wspace=0.08)
    top = max(1, int(data.max()))                  # same brightness scale for all 8 maps of a layer
    for f in range(8):
        ax = fig.add_subplot(g[f // 2, f % 2])
        ax.imshow(data[:, :, f], cmap="gray", vmin=0, vmax=top)
        ax.set_xticks([]); ax.set_yticks([])
        ax.set_title(f"filter {f}", fontsize=8, pad=2)

def arrow(spec):
    ax = fig.add_subplot(spec); ax.axis("off")
    ax.text(0.5, 0.5, "→", ha="center", va="center", fontsize=30)

# Input
ax = column_title(outer[0], 'Input "3"', "28 × 28 pixels (int8)", "black")
ax_img = fig.add_subplot(outer[0].subgridspec(3, 1)[1])
ax_img.imshow(x[0], cmap="gray", vmin=0, vmax=127); ax_img.set_xticks([]); ax_img.set_yticks([])
arrow(outer[1])

maps(outer[2], r1, "Conv1 + ReLU\n8 filters of 3×3 → 26×26×8", "48,672 MACs on the accelerator", HW)
arrow(outer[3])
maps(outer[4], a1, "MaxPool 2×2\n→ 13×13×8", "testbench", SW)
arrow(outer[5])
maps(outer[6], r2, "Conv2 + ReLU\n8 filters of 3×3×8 → 11×11×8", "69,696 MACs on the accelerator", HW)
arrow(outer[7])
maps(outer[8], a2, "MaxPool 2×2\n→ 5×5×8 = 200", "testbench", SW)
arrow(outer[9])

# Dense scores
column_title(outer[10], "Dense 200 → 10 scores", "2,000 MACs on the accelerator", HW)
ax = fig.add_subplot(outer[10].subgridspec(5, 1)[1:4])
colors = [HW if d == pred else "#C8C8C8" for d in range(10)]
ax.barh(range(10), scores[:10], color=colors)
ax.set_yticks(range(10)); ax.invert_yaxis(); ax.axvline(0, color="black", lw=0.8)
ax.set_xticks([]); ax.tick_params(axis="y", labelsize=11)
for s in ("top", "right", "bottom"): ax.spines[s].set_visible(False)
ax.set_title(f"biggest score → predicted {pred}", fontsize=11, color=HW, weight="bold")

fig.suptitle("How the CNN sees a 3: every layer, computed in INT8 (all multiply-accumulates run on the systolic array)",
             fontsize=15, y=1.06)
fig.savefig("cnn_layers_on_3.png", dpi=150, bbox_inches="tight")
plt.show()

from google.colab import files
files.download("cnn_layers_on_3.png")
