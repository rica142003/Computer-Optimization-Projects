import re
from pathlib import Path
import pandas as pd

# -----------------------------
# Config: update if needed
# -----------------------------
DATA_DIR = Path("data")
OUT_DIR = Path("tables")
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Benchmark CSV columns
BENCH_COLS = ["mode","m","k","n","density","threads","rep","ms","gflops","nnz",
              "colchunk","Ti","Tj","Tk","seed"]

# Perf events we care about
WANT_EVENTS = {"cycles", "instructions", "cache-misses", "LLC-load-misses", "branch-misses"}

def read_bench_csv(path: Path) -> pd.DataFrame:
    return pd.read_csv(path, header=None, names=BENCH_COLS)

def parse_perf_stat_csv(path: Path) -> pd.DataFrame:
    """
    Parse perf stat -x, output where events look like:
      cpu_atom/cycles/ , cpu_core/cycles/ , ...
    We extract the base event name and SUM across domains.
    """
    rows = []
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue

            parts = [p.strip() for p in line.split(",")]
            if len(parts) < 3:
                continue

            # value is usually first column
            val_str = parts[0].replace(",", "")
            try:
                value = float(val_str)
            except ValueError:
                continue

            # event is usually third column
            ev = parts[2]  # e.g., "cpu_core/cycles/"
            # Extract base event between slashes: cpu_core/<base>/
            m = re.match(r"[^/]+/([^/]+)/", ev)
            if not m:
                continue
            base_event = m.group(1)

            if base_event not in WANT_EVENTS:
                continue

            rows.append({"event": base_event, "value": value})

    df = pd.DataFrame(rows)
    if df.empty:
        raise RuntimeError(f"Could not parse events from {path}. Check perf output format.")

    # Sum cpu_atom + cpu_core
    df = df.groupby("event", as_index=False)["value"].sum()
    return df



def lookup_nnzs_from_bench(bench_df: pd.DataFrame, *, m, k, n, density, threads):
    """
    Find nnz and median ms for a given config from benchmark CSV.
    Uses a tolerant match for density due to floating formatting.
    """
    eps = 1e-12
    sub = bench_df[
        (bench_df["m"] == m) &
        (bench_df["k"] == k) &
        (bench_df["n"] == n) &
        (bench_df["threads"] == threads) &
        (bench_df["density"].between(density - eps, density + eps))
    ]
    if sub.empty:
        return None, None, None
    nnz = int(sub["nnz"].median()) if sub["nnz"].notna().any() else None
    ms_med = float(sub["ms"].median())
    gflops_med = float(sub["gflops"].median())
    return nnz, ms_med, gflops_med

def latex_table(df: pd.DataFrame, caption: str, label: str) -> str:
    """
    Generate a simple LaTeX table (booktabs style).
    """
    cols = list(df.columns)
    lines = []
    lines.append("\\begin{table}[H]")
    lines.append("\\centering")
    lines.append(f"\\caption{{{caption}}}")
    lines.append(f"\\label{{{label}}}")
    lines.append("\\begin{tabular}{" + "l" * len(cols) + "}")
    lines.append("\\toprule")
    lines.append(" & ".join([str(c) for c in cols]) + " \\\\")
    lines.append("\\midrule")
    for _, row in df.iterrows():
        vals = []
        for c in cols:
            v = row[c]
            if isinstance(v, float):
                vals.append(f"{v:.3g}")
            else:
                vals.append(str(v))
        lines.append(" & ".join(vals) + " \\\\")
    lines.append("\\bottomrule")
    lines.append("\\end{tabular}")
    lines.append("\\end{table}")
    return "\n".join(lines)

