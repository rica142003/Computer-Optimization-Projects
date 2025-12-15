#include "cli.h"
#include <cstdlib>

BenchConfig parse_args(int argc, char** argv) {
  BenchConfig c;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto need = [&](const char* name) {
      if (i + 1 >= argc) {
        std::cerr << "Missing value for " << name << "\n";
        std::exit(2);
      }
      return std::string(argv[++i]);
    };

    if (a == "--filter") c.filter = need("--filter");
    else if (a == "--workload") c.workload = need("--workload");
    else if (a == "--dist") c.dist = need("--dist");
    else if (a == "--seed") c.seed = std::stoull(need("--seed"));
    else if (a == "--run") c.run = std::stoi(need("--run"));

    else if (a == "--n") c.n = std::stoull(need("--n"));
    else if (a == "--target_fpr") c.target_fpr = std::stod(need("--target_fpr"));
    else if (a == "--neg_share") c.neg_share = std::stod(need("--neg_share"));
    else if (a == "--load_factor") c.load_factor = std::stod(need("--load_factor"));

    else if (a == "--threads") c.threads = std::stoi(need("--threads"));
    else if (a == "--fp_bits") c.fp_bits = std::stoi(need("--fp_bits"));

    else if (a == "--ops") c.ops = std::stoull(need("--ops"));
    else if (a == "--warmup_ops") c.warmup_ops = std::stoull(need("--warmup_ops"));
    else if (a == "--check") c.check = std::stoi(need("--check"));

    else if (a == "-h" || a == "--help") {
      std::cout << "a3_bench flags:\n"
                << "  --filter {bloom|xor|cuckoo|quotient}\n"
                << "  --n <int> --target_fpr <float> --neg_share <float>\n"
                << "  --workload {read_only|read_mostly|balanced}\n"
                << "  --load_factor <float> --fp_bits {8|12|16}\n"
                << "  --threads <int> --ops <int> --warmup_ops <int>\n"
                << "  --dist {uniform|sequential} --seed <int> --run <int>\n"
                << "  --check 1\n";
      std::exit(0);
    } else {
      std::cerr << "Unknown arg: " << a << "\n";
      std::exit(2);
    }
  }
  return c;
}
