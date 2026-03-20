# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

"""
Provides virtual scenes for testing the mini-isp.
"""

from raysect.optical import ConstantSF, Point3D, World, d65_white, rotate, translate
from raysect.optical.library import Aluminium, Copper, Gold, Silver, Titanium
from raysect.optical.material import Lambert, UniformSurfaceEmitter
from raysect.primitive import Box, Cylinder, Sphere


def default_scene() -> World:
    world = World()

    Sphere(0.5, world, transform=translate(1.2, 0.5001, 0.6), material=Gold())
    Sphere(0.5, world, transform=translate(0.6, 0.5001, -0.6), material=Silver())
    Sphere(0.5, world, transform=translate(0, 0.5001, 0.6), material=Copper())
    Sphere(0.5, world, transform=translate(-0.6, 0.5001, -0.6), material=Titanium())
    Sphere(0.5, world, transform=translate(-1.2, 0.5001, 0.6), material=Aluminium())

    Box(
        Point3D(-100, -0.1, -100),
        Point3D(100, 0, 100),
        world,
        material=Lambert(ConstantSF(1.0)),
    )
    Cylinder(
        3.0,
        8.0,
        world,
        transform=translate(4, 8, 0) * rotate(90, 0, 0),
        material=UniformSurfaceEmitter(d65_white, 1.0),
    )

    return world
