# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT


def pytest_addoption(parser):
    parser.addoption(
        "--speed",
        action="store",
        default="default",
        help="speed: default, simfast, full, minimal",
        choices=("default", "simfast", "full", "minimal"),
    )
