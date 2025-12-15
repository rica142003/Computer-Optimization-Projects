#!/usr/bin/env bash
set -euo pipefail

echo "Optional environment stabilization steps (some require sudo)."
echo "1) Set performance governor (if available):"
echo "   sudo cpupower frequency-set -g performance"
echo "2) Disable turbo (optional):"
echo "   echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo"
echo "3) Disable transparent huge pages (optional):"
echo "   echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled"
echo "4) Reduce perf paranoia (if you plan to use perf):"
echo "   sudo sysctl -w kernel.perf_event_paranoid=1"
echo "   sudo sysctl -w kernel.kptr_restrict=0"
echo
echo "This script only prints commands so it is safe to run without sudo."
