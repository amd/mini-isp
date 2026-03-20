# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

"""
Min, Max and Mean implementation.
"""

import numpy as np


class MinMaxMean:
    """
    MinMaxMean Computes the minimum, maximum and mean of an input array.
    """

    def __init__(self):
        super().__init__()

    def reference(self, array: np.ndarray):
        """
        Implements min, max and mean.
        Uses Numpy for exaxt values.
        """

        return np.min(array), np.max(array), np.mean(array)

    def hardware(self, array: np.ndarray):
        """
        HW implementtion (it is identical).
        """

        return self.reference(array)
