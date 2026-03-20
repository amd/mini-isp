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
from mini_isp.ccm import Ccm
from mini_isp.config import ParamSet, get_param, get_rtl_path
from mini_isp.rtl import Rtl

toplevel = "ccm"
sources = [
    get_rtl_path() / "ccm.sv",
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
async def test_ccm_basic(dut):
    """Try accessing the design."""

    tb = TB(dut)

    tb.set_idle_generator(generator=tb.random_pause)
    tb.set_backpressure_generator(generator=tb.random_pause)

    await tb.reset()

    # Format: 4.12
    # TODO: random matrix
    matrix = (
        np.array(
            [
                [1.7846716625128374, -0.7261240476375332, -0.08274697420358428],
                [-0.2975654035173307, 1.5960425637021738, -0.2961043416505157],
                [0.12546426281675097, -0.8773434727076518, 1.7330356805246686],
            ]
        )
        * (2**12)
    ).astype(np.int32)

    dut.ccm_r_r.value = int(matrix[0, 0])
    dut.ccm_r_g.value = int(matrix[0, 1])
    dut.ccm_r_b.value = int(matrix[0, 2])
    dut.ccm_g_r.value = int(matrix[1, 0])
    dut.ccm_g_g.value = int(matrix[1, 1])
    dut.ccm_g_b.value = int(matrix[1, 2])
    dut.ccm_b_r.value = int(matrix[2, 0])
    dut.ccm_b_g.value = int(matrix[2, 1])
    dut.ccm_b_b.value = int(matrix[2, 2])

    # load image
    cfa = np.random.rand(64, 64, 3)

    h = cfa.shape[0]
    w = cfa.shape[1]

    # scale to full range
    old_max_px = np.max(cfa)
    new_max_px = 2 ** dut.COMPONENT_BIT_WIDTH.value.to_unsigned() - 1
    cfa = ((cfa / old_max_px) * new_max_px).astype(np.uint32) / 2

    h = cfa.shape[0]
    w = cfa.shape[1]

    # RGB to RBG
    cfa_rbg = cfa.copy()
    r = cfa[:, :, 0]
    g = cfa[:, :, 1]
    b = cfa[:, :, 2]
    cfa_rbg[:, :, 0] = g
    cfa_rbg[:, :, 1] = b
    cfa_rbg[:, :, 2] = r
    cfa_rbg = cfa_rbg.reshape((h, 3 * w))

    # loop over the image
    tuser = [1] * tb.axis_source.byte_lanes + [0]
    for y in range(0, h):
        frame = AxiStreamFrame(
            pack_buffer(
                cfa_rbg[y, :].astype(np.uint32),
                dut.PIXEL_PER_CYCLE.value.to_unsigned(),
                dut.COMPONENT_BIT_WIDTH.value.to_unsigned(),
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
            dut.PIXEL_PER_CYCLE.value.to_unsigned(),
            dut.COMPONENT_BIT_WIDTH.value.to_unsigned(),
            3,
        )

    rgb = np.reshape(result, (h, w, 3))
    # RBG to RGB
    r = rgb[:, :, 2]
    g = rgb[:, :, 0]
    b = rgb[:, :, 1]
    rgb2 = rgb.copy()
    rgb2[:, :, 2] = b
    rgb2[:, :, 1] = g
    rgb2[:, :, 0] = r

    ccm = Ccm(matrix / (2**12))
    ref = ccm.reference(np.reshape(cfa, (h, w, 3)))
    ref[ref < 0.0] = 0
    ref[ref > new_max_px] = new_max_px

    np.savetxt("orig.txt", cfa.reshape((h, 3 * w)).astype(np.uint32))
    np.savetxt("ccm.txt", rgb2.reshape((h, 3 * w)).astype(np.uint32))
    np.savetxt("ref.txt", ref.reshape((h, 3 * w)).astype(np.uint32))

    cv2.imwrite("orig.png", cfa.astype(np.uint8))
    cv2.imwrite("ccm.png", rgb2.astype(np.uint8))
    cv2.imwrite("ref.png", ref.astype(np.uint8))

    print(rgb2)
    print(ref.astype(np.uint32))

    np.testing.assert_allclose(rgb2.astype(np.uint32), ref.astype(np.uint32), atol=1)

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_ccm_synth(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("PIXEL_PER_CYCLE", paramset),
                ("COMPONENT_BIT_WIDTH", [8, 10, 12]),
            ]
        ),
    )

    rtl.export_markdown_report(
        "Color Correction Matrix", rtl.synthesize_all(family="xc7")
    )


@pytest.mark.sim
def test_ccm_sim(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("PIXEL_PER_CYCLE", paramset),
                ("COMPONENT_BIT_WIDTH", [8, 10, 12]),
            ]
        ),
    )

    rtl.simulate_all("tb.test_ccm, ", waves=True)
