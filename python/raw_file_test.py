# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import os
import sys

import cv2 as cv2
import numpy as np

from .mini_isp.decompand import Decompand
from .mini_isp.demosaic import Demosaic
from .mini_isp.gamma import Gamma
from .mini_isp.tonemap import GtoKimKautz
from .mini_isp.utils import read_raw

np.set_printoptions(threshold=sys.maxsize, linewidth=100000)


def convert_raw(filename, width, height, dtype=np.uint32):
    raw = read_raw(filename, width, height, dtype)
    cv2.imwrite(os.path.basename(filename) + "_raw.png", raw.astype(np.uint16))

    # 16 bit to 24 bit decompanding?
    isp_decomp = Decompand(
        [
            0,
            0x0200,
            0x0400,
            0x0800,
            0x1000,
            0x2000,
            0x4000,
            0x8000,
            0x8200,
            0x8600,
            0x8E00,
            0x9E00,
            0xBE00,
            0xC200,
            0xCA00,
            0xDA00,
            0xFA00,
        ],
        [
            0,
            2**9,
            2**10,
            2**11,
            2**12,
            2**13,
            2**14,
            2**15,
            2**16,
            2**17,
            2**18,
            2**19,
            2**20,
            2**21,
            2**22,
            2**23,
            2**24,
        ],
    )
    # 12 bit to 24 bit decompanding?
    # isp_decomp = Decompand([0, 0x2000, 0x4000, 0x6000, 0x7000, 0x8000, 0x9000, 0x9800, 0xA000, 0xB000, 0xB800, 0xC000, 0xC800, 0xD000, 0xE000, 0xE800, 0xF000], [0, 2**9, 2**10, 2**11, 2**12, 2**13, 2**14, 2**15, 2**16, 2**17, 2**18, 2**19, 2**20, 2**21, 2**22, 2**23, 2**24])
    dec_raw = isp_decomp.reference(raw)
    # dec_raw = raw
    cv2.imwrite(os.path.basename(filename) + "_dec.png", (dec_raw).astype(np.uint16))

    isp_demosaic = Demosaic()
    rgb = isp_demosaic.reference(dec_raw)
    rgb[rgb < 1] = 1
    rgb[rgb > 2**24 - 1] = 2**24 - 1
    cv2.imwrite(os.path.basename(filename) + "_rgb.png", (rgb).astype(np.uint16))

    isp_tonemap = GtoKimKautz(c1=3.0, c2=0.5)
    rgb_tm = isp_tonemap.hardware(rgb)
    cv2.imwrite(os.path.basename(filename) + "_tm.png", rgb_tm.astype(np.uint8))


def convert_raw_cfa(filename, width, height, dtype=np.uint32):
    raw = read_raw(filename, width, height, dtype)
    cv2.imwrite(os.path.basename(filename) + "_raw.png", raw.astype(np.uint16))

    # 16 bit to 24 bit decompanding?
    isp_decomp = Decompand(
        [
            0,
            0x0200,
            0x0400,
            0x0800,
            0x1000,
            0x2000,
            0x4000,
            0x8000,
            0x8200,
            0x8600,
            0x8E00,
            0x9E00,
            0xBE00,
            0xC200,
            0xCA00,
            0xDA00,
            0xFA00,
        ],
        [
            0,
            2**9,
            2**10,
            2**11,
            2**12,
            2**13,
            2**14,
            2**15,
            2**16,
            2**17,
            2**18,
            2**19,
            2**20,
            2**21,
            2**22,
            2**23,
            2**24,
        ],
    )
    # 12 bit to 24 bit decompanding?
    # isp_decomp = Decompand([0, 0x2000, 0x4000, 0x6000, 0x7000, 0x8000, 0x9000, 0x9800, 0xA000, 0xB000, 0xB800, 0xC000, 0xC800, 0xD000, 0xE000, 0xE800, 0xF000], [0, 2**9, 2**10, 2**11, 2**12, 2**13, 2**14, 2**15, 2**16, 2**17, 2**18, 2**19, 2**20, 2**21, 2**22, 2**23, 2**24])
    dec_raw = isp_decomp.reference(raw)
    # dec_raw = raw
    cv2.imwrite(os.path.basename(filename) + "_dec.png", (dec_raw).astype(np.uint16))

    isp_tonemap = GtoKimKautz(c1=3, c2=0.5)
    cfa_tm = isp_tonemap.hardware_cfa(dec_raw)
    cv2.imwrite(os.path.basename(filename) + "_tm_cfa.png", cfa_tm.astype(np.uint16))

    isp_demosaic = Demosaic()
    rgb = isp_demosaic.reference(cfa_tm)
    cv2.imwrite(os.path.basename(filename) + "_rgb.png", (rgb).astype(np.uint16))

    # Contrast stretch
    final_min = np.quantile(rgb, 0.01)  # once per pixel
    final_max = np.quantile(rgb, 0.99)  # once per pixel
    rgb[rgb < final_min] = final_min  # once per pixel
    rgb[rgb > final_max] = final_max  # once per pixel
    print("  final_max  :", final_max)
    print("  final_min  :", final_min)
    rgb = (rgb - final_min) / (final_max - final_min)  # once per pixel

    print(" max(rgb_kimkautz): ", np.max(rgb))
    print(" min(rgb_kimkautz): ", np.min(rgb))

    cv2.imwrite(os.path.basename(filename) + "_cfa_rgb.png", (rgb).astype(np.uint8))


