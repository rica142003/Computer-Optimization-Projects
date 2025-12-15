#pragma once
#include <vector>
double now_sec();
double calibrate_cycles_per_ns(int ms = 30);
double percentile(std::vector<double>& xs, double p);
