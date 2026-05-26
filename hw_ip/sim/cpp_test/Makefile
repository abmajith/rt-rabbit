# ==============================================================================
# RT-Rabbit Project: Telemetry PHY Pipeline Simulation Makefile
# ==============================================================================

# Toolchain definitions
VERILATOR = verilator
CXX       = g++

# Source and Directory Configurations
INC_DIR   = ../../components/telemetry
TOP_V     = telemetry_phy_test_wrap.v
TB_CPP    = tb_telemetry_phy.cpp
OBJ_DIR   = obj_dir
TARGET    = v_telemetry_agent_sim

# Verilator Compilation Flags
# -Wall: Enable all linter checks
# -I$(INC_DIR): Include directory to automatically locate child submodules
VERILATOR_FLAGS = --cc --exe --build -Wall -I$(INC_DIR)

.PHONY: all run clean help

# Default target compiles the simulation binary
all: $(TARGET)

$(TARGET): $(TOP_V) $(TB_CPP)
	@echo "[MAKE] Commencing Verilator hardware-to-C++ compilation pipeline..."
	$(VERILATOR) $(VERILATOR_FLAGS) $(TOP_V) $(TB_CPP) -o $(TARGET)
	@echo "[MAKE] Compilation successful. Target binary created at $(OBJ_DIR)/$(TARGET)"

# Convenience target to build and run the simulation in one go
run: all
	@echo "[MAKE] Launching Telemetry Pipeline Simulation execution..."
	@./$(OBJ_DIR)/$(TARGET)

# Clean target to clear out local obj_dir and avoid bloating workspaces
clean:
	@echo "[MAKE] Cleaning up simulation workspace artifacts..."
	@rm -rf $(OBJ_DIR)
	@echo "[MAKE] Clean complete."

# Help documentation overview layout 
help:
	@echo "Available Makefile targets:"
	@echo "  make       - Compile the Verilator simulation binary target"
	@echo "  make run   - Compile (if needed) and run the telemetry sim test suite"
	@echo "  make clean - Delete the generated '$(OBJ_DIR)' workspace directory"
	@echo "  make help  - Display this tracking options summary guide"