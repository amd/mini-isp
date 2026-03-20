# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import numpy as np
import sympy as sym
from colour.models import RGB_Colourspace
from colour.plotting import plot_RGB_colourspaces_in_chromaticity_diagram_CIE1931

xr, yr = sym.symbols("xr, yr")
xg, yg = sym.symbols("xg, yg")
xb, yb = sym.symbols("xb, yb")

XW, YW, ZW = sym.symbols("XW, YW, ZW")

Xr = xr / yr
Yr = 1
Zr = (1 - xr - yr) / yr

Xg = xg / yg
Yg = 1
Zg = (1 - xg - yg) / yg

Xb = xb / yb
Yb = 1
Zb = (1 - xb - yb) / yb

W = sym.Matrix([XW, YW, ZW])

XYZ = sym.Matrix([[Xr, Xg, Xb], [Yr, Yg, Yb], [Zr, Zg, Zb]])

S = XYZ.inv() * W

print(S)
M = XYZ
M.col_op(0, lambda x, j: x * S[0])
M.col_op(1, lambda x, j: x * S[1])
M.col_op(2, lambda x, j: x * S[2])

print(M)

# sRGB
print(
    M.evalf(
        subs={
            xr: 0.64,
            yr: 0.33,
            xg: 0.3,
            yg: 0.6,
            xb: 0.15,
            yb: 0.06,
            XW: 0.9504,
            YW: 1,
            ZW: 1.0888,
        }
    )
)


# My RGB
# Good one:
# red_x = sym.Rational(1, 2) + sym.Rational(1, 8)     # 0.5 + 0.125 = 0.625
# red_y = sym.Rational(1, 4) + sym.Rational(1, 16)    # 0.25 + 0.0625 = 0.3125
# green_x = sym.Rational(1, 4)                        # 0.25
# green_y = sym.Rational(1, 2) + sym.Rational(1, 8)   # 0.5 + 0.125 = 0.625
# blue_x = sym.Rational(1, 8)                         # 0.125
# blue_y = sym.Rational(1, 16)                        # 0.0625

red_x = sym.Rational(1, 2) + sym.Rational(1, 8)  # 0.5 + 0.125 = 0.625
# red_x = sym.Rational(82, 128)
red_y = sym.Rational(1, 4) + sym.Rational(1, 16)  # 0.25 + 0.0625 = 0.3125
# red_y = sym.Rational(42, 128)

green_x = sym.Rational(1, 4)  # 0.25
# green_x = sym.Rational(42, 128)
green_y = sym.Rational(1, 2) + sym.Rational(1, 8)  # 0.5 + 0.125 = 0.625
# green_y = sym.Rational(82, 128)

blue_x = sym.Rational(1, 8)  # 0.125
# blue_x = sym.Rational(20, 128)
blue_y = sym.Rational(1, 16)  # 0.0625
# blue_y = sym.Rational(8, 128)

white_x = sym.Rational(8, 8)
white_y = sym.Rational(8, 8)
white_z = sym.Rational(8, 8)

my_rgb = sym.simplify(
    M.subs(
        {
            xr: red_x,
            yr: red_y,
            xg: green_x,
            yg: green_y,
            xb: blue_x,
            yb: blue_y,
            XW: white_x,
            YW: white_y,
            ZW: white_z,
        }
    )
)
print(my_rgb.evalf())
print(my_rgb.inv().evalf())
print(my_rgb)
print(my_rgb.inv())
# print(M.evalf(subs={xr:red_x, yr:red_y, xg:green_x, yg:green_y, xb:blue_x, yb:blue_y, XW:1, YW:1, ZW:1}))

p = np.array([0.625, 0.3125, 0.25, 0.625, 0.125, 0.0625])
whitepoint = np.array([0.33333, 0.33333])
matrix_RGB_to_XYZ = np.identity(3)
matrix_XYZ_to_RGB = np.identity(3)
colourspace = RGB_Colourspace(
    "Simple RGB",
    p,
    whitepoint,
    "ACES",
    matrix_RGB_to_XYZ,
    matrix_XYZ_to_RGB,
)

print(colourspace.matrix_RGB_to_XYZ)
print(colourspace.matrix_XYZ_to_RGB)

colourspace.use_derived_transformation_matrices(True)

print(colourspace.matrix_RGB_to_XYZ)
print(colourspace.matrix_XYZ_to_RGB)

plot_RGB_colourspaces_in_chromaticity_diagram_CIE1931(
    ["Beta RGB", "sRGB", "S-Gamut", colourspace]
)
