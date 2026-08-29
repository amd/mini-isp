# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import matplotlib
import numpy as np

matplotlib.use("Agg")
from matplotlib import pyplot as plt
from mini_isp.utils import bitlog2, bitsqrt, bitsqrt_lut, export_lut


def test_bitlog():
    """
    Test bitlog
    """
    # rand = (np.random.rand(100, 100) * np.iinfo(np.uint32).max).astype(np.uint32)
    rand = np.linspace(1, np.iinfo(np.uint32).max - 1, 100000).astype(np.uint32)
    rand[rand == 0] = 1  # exclude zero
    # output = bitlog2(rand).astype(np.float32) / 2**24
    output = bitlog2(rand).astype(np.float32) / 2**24
    reference = np.log2(rand)
    print("max error: ", np.max(np.abs(output - reference)))
    # assert np.allclose(output, reference, atol=1e-2)
    mask = np.abs(output - reference) > 1e-3
    masked = output.copy()
    masked[mask] = 0
    plt.plot(output)
    plt.plot(masked)
    plt.plot(reference)
    plt.savefig("bitlog_plot.pdf")
    plt.close()


def test_bitsqrt():
    """
    Test bitsqrt
    """
    export_lut(bitsqrt_lut, "bitsqrt.mem")
    rand = np.linspace(1, np.iinfo(np.uint32).max - 1, 10000000).astype(np.uint32)
    rand[rand == 0] = 1  # exclude zero
    output = bitsqrt(rand).astype(np.float32) / 2**16
    reference = np.sqrt(rand)
    print("max error: ", np.max(np.abs(output - reference)))
    np.testing.assert_allclose(output, reference, rtol=1e-2)
    mask = np.abs(output - reference) > 60
    masked = output.copy()
    masked[mask] = 0
    plt.plot(output)
    plt.plot(masked)
    plt.plot(reference)
    plt.savefig("bitsqrt_plot.pdf")
    plt.close()
