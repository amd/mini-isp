# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import cocotb
import pytest
from cocotb.clock import Clock
from cocotb.handle import Immediate
from cocotb.triggers import RisingEdge, Timer
from mini_isp.config import get_rtl_path
from mini_isp.rtl import Rtl

toplevel = "non_restoring_unsigned_divider"
sources = [
    get_rtl_path() / "non_restoring_unsigned_divider.sv",
    get_rtl_path() / "minmaxmean.sv",
]


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    async def reset(self):
        self.dut.rstn.set(Immediate(1))
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rstn.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rstn.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)


@cocotb.test()
@pytest.mark.sim
async def test_non_restoring_unsigned_divider_basic(dut):
    """Try accessing the design."""

    tb = TB(dut)

    await tb.reset()

    nom = 1 * 2**24
    den = 123456

    await RisingEdge(dut.clk)
    dut.nom.value = nom
    dut.den.value = den
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    await RisingEdge(dut.done)
    await RisingEdge(dut.clk)

    # TODO: implement real tests here

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_non_restoring_unsigned_divider_synth():
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                ("NOM_DATA_WIDTH", [48]),
                ("DEN_DATA_WIDTH", [24]),
            ]
        ),
    )

    rtl.export_markdown_report(
        "Non-Restoring Divider", rtl.synthesize_all(family="xc7")
    )


@pytest.mark.sim
def test_non_restoring_unsigned_divider_sim():
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                ("NOM_DATA_WIDTH", [48]),
                ("DEN_DATA_WIDTH", [24]),
            ]
        ),
    )

    rtl.simulate_all("tb.test_non_restoring_unsigned_divider, ", waves=False)
