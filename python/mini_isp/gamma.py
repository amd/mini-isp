# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

# See https://mimosa-pudica.net/fast-gamma/

# SPDX-License-Identifier: MIT

"""
Gamma encoding. All Modules related to gamma encoding / sRGB.
"""

import numpy as np
from scipy.optimize import leastsq

from .utils import lzc


class Gamma:
    """
    Gamma encodes the input
    """

    def __init__(self, bitwidth: int = 24):
        super().__init__()
        # sRGB standard values
        self.V = 0.0031308
        self.A = 12.92
        self.C = 0.055
        self.gamma = 2.4
        self.bitwidth = bitwidth
        self.lutfp, self.lutp = self.generate_lut(bitwidth)

    def residuals(self, p, fp, y, x):
        return y - np.interp(x, fp, p)

    def generate_lut(self, bitwidth):
        # fill initial LUT values with reference calculation
        fp = np.zeros([bitwidth + 2])
        fp[0] = 0
        for i in range(bitwidth + 1):
            fp[i + 1] = (2**i) / (2**bitwidth)
        p = self.reference(fp)

        # now we use least square to minimize the error
        array = np.linspace(0.0, 1.0, 10000)
        reference = self.reference(array)
        cnsts = leastsq(self.residuals, p, args=(fp, reference, array))[0]

        return fp, cnsts

    def export_lut(self, filename: str):
        x = (self.lutfp * 2**self.bitwidth).astype(np.uint32)
        y = (self.lutp * 2**self.bitwidth).astype(np.uint32)

        # figure out the best shift we can do to get to a 16 bit value
        y_diff = 2 * (
            (self.lutp[1:] - self.lutp[:-1]) / (self.lutfp[1:] - self.lutfp[:-1])
        )
        shift = int(np.floor(np.log2(2**16 / np.max(y_diff))))
        y_diff = (y_diff * 2**shift).astype(np.uint16)
        print("Shift: ", shift)

        with open(filename + "_offset.mem", "w", encoding="utf-8") as f:
            for i in range(len(x) - 2):
                f.write(int(y[i + 1]).to_bytes(4, byteorder="big").hex() + "\n")

        with open(filename + "_gain.mem", "w", encoding="utf-8") as f:
            for i in range(len(x) - 2):
                f.write(int(y_diff[i + 1]).to_bytes(2, byteorder="big").hex() + "\n")

    def export_full_lut(
        self, filename: str, input_bit_width: int = 12, output_bit_width: int = 8
    ):
        inp = np.linspace(0, 1, 2**input_bit_width, endpoint=False)
        outp = self.reference(inp)

        with open(filename, "w", encoding="utf-8") as f:
            for i in range(len(inp)):
                z = int(outp[i] * 2**output_bit_width)
                f.write(f"{z:02x}" + "\n")

    def reference(self, arr: np.ndarray) -> np.ndarray:
        """
        Gamma encode input
        (uses standard sRGB method)
        """
        srgb = arr.copy()
        mask = srgb <= self.V
        srgb[mask] *= self.A
        srgb[~mask] = (1.0 + self.C) * np.power(srgb[~mask], 1.0 / self.gamma) - self.C

        return srgb

    def hardware(self, arr: np.ndarray) -> np.ndarray:
        """
        Gamma encode with PWL
        (uses standard sRGB method)
        """
        return np.interp(arr, self.lutfp, self.lutp)

    def hardware_pwl(self, arr: np.ndarray) -> np.ndarray:
        """
        Gamma encode with PWL
        (uses standard sRGB method)
        """
        (self.lutfp * 2**self.bitwidth).astype(np.uint32)
        y = (self.lutp * 2**self.bitwidth).astype(np.uint32)

        y_diff = ((self.lutp[1:] - self.lutp[:-1]) * 2**self.bitwidth).astype(np.uint32)

        result = (arr.copy() * 2**self.bitwidth).astype(np.uint32)
        flat = result.ravel()

        for i in range(flat.size):
            cnt, remain = lzc(flat[i], np.uint32(24), np.uint32(0))
            flat[i] = y[cnt + 1] + remain * 2 * (y_diff[cnt + 1] / 2**self.bitwidth)

        return result / 2**self.bitwidth
