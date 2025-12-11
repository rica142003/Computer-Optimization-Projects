import re
import pandas as pd
import matplotlib.pyplot as plt

def parse_rw_mix(filename):
    results = []
    current = None
    with open(filename) as f:
        for line in f:
            # Detect start of job section
            if line.startswith("rwmix_") and ":" in line:
                jobname = line.split(":")[0].strip()
                current = {"job": jobname}
                continue

            # Capture throughput line (requires a current job)
            if current is not None and "IOPS=" in line and ("read:" in line or "write:" in line):
                bw_match = re.search(r'BW=([\d\.]+)([KMG])iB/s', line)
                if bw_match:
                    bw_val = float(bw_match.group(1))
                    unit = bw_match.group(2)
                    scale = {"K":1, "M":1024, "G":1024*1024}
                    bw_kib = bw_val * scale[unit]
                    current["bw_MBps"] = bw_kib / 1024

            # Capture avg latency (close out record)
            if current is not None and "clat" in line and "avg=" in line:
                lat_match = re.search(r'avg=([\d\.]+)', line)
                if lat_match:
                    current["lat_us"] = float(lat_match.group(1))
                    results.append(current)
                    current = None  # reset for next job
    return pd.DataFrame(results)

# -------- Main --------
df = parse_rw_mix("rw_mix_output.txt")
if df.empty:
    raise RuntimeError("No jobs parsed — check rw_mix_output.txt formatting")

df["lat_ms"] = df["lat_us"] / 1000.0

# Sort jobs in desired order
order = ["rwmix_100R", "rwmix_70R30W", "rwmix_50R50W", "rwmix_100W"]
df["job"] = pd.Categorical(df["job"], categories=order, ordered=True)
df = df.sort_values("job")

print(df)

# Dual-axis plot
fig, ax1 = plt.subplots(figsize=(7,5))
ax1.bar(df["job"], df["bw_MBps"], color="tab:blue", alpha=0.7, label="Throughput (MB/s)")
ax1.set_ylabel("Throughput (MB/s)", color="tab:blue")
ax1.tick_params(axis="y", labelcolor="tab:blue")

ax2 = ax1.twinx()
ax2.plot(df["job"], df["lat_ms"], marker="o", color="tab:red", label="Latency (ms)")
ax2.set_ylabel("Avg Latency (ms)", color="tab:red")
ax2.tick_params(axis="y", labelcolor="tab:red")

plt.title("Read/Write Mix Sweep (4 KiB Random, QD=1)")
fig.tight_layout()
plt.savefig("rw_mix_sweep.png", dpi=150)
plt.show()
