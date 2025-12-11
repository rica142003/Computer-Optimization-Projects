import pandas as pd
import matplotlib.pyplot as plt

def plot_alignment_tail(csv_file, metric="Runtime", cpu_freq=2.5e9):
    """
    Plot aligned vs misaligned performance from CSV results.

    Parameters:
        csv_file (str): Path to the CSV file.
        metric (str): One of "Runtime", "GFLOPs", or "CPE".
        cpu_freq (float): CPU frequency in Hz (needed for CPE).
    """
    # Load CSV
    df = pd.read_csv(csv_file)

    # Add derived CPE column if needed
    if metric == "CPE":
        df["CPE"] = (df["Time_ns"] * 1e-9 * cpu_freq) / df["Size"]

    # Pick column based on metric
    if metric == "Runtime":
        y_col, y_label, scale = "Time_ns", "Runtime (ms)", 1e6
    elif metric == "GFLOPs":
        y_col, y_label, scale = "GFLOPs", "GFLOP/s", 1
    elif metric == "CPE":
        y_col, y_label, scale = "CPE", "Cycles per Element (CPE)", 1
    else:
        raise ValueError("metric must be 'Runtime', 'GFLOPs', or 'CPE'")

    # Group by Case and Size for mean/std
    summary = df.groupby(["Case", "Size"]).agg(
        mean=(y_col, "mean"),
        std=(y_col, "std")
    ).reset_index()

    # Separate aligned and misaligned
    aligned = summary[summary["Case"] == "Aligned"]
    misaligned = summary[summary["Case"] == "Misaligned"]

    # Plot with error bars
    plt.errorbar(aligned["Size"], aligned["mean"]/scale, yerr=aligned["std"]/scale,
                 fmt="-o", capsize=4, label="Aligned")
    plt.errorbar(misaligned["Size"], misaligned["mean"]/scale, yerr=misaligned["std"]/scale,
                 fmt="-o", capsize=4, label="Misaligned")

    plt.xlabel("Problem Size")
    plt.ylabel(y_label)
    plt.title(f"Aligned vs Misaligned ({metric})")
    plt.legend()
    plt.grid(True)
    plt.xscale("log", base=2)
    plt.show()


# Example usage:
# plot_alignment_tail("alignment_tail_results.csv", metric="Runtime")
# plot_alignment_tail("alignment_tail_results.csv", metric="GFLOPs")
# plot_alignment_tail("alignment_tail_results.csv", metric="CPE", cpu_freq=2.5e9)
