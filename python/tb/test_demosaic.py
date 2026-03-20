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
from colour_demosaicing import demosaicing_CFA_Bayer_Malvar2004
from mini_isp.config import ParamSet, get_param, get_rtl_path
from mini_isp.rtl import Rtl

toplevel = "demosaic"
sources = [
    get_rtl_path() / "simple_dual_ported_ram.sv",
    get_rtl_path() / "linebuffer.sv",
    get_rtl_path() / "demosaic.sv",
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
async def test_demosaic_basic(dut):
    """Try accessing the design."""

    tb = TB(dut)

    tb.set_idle_generator(generator=tb.random_pause)
    tb.set_backpressure_generator(generator=tb.random_pause)

    await tb.reset()

    # load image
    cfa = np.random.rand(64, 64)

    h = cfa.shape[0]
    w = cfa.shape[1]

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

    result = np.zeros((h - 4, 3 * (w - 4)), dtype=np.uint16)
    for y in range(0, h - 4):
        frame = await tb.axis_sink.recv()
        result[y, :] = unpack_buffer(
            frame.tdata,
            int(dut.PIXEL_PER_CYCLE.value),
            int(dut.PIXEL_BIT_WIDTH.value),
            3,
        )

    rgb = np.reshape(result, (h - 4, w - 4, 3))
    g = rgb[:, :, 0]
    b = rgb[:, :, 1]
    r = rgb[:, :, 2]
    rgb2 = np.zeros(rgb.shape)
    rgb2[:, :, 0] = b
    rgb2[:, :, 1] = g
    rgb2[:, :, 2] = r
    rgb3 = np.zeros(rgb.shape)
    rgb3[:, :, 0] = r
    rgb3[:, :, 1] = g
    rgb3[:, :, 2] = b

    # CFA orientation. CFA_BG=0, CFA_GB=1, CFA_GR=2, CFA_RG=3
    match int(dut.CFA_ORIENTATION.value):
        case 0:
            pattern = "BGGR"
        case 1:
            pattern = "GBRG"
        case 2:
            pattern = "GRBG"
        case _:
            pattern = "RGGB"

    ref_rgb = demosaicing_CFA_Bayer_Malvar2004(cfa, pattern)[2:-2, 2:-2]
    ref_rgb[ref_rgb < 0] = 0
    ref_rgb[ref_rgb > new_max_px] = new_max_px

    cv2.imwrite("demosaic.png", (rgb2 / np.max(rgb2)) * 256)
    cv2.imwrite("demosaic_ref.png", (ref_rgb / np.max(ref_rgb)) * 256)

    assert np.allclose(rgb3.astype(np.uint32), ref_rgb.astype(np.uint32), atol=0)

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_demosaic_synth(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("CFA_ORIENTATION", paramset),
                get_param("MAX_RESOLUTION", paramset),
                get_param("PIXEL_PER_CYCLE", paramset),
                get_param("PIXEL_BIT_WIDTH", paramset),
            ]
        ),
    )

    rtl.export_markdown_report("Demosaic", rtl.synthesize_all(family="xc7"))


@pytest.mark.sim
def test_demosaic_sim(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("CFA_ORIENTATION", paramset),
                get_param("MAX_RESOLUTION", paramset),
                get_param("PIXEL_PER_CYCLE", paramset),
                get_param("PIXEL_BIT_WIDTH", paramset),
            ]
        ),
    )

    rtl.simulate_all("tb.test_demosaic, ", waves=False)
