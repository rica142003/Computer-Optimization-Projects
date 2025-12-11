import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

# --- Load CSVs ---
scalar_df = pd.read_csv("benchmark_results_novec.csv")
vec_df = pd.read_csv("benchmark_results_vec.csv")

# --- Average + std across trials ---
def summarize(df):
    return df.groupby(["Kernel", "Size"]).agg(
        Time_mean=("Time_ns", "mean"),
        Time_std=("Time_ns", "std"),
        GFLOPs_mean=("GFLOPs", "mean"),
        GFLOPs_std=("GFLOPs", "std")
    ).reset_index()

scalar_summary = summarize(scalar_df)
vec_summary = summarize(vec_df)

# --- Merge scalar & vectorized ---
merged = pd.merge(
    scalar_summary,
    vec_summary,
    on=["Kernel", "Size"],
    suffixes=("_scalar", "_vec")
)

# --- Compute speedup and error bars (propagation of std) ---
merged["Speedup"] = merged["Time_mean_scalar"] / merged["Time_mean_vec"]
merged["Speedup_std"] = merged["Speedup"] * np.sqrt(
    (merged["Time_std_scalar"] / merged["Time_mean_scalar"])**2 +
    (merged["Time_std_vec"] / merged["Time_mean_vec"])**2
)

# Calculate correct cache boundaries based on your actual cache sizes
# We're using 3 arrays of floats (4 bytes each), so total memory = 12 * n bytes
cache_sizes = {
    "L1d (384 KiB)": 384 * 1024 / 12,    # 384 KiB in bytes / 12 bytes per element
    "L2 (10 MiB)": 10 * 1024 * 1024 / 12, # 10 MiB in bytes / 12 bytes per element
    "L3 (18 MiB)": 18 * 1024 * 1024 / 12  # 18 MiB in bytes / 12 bytes per element
}

# --- Plot 1: Speedup vs Size ---
plt.figure(figsize=(10, 6))
for kernel in merged["Kernel"].unique():
    subset = merged[merged["Kernel"] == kernel]
    plt.errorbar(
        subset["Size"], subset["Speedup"],
        yerr=subset["Speedup_std"], fmt='-o', capsize=4, label=kernel
    )

# Add vertical lines at correct cache sizes
for label, size in cache_sizes.items():
    plt.axvline(x=size, color="red", linestyle="--", alpha=0.7)
    plt.text(size, plt.ylim()[1]*0.9, label, rotation=90, va="top", ha="right", fontsize=8)

plt.xscale("log")
plt.xlabel("Problem Size (number of elements)")
plt.ylabel("Speedup (Scalar / Vectorized)")
plt.title("Speedup vs Problem Size")
plt.legend()
plt.grid(True, which="both", ls="--")
plt.tight_layout()
plt.savefig("speedup_vs_size.png")
plt.show()

# --- Plot 2: Scalar GFLOPs/s vs Size ---
plt.figure(figsize=(10, 6))
for kernel in scalar_summary["Kernel"].unique():
    subset = scalar_summary[scalar_summary["Kernel"] == kernel]
    plt.errorbar(
        subset["Size"], subset["GFLOPs_mean"],
        yerr=subset["GFLOPs_std"], fmt='-o', capsize=4, label=kernel
    )

# Add cache lines again
for label, size in cache_sizes.items():
    plt.axvline(x=size, color="red", linestyle="--", alpha=0.7)
    plt.text(size, plt.ylim()[1]*0.9, label, rotation=90, va="top", ha="right", fontsize=8)

plt.xscale("log")
plt.xlabel("Problem Size (number of elements)")
plt.ylabel("GFLOPs/s (Scalar)")
plt.title("Scalar GFLOPs/s vs Problem Size")
plt.legend()
plt.grid(True, which="both", ls="--")
plt.tight_layout()
plt.savefig("scalar_gflops_vs_size.png")
plt.show()

# --- Plot 3: Vectorized GFLOPs/s vs Size ---
plt.figure(figsize=(10, 6))
for kernel in vec_summary["Kernel"].unique():
    subset = vec_summary[vec_summary["Kernel"] == kernel]
    plt.errorbar(
        subset["Size"], subset["GFLOPs_mean"],
        yerr=subset["GFLOPs_std"], fmt='-o', capsize=4, label=kernel
    )

# Add cache lines again
for label, size in cache_sizes.items():
    plt.axvline(x=size, color="red", linestyle="--", alpha=0.7)
    plt.text(size, plt.ylim()[1]*0.9, label, rotation=90, va="top", ha="right", fontsize=8)

plt.xscale("log")
plt.xlabel("Problem Size (number of elements)")
plt.ylabel("GFLOPs/s (Vectorized)")
plt.title("Vectorized GFLOPs/s vs Problem Size")
plt.legend()
plt.grid(True, which="both", ls="--")
plt.tight_layout()
plt.savefig("vectorized_gflops_vs_size.png")
plt.show()