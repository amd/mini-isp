# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

"""
Percentile. Controls for a set of percentiles over a video stream.
"""

import numpy as np


class Percentile:
    """
    ColorGain applies multiplicative factors to a CFA array.
    """

    def __init__(
        self,
        total_count: np.uint32 = np.uint32(1920 * 1080),
        min_percentile: np.float32 = np.float32(1.0),
        max_percentile: np.float32 = np.float32(99.0),
        median_percentile: np.float32 = np.float32(50.0),
    ):
        super().__init__()
        self.total_count = total_count
        self.min_percentile = min_percentile
        self.max_percentile = max_percentile
        self.median_percentile = median_percentile
        self.min_count = np.uint32(total_count * (min_percentile / 100))
        self.max_count = np.uint32(total_count * (max_percentile / 100))
        self.median_count = np.uint32(total_count * (median_percentile / 100))
        self.min_set_value = 0
        self.max_set_value = 0
        self.median_set_value = 0

        self.min_Kp = 128
        self.min_Ki = 16
        self.min_Kd = 0

        self.max_Kp = 128
        self.max_Ki = 16
        self.max_Kd = 0

        self.median_Kp = 16
        self.median_Ki = 16
        self.median_Kd = 0

        self.min_previous_error = 0
        self.min_integral = 0
        self.max_previous_error = 0
        self.max_integral = 0
        self.median_previous_error = 0
        self.median_integral = 0
        self.dt = 1 / 32

    def reference(self, array: np.ndarray):
        """
        Implments the percentile reference implementation.
        Uses Numpy for exaxt values.
        """

        return (
            np.percentile(array, self.min_percentile),
            np.percentile(array, self.max_percentile),
            np.percentile(array, self.median_percentile),
        )

    def hardware(self, cfa: np.ndarray):
        """
        Implements control loop to determine percentiles
        """
        # get control value
        act_min = (cfa < self.min_set_value).sum()
        act_max = (cfa < self.max_set_value).sum()
        act_median = (cfa < self.median_set_value).sum()

        err_min = self.min_count - act_min
        err_max = self.max_count - act_max
        err_median = self.median_count - act_median

        prop_min = err_min
        prop_max = err_max
        prop_median = err_median

        self.min_integral = self.min_integral + err_min * self.dt
        self.max_integral = self.max_integral + err_max * self.dt
        self.median_integral = self.median_integral + err_median * self.dt

        deriv_min = (err_min - self.min_previous_error) / self.dt
        deriv_max = (err_max - self.max_previous_error) / self.dt
        deriv_median = (err_median - self.median_previous_error) / self.dt

        self.min_set_value += (
            self.min_Kp * prop_min
            + self.min_Ki * self.min_integral
            + self.min_Kd * deriv_min
        )
        self.max_set_value += (
            self.max_Kp * prop_max
            + self.max_Ki * self.max_integral
            + self.max_Kd * deriv_max
        )
        self.median_set_value += (
            self.median_Kp * prop_median
            + self.median_Ki * self.median_integral
            + self.median_Kd * deriv_median
        )

        if self.min_set_value > np.max(cfa) or self.min_set_value < np.min(cfa):
            self.min_set_value = np.min(cfa)

        if self.max_set_value > np.max(cfa) or self.max_set_value < np.min(cfa):
            self.max_set_value = np.max(cfa)

        if self.median_set_value > np.max(cfa) or self.median_set_value < np.min(cfa):
            self.median_set_value = (np.max(cfa) + np.min(cfa)) / 2

        self.min_previous_error = err_min
        self.max_previous_error = err_max
        self.median_previous_error = err_median

        return self.min_set_value, self.max_set_value, self.median_set_value
        # return cfa.min(), cfa.max(), np.mean(cfa)