def main():
    # --- Load benchmark CSVs you said you have ---
    speedup_spmm = read_bench_csv(DATA_DIR / "speedup_spmm.csv")
    size_spmm = read_bench_csv(DATA_DIR / "size_spmm.csv")

    # If you have a dense size file too, you can add it similarly.
    # For now, we only need dense perf file for counters comparison.
    # We'll compute dense "ops" from its perf run config if possible.

    # --- Parse perf files ---
    perf_spmm = parse_perf_stat_csv(DATA_DIR / "perf_spmm.csv")
    perf_dense = parse_perf_stat_csv(DATA_DIR / "perf_dense.csv")

    # --- Choose the config used for perf runs ---
    # If your perf runs used different parameters, update these constants.
    # (These match what we recommended earlier.)
    SPMM_CFG = dict(m=1024, k=1024, n=1024, density=0.01, threads=8)
    DENSE_CFG = dict(m=1024, k=1024, n=1024, density=1.0, threads=8)

    # --- Look up nnz and median runtime from benchmark CSV (for derived metrics) ---
    nnz, spmm_ms, spmm_gflops = lookup_nnzs_from_bench(
        size_spmm if not size_spmm.empty else speedup_spmm, **SPMM_CFG
    )

    # Dense runtime is not needed for cycles/op, but can be used for context if present elsewhere.
    # We’ll compute dense work in operations: FLOPs = 2*m*k*n
    m = DENSE_CFG["m"]; k = DENSE_CFG["k"]; n = DENSE_CFG["n"]
    dense_flops = 2.0 * m * k * n

    # --- Build a combined summary table for counters ---
    def get_val(df, ev):
        s = df[df["event"] == ev]["value"]
        return float(s.iloc[0]) if len(s) else None

    dense_cycles = get_val(perf_dense, "cycles")
    dense_llc = get_val(perf_dense, "LLC-load-misses")
    dense_inst = get_val(perf_dense, "instructions")

    spmm_cycles = get_val(perf_spmm, "cycles")
    spmm_llc = get_val(perf_spmm, "LLC-load-misses")
    spmm_inst = get_val(perf_spmm, "instructions")

    # Derived metrics
    dense_cycles_per_flop = (dense_cycles / dense_flops) if (dense_cycles is not None) else None
    dense_llc_per_gflop = (dense_llc / (dense_flops / 1e9)) if (dense_llc is not None) else None

    spmm_cycles_per_nnz = (spmm_cycles / nnz) if (spmm_cycles is not None and nnz) else None
    spmm_llc_per_nnz = (spmm_llc / nnz) if (spmm_llc is not None and nnz) else None

    # Summary dataframe
    summary = pd.DataFrame([
        {
            "Kernel": "Dense GEMM",
            "Config": f"{m}x{k}x{n}, T={DENSE_CFG['threads']}",
            "cycles": dense_cycles,
            "instructions": dense_inst,
            "LLC-load-misses": dense_llc,
            "cycles/FLOP": dense_cycles_per_flop,
            "LLC/GFLOP": dense_llc_per_gflop,
        },
        {
            "Kernel": "CSR SpMM",
            "Config": f"{SPMM_CFG['m']}x{SPMM_CFG['k']}x{SPMM_CFG['n']}, p={SPMM_CFG['density']}, T={SPMM_CFG['threads']}",
            "cycles": spmm_cycles,
            "instructions": spmm_inst,
            "LLC-load-misses": spmm_llc,
            "cycles/NNZ": spmm_cycles_per_nnz,
            "LLC/NNZ": spmm_llc_per_nnz,
        }
    ])

    # Save CSV
    out_csv = DATA_DIR / "sectionE_perf_summary.csv"
    summary.to_csv(out_csv, index=False)
    print(f"Wrote {out_csv}")

    # Write LaTeX tables
    # Table 1: raw perf counters (compact)
    t1 = summary[["Kernel","Config","cycles","instructions","LLC-load-misses"]].copy()
    tex1 = latex_table(t1, "Hardware counter summary (perf stat).", "tab:perf_counters")
    (OUT_DIR / "perf_counters.tex").write_text(tex1)

    # Table 2: derived metrics (what you interpret)
    # Keep only non-null columns
    derived_cols = ["Kernel","Config","cycles/FLOP","LLC/GFLOP","cycles/NNZ","LLC/NNZ"]
    t2 = summary[derived_cols].copy()
    tex2 = latex_table(t2, "Derived metrics from counters (used for interpretation).", "tab:perf_derived")
    (OUT_DIR / "perf_derived.tex").write_text(tex2)

    print(f"Wrote {OUT_DIR/'perf_counters.tex'} and {OUT_DIR/'perf_derived.tex'}")

    # Note if we couldn't find nnz
    if nnz is None:
        print("WARNING: Could not match nnz for SpMM config in your benchmark CSV.")
        print("Update SPMM_CFG in the script to match the exact perf run parameters.")

if __name__ == "__main__":
    main()
