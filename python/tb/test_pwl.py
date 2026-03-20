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
from mini_isp.gamma import Gamma
from mini_isp.rtl import Rtl

toplevel = "pwl"
sources = [
    get_rtl_path() / "simple_dual_ported_rom.sv",
    get_rtl_path() / "pwl.sv",
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
async def test_pwl_basic(dut):
    """Try accessing the design."""

    tb = TB(dut)

    tb.set_idle_generator(generator=tb.random_pause)
    tb.set_backpressure_generator(generator=tb.random_pause)

    await tb.reset()

    # cfa = np.random.randint(2**(dut.PIXEL_BIT_WIDTH.value), size=(128, 128), dtype=np.uint32)
    cfa = np.linspace(
        start=0,
        stop=2 ** (dut.PIXEL_BIT_WIDTH.value.to_unsigned()),
        endpoint=False,
        num=128 * 128,
        dtype=np.uint32,
    )
    cfa = cfa.reshape(128, 128)

    h = cfa.shape[0]
    w = cfa.shape[0]

    # loop over the image
    tuser = [1] * tb.axis_source.byte_lanes + [0]
    for y in range(0, h):
        frame = AxiStreamFrame(
            pack_buffer(
                cfa[y, :].astype(np.uint32),
                dut.PIXEL_PER_CYCLE.value.to_unsigned(),
                dut.PIXEL_BIT_WIDTH.value.to_unsigned(),
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
            dut.PIXEL_PER_CYCLE.value.to_unsigned(),
            dut.PIXEL_BIT_WIDTH.value.to_unsigned(),
        )

    gamma = Gamma()

    # check bitlog output against reference
    ref = (
        gamma.hardware_pwl(cfa / 2 ** dut.PIXEL_BIT_WIDTH.value.to_unsigned())
        * 2 ** dut.PIXEL_BIT_WIDTH.value.to_unsigned()
    ).astype(np.uint32)

    # TODO: clipping in RTL module
    result[ref > 2 ** dut.PIXEL_BIT_WIDTH.value.to_unsigned() - 1] = (
        2 ** dut.PIXEL_BIT_WIDTH.value.to_unsigned() - 1
    )
    ref[ref > 2 ** dut.PIXEL_BIT_WIDTH.value.to_unsigned() - 1] = (
        2 ** dut.PIXEL_BIT_WIDTH.value.to_unsigned() - 1
    )

    diff = ref - result
    diff[diff > 320] = 320
    plt.plot(ref.reshape(w * h))
    plt.plot(result.reshape(w * h))
    plt.savefig("plot.pdf")
    plt.close()

    # TODO: improve matching to reference LUT... this should be better
    np.testing.assert_allclose(result, ref, atol=2300)

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_pwl_synth(paramset: ParamSet):
    rtl = Rtl(
        "pwl",
        [
            get_rtl_path() / "simple_dual_ported_rom.sv",
            get_rtl_path() / "pwl.sv",
        ],
        dict(
            [
                get_param("PIXEL_PER_CYCLE", paramset),
                ("PIXEL_BIT_WIDTH", [24]),
                ("OFFSET_FILE", [str(get_rtl_path() / "gamma_offset.mem")]),
                ("GAIN_FILE", [str(get_rtl_path() / "gamma_gain.mem")]),
            ]
        ),
    )

    rtl.export_markdown_report("Piece-wise Linear", rtl.synthesize_all(family="xc7"))


@pytest.mark.sim
def test_pwl_sim(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("PIXEL_PER_CYCLE", paramset),
                ("PIXEL_BIT_WIDTH", [24]),
                ("OFFSET_FILE", ['"' + str(get_rtl_path() / "gamma_offset.mem") + '"']),
                ("GAIN_FILE", ['"' + str(get_rtl_path() / "gamma_gain.mem") + '"']),
            ]
        ),
    )

    rtl.simulate_all("tb.test_pwl, ", waves=False)
