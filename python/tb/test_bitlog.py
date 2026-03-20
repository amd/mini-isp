# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import itertools
import logging
import random

import cocotb
import matplotlib

matplotlib.use("Agg")
import cv2 as cv2
import numpy as np
import pytest
from axis_video import pack_buffer, unpack_buffer
from cocotb.clock import Clock
from cocotb.handle import Immediate
from cocotb.triggers import RisingEdge, Timer
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource
from matplotlib import pyplot as plt
from mini_isp.config import ParamSet, get_param, get_rtl_path
from mini_isp.rtl import Rtl
from mini_isp.utils import bitlog2

toplevel = "bitlog"
sources = [
    get_rtl_path() / "simple_dual_ported_rom.sv",
    get_rtl_path() / "bitlog.sv",
]


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

        self.axis_source = AxiStreamSource(
            AxiStreamBus.from_prefix(dut, "s_axis"),
            dut.clk,
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
async def test_bitlog_basic(dut):
    """Try accessing the design."""

    tb = TB(dut)

    tb.set_idle_generator(generator=tb.random_pause)
    tb.set_backpressure_generator(generator=tb.random_pause)

    await tb.reset()

    # cfa = np.random.randint(2**(dut.PIXEL_BIT_WIDTH.value), size=(128, 128), dtype=np.uint32)
    cfa = np.linspace(
        start=0,
        stop=2 ** int(dut.PIXEL_BIT_WIDTH.value),
        endpoint=False,
        num=128 * 128,
        dtype=np.uint32,
    )
    cfa = cfa.reshape(128, 128)

    h = cfa.shape[0]
    cfa.shape[1]

    # loop over the image
    tuser = [1] * tb.axis_source.byte_lanes + [0]
    for y in range(0, h):
        frame = AxiStreamFrame(
            pack_buffer(
                cfa[y, :].astype(np.uint32),
                int(dut.PIXEL_PER_CYCLE.value),
                int(dut.PIXEL_BIT_WIDTH.value),
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
            frame.tdata, int(dut.PIXEL_PER_CYCLE.value), int(dut.PIXEL_BIT_WIDTH.value)
        )

    # check bitlog output against reference
    lzc_width = np.ceil(np.log2(int(dut.PIXEL_BIT_WIDTH.value)))
    bit_width_diff = 32 - int(dut.PIXEL_BIT_WIDTH.value)
    shift = bit_width_diff - (8 - lzc_width)
    ref = bitlog2(cfa) >> int(shift)

    plt.plot(ref.reshape(128 * 128))
    plt.plot(result.reshape(128 * 128))
    plt.savefig("plot.png")
    plt.close()

    np.testing.assert_array_equal(result, ref)

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_bitlog_synth(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("PIXEL_PER_CYCLE", paramset),
                get_param("PIXEL_BIT_WIDTH", paramset),
                ("BITLOG_FILE", [str(get_rtl_path() / "bitlog.mem")]),
            ]
        ),
    )

    rtl.export_markdown_report("Bitlog", rtl.synthesize_all(family="xc7"))


@pytest.mark.sim
def test_bitlog_sim(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("PIXEL_PER_CYCLE", paramset),
                get_param("PIXEL_BIT_WIDTH", paramset),
                ("BITLOG_FILE", ['"' + str(get_rtl_path() / "bitlog.mem") + '"']),
            ]
        ),
    )

    rtl.simulate_all("tb.test_bitlog, ", waves=False)
