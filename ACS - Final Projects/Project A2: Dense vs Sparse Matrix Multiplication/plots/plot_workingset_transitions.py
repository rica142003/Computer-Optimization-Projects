import pandas as pd
import matplotlib.pyplot as plt

# CSV format from your benchmark:
# mode,m,k,n,density,threads,rep,ms,gflops,nnz,colchunk,Ti,Tj,Tk,seed
COLS = ["mode","m","k","n","density","threads","rep","ms","gflops","nnz",
        "colchunk","Ti","Tj","Tk","seed"]

def load_csv(path: str) -> pd.DataFrame:
    return pd.read_csv(path, header=None, names=COLS)

def median_by_size(df: pd.DataFrame) -> pd.DataFrame:
    # In your size sweep, m=k=n, so we can use n as "size"
    med = (df.groupby("n")
             .agg(ms_med=("ms","median"),
                  gflops_med=("gflops","median"),
                  threads=("threads","first"),
                  density=("density","first"))
             .reset_index()
             .sort_values("n"))
    return med

def detect_drop_points(sizes, perf, drop_frac=0.20, min_size_index=1):
    """
    Detect 'drops' where performance falls by >= drop_frac relative to the best
    performance seen so far.
    Returns a list of sizes where drops occur.
    """
    drops = []
    best_so_far = perf[0]
    for i in range(min_size_index, len(sizes)):
        best_so_far = max(best_so_far, perf[i-1])
        if perf[i] < (1.0 - drop_frac) * best_so_far:
            drops.append(sizes[i])
            # reset baseline to avoid marking every subsequent point
            best_so_far = perf[i]
    return drops

def plot_kernel(med: pd.DataFrame, title: str, out_png: str,
                drop_frac=0.20, show_expected=True):
    sizes = med["n"].to_list()
    gflops = med["gflops_med"].to_list()

    plt.figure()
    plt.plot(sizes, gflops, marker="o", label="Median GFLOP/s")

    # Heuristic drop detection (cache boundary “knees”)
    drops = detect_drop_points(sizes, gflops, drop_frac=drop_frac)
    for x in drops[:3]:  # limit clutter
        plt.axvline(x, linestyle="--", label=f"Detected drop near n={x}")

    # Expected boundaries (approx) for i7-1260P:
    # L2 is ~1.5 MiB per cluster; LLC is 18 MiB shared.
    # For dense (A,B,C) ~ 3*n^2*8 bytes. Solve for n.
    if show_expected:
        # rough boundaries (good enough for a report figure)
        n_l2  = 256   # ~L2-ish scale
        n_llc = 896   # ~LLC-ish scale
        plt.axvline(n_l2,  linestyle=":", label="Approx L2 region")
        plt.axvline(n_llc, linestyle=":", label="Approx LLC region")

    plt.xlabel("Matrix size n (for n×n×n)")
    plt.ylabel("GFLOP/s (median)")
    plt.title(title)
    plt.xticks(sizes)
    plt.grid(True)
    plt.legend()
    plt.tight_layout()
    plt.savefig(out_png, dpi=200)
    print(f"Saved {out_png}")
    if drops:
        print(f"{title}: detected drop points at n = {drops}")
    else:
        print(f"{title}: no strong drop detected with drop_frac={drop_frac}")

if __name__ == "__main__":
    dense = load_csv("data/size_dense.csv")
    spmm  = load_csv("data/size_spmm.csv")

    dense_med = median_by_size(dense)
    spmm_med  = median_by_size(spmm)

    # Dense often has smoother scaling; use slightly smaller threshold if needed (0.15)
    plot_kernel(dense_med,
                "Working-set transitions (Dense GEMM): GFLOP/s vs size",
                "plots/size_dense_transitions.png",
                drop_frac=0.15,
                show_expected=True)

    # SpMM can be noisier; use 0.20 to avoid over-marking
    plot_kernel(spmm_med,
                "Working-set transitions (CSR SpMM): GFLOP/s vs size",
                "plots/size_spmm_transitions.png",
                drop_frac=0.20,
                show_expected=True)
