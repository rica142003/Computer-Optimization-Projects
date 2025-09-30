import re, sys, math, statistics as stats
from pathlib import Path
import pandas as pd
import matplotlib.pyplot as plt

READLINE = re.compile(r'^\s*read:\s+IOPS=([^,]+), BW=([\d\.]+)([KMG])iB/s')
CLATAVG  = re.compile(r'^\s*clat .*avg=([\d\.]+)')
P95      = re.compile(r'^\s*clat percentiles.*')
PERC     = re.compile(r'^\s*\|\s*50th=\[[^\]]+\],\s*95th=\[\s*([0-9]+)\],\s*99th=\[\s*([0-9]+)\]')

UNIT = {"K":1, "M":1024, "G":1024*1024}



def parse_one(path: Path):
    """Return dict with iodepth/qd and performance stats for one fio log."""
    qd = None
    for token in path.stem.split("_"):
        if token.startswith("qd") and token[2:].isdigit():
            qd = int(token[2:])
            break
    if qd is None:
        return None
    ...

    iops = mbps = lat_us = None
    p95_us = p99_us = None
    saw_p95_header = False

    with path.open() as f:
        for line in f:
            m = READLINE.match(line)
            if m and iops is None:
                iops_str, bw_val, unit = m.groups()
                # Normalize IOPS like "1.6k"
                if iops_str.endswith('k'): I = float(iops_str[:-1]) * 1_000
                elif iops_str.endswith('M'): I = float(iops_str[:-1]) * 1_000_000
                else: I = float(iops_str)
                iops = I
                mbps = (float(bw_val) * UNIT[unit]) / 1024.0  # KiB/s -> MB/s
                continue
            m = CLATAVG.match(line)
            if m and lat_us is None:
                lat_us = float(m.group(1))
                continue
            if P95.match(line):      # next line holds percentiles block
                saw_p95_header = True
                continue
            if saw_p95_header:
                saw_p95_header = False
                mp = PERC.match(line)
                if mp:
                    p95_us = float(mp.group(1))
                    p99_us = float(mp.group(2))
    if None in (iops, mbps, lat_us):
        return None
    return {"qd": qd, "iops": iops, "mbps": mbps,
            "lat_us": lat_us, "p95_us": p95_us, "p99_us": p99_us}

def aggregate(logdir: Path):
    rows = []
    for p in sorted(logdir.glob("*.txt")):
        rec = parse_one(p)
        if rec: rows.append({"qd":rec["qd"], **rec})
    df = pd.DataFrame(rows)
    if df.empty:
        raise SystemExit(f"No parsed data in {logdir}")
    # group by QD and compute mean/std
    agg = df.groupby("qd").agg(
        iops_mean=("iops","mean"),   iops_std=("iops","std"),
        mbps_mean=("mbps","mean"),   mbps_std=("mbps","std"),
        lat_mean=("lat_us","mean"),  lat_std=("lat_us","std"),
        p95_mean=("p95_us","mean"),  p99_mean=("p99_us","mean")
    ).reset_index().sort_values("qd")
    return agg

def find_knee(d):
    """
    Heuristic knee: first QD where throughput gain <5% over previous
    while latency jump >20% over previous (Little’s-law pain zone).
    """
    for i in range(1, len(d)):
        t_prev, t_now = d["mbps_mean"].iloc[i-1], d["mbps_mean"].iloc[i]
        L_prev, L_now = d["lat_mean"].iloc[i-1], d["lat_mean"].iloc[i]
        if t_prev <= 0: continue
        gain = (t_now - t_prev)/t_prev
        blow = (L_now - L_prev)/L_prev if L_prev>0 else 0
        if gain < 0.05 and blow > 0.20:
            return int(d["qd"].iloc[i])
    return int(d["qd"].iloc[d["mbps_mean"].idxmax()])  # fallback: peak tput

def main():
    if len(sys.argv) < 2:
        print("Usage: python plot_qd_curve.py <logdir> [PEAK_MBps]")
        sys.exit(1)
    logdir = Path(sys.argv[1])
    peak = float(sys.argv[2]) if len(sys.argv) >= 3 else None

    d = aggregate(logdir)
    d["lat_ms_mean"] = d["lat_mean"] / 1000.0
    d["lat_ms_std"]  = d["lat_std"] / 1000.0

    knee_qd = find_knee(d)
    knee_row = d[d["qd"]==knee_qd].iloc[0]

    # % of peak (interface or vendor spec)
    pct_peak = None
    if peak:
        pct_peak = 100.0 * (d["mbps_mean"].max() / peak)

    # Save matrix
    d.to_csv(logdir / "qd_matrix.csv", index=False)

   
    # Plot: Throughput vs Latency (single curve with error bars)
    fig, ax = plt.subplots(figsize=(7,5))
    ax.errorbar(d["iops_mean"], d["lat_ms_mean"],
                xerr=d["iops_std"].fillna(0.0),
                yerr=d["lat_ms_std"].fillna(0.0),
                fmt="o-", capsize=3)

    for _, row in d.iterrows():
        ax.annotate(f"QD{int(row['qd'])}",
                    (row["iops_mean"], row["lat_ms_mean"]),
                    textcoords="offset points", xytext=(5,5), fontsize=8)

    # Knee marker
    ax.scatter([knee_row["iops_mean"]], [knee_row["lat_ms_mean"]],
            s=80, marker="D", color="red")
    ax.annotate(f"Knee @ QD={knee_qd}",
                (knee_row["iops_mean"], knee_row["lat_ms_mean"]),
                textcoords="offset points", xytext=(8,-12), fontsize=9)

    ax.set_xlabel("Throughput (IOPS)")
    ax.set_ylabel("Average Latency (ms)")
    ax.set_title("QD Sweep (4 KiB random): Latency vs Throughput")
    ax.grid(True, linestyle=":")
    fig.tight_layout()
    fig.savefig(logdir / "qd_latency_vs_tput.png", dpi=150)


    # Tail-latency note near knee (p95/p99)
    p95 = knee_row["p95_mean"]
    p99 = knee_row["p99_mean"]
    with open(logdir / "qd_notes.txt","w") as f:
        f.write(f"Knee QD = {knee_qd}\n")
        if peak:
            f.write(f"Peak throughput = {d['mbps_mean'].max():.2f} MB/s "
                    f"({pct_peak:.1f}% of {peak:.2f} MB/s spec)\n")
        if pd.notna(p95) and pd.notna(p99):
            f.write(f"Tail latency near knee: p95 ≈ {p95/1000:.2f} ms, p99 ≈ {p99/1000:.2f} ms\n")
        else:
            f.write("Tail percentiles not found in logs; enable percentile_list in fio.\n")

    # Console summary
    print("\n=== QD Matrix (means) ===")
    print(d[["qd","mbps_mean","lat_ms_mean","iops_mean"]])
    print(f"\nKnee identified at QD={knee_qd} (Little’s Law: T ≈ QD / Lat).")
    if peak:
        print(f"Peak throughput ≈ {d['mbps_mean'].max():.2f} MB/s "
              f"({pct_peak:.1f}% of provided peak {peak:.2f} MB/s).")
    if pd.notna(p95) and pd.notna(p99):
        print(f"Near knee tail-latency: p95≈{p95/1000:.2f} ms, p99≈{p99/1000:.2f} ms.")
    print(f"\nSaved: {logdir/'qd_matrix.csv'}, {logdir/'qd_tput_vs_latency.png'}, {logdir/'qd_notes.txt'}")

if __name__ == "__main__":
    main()
