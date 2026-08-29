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
from axis_video import pack_buffer
from cocotb.clock import Clock
from cocotb.handle import Immediate
from cocotb.triggers import RisingEdge, Timer
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSource
from mini_isp.config import ParamSet, get_param, get_rtl_path
from mini_isp.rtl import Rtl

toplevel = "minmaxmean"
sources = [
    get_rtl_path() / "non_restoring_unsigned_divider.sv",
    get_rtl_path() / "minmaxmean.sv",
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

        # set log level
        self.axis_source.log.setLevel(logging.WARNING)

    def random_pause(self):
        return itertools.cycle(random.choices([0, 1], k=random.randint(7, 1023)))

    def set_idle_generator(self, generator=None):
        if generator:
            self.axis_source.set_pause_generator(generator())

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
async def test_minmaxmean_basic(dut):
    """Try accessing the design."""

    tb = TB(dut)

    tb.set_idle_generator(generator=tb.random_pause)

    await tb.reset()

    # load image
    cfa = np.random.rand(64, 64)

    # scale to full range
    old_max_px = np.max(cfa)
    new_max_px = 2 ** int(dut.PIXEL_BIT_WIDTH.value) - 1
    cfa = ((cfa / old_max_px) * new_max_px).astype(np.uint32)

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

    for _ in range(0, h):
        await RisingEdge(dut.valid_out)

    ref_min = np.min(cfa)
    ref_max = np.max(cfa)
    ref_mean = np.mean(cfa).astype(np.uint32)
    dut_min = dut.min_out.value.integer
    dut_max = dut.max_out.value.integer
    dut_mean = dut.mean_out.value.integer

    assert dut_min == ref_min, f"Min mismatch: {dut_min} != {ref_min}"
    assert dut_max == ref_max, f"Max mismatch: {dut_max} != {ref_max}"
    assert dut_mean == ref_mean, f"Mean mismatch: {dut_mean} != {ref_mean}"

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_minmaxmean_synth(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("PIXEL_PER_CYCLE", paramset),
                get_param("PIXEL_BIT_WIDTH", paramset),
            ]
        ),
    )

    rtl.export_markdown_report("MinMaxMean", rtl.synthesize_all(family="xc7"))


@pytest.mark.sim
def test_minmaxmean_sim(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                # TODO: support 2 and 4 PPC
                ("PIXEL_PER_CYCLE", [1]),
                get_param("PIXEL_BIT_WIDTH", paramset),
            ]
        ),
    )

    rtl.simulate_all("tb.test_minmaxmean, ", waves=False)
