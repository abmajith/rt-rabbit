VERILATOR = verilator
CXX       = g++

INC_DIR   = ../../components/telemetry
TOP_V     = telemetry_phy_test_wrap.v
TB_CPP    = tb_telemetry_phy.cpp
OBJ_DIR   = obj_dir
TARGET    = v_telemetry_agent_sim

VERILATOR_FLAGS = --cc --exe --build -Wall -I$(INC_DIR)

.PHONY: all run clean help

all: $(TARGET)

$(TARGET): $(TOP_V) $(TB_CPP)
	$(VERILATOR) $(VERILATOR_FLAGS) $(TOP_V) $(TB_CPP) -o $(TARGET)

run: all
	@./$(OBJ_DIR)/$(TARGET)

clean:
	@echo "[MAKE] Cleaning up simulation workspace artifacts..."
	@rm -rf $(OBJ_DIR)
	@echo "[MAKE] Clean complete."
