#include <iostream>
#include <memory>
#include <vector>
#include <queue>
#include <cstdlib>
#include <ctime>
#include "Vtelemetry_phy_test_wrap.h"
#include "verilated.h"

class RFTransceiverDriver {
private:
    double clk_period_ns;
    double accumulator;
    bool clk_state;
    size_t bit_idx;
    std::vector<bool> bit_stream;

public:
    RFTransceiverDriver(double period_ns) 
        : clk_period_ns(period_ns), accumulator(0.0), clk_state(false), bit_idx(0) {}
    
    void send_packet(
        uint16_t sof, 
        uint16_t idx, 
        uint16_t type, 
        uint16_t length, 
        const std::vector<uint16_t>& payload, 
        uint16_t eof
    ) {
        auto push_word = [this](uint16_t word) {
            for (int i = 15; i >= 0; --i) {
                bit_stream.push_back((word >> i) & 0x01);
            }
        };
        push_word(sof);
        push_word(idx);
        push_word(type);
        push_word(length);
        for (uint16_t p : payload) push_word(p);
        push_word(0x0000); // Dummy CRC word placeholder
        push_word(eof);
    }

    void drive(
        double time_delta_ns, 
        bool& out_clk, 
        bool& out_data
    ) {
        accumulator += time_delta_ns;
        if (accumulator >= (clk_period_ns / 2.0)) {
            accumulator -= (clk_period_ns / 2.0);
            clk_state = !clk_state; // Toggle clock edge
            
            // FIX: Advance to the next data bit on the FALLING edge of the RF clock.
            // This gives maximum setup/hold stability when the synchronizer captures the rising edge.
            if (!clk_state && bit_idx < bit_stream.size()) {
                bit_idx++;
            }
        }
        out_clk = clk_state;
        if (bit_idx < bit_stream.size()) {
            out_data = bit_stream[bit_idx];
        } else {
            out_data = rand() % 2; // Inject continuous raw noise channel energy when empty
        }
    }

    bool is_done() const { return bit_idx >= bit_stream.size(); }
};

class TelemetryMonitor {
public:
    std::queue<uint16_t> captured_payloads;
    bool dynamic_frame_complete = false;
    uint16_t last_packet_idx = 0;
    uint16_t last_data_type = 0;

    void monitor(
        bool sys_clk, 
        bool strobe, 
        uint16_t data, 
        bool complete, 
        uint16_t idx, 
        uint16_t type
    ) {
        if (sys_clk) { // Sample strictly on rising edges
            if (strobe) {
                captured_payloads.push(data);
            }
            if (complete) {
                dynamic_frame_complete = true;
                last_packet_idx = idx;
                last_data_type = type;
            }
        }
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    srand(1337); // Fixed seed for predictable verification steps

    auto dut = std::make_unique<Vtelemetry_phy_test_wrap>();
    RFTransceiverDriver driver(2000.0); // 500kHz RF Clock Domain
    TelemetryMonitor    monitor;
    
    std::vector<uint16_t> payload = {0xDEAD, 0xBEEF, 0xAAAA};
    driver.send_packet(0xF53A, 0x00A1, 0x0002, payload.size(), payload, 0x0AC5);

    // Initial Conditions
    dut->rst = 1; 
    bool sys_clk = false;

    std::cout << "[C++ TB] Commencing Agent-Driven Telemetry Sim Loop..." << std::endl;

    // Run the main step-execution loop (expanded bounds to ensure complete data extraction)
    for (int step = 0; step < 200000; step++) {
        
        // FIX: Hold reset high for several complete system clock cycles to initialize registers cleanly
        if (step == 100) dut->rst = 0;

        // 1. Manage the asynchronous RF side (Fixed 5.0ns step per phase loop evaluation)
        bool rf_pins_clk = false;
        bool rf_pins_data = false;
        driver.drive(5.0, rf_pins_clk, rf_pins_data);

        dut->rf_clock_i = rf_pins_clk;
        dut->rf_data_i  = rf_pins_data;

        // 2. Toggle the System Clock Edge
        sys_clk = !sys_clk;
        dut->clk = sys_clk ? 1 : 0;
        
        // 3. Evaluate Module Hierarchy Connections
        dut->eval();

        // Feed monitor on the system clock transition states
        monitor.monitor(sys_clk, dut->dma_write_strobe_o, dut->dma_data_o, 
                        dut->frame_complete_o, dut->out_packet_idx, dut->out_data_type);

        if (monitor.dynamic_frame_complete) {
            std::cout << "\n==================================================" << std::endl;
            std::cout << "[SCOREBOARD PASSED] Robot Telemetry Packet Locked!" << std::endl;
            std::cout << "-> Parsed Packet Index: 0x" << std::hex << monitor.last_packet_idx << std::endl;
            std::cout << "-> Detected Data Type:  0x" << std::hex << monitor.last_data_type << std::endl;
            std::cout << "-> Streamed Words Extracted: " << std::dec << monitor.captured_payloads.size() << std::endl;
            
            while(!monitor.captured_payloads.empty()) {
                std::cout << "    |-- Payload Word: 0x" << std::hex << monitor.captured_payloads.front() << std::endl;
                monitor.captured_payloads.pop();
            }
            std::cout << "==================================================" << std::endl;
            return 0;
        }
    }

    std::cerr << "[TEST FAIL] Simulation loop timed out." << std::endl;
    return -1;
}