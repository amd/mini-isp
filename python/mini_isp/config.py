# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import pathlib
from dataclasses import asdict, dataclass
from enum import Enum

from mini_isp import __version__


def get_version() -> str:
    """
    Get the current version of the mini-isp package.
    """
    return __version__


def get_rtl_path() -> pathlib.Path:
    """
    Get the absolute path to the RTL source code folder.
    """
    return pathlib.Path(pathlib.Path(__file__).parent / ".." / ".." / "rtl").resolve()


def get_build_path() -> pathlib.Path:
    """
    Get the absolute path to the build folder.
    """
    # TODO: add configuration option?
    # Create if it does not exist
    build_path = pathlib.Path("build").resolve()
    build_path.mkdir(parents=True, exist_ok=True)
    return build_path


def get_reports_path() -> pathlib.Path:
    docs_path = (get_build_path() / "docs" / "reports").resolve()
    docs_path.mkdir(parents=True, exist_ok=True)
    return docs_path


class ParamSet(str, Enum):
    FULL = "full"
    SIMFAST = "simfast"
    DEFAULT = "default"
    MINIMAL = "minimal"


@dataclass(frozen=True)
class ParamSets:
    full: list
    simfast: list
    default: list
    minimal: list


@dataclass(frozen=True)
class ParamConfig:
    params: dict[str, ParamSets]


_config_params: ParamConfig = ParamConfig(
    params={
        "CFA_ORIENTATION": ParamSets(
            full=[0, 1, 2, 3],
            simfast=[0],
            default=[0],
            minimal=[0],
        ),
        "MAX_RESOLUTION": ParamSets(
            full=[2048, 4096, 8192],
            simfast=[2048],
            default=[4096],
            minimal=[2048],
        ),
        "PIXEL_BIT_WIDTH": ParamSets(
            full=[10, 12, 14, 16, 18, 20, 22, 24],
            simfast=[16],
            default=[10, 12, 14],
            minimal=[10],
        ),
        "PIXEL_PER_CYCLE": ParamSets(
            full=[1, 2, 4],
            simfast=[4],
            default=[1, 2],
            minimal=[1],
        ),
    }
)


def get_param(
    name: str, param_set: ParamSet = ParamSet.DEFAULT
) -> tuple[str, list[str | int]]:
    """
    Get the parameter configuration for different build types.
    """
    values = _config_params.params.get(name, None)
    if values is None:
        raise ValueError(f"Parameter '{name}' not found in configuration.")

    return tuple([name, asdict(values)[param_set]])
