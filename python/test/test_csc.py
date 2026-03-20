# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import numpy as np
from mini_isp.csc import Rgb2YCoCg


def test_csc():
    """
    Test the color space conversion
    """
    csc = Rgb2YCoCg()
    img = np.random.rand(100, 100, 3)
    output = csc.reference(img)
    assert output.shape == img.shape
    assert output.dtype == img.dtype
    output_hw = csc.hardware(img)
    assert output_hw.shape == img.shape