def motion_video(
    filename, width, height, dtype=np.uint32, target_width=640, target_height=480
):
    raw = read_raw(filename, width, height, dtype)
    isp_decomp = Decompand(
        [
            0,
            0x0200,
            0x0400,
            0x0800,
            0x1000,
            0x2000,
            0x4000,
            0x8000,
            0x8200,
            0x8600,
            0x8E00,
            0x9E00,
            0xBE00,
            0xC200,
            0xCA00,
            0xDA00,
            0xFA00,
        ],
        [
            0,
            2**9,
            2**10,
            2**11,
            2**12,
            2**13,
            2**14,
            2**15,
            2**16,
            2**17,
            2**18,
            2**19,
            2**20,
            2**21,
            2**22,
            2**23,
            2**24,
        ],
    )
    dec_raw = isp_decomp.reference(raw)

    img_cnt = 0
    x_pos = 0
    y_pos = 826
    for x_pos in range(0, width - target_width, 2):
        cropped = dec_raw[y_pos : y_pos + target_height, x_pos : x_pos + target_width]
        isp_tonemap = GtoKimKautz(c1=3, c2=0.5)
        cfa_tm = isp_tonemap.hardware_cfa(cropped)
        # cv2.imwrite(os.path.basename(filename) + '_tm_cfa.png', cfa_tm.astype(np.uint16))

        isp_demosaic = Demosaic()
        rgb = isp_demosaic.reference(cfa_tm)
        # cv2.imwrite(os.path.basename(filename) + '_rgb.png', (rgb).astype(np.uint16))

        # Contrast stretch
        final_min = np.quantile(rgb, 0.01)  # once per pixel
        final_max = np.quantile(rgb, 0.99)  # once per pixel
        rgb[rgb < final_min] = final_min  # once per pixel
        rgb[rgb > final_max] = final_max  # once per pixel
        print("  final_max  :", final_max)
        print("  final_min  :", final_min)

        rgb = ((rgb - final_min) / (final_max - final_min)) * 2048  # once per pixel

        print(" max(rgb_kimkautz): ", np.max(rgb))
        print(" min(rgb_kimkautz): ", np.min(rgb))

        # Gamma correction
        srgb = Gamma()
        rgb = srgb.reference(rgb)

        cv2.imwrite(
            os.path.basename(filename) + "_vid_" + str(img_cnt) + ".png",
            (rgb).astype(np.uint8),
        )
        img_cnt += 1


if __name__ == "__main__":
    # convert_raw('../dataset/ar0820_16bit_companding_color_processing_on.raw', 3848, 2168)
    # convert_raw('../dataset/ar0820_16bit_companding0000.raw', 3848, 2168, np.uint16)
    # convert_raw_cfa('../dataset/ar0820_16bit_companding0000.raw', 3848, 2168, np.uint16)
    motion_video("../dataset/ar0820_16bit_companding0000.raw", 3848, 2168, np.uint16)
