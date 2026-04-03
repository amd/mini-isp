# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

"""
Black Level Correction. Subtracts the black level from input pixel data
"""

import numpy as np


class BlackLevelCorrection:
    """
    Black level correction subtracts the black level rom input pixel data
    """

    def __init__(self, black_level: np.uint32 = np.uint32(0)):
        super().__init__()
        self.black_level = black_level

    def reference(self, cfa: np.ndarray) -> np.ndarray:
        """
        Reference implementation for black level correction
        """
        result = cfa.copy().astype(np.double)
        mask = result < np.max(result)
        np.putmask(result, mask, result - self.black_level)

        # clip to 0
        result[result < 0] = 0

        return result

    def hardware(self, cfa: np.ndarray) -> np.ndarray:
        """
        Reference implementation for black level correction
        Identical to reference implementation
        """
        return self.reference(cfa)
