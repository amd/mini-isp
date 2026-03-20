# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import cocotb
import pytest
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from mini_isp.config import get_rtl_path
from mini_isp.rtl import Rtl

toplevel = "simple_dual_ported_ram"
sources = [
    get_rtl_path() / "simple_dual_ported_ram.sv",
]


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    async def reset(self):
        pass


@cocotb.test()
@pytest.mark.sim
async def test_simple_dual_ported_ram_basic(dut):
    """Try accessing the design."""

    tb = TB(dut)

    await tb.reset()

    await RisingEdge(dut.clk)

    # TODO: implement RAM tests

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_simple_dual_ported_ram_synth():
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                ("DATA_WIDTH", [16, 32, 64]),
                ("ADDR_WIDTH", [8, 10, 12]),
            ]
        ),
    )

    rtl.export_markdown_report(
        "Simple Dual-ported RAM", rtl.synthesize_all(family="xc7")
    )


@pytest.mark.sim
def test_simple_dual_ported_ram_sim():
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                ("DATA_WIDTH", [16, 32, 64]),
                ("ADDR_WIDTH", [8, 10, 12]),
            ]
        ),
    )

    rtl.simulate_all("tb.test_simple_dual_ported_ram, ", waves=False)
