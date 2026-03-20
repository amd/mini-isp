# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import itertools
import random

import cocotb
import pytest
from cocotb.clock import Clock
from cocotb.handle import Immediate
from cocotb.triggers import RisingEdge, Timer
from cocotbext.axi import AxiLiteBus, AxiLiteMaster
from mini_isp.config import get_rtl_path
from mini_isp.rtl import Rtl

toplevel = "axi_lite_register"
sources = [
    get_rtl_path() / "axi_lite_register.sv",
]


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

        self.axi_master = AxiLiteMaster(
            AxiLiteBus.from_prefix(dut, "s_axi"),
            dut.clk,
            dut.rstn,
            reset_active_level=False,
        )

    def random_pause(self):
        return itertools.cycle(random.choices([0, 1], k=random.randint(7, 1023)))

    def set_idle_generator(self, generator=None):
        pass

    def set_backpressure_generator(self, generator=None):
        pass

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
async def test_axi_lite_register_basic(dut):
    """Try accessing the design."""

    tb = TB(dut)

    await tb.reset()

    # check reset values
    assert tb.dut.black_level.value.to_unsigned() == 256

    assert tb.dut.rgain.value.to_unsigned() == 128
    assert tb.dut.bgain.value.to_unsigned() == 128
    assert tb.dut.g0gain.value.to_unsigned() == 128
    assert tb.dut.g1gain.value.to_unsigned() == 128

    assert tb.dut.ccm_r_r.value.to_unsigned() == 4096
    assert tb.dut.ccm_r_g.value.to_unsigned() == 0
    assert tb.dut.ccm_r_b.value.to_unsigned() == 0

    assert tb.dut.ccm_g_r.value.to_unsigned() == 0
    assert tb.dut.ccm_g_g.value.to_unsigned() == 4096
    assert tb.dut.ccm_g_b.value.to_unsigned() == 0

    assert tb.dut.ccm_b_r.value.to_unsigned() == 0
    assert tb.dut.ccm_b_g.value.to_unsigned() == 0
    assert tb.dut.ccm_b_b.value.to_unsigned() == 4096

    register0 = random.randint(0, 2**31 - 1)
    register1 = random.randint(0, 2**31 - 1)
    register2 = random.randint(0, 2**31 - 1)
    register3 = random.randint(0, 2**31 - 1)
    register4 = random.randint(0, 2**31 - 1)
    register5 = random.randint(0, 2**31 - 1)
    register6 = random.randint(0, 2**31 - 1)

    # check write to every register
    await tb.axi_master.write(0x00, register0.to_bytes(4, byteorder="little"))
    await RisingEdge(tb.dut.clk)
    assert tb.dut.bgain.value.to_unsigned() == register0 >> 16
    assert tb.dut.rgain.value.to_unsigned() == register0 & 0xFFFF

    await tb.axi_master.write(0x04, register1.to_bytes(4, byteorder="little"))
    await RisingEdge(tb.dut.clk)
    assert tb.dut.g1gain.value.to_unsigned() == register1 >> 16
    assert tb.dut.g0gain.value.to_unsigned() == register1 & 0xFFFF

    await tb.axi_master.write(0x08, register2.to_bytes(4, byteorder="little"))
    await RisingEdge(tb.dut.clk)
    assert tb.dut.ccm_r_g.value.to_unsigned() == register2 >> 16
    assert tb.dut.ccm_r_r.value.to_unsigned() == register2 & 0xFFFF

    await tb.axi_master.write(0x0C, register3.to_bytes(4, byteorder="little"))
    await RisingEdge(tb.dut.clk)
    assert tb.dut.ccm_g_r.value.to_unsigned() == register3 >> 16
    assert tb.dut.ccm_r_b.value.to_unsigned() == register3 & 0xFFFF

    await tb.axi_master.write(0x10, register4.to_bytes(4, byteorder="little"))
    await RisingEdge(tb.dut.clk)
    assert tb.dut.ccm_g_b.value.to_unsigned() == register4 >> 16
    assert tb.dut.ccm_g_g.value.to_unsigned() == register4 & 0xFFFF

    await tb.axi_master.write(0x14, register5.to_bytes(4, byteorder="little"))
    await RisingEdge(tb.dut.clk)
    assert tb.dut.ccm_b_g.value.to_unsigned() == register5 >> 16
    assert tb.dut.ccm_b_r.value.to_unsigned() == register5 & 0xFFFF

    await tb.axi_master.write(0x18, register6.to_bytes(4, byteorder="little"))
    await RisingEdge(tb.dut.clk)
    assert tb.dut.black_level.value.to_unsigned() == register6 >> 16
    assert tb.dut.ccm_b_b.value.to_unsigned() == register6 & 0xFFFF

    # read back data
    data = await tb.axi_master.read(0x00, 4)
    assert data.data == register0.to_bytes(4, byteorder="little")

    data = await tb.axi_master.read(0x04, 4)
    assert data.data == register1.to_bytes(4, byteorder="little")

    data = await tb.axi_master.read(0x08, 4)
    assert data.data == register2.to_bytes(4, byteorder="little")

    data = await tb.axi_master.read(0x0C, 4)
    assert data.data == register3.to_bytes(4, byteorder="little")

    data = await tb.axi_master.read(0x10, 4)
    assert data.data == register4.to_bytes(4, byteorder="little")

    data = await tb.axi_master.read(0x14, 4)
    assert data.data == register5.to_bytes(4, byteorder="little")

    data = await tb.axi_master.read(0x18, 4)
    assert data.data == register6.to_bytes(4, byteorder="little")

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_axi_lite_register_synth():
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                ("S_AXI_DATA_WIDTH", [32]),
            ]
        ),
    )

    rtl.export_markdown_report("AXI Lite Register", rtl.synthesize_all(family="xc7"))


@pytest.mark.sim
def test_axi_lite_register_sim():
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                ("S_AXI_DATA_WIDTH", [32]),
            ]
        ),
    )

    rtl.simulate_all("tb.test_axi_lite_register, ", waves=True)
