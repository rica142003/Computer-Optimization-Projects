#!/usr/bin/env python3
import argparse, csv, glob, os, re
from collections import defaultdict

# Combines:
#  - bench_*.csv : single CSV line produced by a4_bench
#  - perf_*.csv  : perf stat output in CSV (-x,). Multiple lines, one per event.
#
# Output: results.csv with benchmark columns plus perf columns and derived "cycles_per_op" etc.
#
# Expected benchmark header:
# variant,workload,nkeys,threads,seconds,seed,ops,total_finds,total_inserts,total_misses,ops_per_s
#
# Perf CSV format (common):
# value,unit,event, ... (fields can vary slightly across perf versions)
# We read first 3 columns: value, unit, event

def read_bench(path):
  with open(path, "r") as f:
    line = f.read().strip().splitlines()[-1]
  parts = line.split(",")
  if len(parts) < 11:
    raise ValueError(f"bad bench line in {path}: {line}")
  keys = ["variant","workload","nkeys","threads","seconds","seed","ops","total_finds","total_inserts","total_misses","ops_per_s"]
  row = dict(zip(keys, parts[:11]))
  # cast numerics
  for k in ["nkeys","threads","seconds","seed","ops","total_finds","total_inserts","total_misses"]:
    row[k] = int(row[k])
  row["ops_per_s"] = float(row["ops_per_s"])
  return row

def read_perf(path):
  events = {}
  with open(path, "r") as f:
    for line in f:
      line = line.strip()
      if not line: continue
      cols = [c.strip() for c in line.split(",")]
      if len(cols) < 3: continue
      val, unit, event = cols[0], cols[1], cols[2]
      # skip <not counted> and <not supported>
      if "<not" in val: 
        continue
      # remove thousands separators
      val = val.replace(",", "")
      try:
        v = float(val)
      except:
        continue
      events[event] = v
  return events

def key_from_name(fname):
  # bench_{v}_{w}_n{n}_t{t}_s{secs}_r{seed}.csv
  m = re.search(r"bench_(\w+)_(\w+)_n(\d+)_t(\d+)_s(\d+)_r(\d+)\.csv$", fname)
  if not m:
    return None
  return tuple(m.groups())

def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--rawdir", required=True)
  ap.add_argument("--out", required=True)
  args = ap.parse_args()

  bench_files = glob.glob(os.path.join(args.rawdir, "bench_*.csv"))
  rows = []

  for b in sorted(bench_files):
    k = key_from_name(os.path.basename(b))
    if not k: 
      continue
    v,w,n,t,secs,seed = k
    perf_path = os.path.join(args.rawdir, f"perf_{v}_{w}_n{n}_t{t}_s{secs}_r{seed}.csv")
    if not os.path.exists(perf_path):
      continue
    bench = read_bench(b)
    perf = read_perf(perf_path)

    cycles = perf.get("cycles")
    llc_lm = perf.get("LLC-load-misses")
    llc_sm = perf.get("LLC-store-misses")
    if cycles is not None and bench["ops"] > 0:
      bench["cycles_per_op"] = cycles / bench["ops"]
    else:
      bench["cycles_per_op"] = ""
    bench["cycles"] = cycles if cycles is not None else ""
    bench["LLC-load-misses"] = llc_lm if llc_lm is not None else ""
    bench["LLC-store-misses"] = llc_sm if llc_sm is not None else ""
    rows.append(bench)

  fieldnames = ["variant","workload","nkeys","threads","seconds","seed","ops","total_finds","total_inserts","total_misses","ops_per_s",
                "cycles","LLC-load-misses","LLC-store-misses","cycles_per_op"]
  with open(args.out, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for r in rows:
      w.writerow(r)

if __name__ == "__main__":
  main()
