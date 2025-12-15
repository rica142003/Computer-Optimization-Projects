cmake_minimum_required(VERSION 3.16)
project(project_a3_filters CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

add_executable(a3_bench
  src/main.cppake
  src/cli.cpp
  src/hash.cpp
  src/dataset.cpp
  src/timing.cpp
  src/blocked_bloom.cpp
  src/xor_filter.cpp
  src/cuckoo_filter.cpp
  src/quotient_filter.cpp
)

target_include_directories(a3_bench PRIVATE src)
target_compile_options(a3_bench PRIVATE -O3 -march=native -Wall -Wextra -Wpedantic)
target_link_libraries(a3_bench PRIVATE pthread)
