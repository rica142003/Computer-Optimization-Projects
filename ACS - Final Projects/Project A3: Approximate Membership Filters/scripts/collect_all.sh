#!/usr/bin/env bash
set -euo pipefail
bash scripts/build.sh
bash scripts/run_a3_sweeps.sh
python3 plots/plot_a3.py results/results.csv results/figs
echo "Done. See results/figs/"
