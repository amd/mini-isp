# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

"""
Ccm. All Modules related to Color Correction Matrix.
"""

import numpy as np


class Ccm:
    """
    Ccm multiplies input (RGB) ndarray with a 3x4 transformation matrix.
    """

    def __init__(self, ccm: np.ndarray):
        self.ccm = ccm

    def reference(self, img: np.ndarray) -> np.ndarray:
        """
        Multiply img with Ccm
        """
        return np.matmul(img, self.ccm.T)

    def hardware(self, img: np.ndarray) -> np.ndarray:
        """
        Multiply img with Ccm (bit-accurate)
        """
        return np.matmul(img, self.ccm.T)
