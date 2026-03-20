# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import numpy as np


def read_raw(filename: str, width, height, dtype=np.uint32) -> np.ndarray:
    """
    Read a raw file into a numpy array
    """
    with open(filename, "rb") as f:
        a = np.fromfile(f, dtype=dtype)
        return a.reshape((height, width))


# generate bitlog2 LUT
def generate_bitlog2_lut(logsize: int = 10, dtype=np.uint32) -> np.ndarray:
    """
    Generate a bitlog2 LUT
    """
    size = 2**logsize
    lut = np.zeros(size, dtype=dtype)
    y = np.linspace(1.0, 2.0, size, endpoint=False)
    for i in range(len(y)):
        lut[i] = (np.log2(y[i]).astype(np.float64) * (np.iinfo(dtype).max + 1)).astype(
            dtype
        )
    return lut


# generate bitsqrt LUT
def generate_bitsqrt_lut(logsize: int = 10, dtype=np.uint32) -> np.ndarray:
    """
    Generate a bitsqrt LUT
    """
    size = 2**logsize
    y = np.linspace(0.0, 1.0, size, endpoint=False)
    return (np.sqrt(y).astype(np.float64) * (np.iinfo(dtype).max + 1)).astype(dtype)


bitlog2_lut = generate_bitlog2_lut()
bitsqrt_lut = generate_bitsqrt_lut()


def export_lut(lut: np.ndarray, filename: str):
    """
    Export the bitlog LUT to VErilog mem file
    """
    with open(filename, "w", encoding="utf-8") as f:
        for val in lut:
            f.write(int(val).to_bytes(4, byteorder="big").hex() + "\n")


# leading zero count
def lzc(
    el: np.uint32, num_bits: np.uint32 = np.uint32(32), shift: np.uint32 = np.uint32(21)
) -> tuple[np.uint32, np.uint32]:
    """
    leading zero count - counts the number of leading zeros in a 32-bit integer
    returns the leading zero count and the first 31-shift bit (for LUT look-up)
    without the first leading one
    """
    # TODO: look into https://numpy.org/doc/stable/reference/generated/numpy.frexp.html
    # leading zero count
    assert num_bits <= 32
    assert num_bits >= 1
    assert shift < num_bits
    mask: np.uint32 = np.uint32(1 << (num_bits - 1))
    bitmask: np.uint32 = np.uint32((2 ** (num_bits - shift - 1)) - 1)
    for cnt in reversed(range(num_bits)):
        if el & mask:
            return np.uint32(cnt), np.uint32((el >> shift) & bitmask)
        el = el << np.uint32(1)

    return np.uint32(0), np.uint32(0)


# leading double zero count
def ldzc(el: np.uint32) -> tuple[np.uint32, np.uint32]:
    """
    leading double zero count - counts the number of leading double zeros in a 32-bit integer
    returns the shifted value and the remaining number
    """
    mask: np.uint32 = np.uint32(0xFFFFFC00)
    shift: np.uint32 = np.uint32(0)
    while el & mask:
        el = el >> np.uint32(2)
        shift = shift + np.uint32(1)

    return shift, el


def bitlog2(array: np.ndarray) -> np.ndarray:
    """
    Compute the base 2 logarithm of an array just as in hardware
    Results are 8.24 fixed point
    """
    assert array.dtype == np.uint32
    result = array.copy()
    flat = result.ravel()

    for i in range(flat.size):
        cnt, remain = lzc(flat[i])
        flat[i] = (cnt << 24) | (bitlog2_lut[remain] >> 8)

    return result


def bitlog2_nolut(array: np.ndarray) -> np.ndarray:
    """
    Compute the base 2 logarithm of an array just as in hardware
    Results are 8.24 fixed point
    """
    assert array.dtype == np.uint32
    result = array.copy()
    flat = result.ravel()

    for i in range(flat.size):
        cnt, mask = lzc(flat[i])
        exp = 31 - int(min(cnt, np.uint32(31)))
        shift = 24 - exp
        if shift > 0:
            remain = (flat[i] & ~mask) << shift
        else:
            remain = (flat[i] & ~mask) >> -shift

        flat[i] = (exp << 24) | remain

    return result


def bitsqrt(array: np.ndarray) -> np.ndarray:
    """
    Compute the square root of an array just as in hardware.
    Results are 16.16 fixed point
    """
    assert array.dtype == np.uint32
    result = array.copy()
    flat = result.ravel()

    for i in range(flat.size):
        shift, remain = ldzc(flat[i])
        back = (27 - 16) - shift
        if back > 0:
            flat[i] = bitsqrt_lut[remain] >> back
        else:
            flat[i] = bitsqrt_lut[remain] << -back

    return result
