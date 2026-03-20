# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

"""
Implements a virtual camera using raysect. Useful to generate test data and to compare the results of the mini-isp with a reference implementation.
"""

import cv2
import numpy as np
from raysect.optical import InterpolatedSF, rotate, translate
from raysect.optical.observer import BayerPipeline2D, PinholeCamera

from .scenes import default_scene


class Camera:
    """
    Camera provides the RAW simulated camera output.
    """

    def __init__(
        self,
        width: int = 128,
        height: int = 128,
        data_pedestal: int = 50,
        bitwidth: int = 24,
    ):
        # TODO: allow different bayer patterns
        # TODO: allow different scenes
        self._world = default_scene()

        self._data_pedestal = data_pedestal
        self._bitwidth = bitwidth

        self._camera = PinholeCamera(
            (width, height),
            parent=self._world,
            transform=translate(0, 4, -3.5) * rotate(0, -48, 0),
        )
        self._camera.spectral_bins = 15
        self._camera.pixel_samples = 100

        filter_red = InterpolatedSF([100, 650, 660, 670, 680, 800], [0, 0, 1, 1, 0, 0])
        filter_green = InterpolatedSF(
            [100, 530, 540, 550, 560, 800], [0, 0, 1, 1, 0, 0]
        )
        filter_blue = InterpolatedSF([100, 480, 490, 500, 510, 800], [0, 0, 1, 1, 0, 0])
        bayer = BayerPipeline2D(
            filter_red,
            filter_green,
            filter_blue,
            display_unsaturated_fraction=1.0,
            display_auto_exposure=True,
            display_black_point=0.1,
            display_gamma=1.0,
            display_progress=False,
            name="Bayer Filter",
        )

        # Attach the pipeline to the camera
        self._camera.pipelines = [bayer]

    def reference(self) -> np.ndarray:
        """
        Render a scene and return the raw image as a numpy array.
        """
        self._camera.observe()

        image = self._camera.pipelines[0]._generate_display_image(
            self._camera.pipelines[0].frame
        )

        minrange = self._data_pedestal
        maxrange = 2**self._bitwidth - 1
        # convert to uint32
        image = image / np.max(image)  # range 0.0 to 1.0
        # map between data_pedestal and 2^bitwidth - 1
        image_fixed = np.clip(
            image * (maxrange - minrange) + minrange, 0, maxrange
        ).astype(np.uint32)

        return image_fixed.T

    def hardware(self) -> np.ndarray:
        """
        Render a scene and return the raw image as a numpy array.
        """
        # TODO: Camera is only used in testing; no hardware implementation
        raise NotImplementedError


if __name__ == "__main__":
    # Example usage of the Camera class
    camera = Camera(width=640, height=480, bitwidth=16)
    raw_image = camera.reference()
    cv2.imwrite("raw_image.png", raw_image.astype(np.uint16))
