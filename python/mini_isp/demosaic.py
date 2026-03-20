# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

"""
Demosaic. All Modules related to demosaicking.
"""

import cv2
import numpy as np
from colour_demosaicing import demosaicing_CFA_Bayer_Malvar2004


class Demosaic:
    """
    Demosaic converts input raw image into a RGB output.
    """

    def __init__(self, code: int = cv2.COLOR_BayerBGGR2BGR):
        super().__init__()
        self.code = code

    def reference(self, cfa: np.ndarray) -> np.ndarray:
        """
        Demosaic converts input raw image into a RGB output.
        """
        # TODO: decode code and find correct pattern
        # rgb = demosaicing_CFA_Bayer_Malvar2004(cfa, "BGGR")
        rgb = demosaicing_CFA_Bayer_Malvar2004(cfa, "GBRG")
        return rgb

    def hardware(self, cfa: np.ndarray) -> np.ndarray:
        """
        Demosaic converts input raw image into a RGB output.
        """
        # TODO: impelment just as in hardware
        raise NotImplementedError
