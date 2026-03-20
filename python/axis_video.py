# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import math

import numpy as np


def pack_buffer(
    line: np.ndarray,
    pixel_per_cycle: int,
    pixel_bit_width: int,
    color_channels: int = 1,
):
    w = line.shape[0]
    interface_width = math.floor(
        (color_channels * pixel_per_cycle * pixel_bit_width + 7) / 8
    )

    mask = (2**pixel_bit_width) - 1

    result = bytearray()
    for x in range(0, w, pixel_per_cycle * color_channels):
        res: int = 0
        for p in range(0, pixel_per_cycle):
            for c in range(0, color_channels):
                # TODO: maybe saturate input to bit width?
                res |= (int(line[x + p * color_channels + c]) & mask) << (
                    (p * color_channels + c) * pixel_bit_width
                )
        result.extend(res.to_bytes(interface_width, byteorder="little"))

    return bytes(result)


def unpack_buffer(
    line: bytes, pixel_per_cycle: int, pixel_bit_width: int, color_channels: int = 1
):
    w = len(line)
    interface_width = math.floor(
        (color_channels * pixel_per_cycle * pixel_bit_width + 7) / 8
    )
    num_pixel = int((w / interface_width) * pixel_per_cycle * color_channels)

    mask = (2**pixel_bit_width) - 1

    result = np.zeros(num_pixel)
    px = 0
    for x in range(0, w, interface_width):
        transaction = int.from_bytes(line[x : x + interface_width], byteorder="little")
        for p in range(0, pixel_per_cycle):
            for c in range(0, color_channels):
                # TODO: maybe saturate input to bit width?
                result[px] = transaction & mask
                transaction = transaction >> pixel_bit_width
                px += 1

    return result
