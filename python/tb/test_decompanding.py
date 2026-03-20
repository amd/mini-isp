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
from mini_isp.decompand import Decompand
from mini_isp.rtl import Rtl

toplevel = "decompanding"
sources = [get_rtl_path() / "decompanding.sv"]


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
async def test_decompanding(dut):
    """Try accessing the design."""

    tb = TB(dut)

    tb.set_idle_generator(generator=tb.random_pause)
    tb.set_backpressure_generator(generator=tb.random_pause)

    await tb.reset()

    cfa = np.random.randint(
        0, 2 ** (int(dut.PIXEL_BIT_WIDTH_IN.value)), (64, 64), dtype=np.uint16
    )

    h = cfa.shape[0]
    w = cfa.shape[1]

    # loop over the image
    tuser = [1] * tb.axis_source.byte_lanes + [0]
    for y in range(0, h):
        frame = AxiStreamFrame(
            pack_buffer(
                cfa[y, :].astype(np.uint16),
                int(dut.PIXEL_PER_CYCLE.value),
                int(dut.PIXEL_BIT_WIDTH_IN.value),
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
            int(dut.PIXEL_BIT_WIDTH_OUT.value),
        )

    # 16 bit to 24 bit decompanding
    # isp_decomp = decompand.Decompand([0, 0x0200, 0x0400, 0x0800, 0x1000, 0x2000, 0x4000, 0x8000, 0x8200, 0x8600, 0x8E00, 0x9E00, 0xBE00, 0xC200, 0xCA00, 0xDA00, 0xFA00], [0, 2**9, 2**10, 2**11, 2**12, 2**13, 2**14, 2**15, 2**16, 2**17, 2**18, 2**19, 2**20, 2**21, 2**22, 2**23, 2**24])
    # 12 bit to 24 bit decompanding
    isp_decomp = Decompand(
        [
            0,
            0x200,
            0x400,
            0x600,
            0x700,
            0x800,
            0x900,
            0x980,
            0xA00,
            0xB00,
            0xB80,
            0xC00,
            0xC80,
            0xD00,
            0xE00,
            0xE80,
            0xF00,
        ],
        [
            0,
            2**9,
            2**10,
            2**11,
            2**12,
            2**13,
            2**14,
            2**15,
            2**16,
            2**17,
            2**18,
            2**19,
            2**20,
            2**21,
            2**22,
            2**23,
            2**24,
        ],
    )
    dec_raw = isp_decomp.reference(cfa).astype(np.uint32)

    # clamp to 24 bit
    dec_raw[dec_raw > 2**24 - 1] = 2**24 - 1

    np.testing.assert_array_equal(result, dec_raw)

    for y in range(0, h):
        for x in range(0, w):
            if result[y, x] != dec_raw[y, x]:
                print(
                    "CFA: ",
                    cfa[y, x],
                    " (",
                    hex(cfa[y, x]),
                    "), Result: ",
                    result[y, x],
                    " (",
                    hex(result[y, x]),
                    "), reference: ",
                    dec_raw[y, x],
                    " (",
                    hex(dec_raw[y, x]),
                    ")",
                )

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_decompanding_synth(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("PIXEL_PER_CYCLE", paramset),
                ("XLUT_FILE", [str(get_rtl_path() / "decompanding_xlut.mem")]),
                ("YLUT_FILE", [str(get_rtl_path() / "decompanding_ylut_12_bit.mem")]),
                ("FLUT_FILE", [str(get_rtl_path() / "decompanding_flut_12_bit.mem")]),
            ]
        ),
    )

    rtl.export_markdown_report("Decompanding", rtl.synthesize_all(family="xc7"))


@pytest.mark.sim
def test_decompanding_sim(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("PIXEL_PER_CYCLE", paramset),
                (
                    "XLUT_FILE",
                    ['"' + str(get_rtl_path() / "decompanding_xlut.mem") + '"'],
                ),
                (
                    "YLUT_FILE",
                    ['"' + str(get_rtl_path() / "decompanding_ylut_12_bit.mem") + '"'],
                ),
                (
                    "FLUT_FILE",
                    ['"' + str(get_rtl_path() / "decompanding_flut_12_bit.mem") + '"'],
                ),
            ]
        ),
    )
    rtl.simulate_all("tb.test_decompanding, ", waves=False)
