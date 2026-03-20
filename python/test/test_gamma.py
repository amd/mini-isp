# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import matplotlib
import numpy as np

matplotlib.use("Agg")
from matplotlib import pyplot as plt
from mini_isp.gamma import Gamma


def residuals(p, y, x):
    srgb = Gamma()
    return y - srgb.hardware_pwl(x, p)


def max_error(p, y, x):
    srgb = Gamma()
    print(p)
    return np.max(y - srgb.hardware(x, p))


def test_gamma():
    """
    Test gamma
    """
    rand = np.linspace(0.0, 0.005, 10000, endpoint=False)
    srgb = Gamma()

    reference = srgb.reference(rand)
    output = srgb.hardware(rand)
    output_pwl = srgb.hardware_pwl(rand)

    srgb.export_lut("gamma")

    diff = np.abs(output - reference)
    print("max absolute error: ", np.max(diff))

    diff_pwl = np.abs(output_pwl - reference)
    print("max absolute error pwl: ", np.max(diff_pwl))
    assert np.allclose(output_pwl, reference, atol=1e-2)

    # plt.plot(reference)
    # plt.plot(output)
    # plt.plot(output_pwl)
    plt.plot(diff * 2**24)
    plt.savefig("gamma_plot.pdf")
    plt.close()
