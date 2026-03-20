# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import numpy as np


class Decompand:
    """
    Decompand applies a LUT to decompand an companded RAW image.
    """

    def __init__(self, xp: np.ndarray, fp: np.ndarray):
        super().__init__()
        # LUT shall be ordered. X values first, Y values second.
        self.xp = xp
        self.fp = fp

    def reference(self, raw: np.ndarray) -> np.ndarray:
        """
        Decompand input raw image (should be integer)
        """
        # Formula:
        # P_o = P_y0 + (P_y1 - P_y0) * (P_i - P_x0) / (P_x1 - P_x0)

        # Find the two closest values in the LUT
        # Use numpy
        return np.interp(raw, self.xp, self.fp)

    def hardware(self, raw: np.ndarray) -> np.ndarray:
        """
        Decompand input raw image (should be integer)
        """
        raise NotImplementedError
