# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

"""
ColorGain. All Modules related to ColorGain
"""

import cv2
import numpy as np


class ColorGain:
    """
    ColorGain applies multiplicative factors to a CFA array.
    """

    def __init__(
        self,
        rgain: float = 1.0,
        bgain: float = 1.0,
        g0gain: float = 1.0,
        g1gain: float = 1.0,
        code: int = cv2.COLOR_BayerBGGR2BGR,
    ):
        super().__init__()
        self.code = code
        self.rgain = rgain
        self.bgain = bgain
        self.g0gain = g0gain
        self.g1gain = g1gain

    def reference(self, cfa: np.ndarray) -> np.ndarray:
        """
        Implments the ColorGain reference implementation
        """

        # TODO assert that input shape is width x height x 1 ndarray
        # TODO: refactor using numpy/cv2 for faster compute
        h = cfa.shape[0]
        w = cfa.shape[1]

        result = cfa.copy()

        # default: COLOR_BayerBGGR2BGR
        b_y = 0
        b_x = 0
        g0_y = 0
        g0_x = 1
        g1_y = 1
        g1_x = 0
        r_y = 1
        r_x = 1

        if self.code == cv2.COLOR_BayerGBRG2BGR:
            g0_y = 0
            g0_x = 0
            b_y = 0
            b_x = 1
            r_y = 1
            r_x = 0
            g1_y = 1
            g1_x = 1

        elif self.code == cv2.COLOR_BayerGRBG2BGR:
            g0_y = 0
            g0_x = 0
            r_y = 0
            r_x = 1
            b_y = 1
            b_x = 0
            g1_y = 1
            g1_x = 1

        elif self.code == cv2.COLOR_BayerRGGB2BGR:
            r_y = 0
            r_x = 0
            g0_y = 0
            g0_x = 1
            g1_y = 1
            g1_x = 0
            b_y = 1
            b_x = 1

        # loop over the image
        for y in range(0, h, 2):
            for x in range(0, w, 2):
                result[y + r_y, x + r_x] *= self.rgain
                result[y + g0_y, x + g0_x] *= self.g0gain
                result[y + g1_y, x + g1_x] *= self.g1gain
                result[y + b_y, x + b_x] *= self.bgain

        return result

    def hardware(self, cfa: np.ndarray) -> np.ndarray:
        """
        Implements the hardware-implemented ColorGain function
        """
        raise NotImplementedError
