import re
import pandas as pd
import matplotlib.pyplot as plt

def parse_tail_latency(filename):
    results = []
    current_job = None
    with open(filename) as f:
        for line in f:
            # Detect job header
            if line.strip().startswith("qd") and ":" in line:
                current_job = line.split(":")[0].strip()
            if "percentiles" in line:
                for _ in range(2):  # just the next couple of lines
                    l = next(f)
                    matches = re.findall(r'(\d+\.?9*)th=\[\s*([0-9]+)\]', l)
                    for perc, val in matches:
                        results.append({
                            "job": current_job,
                            "percentile": perc,
                            "lat_us": int(val),
                            "type": "clat" if "clat" in line else "lat"
                        })

    return pd.DataFrame(results)

# -------- Main --------
df = parse_tail_latency("tail_latency_output.txt")

if df.empty:
    raise RuntimeError("No percentile data found. Did fio run with lat_percentiles?")

# Average duplicate entries
df = df.groupby(["job","percentile"], as_index=False)["lat_us"].mean()

# Pivot wide
pivot = df.pivot(index="job", columns="percentile", values="lat_us").reset_index()

# Convert µs → ms
for c in pivot.columns:
    if c != "job":
        pivot[c] = pivot[c] / 1000.0

pivot.to_csv("tail_latency_summary.csv", index=False)

# Markdown table
print("| Job | p50 (ms) | p95 (ms) | p99 (ms) | p99.9 (ms) |")
print("|-----|----------|----------|----------|------------|")
for _, row in pivot.iterrows():
    print(f"| {row['job']} | {row.get('50', float('nan')):.2f} | {row.get('95', float('nan')):.2f} | {row.get('99', float('nan')):.2f} | {row.get('99.9', float('nan')):.2f} |")

# Plot tail latency vs QD
pivot["qd"] = pivot["job"].str.extract(r'qd(\d+)').astype(int)
pivot = pivot.sort_values("qd")

plt.figure(figsize=(7,5))
for perc in ["50","95","99","99.9"]:
    if perc in pivot.columns:
        plt.plot(pivot["qd"], pivot[perc], marker="o", label=f"p{perc}")
plt.xscale("log", base=2)
plt.yscale("log")
plt.xlabel("Queue Depth (log2)")
plt.ylabel("Latency (ms, log)")
plt.title("Tail Latency vs Queue Depth (4 KiB random read)")
plt.grid(True, which="both", linestyle=":")
plt.legend()
plt.tight_layout()
plt.savefig("tail_latency_plot.png", dpi=150)
plt.show()
