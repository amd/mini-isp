# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

"""
CSC. All Modules related to Color Space Conversion.
"""

import numpy as np


class CSC:
    """
    CSC converts input ndarray to another color space using linear transformation.
    """

    def __init__(self, ccm: np.ndarray):
        super().__init__()
        self.ccm = ccm

    def reference(self, img: np.ndarray) -> np.ndarray:
        """
        Convert img into another color space as defined in CCM
        """
        return np.matmul(img, self.ccm.T)

    def hardware(self, img: np.ndarray) -> np.ndarray:
        """
        Convert img into another color space bit-accurate
        """
        return np.matmul(img, self.ccm.T)


class Rgb2YCoCg(CSC):
    """
    Helper class Rgb2YCoCg converts input RGB ndarray to YCoCg.
    """

    def __init__(self):
        super().__init__(
            np.array([[0.25, 0.5, 0.25], [-0.5, 0, 0.5], [-0.25, 0.5, -0.25]])
        )


class YCoCg2Rgb(CSC):
    """
    Helper class YCoCg2Rgb converts input YCoCg ndarray to RGB.
    """

    def __init__(self):
        super().__init__(np.array([[1, 1, -1], [1, 0, 1], [1, -1, -1]]))


class Rgb2Xyz(CSC):
    """
    Helper class Rgb2Xyz converts input RGB ndarray to Custom XYZ.
    """

    def __init__(self):
        super().__init__(
            np.array(
                [
                    [0.6250, 0.2500, 0.1250],
                    [0.3125, 0.6250, 0.0625],
                    [0.0625, 0.1250, 0.8125],
                ]
            )
        )


class Xyz2Rgb(CSC):
    """
    Helper class Xyz2Rgb converts input Custom XZY ndarray to RGB.
    """

    def __init__(self):
        super().__init__(
            np.array([[2.00, -0.75, -0.25], [-1.00, 2.00, 0], [0, -0.25, 1.25]])
        )
