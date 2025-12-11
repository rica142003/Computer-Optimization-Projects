import re
import sys
import math
import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path

# ---------- helpers ----------
SIZE_RE = re.compile(r'(\w+)_([0-9]+[kKmMgG])')
JOB_HDR_RE = re.compile(r'^(\w+_[0-9]+[kKmMgG]): \(')
READWRITE_LINE = re.compile(r'^\s*(read|write): IOPS=([^,]+), BW=([\d\.]+)([KMG])iB/s')
CLAT_LINE = re.compile(r'^\s*clat .*avg=([\d\.]+)')

UNIT_KIB = {'K':1, 'M':1024, 'G':1024*1024}

def bs_to_bytes(bs:str) -> int:
    bs = bs.lower()
    if bs.endswith('k'): return int(bs[:-1]) * 1024
    if bs.endswith('m'): return int(bs[:-1]) * 1024 * 1024
    if bs.endswith('g'): return int(bs[:-1]) * 1024 * 1024 * 1024
    return int(bs)

def parse_fio_log(path: Path):
    """
    Returns rows: pattern, bs_label, bs_bytes, iotype(read/write), iops, bw_MBps, lat_us_avg
    """
    rows = []
    current = None  # dict with keys: name, pattern, bs_label

    with path.open() as f:
        for line in f:
            # detect section / job name header line printed by fio during results
            m = JOB_HDR_RE.match(line.strip())
            if m:
                name = m.group(1)  # e.g., randread_4k
                m2 = SIZE_RE.match(name)
                if not m2:
                    current = None
                    continue
                pattern = m2.group(1)      # randread / seqread etc.
                bs_label = m2.group(2).lower()
                current = {"name":name, "pattern":pattern, "bs_label":bs_label,
                           "iops":None, "bw_MBps":None, "lat_us":None, "iotype":None}
                continue

            if current is None:
                continue

            # read/write throughput line
            mrw = READWRITE_LINE.match(line)
            if mrw:
                iotype = mrw.group(1)                        # read or write
                iops_str = mrw.group(2).strip()              # may contain decimals
                bw_val = float(mrw.group(3))
                bw_unit = mrw.group(4)
                # IOPS can be like "1.2k" too; normalize
                if iops_str.endswith('k'):
                    iops = float(iops_str[:-1]) * 1_000
                elif iops_str.endswith('M'):
                    iops = float(iops_str[:-1]) * 1_000_000
                else:
                    try:
                        iops = float(iops_str)
                    except:
                        iops = None
                bw_kib = bw_val * UNIT_KIB[bw_unit]
                current["iotype"] = iotype
                current["iops"] = iops
                current["bw_MBps"] = bw_kib / 1024.0
                continue

            # clat avg line
            mlat = CLAT_LINE.match(line)
            if mlat:
                current["lat_us"] = float(mlat.group(1))
                # finalize row once we have avg latency; bs known from header
                row = dict(current)  # copy
                row["bs_bytes"] = bs_to_bytes(current["bs_label"])
                rows.append(row)
                current = None

    return rows

def build_matrix(rows):
    df = pd.DataFrame(rows)
    # Keep only read rows for this assignment if you ran read sweeps; but leave writes if present
    df["pattern_norm"] = df["pattern"].str.replace('seqread','read').str.replace('seqwrite','write')
    df = df.sort_values(["pattern_norm","bs_bytes","iotype"])
    return df

def save_matrix_csvs(df: pd.DataFrame, outprefix: str):
    for patt in sorted(df["pattern_norm"].unique()):
        d = df[df["pattern_norm"]==patt].copy()
        d["lat_ms"] = d["lat_us"]/1000.0
        d = d[["bs_label","iotype","iops","bw_MBps","lat_ms"]]
        d.to_csv(f"{outprefix}_{patt}_matrix.csv", index=False)

def plot_pattern(df_pat: pd.DataFrame, patt_label: str, outprefix: str):
    # Choose READ rows if available, else WRITE
    if "read" in df_pat["iotype"].unique():
        d = df_pat[df_pat["iotype"]=="read"].copy()
        rw = "read"
    else:
        d = df_pat[df_pat["iotype"]=="write"].copy()
        rw = "write"

    d = d.sort_values("bs_bytes")
    # Throughput figure (dual axis)
    fig, ax1 = plt.subplots()
    ax1.set_xscale("log", base=2)
    ax1.plot(d["bs_bytes"], d["iops"], marker="o", label="IOPS")
    ax1.set_xlabel("Block size (bytes, log2)")
    ax1.set_ylabel("IOPS")
    ax1.grid(True, which="both", axis="both", linestyle=":")
    # secondary axis for MB/s
    ax2 = ax1.twinx()
    ax2.plot(d["bs_bytes"], d["bw_MBps"], marker="s", linestyle="--", label="MB/s")
    ax2.set_ylabel("Throughput (MB/s)")

    # Crossover markers
    for x in [64*1024, 128*1024]:
        ax1.axvline(x, linestyle="--", alpha=0.5)
    ax1.text(64*1024, ax1.get_ylim()[1]*0.9, "64 KiB", rotation=90, va="top", ha="right")
    ax1.text(128*1024, ax1.get_ylim()[1]*0.9, "128 KiB", rotation=90, va="top", ha="right")

    plt.title(f"Block-size Sweep ({patt_label}, {rw}): IOPS & MB/s")
    fig.tight_layout()
    fig.savefig(f"{outprefix}_{patt_label}_{rw}_throughput.png", dpi=150)

    # Latency figure
    plt.figure()
    plt.xscale("log", base=2)
    plt.plot(d["bs_bytes"], d["lat_us"]/1000.0, marker="o")
    for x in [64*1024, 128*1024]:
        plt.axvline(x, linestyle="--", alpha=0.5)
    plt.xlabel("Block size (bytes, log2)")
    plt.ylabel("Avg Latency (ms)")
    plt.title(f"Block-size Sweep ({patt_label}, {rw}): Avg Latency")
    plt.grid(True, which="both", linestyle=":")
    plt.tight_layout()
    plt.savefig(f"{outprefix}_{patt_label}_{rw}_latency.png", dpi=150)

def main():
    # default files; pass custom filenames as args if you like
    in1 = Path("bsweep_randread.txt")
    in2 = Path("bsweep_seqread.txt")
    if len(sys.argv) >= 2: in1 = Path(sys.argv[1])
    if len(sys.argv) >= 3: in2 = Path(sys.argv[2])

    rows = []
    if in1.exists(): rows += parse_fio_log(in1)
    if in2.exists(): rows += parse_fio_log(in2)

    if not rows:
        print("No data parsed. Did you run fio and save outputs?")
        sys.exit(1)

    df = build_matrix(rows)
    # Normalize pattern names to {randread, read, randwrite, write}
    df["pattern_norm"] = df["pattern"].str.replace('seqread','read').str.replace('seqwrite','write')
    outprefix = "bsweep"

    # Save matrices
    save_matrix_csvs(df, outprefix)

    # Produce plots for each pattern present
    for patt in sorted(df["pattern_norm"].unique()):
        df_pat = df[df["pattern_norm"]==patt]
        pretty = "Random" if "rand" in patt else "Sequential"
        plot_pattern(df_pat, pretty, outprefix)

    print("Done. Wrote CSVs and PNGs with prefix:", outprefix)

if __name__ == "__main__":
    main()
