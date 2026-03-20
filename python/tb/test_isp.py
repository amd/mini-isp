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
from cocotbext.axi import (
    AxiLiteBus,
    AxiLiteMaster,
    AxiStreamBus,
    AxiStreamFrame,
    AxiStreamSink,
    AxiStreamSource,
)
from mini_isp.camera import Camera
from mini_isp.config import ParamSet, get_param, get_rtl_path
from mini_isp.rtl import Rtl

toplevel = "isp"
sources = [
    get_rtl_path() / "axi_lite_register.sv",
    get_rtl_path() / "skidbuffer.sv",
    get_rtl_path() / "decompanding.sv",
    get_rtl_path() / "colorgain.sv",
    get_rtl_path() / "simple_dual_ported_ram.sv",
    get_rtl_path() / "linebuffer.sv",
    get_rtl_path() / "demosaic.sv",
    get_rtl_path() / "ccm.sv",
    get_rtl_path() / "simple_dual_ported_rom.sv",
    get_rtl_path() / "lut.sv",
    get_rtl_path() / "gamma.sv",
    get_rtl_path() / "blc.sv",
    get_rtl_path() / "isp.sv",
]


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

        self.axi_master = AxiLiteMaster(
            AxiLiteBus.from_prefix(dut, "s_axi"),
            dut.clk,
            dut.rstn,
            reset_active_level=False,
        )

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
async def test_isp(dut):
    """Try accessing the design."""

    tb = TB(dut)

    tb.set_idle_generator(generator=tb.random_pause)
    tb.set_backpressure_generator(generator=tb.random_pause)

    await tb.reset()

    # set 6600K color gains {478, 152},
    await tb.axi_master.write(0x00, 0x009801DE.to_bytes(4, byteorder="little"))

    # set 6600K CCM {8775, -574, 63, -4647, 6556, -2026, 43, -1981, 6116},
    await tb.axi_master.write(0x08, 0xFDC22247.to_bytes(4, byteorder="little"))
    await tb.axi_master.write(0x0C, 0xEDD9003F.to_bytes(4, byteorder="little"))
    await tb.axi_master.write(0x10, 0xF816199C.to_bytes(4, byteorder="little"))
    await tb.axi_master.write(0x14, 0xF843002B.to_bytes(4, byteorder="little"))
    await tb.axi_master.write(0x18, 0x010017E4.to_bytes(4, byteorder="little"))

    cam = Camera(width=128, height=128, bitwidth=int(dut.PIXEL_BIT_WIDTH.value))
    cfa = cam.reference()

    for img in range(0, 1):
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

        result = np.zeros((h - 4, 3 * (w - 4)), dtype=np.uint32)
        for y in range(0, h - 4):
            frame = await tb.axis_sink.recv()
            result[y, :] = unpack_buffer(
                frame.tdata,
                int(dut.PIXEL_PER_CYCLE.value),
                int(dut.COMPONENT_BIT_WIDTH.value),
                3,
            )
            print(
                "Completed frame " + str(img) + ", line " + str(y) + " of " + str(h - 4)
            )

        rgb = np.reshape(result, (h - 4, w - 4, 3))
        g = rgb[:, :, 0]
        b = rgb[:, :, 1]
        r = rgb[:, :, 2]
        rgb2 = np.zeros(rgb.shape)
        rgb2[:, :, 0] = b
        rgb2[:, :, 1] = g
        rgb2[:, :, 2] = r

        # TODO: check against reference implementation!

        cv2.imwrite("full_isp_" + str(img) + ".png", rgb2.astype(np.uint8))

    await Timer(20 * 10, unit="ns")


@pytest.mark.synth
def test_isp_synth(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("CFA_ORIENTATION", ParamSet.SIMFAST),
                get_param("MAX_RESOLUTION", paramset),
                get_param("PIXEL_PER_CYCLE", paramset),
                get_param("PIXEL_BIT_WIDTH", ParamSet.DEFAULT),
                (
                    "DECOMPANDING_XLUT_FILE",
                    [str(get_rtl_path() / "decompanding_xlut.mem")],
                ),
                (
                    "DECOMPANDING_YLUT_FILE",
                    [str(get_rtl_path() / "decompanding_ylut_12_bit.mem")],
                ),
                (
                    "DECOMPANDING_FLUT_FILE",
                    [str(get_rtl_path() / "decompanding_flut_12_bit.mem")],
                ),
                ("GAMMA_LUT_FILE", [str(get_rtl_path() / "lut.mem")]),
            ]
        ),
    )

    rtl.export_markdown_report("ISP", rtl.synthesize_all(family="xc7"))


@pytest.mark.sim
def test_isp_sim(paramset: ParamSet):
    rtl = Rtl(
        toplevel,
        sources,
        dict(
            [
                get_param("CFA_ORIENTATION", ParamSet.SIMFAST),
                get_param("MAX_RESOLUTION", paramset),
                get_param("PIXEL_PER_CYCLE", paramset),
                ("PIXEL_BIT_WIDTH", [12]),
                (
                    "DECOMPANDING_XLUT_FILE",
                    ['"' + str(get_rtl_path() / "decompanding_xlut.mem") + '"'],
                ),
                (
                    "DECOMPANDING_YLUT_FILE",
                    ['"' + str(get_rtl_path() / "decompanding_ylut_12_bit.mem") + '"'],
                ),
                (
                    "DECOMPANDING_FLUT_FILE",
                    ['"' + str(get_rtl_path() / "decompanding_flut_12_bit.mem") + '"'],
                ),
                ("GAMMA_LUT_FILE", ['"' + str(get_rtl_path() / "lut.mem") + '"']),
            ]
        ),
    )

    rtl.simulate_all("tb.test_isp, ", waves=False)
