import pandas as pd
import matplotlib.pyplot as plt

COLS = ["mode","m","k","n","density","threads","rep","ms","gflops","nnz",
        "colchunk","Ti","Tj","Tk","seed"]

def load_and_split_variants(path: str) -> pd.DataFrame:
    df = pd.read_csv(path, header=None, names=COLS)

    # For each (threads, rep), you have two runs: nosimd and simd.
    # We label the smaller ms as simd, larger ms as nosimd.
    df = df.sort_values(["threads", "rep", "ms"]).copy()
    df["rank"] = df.groupby(["threads", "rep"]).cumcount()

    df["variant"] = None
    df.loc[df["rank"] == 0, "variant"] = "simd"
    df.loc[df["rank"] == 1, "variant"] = "nosimd"

    # Keep only the expected two rows per (threads, rep)
    df = df[df["variant"].notna()].drop(columns=["rank"])
    return df

def median_speedup(df: pd.DataFrame) -> pd.DataFrame:
    med = (df.groupby(["variant", "threads"])["ms"]
             .median()
             .reset_index())

    # Speedup = median_ms(threads=1) / median_ms(threads=T), per variant
    base = med[med["threads"] == 1].set_index("variant")["ms"].to_dict()
    med["speedup"] = med.apply(lambda r: base[r["variant"]] / r["ms"], axis=1)
    return med

def plot_speedup(med: pd.DataFrame, title: str, out_png: str):
    plt.figure()
    for variant in ["nosimd", "simd"]:
        sub = med[med["variant"] == variant].sort_values("threads")
        plt.plot(sub["threads"], sub["speedup"], marker="o", label=variant)
    plt.xlabel("Threads")
    plt.ylabel("Speedup (median runtime)")
    plt.title(title)
    plt.xticks(sorted(med["threads"].unique()))
    plt.grid(True)
    plt.legend()
    plt.tight_layout()
    plt.savefig(out_png, dpi=200)

if __name__ == "__main__":
    dense = load_and_split_variants("data/speedup_dense.csv")
    spmm  = load_and_split_variants("data/speedup_spmm.csv")

    dense_med = median_speedup(dense)
    spmm_med  = median_speedup(spmm)

    plot_speedup(dense_med, "Dense GEMM: Speedup vs Threads (median)", "plots/speedup_dense.png")
    plot_speedup(spmm_med,  "CSR SpMM: Speedup vs Threads (median)",   "plots/speedup_spmm.png")

    # Optional: print the median table you used for the plots
    print("\nDense medians:\n", dense_med)
    print("\nSpMM medians:\n", spmm_med)
