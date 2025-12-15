#!/usr/bin/env python3
import argparse
import os
import pandas as pd
import matplotlib.pyplot as plt

def savefig(path):
  plt.tight_layout()
  plt.savefig(path, dpi=200)
  plt.close()

def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--in", dest="inp", required=True)
  ap.add_argument("--outdir", required=True)
  args = ap.parse_args()

  os.makedirs(args.outdir, exist_ok=True)
  df = pd.read_csv(args.inp)

  # Aggregate across repetitions (seed) -> mean and std
  gcols = ["variant","workload","nkeys","threads"]
  agg = df.groupby(gcols)["ops_per_s"].agg(["mean","std","count"]).reset_index()

  # Throughput vs threads for each workload and size
  for nkeys in sorted(agg["nkeys"].unique()):
    for workload in sorted(agg["workload"].unique()):
      sub = agg[(agg["nkeys"]==nkeys) & (agg["workload"]==workload)]
      if sub.empty: 
        continue
      plt.figure()
      for variant in sorted(sub["variant"].unique()):
        s2 = sub[sub["variant"]==variant].sort_values("threads")
        plt.errorbar(s2["threads"], s2["mean"], yerr=s2["std"], marker="o", label=variant)
      plt.xlabel("Threads")
      plt.ylabel("Throughput (ops/s)")
      plt.title(f"Throughput vs Threads (nkeys={nkeys}, workload={workload})")
      plt.legend()
      savefig(os.path.join(args.outdir, f"fig_throughput_n{nkeys}_{workload}.png"))

  # Speedup vs threads (relative to 1-thread mean within each variant/workload/nkeys)
  base = agg[agg["threads"]==1][["variant","workload","nkeys","mean"]].rename(columns={"mean":"mean_1t"})
  merged = agg.merge(base, on=["variant","workload","nkeys"], how="left")
  merged["speedup"] = merged["mean"] / merged["mean_1t"]

  for nkeys in sorted(merged["nkeys"].unique()):
    for workload in sorted(merged["workload"].unique()):
      sub = merged[(merged["nkeys"]==nkeys) & (merged["workload"]==workload)]
      if sub.empty: 
        continue
      plt.figure()
      for variant in sorted(sub["variant"].unique()):
        s2 = sub[sub["variant"]==variant].sort_values("threads")
        plt.plot(s2["threads"], s2["speedup"], marker="o", label=variant)
      plt.xlabel("Threads")
      plt.ylabel("Speedup vs 1 thread")
      plt.title(f"Speedup vs Threads (nkeys={nkeys}, workload={workload})")
      plt.legend()
      savefig(os.path.join(args.outdir, f"fig_speedup_n{nkeys}_{workload}.png"))

  # Optional: cycles per op plot if present and numeric
  if "cycles_per_op" in df.columns:
    df2 = df.copy()
    df2["cycles_per_op"] = pd.to_numeric(df2["cycles_per_op"], errors="coerce")
    if df2["cycles_per_op"].notna().any():
      agg2 = df2.groupby(gcols)["cycles_per_op"].agg(["mean","std"]).reset_index()
      for nkeys in sorted(agg2["nkeys"].unique()):
        for workload in sorted(agg2["workload"].unique()):
          sub = agg2[(agg2["nkeys"]==nkeys) & (agg2["workload"]==workload)]
          if sub.empty: 
            continue
          plt.figure()
          for variant in sorted(sub["variant"].unique()):
            s2 = sub[sub["variant"]==variant].sort_values("threads")
            plt.errorbar(s2["threads"], s2["mean"], yerr=s2["std"], marker="o", label=variant)
          plt.xlabel("Threads")
          plt.ylabel("Cycles per operation")
          plt.title(f"Cycles/op vs Threads (nkeys={nkeys}, workload={workload})")
          plt.legend()
          savefig(os.path.join(args.outdir, f"fig_cycles_per_op_n{nkeys}_{workload}.png"))

if __name__ == "__main__":
  main()
