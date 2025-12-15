CXX ?= g++
CXXFLAGS ?= -O3 -march=native -std=c++17 -Wall -Wextra -Wpedantic -pthread
LDFLAGS ?= -pthread

BIN_DIR := bin
SRC_DIR := src
SOURCES := $(SRC_DIR)/benchmark.cpp
TARGET := $(BIN_DIR)/a4_bench

all: $(TARGET)

$(TARGET): $(SOURCES) $(SRC_DIR)/hashtable.h
	@mkdir -p $(BIN_DIR)
	$(CXX) $(CXXFLAGS) $(SOURCES) -o $@ $(LDFLAGS)

clean:
	rm -rf $(BIN_DIR) data/processed/*.png

.PHONY: all clean
