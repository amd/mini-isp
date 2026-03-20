# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import math


def find_coefficient(c: float, num_adds: int = 2, bits: int = 16):
    fixed = math.floor(c * 2**bits)

    return fixed / (2**bits)


coeff = [
    0.4887180,
    0.3106803,
    0.2006017,
    0.1762044,
    0.8129847,
    0.0108109,
    0.0000000,
    0.0102048,
    0.9897952,
]

bits = 16
num_adds = 4

base_numbers = []

for i in range(0, bits + 6):
    base_numbers.append(2**i)

numbers = [0]
for adds in range(0, num_adds):
    temp = []
    for num in numbers:
        for i in base_numbers:
            temp.append(i + num)
            temp.append(i - num)
    numbers = numbers + temp
    numbers = list(dict.fromkeys(numbers))

numbers = sorted(numbers)
# print(numbers)
print(len(numbers))

for c in coeff:
    # approx = find_coefficient(c)
    c_fix = math.floor(c * 2**bits)
    c_approx = min(numbers, key=lambda x: abs(x - c_fix))
    approx = c_approx / (2**bits)
    print(
        f"{c:6e} {approx:6e} {c - approx:6e} {c_fix:6d} {c_approx:6d} {c_fix - c_approx:6d}"
    )
