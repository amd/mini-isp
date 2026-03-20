# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import itertools
import logging
import random

import cocotb
import cv2 as cv2
import numpy as np
import pytest
from axis_video import pack_buffer, unpack_buffer
from cocotb.clock import Clock
from cocotb.handle import Immediate
from cocotb.triggers import RisingEdge, Timer
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource
from mini_isp.config import get_rtl_path
from mini_isp.rtl import Rtl

toplevel = "skidbuffer"
sources = [get_rtl_path() / "skidbuffer.sv"]


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
async def test_skidbuffer_basic(dut):
    """Try accessing the design."""

    tb = TB(dut)

    tb.set_idle_generator(generator=tb.random_pause)
    tb.set_backpressure_generator(generator=tb.random_pause)

    await tb.reset()

    # load image
    cfa = np.linspace(0, 399, 400)
    cfa = np.reshape(cfa, (-1, 20))

    h = cfa.shape[0]
    w = cfa.shape[1]

    # loop over the image
    tuser = [1] * tb.axis_source.byte_lanes + [0]
    for y in range(0, h):
        frame = AxiStreamFrame(
            pack_buffer(
                cfa[y, :].astype(np.uint16), 1, dut.DATA_WIDTH.value.to_unsinged()
            ),
            tuser=tuser,
        )
        await tb.axis_source.send(frame)
        # tuser should only be set for first line (signals start of frame)
        tuser = 0

    result = np.zeros((h, w), dtype=np.uint16)
    for y in range(0, h):
        frame = await tb.axis_sink.recv()
        result[y, :] = unpack_buffer(frame.tdata, 1, dut.DATA_WIDTH.value.to_unsinged())

    # TODO: implement real skidbuffer tests

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_skidbuffer_synth():
    rtl = Rtl(
        toplevel,
        sources,
        dict([("DATA_WIDTH", [16, 32])]),
    )

    rtl.export_markdown_report("Skid buffer", rtl.synthesize_all(family="xc7"))


@pytest.mark.sim
def test_skidbuffer_sim():
    rtl = Rtl(
        toplevel,
        sources,
        dict([("DATA_WIDTH", [16, 32])]),
    )

    rtl.simulate_all("tb.test_skidbuffer, ", waves=False)
