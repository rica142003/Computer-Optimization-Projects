#!/usr/bin/env python3
import sys
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

def mean_std(x):
    x = np.asarray(x, dtype=float)
    x = x[~np.isnan(x)]
    if len(x) == 0:
        return np.nan, np.nan
    return float(np.mean(x)), float(np.std(x, ddof=1)) if len(x) > 1 else 0.0

def savefig(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    plt.tight_layout()
    plt.savefig(path, dpi=200)
    plt.close()

def main():
    if len(sys.argv) != 3:
        print("usage: plot_a3.py <results.csv> <out_dir>")
        sys.exit(2)
    csv_path = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    df = pd.read_csv(csv_path)

    for col in ["target_fpr","achieved_fpr","bpe","neg_share","load_factor","ops_per_s","p50_ns","p95_ns","p99_ns","threads","fp_bits"]:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    # 1) BPE vs achieved FPR
    d1 = df[(df["workload"]=="read_only") & df["achieved_fpr"].notna() & df["bpe"].notna()].copy()
    for dist in sorted(d1["dist"].dropna().unique()):
        subd = d1[d1["dist"]==dist]
        for tfpr in sorted(subd["target_fpr"].dropna().unique()):
            sub = subd[subd["target_fpr"]==tfpr]
            g = sub.groupby(["filter","fp_bits"], dropna=False)
            rows=[]
            for (filt, fpb), s in g:
                bm, bs = mean_std(s["bpe"])
                fm, fs = mean_std(s["achieved_fpr"])
                rows.append({"filter":filt,"fp_bits":fpb,"bpe_mean":bm,"bpe_std":bs,"fpr_mean":fm,"fpr_std":fs})
            agg = pd.DataFrame(rows)
            plt.figure()
            for filt in sorted(agg["filter"].unique()):
                ss = agg[agg["filter"]==filt]
                plt.scatter(ss["fpr_mean"], ss["bpe_mean"], label=filt)
            plt.xscale("log")
            plt.xlabel("Achieved FPR (log)")
            plt.ylabel("Bits per entry (BPE)")
            plt.title(f"BPE vs Achieved FPR (dist={dist}, target_fpr={tfpr})")
            plt.legend()
            savefig(out_dir/f"bpe_vs_fpr_{dist}_tfpr_{tfpr}.png")

    # 2) Throughput vs negative share (read-only, target=1%)
    d2 = df[(df["workload"]=="read_only") & df["ops_per_s"].notna()].copy()
    for dist in sorted(d2["dist"].dropna().unique()):
        subd = d2[d2["dist"]==dist]
        subd = subd[np.isclose(subd["target_fpr"], 0.01, atol=1e-12)]
        g = subd.groupby(["filter","neg_share"], dropna=False)
        rows=[]
        for (filt, neg), s in g:
            m, sd = mean_std(s["ops_per_s"])
            rows.append({"filter":filt,"neg_share":neg,"ops_mean":m,"ops_std":sd})
        agg = pd.DataFrame(rows)
        plt.figure()
        for filt in sorted(agg["filter"].unique()):
            ss = agg[agg["filter"]==filt].sort_values("neg_share")
            plt.errorbar(ss["neg_share"], ss["ops_mean"], yerr=ss["ops_std"], marker="o", label=filt, capsize=3)
        plt.xlabel("Negative-lookup share")
        plt.ylabel("Queries/sec (mean ± std)")
        plt.title(f"Throughput vs Negative Share (dist={dist}, read-only)")
        plt.legend()
        savefig(out_dir/f"throughput_vs_negative_{dist}.png")

    # 2b) p95 latency vs negative share
    if "p95_ns" in df.columns:
        d2b = df[(df["workload"]=="read_only") & df["p95_ns"].notna()].copy()
        for dist in sorted(d2b["dist"].dropna().unique()):
            subd = d2b[d2b["dist"]==dist]
            subd = subd[np.isclose(subd["target_fpr"], 0.01, atol=1e-12)]
            g = subd.groupby(["filter","neg_share"], dropna=False)
            rows=[]
            for (filt, neg), s in g:
                m, sd = mean_std(s["p95_ns"])
                rows.append({"filter":filt,"neg_share":neg,"p95_mean":m,"p95_std":sd})
            agg = pd.DataFrame(rows)
            plt.figure()
            for filt in sorted(agg["filter"].unique()):
                ss = agg[agg["filter"]==filt].sort_values("neg_share")
                plt.errorbar(ss["neg_share"], ss["p95_mean"], yerr=ss["p95_std"], marker="o", label=filt, capsize=3)
            plt.xlabel("Negative-lookup share")
            plt.ylabel("p95 latency (ns)")
            plt.title(f"p95 vs Negative Share (dist={dist}, read-only)")
            plt.legend()
            savefig(out_dir/f"p95_vs_negative_{dist}.png")

    # 3) Insert/delete throughput vs load factor (balanced, dynamic)
    d3 = df[(df["workload"]=="balanced") & df["ops_per_s"].notna() & df["load_factor"].notna()].copy()
    for dist in sorted(d3["dist"].dropna().unique()):
        subd = d3[d3["dist"]==dist]
        g = subd.groupby(["filter","load_factor"], dropna=False)
        rows=[]
        for (filt, lf), s in g:
            m, sd = mean_std(s["ops_per_s"])
            rows.append({"filter":filt,"load_factor":lf,"ops_mean":m,"ops_std":sd})
        agg = pd.DataFrame(rows)
        if len(agg)==0:
            continue
        plt.figure()
        for filt in sorted(agg["filter"].unique()):
            ss = agg[agg["filter"]==filt].sort_values("load_factor")
            plt.errorbar(ss["load_factor"], ss["ops_mean"], yerr=ss["ops_std"], marker="o", label=filt, capsize=3)
        plt.xlabel("Load factor")
        plt.ylabel("Ops/sec (mean ± std)")
        plt.title(f"Insert/Delete Throughput vs Load Factor (dist={dist})")
        plt.legend()
        savefig(out_dir/f"insert_delete_vs_load_{dist}.png")

    # 4) Thread scaling (read_mostly, balanced)
    d4 = df[df["workload"].isin(["read_mostly","balanced"]) & df["ops_per_s"].notna() & df["threads"].notna()].copy()
    for dist in sorted(d4["dist"].dropna().unique()):
        subd = d4[d4["dist"]==dist]
        for wl in sorted(subd["workload"].unique()):
            sub = subd[subd["workload"]==wl]
            g = sub.groupby(["filter","threads"], dropna=False)
            rows=[]
            for (filt, th), s in g:
                m, sd = mean_std(s["ops_per_s"])
                rows.append({"filter":filt,"threads":th,"ops_mean":m,"ops_std":sd})
            agg = pd.DataFrame(rows)
            if len(agg)==0:
                continue
            plt.figure()
            for filt in sorted(agg["filter"].unique()):
                ss = agg[agg["filter"]==filt].sort_values("threads")
                plt.errorbar(ss["threads"], ss["ops_mean"], yerr=ss["ops_std"], marker="o", label=filt, capsize=3)
            plt.xlabel("Threads")
            plt.ylabel("Ops/sec (mean ± std)")
            plt.title(f"Thread scaling (dist={dist}, workload={wl})")
            plt.legend()
            savefig(out_dir/f"thread_scaling_{dist}_{wl}.png")

    extras = [c for c in ["fail_rate","avg_kicks","stash_hits","avg_probe","cluster_mean","cluster_p99"] if c in df.columns]
    if extras:
        out_dir.mkdir(parents=True, exist_ok=True)
        df[["filter","dist","workload","load_factor","threads","target_fpr"]+extras].to_csv(out_dir/"extra_stats.csv", index=False)

    print(f"Wrote plots to {out_dir}")

if __name__ == "__main__":
    main()
