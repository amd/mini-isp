# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import itertools
import logging
import random

import cocotb
import matplotlib
import pytest

matplotlib.use("Agg")
import cv2 as cv2
import numpy as np
from axis_video import pack_buffer, unpack_buffer
from cocotb.clock import Clock
from cocotb.handle import Immediate
from cocotb.triggers import RisingEdge, Timer
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource
from matplotlib import pyplot as plt
from mini_isp.config import ParamSet, get_param, get_rtl_path
from mini_isp.gamma import Gamma
from mini_isp.rtl import Rtl

toplevel = "lut"
sources = [
    get_rtl_path() / "simple_dual_ported_rom.sv",
    get_rtl_path() / "lut.sv",
]


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

        self.axis_source = AxiStreamSource(
            AxiStreamBus.from_prefix(dut, "s_axis"),
            dut.clk,
            dut.rstn,
            reset_active_level=False,
        )
        self.axis_sink = AxiStreamSink(
            AxiStreamBus.from_prefix(dut, "m_axis"),
            dut.clk,
            dut.rstn,
            reset_active_level=False,
        )

        # set log level
        self.axis_source.log.setLevel(logging.WARNING)
        self.axis_sink.log.setLevel(logging.WARNING)

    def random_pause(self):
        return itertools.cycle(random.choices([0, 1], k=random.randint(7, 1023)))

    def set_idle_generator(self, generator=None):
        if generator:
            self.axis_source.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.axis_sink.set_pause_generator(generator())

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
async def test_lut_basic(dut):
    """Try accessing the design."""

    tb = TB(dut)

    tb.set_idle_generator(generator=tb.random_pause)
    tb.set_backpressure_generator(generator=tb.random_pause)

    await tb.reset()

    cfa = np.linspace(
        start=0,
        stop=2 ** int(dut.INPUT_PIXEL_BIT_WIDTH.value),
        endpoint=False,
        num=64 * 64,
        dtype=np.uint32,
    )
    cfa = cfa.reshape(64, 64)

    h = cfa.shape[0]
    w = cfa.shape[1]

    # loop over the image
    tuser = [1] * tb.axis_source.byte_lanes + [0]
    for y in range(0, h):
        frame = AxiStreamFrame(
            pack_buffer(
                cfa[y, :].astype(np.uint32),
                int(dut.PIXEL_PER_CYCLE.value),
                int(dut.INPUT_PIXEL_BIT_WIDTH.value),
            ),
            tuser=tuser,
        )
        await tb.axis_source.send(frame)
        # tuser should only be set for first line (signals start of frame)
        tuser = 0

    result = np.zeros(np.shape(cfa), dtype=np.uint32)
    for y in range(0, h):
        frame = await tb.axis_sink.recv()
        result[y, :] = unpack_buffer(
            frame.tdata,
            int(dut.PIXEL_PER_CYCLE.value),
            int(dut.OUTPUT_PIXEL_BIT_WIDTH.value),
        )

    # check bitlog output against reference
    gamma_inst = Gamma()
    ref = (
        gamma_inst.reference(cfa / 2 ** int(dut.INPUT_PIXEL_BIT_WIDTH.value))
        * 2 ** int(dut.OUTPUT_PIXEL_BIT_WIDTH.value)
    ).astype(np.uint32)

    plt.plot(ref.reshape(h * w))
    plt.plot(result.reshape(h * w))
    plt.savefig("lut_plot.pdf")
    plt.close()

    np.testing.assert_array_equal(result, ref)

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_lut_synth(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("PIXEL_PER_CYCLE", paramset),
                ("LUT_FILE", [str(get_rtl_path() / "lut.mem")]),
            ]
        ),
    )

    rtl.export_markdown_report("LUT", rtl.synthesize_all(family="xc7"))


@pytest.mark.sim
def test_lut_sim(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("PIXEL_PER_CYCLE", paramset),
                ("LUT_FILE", ['"' + str(get_rtl_path() / "lut.mem") + '"']),
            ]
        ),
    )

    rtl.simulate_all("tb.test_lut, ", waves=False)
