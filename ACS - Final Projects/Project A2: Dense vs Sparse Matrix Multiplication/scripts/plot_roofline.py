import numpy as np
import matplotlib.pyplot as plt

# -----------------------------
# USER INPUTS (fill these in)
# -----------------------------

# Sustained memory bandwidth in GB/s (use STREAM Triad or your own microbench)
BW_GBps = 35.0   # <-- replace with your measuwhite BW

# Peak compute in GFLOP/s (theoretical or measuwhite)
PEAK_GFLOPS = 300.0  # <-- replace if you compute a better estimate

# Achieved points (Arithmetic Intensity in FLOP/byte, Achieved GFLOP/s)
# Put a few representative points from your experiments.
points = [
    # label, AI (FLOP/byte), achieved GFLOP/s
    ("Dense GEMM (n=1024)", 8.0, 30.0),
    ("CSR SpMM (n=1024, p=0.01)", 0.25, 4.5),
]

# Optional vertical dashed reference lines (AI markers), like your screenshot
ai_markers = [0.25, 1.0, 8.0]  # put whatever helps you tell the story

# -----------------------------
# Roofline construction
# -----------------------------
def roofline(ai):
    mem_roof = BW_GBps * ai  # (GB/s)*(FLOP/byte) = GFLOP/s
    return np.minimum(mem_roof, PEAK_GFLOPS)

if __name__ == "__main__":
    # AI axis range (log)
    ai = np.logspace(-3, 3, 400)
    perf = roofline(ai)

    # Dark theme to mimic your example
    plt.figure(figsize=(10, 4), dpi=150)
    ax = plt.gca()
    ax.set_facecolor("white")
    plt.gcf().patch.set_facecolor("white")

    # Roofline curve (black)
    ax.plot(ai, perf, linewidth=3)

    # Memory roof (optional: draw the slanted part separately for clarity)
    mem_roof = BW_GBps * ai
    ax.plot(ai, np.minimum(mem_roof, PEAK_GFLOPS), linewidth=3)

    # Compute roof (horizontal line)
    ax.hlines(PEAK_GFLOPS, ai.min(), ai.max(), linestyles="-", linewidth=3)

    # Vertical dashed markers (like your example)
    for x in ai_markers:
        ax.vlines(x, 1e-3, PEAK_GFLOPS * 1.2, linestyles="--", linewidth=1.5)

    # Scatter your achieved points
    for label, ai_pt, gflops_pt in points:
        ax.scatter([ai_pt], [gflops_pt], s=60)
        ax.text(ai_pt*1.1, gflops_pt*1.05, label, fontsize=9)

    # Axes formatting
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel("Arithmetic Intensity (FLOP/byte)")
    ax.set_ylabel("Performance (GFLOP/s)")
    ax.set_title("Roofline Model")

    # Make text/axes black to show on white
    for spine in ax.spines.values():
        spine.set_color("black")
    ax.tick_params(colors="black")
    ax.xaxis.label.set_color("black")
    ax.yaxis.label.set_color("black")
    ax.title.set_color("black")

    ax.grid(False)  # your example doesn’t show grid
    plt.tight_layout()

    out = "plots/roofline.png"
    import os
    os.makedirs("plots", exist_ok=True)
    plt.savefig(out, facecolor="white", bbox_inches="tight")
    print(f"Saved {out}")
