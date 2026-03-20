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
from mini_isp.config import ParamSet, get_param, get_rtl_path
from mini_isp.gamma import Gamma
from mini_isp.rtl import Rtl

toplevel = "gamma"
sources = [
    get_rtl_path() / "simple_dual_ported_rom.sv",
    get_rtl_path() / "lut.sv",
    get_rtl_path() / "gamma.sv",
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
async def test_gamma_basic(dut):
    """Try accessing the design."""

    tb = TB(dut)

    tb.set_idle_generator(generator=tb.random_pause)
    tb.set_backpressure_generator(generator=tb.random_pause)

    await tb.reset()

    # load image
    cfa = np.random.rand(64, 64, 3)

    h = cfa.shape[0]
    w = cfa.shape[1]

    # scale to full range
    old_max_px = np.max(cfa)
    new_max_px = 2 ** int(dut.INPUT_COMPONENT_BIT_WIDTH.value) - 1
    cfa = ((cfa / old_max_px) * new_max_px).astype(np.uint32)

    h = cfa.shape[0]
    w = cfa.shape[1]

    cfa = cfa.reshape((h, 3 * w))

    # loop over the image
    tuser = [1] * tb.axis_source.byte_lanes + [0]
    for y in range(0, h):
        frame = AxiStreamFrame(
            pack_buffer(
                cfa[y, :].astype(np.uint32),
                int(dut.PIXEL_PER_CYCLE.value),
                int(dut.INPUT_COMPONENT_BIT_WIDTH.value),
                3,
            ),
            tuser=tuser,
        )
        await tb.axis_source.send(frame)
        # tuser should only be set for first line (signals start of frame)
        tuser = 0

    result = np.zeros((h, 3 * (w)), dtype=np.uint32)
    for y in range(0, h):
        frame = await tb.axis_sink.recv()
        result[y, :] = unpack_buffer(
            frame.tdata,
            int(dut.PIXEL_PER_CYCLE.value),
            int(dut.OUTPUT_COMPONENT_BIT_WIDTH.value),
            3,
        )

    rgb = np.reshape(result, (h, w, 3))
    rgb_min = np.min(rgb)
    rgb_max = np.max(rgb)
    offset = rgb_min
    gain = 255 / (rgb_max - rgb_min)

    gamma = Gamma(bitwidth=int(dut.INPUT_COMPONENT_BIT_WIDTH.value))
    ref = np.reshape(
        gamma.reference(cfa / 2 ** int(dut.INPUT_COMPONENT_BIT_WIDTH.value))
        * 2 ** int(dut.OUTPUT_COMPONENT_BIT_WIDTH.value),
        (h, w, 3),
    ).astype(np.uint32)

    rgb = (rgb - offset) * gain

    cv2.imwrite("gamma.png", rgb.astype(np.uint8))

    np.testing.assert_allclose(
        rgb, ref, atol=2 ** (-int(dut.OUTPUT_COMPONENT_BIT_WIDTH.value))
    )

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_gamma_synth(paramset: ParamSet):
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

    rtl.export_markdown_report("Gamma", rtl.synthesize_all(family="xc7"))


@pytest.mark.sim
def test_gamma_sim(paramset: ParamSet):
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

    rtl.simulate_all("tb.test_gamma, ", waves=False)
