# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

import re
from itertools import product
from pathlib import Path

import binpacking
from cocotb_tools.runner import Verilator
from pyosys import libyosys as ys

from .config import get_reports_path


class Rtl:
    def __init__(
        self,
        toplevel: str,
        sources: list[Path],
        params: dict[str, list[str | int]] = {},
    ):
        self._toplevel = toplevel
        self._sources = sources
        self._params = params

    def get_sources(self) -> list[Path]:
        return self._sources

    def get_toplevel(self) -> str:
        return self._toplevel

    def get_params(self) -> dict[str, list[str | int]]:
        return self._params

    def get_all_param_combinations(self) -> list[dict[str, str | int]]:
        """
        Get all combinations of parameters
        """
        return [
            dict(zip(self._params.keys(), combination))
            for combination in product(*self._params.values())
        ]

    def check_param_combination(self, params: dict[str, str | int]) -> bool:
        """
        Check if a parameter combination is valid
        """
        for param, value in params.items():
            if param not in self._params:
                return False
            if value not in self._params[param]:
                return False
        return True

    def _estimate_logic_cells(self, cell_stats: dict[str, int]) -> int:
        # create list with LUT weights
        b = [1] * cell_stats.get("LUT1", 0)
        b.extend([2] * cell_stats.get("LUT2", 0))
        b.extend([3] * cell_stats.get("LUT3", 0))
        b.extend([4] * cell_stats.get("LUT4", 0))
        b.extend([5] * cell_stats.get("LUT5", 0))
        b.extend([6] * cell_stats.get("LUT6", 0))

        if len(b) == 0:
            return 0

        # map to logic cells (6-LUTs) and return number of logic cells
        return len(binpacking.to_constant_volume(b, 6))

    def _aggregate_resource_utilization(
        self, cell_stats: dict[str, int]
    ) -> dict[str, int]:
        """
        Aggregate resource utilization statistics from synthesis cell stats
        """
        aggregated_stats: dict[str, int] = {}
        aggregated_stats["LC"] = self._estimate_logic_cells(cell_stats)
        aggregated_stats["LUT"] = sum(
            [val for key, val in cell_stats.items() if re.search("^LUT.*", key)]
        )

        aggregated_stats["FF"] = sum(
            [val for key, val in cell_stats.items() if re.search("^FD.*", key)]
        )
        aggregated_stats["DSP48"] = sum(
            [val for key, val in cell_stats.items() if re.search("^DSP48.*", key)]
        )
        aggregated_stats["RAMB18"] = sum(
            [val for key, val in cell_stats.items() if re.search("^RAMB18.*", key)]
        )
        aggregated_stats["RAMB36"] = sum(
            [val for key, val in cell_stats.items() if re.search("^RAMB36.*", key)]
        )
        aggregated_stats["URAM"] = sum(
            [val for key, val in cell_stats.items() if re.search("^URAM.*", key)]
        )

        return aggregated_stats

    def synthesize(
        self, params: dict[str, str | int] = {}, family: str = "xc7"
    ) -> dict[str, int]:
        """
        Synthesize core using Yosys
        """
        if not self.check_param_combination(params):
            raise ValueError("Invalid parameter combination")

        design = ys.Design()

        # Read RTL sources
        for source in self._sources:
            ys.run_pass(f"read_verilog -defer -sv {source}", design)

        # Set parameters
        cmd_str = "chparam "
        for param, value in params.items():
            if not isinstance(value, int):
                cmd_str += f'-set {param} "{value}" '
            else:
                cmd_str += f"-set {param} {value} "
        cmd_str += f" {self._toplevel} "

        ys.run_pass(cmd_str, design)

        # Run synthesis
        ys.run_pass(
            f"synth_xilinx -family {family} -run :check -top {self._toplevel}", design
        )

        ## Collect statistics
        cell_stats: dict[str, int] = {}
        for module in design.all_selected_whole_modules():
            for cell in module.selected_cells():
                clean = cell.type.str().rpartition("\\")[-1]

                if clean in cell_stats:
                    cell_stats[clean] += 1
                else:
                    cell_stats[clean] = 1

        return self._aggregate_resource_utilization(cell_stats)

    def synthesize_all(self, family: str = "xc7") -> dict[str, dict[str, int]]:
        """
        Synthesize all parameter combinations using Yosys
        """
        all_param_combinations = self.get_all_param_combinations()
        results = {}
        for params in all_param_combinations:
            key = ", ".join(
                [f"{k}={v}" for k, v in params.items() if k.endswith("_FILE") is False]
            )
            results[key] = self.synthesize(params, family)
        return results

    def simulate(
        self, test_module: str, params: dict[str, str | int] = {}, waves: bool = False
    ):
        """
        Simulate core using Verilator
        """
        if not self.check_param_combination(params):
            raise ValueError("Invalid parameter combination")

        runner = Verilator()

        runner.build(
            build_dir="build/sim/"
            + self.get_toplevel()
            + "/"
            + "_".join(
                [f"{k}={v}" for k, v in params.items() if k.endswith("_FILE") is False]
            ),
            sources=self.get_sources(),
            hdl_toplevel=self.get_toplevel(),
            parameters=params,
            always=True,
            clean=True,
            waves=waves,
        )

        runner.test(
            hdl_toplevel=self.get_toplevel(),
            test_module=test_module,
            parameters=params,
            waves=waves,
        )

    def simulate_all(self, test_module: str, waves: bool = False):
        """
        Simulate all parameter combinations using Verilator
        """
        for param in self.get_all_param_combinations():
            self.simulate(test_module, param, waves)

    def export_markdown_report(self, title: str, results: dict[str, dict[str, int]]):
        """
        Export synthesis results to markdown file
        """
        file = get_reports_path() / (self._toplevel + "_synthesis_report.md")
        delim: str = " | "
        with open(file, "w") as f:
            f.write(f"---\nicon: material/table\n---\n\n# {title} Resource Usage\n\n")
            f.write(f"| Params | {delim.join(next(iter(results.values())).keys())} |\n")
            f.write("|---" * (len(next(iter(results.values())).keys()) + 1) + "|\n")
            for param, stats in results.items():
                f.write(f"| {param} | {delim.join(str(v) for v in stats.values())} |\n")
