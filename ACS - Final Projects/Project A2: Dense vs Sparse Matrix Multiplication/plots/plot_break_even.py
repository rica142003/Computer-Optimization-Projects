import pandas as pd
import matplotlib.pyplot as plt

# Your benchmark CSV format:
# mode,m,k,n,density,threads,rep,ms,gflops,nnz,colchunk,Ti,Tj,Tk,seed
COLS = ["mode","m","k","n","density","threads","rep","ms","gflops","nnz",
        "colchunk","Ti","Tj","Tk","seed"]

def load_csv(path: str) -> pd.DataFrame:
    return pd.read_csv(path, header=None, names=COLS)

def median_by_density(df: pd.DataFrame) -> pd.DataFrame:
    # Median runtime per density (and keep metadata for sanity checks)
    med = (df.groupby("density")
             .agg(ms_med=("ms", "median"),
                  gflops_med=("gflops", "median"),
                  threads=("threads", "first"),
                  m=("m","first"), k=("k","first"), n=("n","first"))
             .reset_index()
             .sort_values("density"))
    return med

def find_break_even(dense_ms: float, spmm_med: pd.DataFrame):
    """
    Returns:
      - break_even_density (exact sampled point) if found, else None
      - bracket (p_low, p_high) where crossing happens if possible
    """
    # First density where sparse is <= dense
    candidates = spmm_med[spmm_med["ms_med"] <= dense_ms]
    if candidates.empty:
        return None, None

    p_be = float(candidates.iloc[0]["density"])

    # Try to also return a bracket just before crossing
    idx = spmm_med.index[spmm_med["density"] == p_be][0]
    prev = spmm_med.iloc[spmm_med.index.get_loc(idx) - 1] if spmm_med.index.get_loc(idx) > 0 else None

    bracket = None
    if prev is not None:
        bracket = (float(prev["density"]), p_be)

    return p_be, bracket

if __name__ == "__main__":
    # Paths: adjust if your files are elsewhere
    dense_path = "data/density_dense_ref.csv"
    spmm_path  = "data/density_spmm.csv"

    dense_df = load_csv(dense_path)
    spmm_df  = load_csv(spmm_path)

    # Dense reference: median across reps (usually only one "density"=1.0 row)
    dense_ms = dense_df["ms"].median()

    spmm_med = median_by_density(spmm_df)

    p_be, bracket = find_break_even(dense_ms, spmm_med)

    # ---- Plot ----
    plt.figure()

    # SpMM curve
    plt.plot(spmm_med["density"], spmm_med["ms_med"], marker="o", label="CSR SpMM (median)")

    # Dense reference as a horizontal line
    plt.axhline(dense_ms, linestyle="--", label=f"Dense GEMM median = {dense_ms:.3f} ms")

    # Break-even marker
    if p_be is not None:
        plt.axvline(p_be, linestyle="--", label=f"Break-even at p = {p_be:g}")
        # Optional: annotate bracket
        if bracket is not None:
            plt.text(p_be, dense_ms, f"  between {bracket[0]:g} and {bracket[1]:g}", va="bottom")

    plt.xlabel("Density (fraction of nonzeros)")
    plt.ylabel("Runtime (ms), median over reps")
    plt.title("Density break-even: Dense GEMM vs CSR SpMM")
    plt.xscale("log")  # helpful since you sweep from 0.1% up to 50%
    plt.grid(True, which="both")
    plt.legend()
    plt.tight_layout()

    out_png = "plots/break_even_density.png"
    plt.savefig(out_png, dpi=200)
    print(f"Saved plot to {out_png}")

    # ---- Print break-even info ----
    print(f"\nDense median runtime: {dense_ms:.3f} ms")
    if p_be is None:
        print("No break-even found: SpMM never beats dense for the sampled densities.")
    else:
        print(f"Break-even density (first sampled point where SpMM <= dense): p = {p_be:g}")
        if bracket is not None:
            print(f"Crossing bracket: {bracket[0]:g} < p <= {bracket[1]:g}")

    # Optional: write a small summary table
    spmm_med.to_csv("data/density_spmm_medians.csv", index=False)
    print("Wrote data/density_spmm_medians.csv (median stats per density).")
