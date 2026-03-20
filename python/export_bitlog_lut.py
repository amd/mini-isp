# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

from matplotlib import pyplot as plt

from .mini_isp.utils import bitlog2_lut, export_bitlog2_lut

export_bitlog2_lut(bitlog2_lut, "bitlog.mem")

plt.plot(bitlog2_lut)
plt.show()
