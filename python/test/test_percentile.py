# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import matplotlib
import numpy as np
from mini_isp.camera import Camera

matplotlib.use("Agg")
from matplotlib import pyplot as plt
from mini_isp.decompand import Decompand
from mini_isp.percentile import Percentile
from mini_isp.utils import bitlog2


def test_percentile():
    """
    Test the color space conversion
    """

    width = 1024
    height = 128
    np.uint16
    target_width = 128
    target_height = 128

    camera = Camera(width=width, height=height, bitwidth=12)
    raw = camera.reference().astype(np.uint16)
    isp_decomp = Decompand(
        [
            0,
            0x0200,
            0x0400,
            0x0800,
            0x1000,
            0x2000,
            0x4000,
            0x8000,
            0x8200,
            0x8600,
            0x8E00,
            0x9E00,
            0xBE00,
            0xC200,
            0xCA00,
            0xDA00,
            0xFA00,
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
    dec_raw = isp_decomp.reference(raw).astype(np.uint32)

    dec_raw = bitlog2(dec_raw)

    x_pos = 0
    y_pos = 0
    size = int((width - target_width) / 2)
    ref_min = np.zeros(size)
    ref_max = np.zeros(size)
    ref_median = np.zeros(size)
    hw_min = np.zeros(size)
    hw_max = np.zeros(size)
    hw_median = np.zeros(size)
    perc = Percentile(target_width * target_height)
    for x_pos in range(0, width - target_width, 2):
        idx = int(x_pos / 2)
        cropped = dec_raw[y_pos : y_pos + target_height, x_pos : x_pos + target_width]
        ref_min[idx], ref_max[idx], ref_median[idx] = perc.reference(cropped)
        hw_min[idx], hw_max[idx], hw_median[idx] = perc.hardware(cropped)

    plt.plot(ref_min, color="lightblue")
    plt.plot(ref_max, color="darkblue")
    plt.plot(ref_median, color="blue")

    plt.plot(hw_min, color="lightsalmon")
    plt.plot(hw_max, color="darksalmon")
    plt.plot(hw_median, color="salmon")

    plt.savefig("percentile_plot.pdf")
    plt.close()
