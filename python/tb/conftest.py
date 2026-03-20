# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import pytest
from mini_isp.config import ParamSet


@pytest.fixture
def paramset(request):
    speed = ParamSet.DEFAULT
    if request.config.getoption("--speed"):
        try:
            speed = ParamSet(request.config.getoption("--speed"))
        except ValueError:
            # TODO: error handling.
            # Using Default for now.
            pass
    return speed
