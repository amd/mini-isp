# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import numpy as np

from .csc import Rgb2Xyz, Xyz2Rgb


class GtoKimKautz:
    """
    GtoKimKautz tonemaps the input RGB image into a tonemapped RGB image
    """

    def __init__(self, c1: float = 3.0, c2: float = 0.5):
        super().__init__()
        self.c1 = c1
        self.c2 = c2

    def reference(self, rgb: np.ndarray) -> np.ndarray:
        """
        Tonemaps the input RGB image into a tonemapped RGB image
        """
        # convert to unsigned integer first
        dynamic_range = np.log2(np.max(rgb)) - np.log2(np.min(rgb))
        print("dynamic_range: ", dynamic_range)
        # RGB to XYZ
        IspRgb2Xyz = Rgb2Xyz()
        xyz = IspRgb2Xyz.reference(rgb)  # once per pixel

        # Log image
        L0 = xyz[:, :, 1]
        logimg = np.log2(L0)  # once per pixel (current + previous frame)
        logmean = np.mean(
            logimg
        )  # once per pixel (previous frame) (add per pixel / divide per frame)
        logmax = np.max(logimg)  # once per pixel (previous frame)
        logmin = np.min(logimg)  # once per pixel (previous frame)

        # Tonemapping
        d0 = logmax - logmin  # once per frame
        sigma = d0 / self.c1  # once per frame / mul / LUT
        w = 2 ** (
            -0.5 * np.square(logimg - logmean) / np.square(sigma)
        )  # once per pixel / LUT?

        maxLd = np.log2(256)  # constant
        minLd = np.log2(1)  # constant
        k1 = (maxLd - minLd) / (logmax - logmin)  # once per frame

        k2 = (1 - k1) * w + k1  # once per pixel

        # L1 = np.exp(c2 * k2 * (logimg - logmean) + logmean)            # once per pixel
        L1 = 2 ** (self.c2 * k2 * (logimg - logmean) + logmean)  # once per pixel
        # L1 = 2 ** (k1 * logimg)

        print("  max img    :", np.max(L0))
        print("  min img    :", np.min(L0))
        print("  d0         :", d0)
        print("  logmax     :", logmax)
        print("  logmin     :", logmin)
        print("  logmean    :", logmean)
        print("  k1         :", k1)
        print("  np.max(k2) :", np.max(k2))
        print("  np.min(k2) :", np.min(k2))
        print("  np.max(w)  :", np.max(w))
        print("  np.min(w)  :", np.min(w))
        print("  c1         :", self.c1)
        print("  c2         :", self.c2)
        print("  np.max(L1) :", np.max(L1))
        print("  np.min(L1) :", np.min(L1))

        # Scaling the color components
        out_kimkautz = np.zeros(xyz.shape)
        mult_kimkautz = L1 / L0  # once per pixel / divide
        print("  mult_max   :", np.max(mult_kimkautz))
        print("  mult_min   :", np.min(mult_kimkautz))

        out_kimkautz[:, :, 0] = mult_kimkautz * xyz[:, :, 0]  # once per pixel
        out_kimkautz[:, :, 1] = L1  # nop
        out_kimkautz[:, :, 2] = mult_kimkautz * xyz[:, :, 2]  # once per pixel

        print("  np.max(L1) :", np.max(L1))
        print("  np.min(L1) :", np.min(L1))

        print(" max(out_kimkautz): ", np.max(out_kimkautz))
        print(" min(out_kimkautz): ", np.min(out_kimkautz))

        # XYZ to RGB
        IspXyz2Rgb = Xyz2Rgb()
        rgb_kimkautz = IspXyz2Rgb.reference(rgb)  # once per pixel

        # Gamma correction
        rgb_kimkautz[rgb_kimkautz < 0] = 0
        rgb_kimkautz = rgb_kimkautz ** (0.45)  # once per pixel

        # Contrast stretch
        final_min = np.quantile(rgb_kimkautz, 0.01)  # once per pixel
        final_max = np.quantile(rgb_kimkautz, 0.99)  # once per pixel
        rgb_kimkautz[rgb_kimkautz < final_min] = final_min  # once per pixel
        rgb_kimkautz[rgb_kimkautz > final_max] = final_max  # once per pixel
        print("  final_max  :", final_max)
        print("  final_min  :", final_min)
        rgb_kimkautz = (
            (rgb_kimkautz - final_min) / (final_max - final_min)
        ) * 255  # once per pixel

        print(" max(rgb_kimkautz): ", np.max(rgb_kimkautz))
        print(" min(rgb_kimkautz): ", np.min(rgb_kimkautz))

        return rgb_kimkautz

    def hardware(self, rgb: np.ndarray) -> np.ndarray:
        """
        Tonemaps the input RGB image into a tonemapped RGB image just as in hardware
        """
        # RGB to XYZ
        IspRgb2Xyz = Rgb2Xyz()
        xyz = IspRgb2Xyz.reference(rgb)  # once per pixel

        # Log image
        L0 = xyz[:, :, 1].astype(np.uint32)
        # logimg = bitlog2(L0) / 2**24                                           # once per pixel (current + previous frame)
        logimg = np.log2(L0)
        logmean = np.mean(
            logimg
        )  # once per pixel (previous frame) (add per pixel / divide per frame)
        logmax = np.max(logimg)  # once per pixel (previous frame)
        # logmin = np.min(logimg)                                         # once per pixel (previous frame)
        logmin = 0

        # Tonemapping
        d0 = logmax - logmin  # once per frame
        # d0 = 12
        one_over_c1 = 1 / self.c1  # once per frame
        sigma = d0 * one_over_c1  # once per frame / mul
        one_over_sigma_square = 1 / np.square(sigma)  # once per frame

        inner1 = (
            -0.5 * np.square(logimg - logmean) * one_over_sigma_square
        )  # once per pixel
        w = 2 ** (inner1)  # once per pixel / LUT?

        maxLd = np.log2(256)  # constant
        minLd = np.log2(1)  # constant
        k1 = (maxLd - minLd) / d0  # once per frame

        k2 = (1 - k1) * w + k1  # once per pixel

        # L1 = np.exp(c2 * k2 * (logimg - logmean) + logmean)            # once per pixel
        L1 = 2 ** (self.c2 * k2 * (logimg - logmean) + logmean)  # once per pixel
        # L1 = 2 ** (k1 * logimg)

        print("  max img    :", np.max(L0))
        print("  min img    :", np.min(L0))
        print("  d0         :", d0)
        print("  1/sigsq    :", one_over_sigma_square)
        print("  logmax     :", logmax)
        print("  logmin     :", logmin)
        print("  logmean    :", logmean)
        print("  k1         :", k1)
        print("  np.max(k2) :", np.max(k2))
        print("  np.min(k2) :", np.min(k2))
        print("  np.max(w)  :", np.max(w))
        print("  np.min(w)  :", np.min(w))
        print("  c1         :", self.c1)
        print("  c2         :", self.c2)
        print("  np.max(L1) :", np.max(L1))
        print("  np.min(L1) :", np.min(L1))

        # Scaling the color components
        out_kimkautz = np.zeros(xyz.shape)
        mult_kimkautz = L1 / L0  # once per pixel / divide
        print("  mult_max   :", np.max(mult_kimkautz))
        print("  mult_min   :", np.min(mult_kimkautz))

        out_kimkautz[:, :, 0] = mult_kimkautz * xyz[:, :, 0]  # once per pixel
        out_kimkautz[:, :, 1] = L1  # nop
        out_kimkautz[:, :, 2] = mult_kimkautz * xyz[:, :, 2]  # once per pixel

        print("  np.max(L1) :", np.max(L1))
        print("  np.min(L1) :", np.min(L1))

        print(" max(out_kimkautz): ", np.max(out_kimkautz))
        print(" min(out_kimkautz): ", np.min(out_kimkautz))

        # XYZ to RGB
        IspXyz2Rgb = Xyz2Rgb()
        rgb_kimkautz = IspXyz2Rgb.reference(out_kimkautz)  # once per pixel

        # Gamma correction
        rgb_kimkautz[rgb_kimkautz < 0] = 0
        rgb_kimkautz = rgb_kimkautz ** (0.45)  # once per pixel

        # Contrast stretch
        final_min = np.quantile(rgb_kimkautz, 0.01)  # once per pixel
        final_max = np.quantile(rgb_kimkautz, 0.99)  # once per pixel
        rgb_kimkautz[rgb_kimkautz < final_min] = final_min  # once per pixel
        rgb_kimkautz[rgb_kimkautz > final_max] = final_max  # once per pixel
        print("  final_max  :", final_max)
        print("  final_min  :", final_min)
        rgb_kimkautz = (
            (rgb_kimkautz - final_min) / (final_max - final_min)
        ) * 255  # once per pixel

        print(" max(rgb_kimkautz): ", np.max(rgb_kimkautz))
        print(" min(rgb_kimkautz): ", np.min(rgb_kimkautz))

        return rgb_kimkautz

    def hardware_cfa(self, cfa: np.ndarray) -> np.ndarray:
        """
        Tonemaps the input CFA image into a tonemapped CFA image just as in hardware
        """
        # Log image
        L0 = cfa.astype(np.uint32)
        # logimg = bitlog2(L0) / 2**24                                           # once per pixel (current + previous frame)
        logimg = np.log2(L0)
        # logmean = np.mean(logimg)                                      # once per pixel (previous frame) (add per pixel / divide per frame)
        logmean = np.median(
            logimg
        )  # once per pixel (previous frame) (add per pixel / divide per frame)
        logmax = np.max(logimg)  # once per pixel (previous frame)
        logmin = np.min(logimg)  # once per pixel (previous frame)

        # Tonemapping
        d0 = logmax - logmin  # once per frame
        # d0 = 12
        one_over_c1 = 1 / self.c1  # constant
        sigma = d0 * one_over_c1  # d0 LUT
        one_over_sigma_square = 1 / np.square(sigma)  # d0 LUT

        inner1 = (
            -0.5 * np.square(logimg - logmean) * one_over_sigma_square
        )  # once per pixel
        w = 2 ** (inner1)  # once per pixel / 10-bit direct LUT

        maxLd = np.log2(256)  # constant
        minLd = np.log2(1)  # constant
        k1 = (maxLd - minLd) / d0  # d0 LUT

        k2 = (1 - k1) * w + k1  # once per pixel

        # L1 = np.exp(c2 * k2 * (logimg - logmean) + logmean)            # once per pixel
        L1 = 2 ** (self.c2 * k2 * (logimg - logmean) + logmean)  # once per pixel
        # L1 = 2 ** (k1 * logimg)

        print("  max img    :", np.max(L0))
        print("  min img    :", np.min(L0))
        print("  d0         :", d0)
        print("  1/sigsq    :", one_over_sigma_square)
        print("  logmax     :", logmax)
        print("  logmin     :", logmin)
        print("  logmean    :", logmean)
        print("  k1         :", k1)
        print("  np.max(k2) :", np.max(k2))
        print("  np.min(k2) :", np.min(k2))
        print("  np.max(w)  :", np.max(w))
        print("  np.min(w)  :", np.min(w))
        print("  c1         :", self.c1)
        print("  c2         :", self.c2)
        print("  np.max(L1) :", np.max(L1))
        print("  np.min(L1) :", np.min(L1))

        return L1
