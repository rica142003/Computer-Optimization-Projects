#!/usr/bin/env python3
import re, sys
from pathlib import Path
import pandas as pd

KV_RE = re.compile(r"(?P<k>[^=\s]+)=(?P<v>[^\s]+)")

def parse_time_to_ns(s: str):
    try:
        if s.endswith("ns"): return float(s[:-2])
        if s.endswith("us"): return float(s[:-2]) * 1e3
        if s.endswith("ms"): return float(s[:-2]) * 1e6
        if s.endswith("s"):  return float(s[:-1]) * 1e9
        return float(s)
    except Exception:
        return None

def main():
    if len(sys.argv) != 3:
        print("usage: parse_a3_log.py <raw.log> <out.csv>", file=sys.stderr)
        sys.exit(2)

    raw = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore").splitlines()
    out = Path(sys.argv[2])

    cfg = {}
    rows = []
    for line in raw:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("CONFIG "):
            cfg = dict(KV_RE.findall(line))
            continue
        kvs = dict(KV_RE.findall(line))
        if "filter" not in kvs or "achieved_fpr" not in kvs or "bpe" not in kvs:
            continue

        row = dict(cfg)
        row.update(kvs)

        for k in ["n","threads","run","rep","fp_bits","ops","warmup_ops"]:
            if k in row:
                try: row[k] = int(float(row[k]))
                except Exception: pass

        for k in ["target_fpr","achieved_fpr","bpe","neg_share","load_factor","ops_per_s",
                  "fail_rate","avg_kicks","stash_hits","avg_probe","cluster_mean","cluster_p99"]:
            if k in row:
                try: row[k] = float(row[k])
                except Exception: pass

        for k in ["p50","p95","p99"]:
            if k in row:
                ns = parse_time_to_ns(str(row[k]))
                if ns is not None:
                    row[k+"_ns"] = ns

        rows.append(row)

    if not rows:
        print("No rows parsed. Ensure benchmark prints key=value tokens including filter=... achieved_fpr=... bpe=...", file=sys.stderr)
        sys.exit(1)

    df = pd.DataFrame(rows)
    out.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out, index=False)
    print(f"Wrote {out} rows={len(df)} cols={len(df.columns)}")

if __name__ == "__main__":
    main()
