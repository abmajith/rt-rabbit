================================================
RT-Rabbit: Hardware IP Core Specifications
================================================

.. contents:: Table of Contents
   :depth: 2

1. Motor PWM Module (`wb_pwm`)
==============================

Specification
-------------
The ``wb_pwm`` component is a Wishbone-managed Pulse Width Modulation 
controller designed to drive H-Bridge motor drivers with precise 
duty-cycle control.

* **Register Address 0 (0x0):** Duty Cycle Register (32-bit, Read/Write).
* **Clock Domain:** Synchronous to ``wb_clk_i``.
* **Reset Strategy:** Synchronous active-high via ``wb_rst_i``.
* **Output:** Single-ended ``pwm_pad_o`` line.

Block Diagram
-------------

.. mermaid::

   graph LR
       subgraph wb_pwm [Motor PWM Core]
           bus_if[Wishbone Bus Interface] --> config_reg[Duty Cycle Register]
           config_reg --> counter[Base Time Counter]
           counter --> comparator[Digital Comparator]
           comparator --> pwm_pad_o((motor_pwm_pin))
       end
       
       WB_CLK_I --> bus_if
       WB_RST_I --> bus_if
       WB_ADR_I --> bus_if
       WB_DAT_I --> bus_if


2. Quadrature Position Encoder Module (`wb_qei`)
=================================================

Specification
-------------
The ``wb_qei`` component decodes phase-shifted signals from a physical 
optical/magnetic encoder attached to the motor shaft to track absolute 
rotational position.

* **Register Address 0 (0x0):** Absolute Position Counter Register (32-bit, Read-Only).
* **Sampling Architecture:** 3-stage shift registers for glitch-filtering on raw external pins.
* **Reset Strategy:** Synchronous active-high via ``wb_rst_i``.

Block Diagram
-------------

.. mermaid::

   graph LR
       subgraph wb_qei [QEI Core]
           enc_a((enc_a_pin)) --> filter_a[3-Stage Shift Filter]
           enc_b((enc_b_pin)) --> filter_b[3-Stage Shift Filter]
           filter_a --> qdec[Quadrature Decoder Logic]
           filter_b --> qdec
           qdec --> pos_cnt[32-bit Position Counter]
           pos_cnt --> wb_if[Wishbone Register Interface]
       end
       
       wb_if --> WB_DAT_O


3. Telemetry Subsystem Block (`wb_telemetry`)
==============================================

Specification
-------------
The ``wb_telemetry`` core serves as a high-speed diagnostic window streaming 
run-time variables out of the system without dragging down processor clock cycles.

* **Register Address 0 (0x0):** Telemetry Streaming Configuration Control (32-bit, Read/Write).
* **Application Interfaces:** Exposes dual parallel channel capture links (`rx_channel_1`, `rx_channel_2`) 
  tied to internal feedback arrays.
* **Reset Strategy:** Asynchronous active-high via ``wb_rst_i``.

Block Diagram
-------------

.. mermaid::

   graph LR
       subgraph wb_telemetry [Telemetry Subsystem]
           rx_ch1[rx_channel_1] --> tx_mux[Stream Multiplexer]
           rx_ch2[rx_channel_2] --> tx_mux
           wb_ctrl[Wishbone Ctrl Reg] --> tx_mux
           tx_mux --> tx_engine[Parallel-to-Serial Stream Engine]
           tx_engine --> tx_stream[tx_raw_stream]
       end


4. Top-Level Integration (`rt_top_integrated`)
===============================================

Specification
-------------
The ``rt_top_integrated`` module binds individual IPs onto a unified 3-bit system address 
bus decoded using an explicit address-space partition map.

+----------------+--------------------+-------------------------+
| Address Range  | Module Selection   | Target Subsystem        |
+================+====================+=========================+
| 3'b000 - 3'b001| ``pwm_select``     | Motor Controller Core   |
+----------------+--------------------+-------------------------+
| 3'b100 - 3'b101| ``qei_select``     | Quadrature Position Tracker|
+----------------+--------------------+-------------------------+
| 3'b110 - 3'b111|``telemetry_select``| Telemetry Subsystem     |
+----------------+--------------------+-------------------------+

Integrated SoC System Block Diagram
-----------------------------------

.. mermaid::

   graph TD
       subgraph rt_top_integrated [True Integrated Top Module]
           direction TB
           dec[3-Way Address Decoder & MUX Control]
           
           pwm[Instance 1: wb_pwm]
           qei[Instance 2: wb_qei]
           tel[Instance 3: wb_telemetry]
           
           %% Shared Address Bus
           dec -->|stb && pwm_select| pwm
           dec -->|stb && qei_select| qei
           dec -->|stb && telemetry_select| tel
           
           %% Internal Loops
           tel -->|tx_raw_stream| tel
       end
       
       %% System Master Boundary
       WB_Master[Wishbone Master Interface] ===> dec
       pwm ==>|pwm_dat_r / pwm_ack| dec
       qei ==>|qei_dat_r / qei_ack| dec
       tel ==>|tel_dat_r / tel_ack| dec


5. Modern Engineering Testing Methodology
==========================================



Specification
-------------
This project uses **Cocotb (Coroutine-based Co-simulation Testbench)** powered by **Verilator**. 
Test scenarios are written in asynchronous Python, abstracting complex digital protocols into clean software drivers.

Testing Framework Block Diagram
-------------------------------

.. mermaid::

   graph LR
       subgraph Python_Environment [Verification Suite]
           test_top[test_top_system.py] --> driver[wb_driver.py]
           driver -->|async write_reg| python_cb[Cocotb Engine]
       end
       
       subgraph C_Simulator [Execution Layer]
           vpi[VPI / DPI Boundary] --> verilator_exe[Verilator Executable Vtop]
       end
       
       subgraph RTL_Design [Hardware Under Test]
           verilator_exe --> dut[rt_top_integrated.v]
       end
       
       python_cb <-->|Inter-Process Communication| vpi
