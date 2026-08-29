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
from mini_isp.colorgain import ColorGain
from mini_isp.config import ParamSet, get_param, get_rtl_path
from mini_isp.rtl import Rtl

toplevel = "colorgain"
sources = [get_rtl_path() / "colorgain.sv"]


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

        self.rgain = int(2 * np.random.rand() * 128) / 128.0
        self.bgain = int(2 * np.random.rand() * 128) / 128.0
        self.g0gain = int(2 * np.random.rand() * 128) / 128.0
        self.g1gain = int(2 * np.random.rand() * 128) / 128.0

        dut.rgain.value = int(self.rgain * 128)
        dut.bgain.value = int(self.bgain * 128)
        dut.g0gain.value = int(self.g0gain * 128)
        dut.g1gain.value = int(self.g1gain * 128)

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
async def test_colorgain_basic(dut):
    """Try accessing the design."""

    tb = TB(dut)

    tb.set_idle_generator(generator=tb.random_pause)
    tb.set_backpressure_generator(generator=tb.random_pause)

    await tb.reset()

    # load image
    cfa = np.random.rand(16, 16)

    h = cfa.shape[0]
    cfa.shape[1]

    # scale to full range
    old_max_px = np.max(cfa)
    new_max_px = 2 ** int(dut.PIXEL_BIT_WIDTH.value) - 1
    cfa = ((cfa / old_max_px) * new_max_px).astype(np.uint32)

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

    # DUT CFA orientation. CFA_BG=0, CFA_GB=1, CFA_GR=2, CFA_RG=3
    code = 0
    match dut.CFA_ORIENTATION.value:
        case 0:
            code = cv2.COLOR_BayerBGGR2BGR
        case 1:
            code = cv2.COLOR_BayerGBRG2BGR
        case 2:
            code = cv2.COLOR_BayerGRBG2BGR
        case 3:
            code = cv2.COLOR_BayerRGGB2BGR

    cg = ColorGain(
        rgain=tb.rgain, bgain=tb.bgain, g0gain=tb.g0gain, g1gain=tb.g1gain, code=code
    )
    ref = cg.reference(cfa)
    ref[ref > new_max_px] = new_max_px

    cv2.imwrite("colorgain_orig.png", ((cfa * 256) / np.max(cfa)).astype(np.uint8))
    cv2.imwrite("colorgain_ref.png", ((ref * 256) / np.max(ref)).astype(np.uint8))
    cv2.imwrite("colorgain.png", ((result * 256) / np.max(result)).astype(np.uint8))

    np.testing.assert_allclose(result.astype(np.uint32), ref.astype(np.uint32), atol=0)

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_colorgain_synth(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("CFA_ORIENTATION", paramset),
                get_param("PIXEL_PER_CYCLE", paramset),
                get_param("PIXEL_BIT_WIDTH", paramset),
            ]
        ),
    )

    rtl.export_markdown_report("Colorgain", rtl.synthesize_all(family="xc7"))


@pytest.mark.sim
def test_colorgain_sim(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("CFA_ORIENTATION", paramset),
                get_param("PIXEL_PER_CYCLE", paramset),
                get_param("PIXEL_BIT_WIDTH", paramset),
            ]
        ),
    )

    rtl.simulate_all("tb.test_colorgain, ", waves=False)
