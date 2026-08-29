# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import itertools
import logging
import random
import sys

import cocotb
import cv2 as cv2
import numpy as np
import pytest
from axis_video import pack_buffer, unpack_buffer
from cocotb.clock import Clock
from cocotb.handle import Immediate
from cocotb.triggers import RisingEdge, Timer
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource
from mini_isp.config import ParamSet, get_param, get_rtl_path
from mini_isp.rtl import Rtl

toplevel = "linebuffer"
sources = [
    get_rtl_path() / "simple_dual_ported_ram.sv",
    get_rtl_path() / "linebuffer.sv",
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
async def test_linebuffer_basic(dut):
    """Try accessing the design."""

    tb = TB(dut)

    tb.set_idle_generator(generator=tb.random_pause)
    tb.set_backpressure_generator(generator=tb.random_pause)

    conv_size = int(dut.CONV_SIZE.value)
    conv_loss = conv_size - 1

    await tb.reset()

    # load image
    cfa = np.random.rand(64, 64)

    # scale to full range
    old_max_px = np.max(cfa)
    new_max_px = 2 ** int(dut.PIXEL_BIT_WIDTH.value) - 1
    cfa = ((cfa / old_max_px) * new_max_px).astype(np.uint32)

    h = cfa.shape[0]
    w = cfa.shape[1]

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

    result = np.zeros((h - conv_loss, w * conv_size), dtype=np.uint32)
    for y in range(0, h - conv_loss):
        frame = await tb.axis_sink.recv()
        result[y, :] = unpack_buffer(
            frame.tdata, int(dut.PIXEL_PER_CYCLE.value), int(dut.PIXEL_BIT_WIDTH.value)
        )

    np.set_printoptions(threshold=sys.maxsize)

    # TODO: assert convolution size and check original values are present in the output

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_linebuffer_synth(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("MAX_RESOLUTION", paramset),
                get_param("PIXEL_PER_CYCLE", paramset),
                get_param("PIXEL_BIT_WIDTH", paramset),
                ("CONV_SIZE", [3, 5, 7]),
            ]
        ),
    )

    rtl.export_markdown_report("Linebuffer", rtl.synthesize_all(family="xc7"))


@pytest.mark.sim
def test_linebuffer_sim(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("MAX_RESOLUTION", paramset),
                get_param("PIXEL_PER_CYCLE", paramset),
                get_param("PIXEL_BIT_WIDTH", paramset),
                ("CONV_SIZE", [3, 5, 7]),
            ]
        ),
    )

    rtl.simulate_all("tb.test_linebuffer, ", waves=False)
