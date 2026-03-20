# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import cocotb
import pytest
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from mini_isp.config import get_rtl_path
from mini_isp.rtl import Rtl

toplevel = "simple_dual_ported_rom"
sources = [
    get_rtl_path() / "simple_dual_ported_rom.sv",
]


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    async def reset(self):
        pass


@cocotb.test()
@pytest.mark.sim
async def test_simple_dual_ported_rom_basic(dut):
    """Try accessing the design."""

    tb = TB(dut)

    await tb.reset()

    await RisingEdge(dut.clk)
    # TODO: implement ROM tests

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_simple_dual_ported_rom_synth():
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                ("DATA_WIDTH", [16, 32, 64]),
                ("ADDR_WIDTH", [10]),
                ("MEM_FILE", [str(get_rtl_path() / "simple_dual_ported_rom.mem")]),
            ]
        ),
    )

    rtl.export_markdown_report(
        "Simple Dual-ported ROM", rtl.synthesize_all(family="xc7")
    )


@pytest.mark.sim
def test_simple_dual_ported_rom_sim():
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                ("DATA_WIDTH", [16, 32, 64]),
                ("ADDR_WIDTH", [10]),
                (
                    "MEM_FILE",
                    ['"' + str(get_rtl_path() / "simple_dual_ported_rom.mem") + '"'],
                ),
            ]
        ),
    )

    rtl.simulate_all("tb.test_simple_dual_ported_rom, ", waves=False)
