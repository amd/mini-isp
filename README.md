# Mini-ISP

<!--
![banner](docs/img/mini-isp.png)
-->

[![Lint, simulate, synthesize, test and docs](https://github.com/amd/mini-isp/actions/workflows/cicd.yml/badge.svg)](https://github.com/amd/mini-isp/actions/workflows/cicd.yml)

A minimal, open-source Image Signal Processor (ISP) for AMD FPGA, implemented in Verilog.

Mini-ISP is a small open-source Image Signal Processor (ISP), completely implemented in programmable logic (PL). It is developed in Verilog RTL and optimized for AMD FPGA. It provides extremely high performance in terms of throughput and latency at an absolute minimum of required PL resources. The ISP ensures an acceptable image quality for a majority of applications.

The Mini-ISP philosophy is summarized as follows:
-	Minimal resources: Always use the absolute minimum number of resources.
-	Maximal performance: Provide the maximum possible performance in terms of pixel per second and latency.
-	Correct results: Ensure that the output is correct in any scenario.
-	Acceptable image quality: Image quality must be acceptable for most applications and subjectively pleasant to the human eye.
-	Open-source: All code and test cases are publicly available under a permissive license.

For more information and resource usage statistics, please refer to [the documentation](https://amd.github.io/mini-isp).

## Table of Contents

- [Security](#security)
- [Background](#background)
- [Install](#install)
- [Usage](#usage)
- [Contributing](#contributing)
- [License](#license)

## Security

To report a security vulnerability in Mini-ISP, please use the GitHub Security Advisory "Report a Vulnerability" tab. For more details, refer to the [SECURITY.md](SECURITY.md).

## Background

An Image Signal Processor (ISP) converts camera sensor RAW data into a processed image that is ready for display, further image processing, or storage. Some AMD SoCs, such as the [AMD Versal™ AI Edge Series Gen 2](https://www.amd.com/en/products/adaptive-socs-and-fpgas/versal/gen2/ai-edge-series.html), feature hardened ISP blocks. Other FPGA and SoCs, however, rely on programmable logic (PL) for ISP.

Mini-ISP provides an ISP solution for these devices.

### Alternatives

There are several other ISP offerings for AMD FPGA, including, but not limited to:

* [10x-Engineers Infinite ISP](https://github.com/10x-Engineers/Infinite-ISP)
* [Xylon HDR ISP](https://www.logicbricks.com/Solutions/Xylon-HDR-ISP.aspx)
* [AMD Vitis™ Vision Library ISP](https://www.amd.com/en/products/software/adaptive-socs-and-fpgas/vitis/vitis-libraries/vitis-vision.html)

Each of these options may be better suited for your use case than Mini-ISP.

### Design choices

Mini-ISP makes some design choices to meet its design goals. Not every image processing algorithm is well-suited for a resource-efficient streaming hardware implementation. Given a choice, an algorithm with lower complexity, and potentially lower image quality, is selected for use in Mini-ISP.

Some image processing algorithms require a significant image context to work on - which is very expensive to implement in FPGA. Examples are most denoising algorithms and most local tone mapping operators. Denoising and local tone mapping algorithms that are well-suited for FPGA implementation typically have very poor image quality performance. In these cases, no algorithm is implemented at all.

Another block that is typically implemented in an ISP is sharpening (or de-convolution). In most cases, sharpening does only reverse some of the unintended effects that were introduced during low-quality denoising. Since denoising is not implemented in Mini-ISP, sharpening is not required, either.

### Features

* Support for virtually all AMD FPGA and SoC devices, UltraScale+ or later
* AXI4 Lite memory mapped register interface for easy integration
* [AXI4 Stream Video](https://docs.amd.com/r/en-US/ug934_axi_videoIP) input and output interfaces; compatible with other Vivado Video IP
* Configurable 1, 2 or 4 pixel-per-cycle (PPC) processing
* Fully pipelined operation of up to 500 Mhz (depending on configuration, speed grade and device)
* Total maximum throughput of 2 GPx/s
* Fully packaged IP and integrated with Vivado IPI

### Planned and implemented image processing algorithms

| Feature                             | Status                 | Details                             |
|-------------------------------------|------------------------|-------------------------------------|
| Decompanding                        |   :white_check_mark:   |                                     |
| Black Level Correction              |   :white_check_mark:   |                                     |
| Lens Shading Correction             |           :x:          |                                     |
| Digital Color Gain                  |   :white_check_mark:   |                                     |
| Dead Pixel Correction               |           :x:          |                                     |
| Bayer-Domain Global Tone Mapping    |           :x:          | Kim and Kautz ([KimKautz 2008](https://vclab.kaist.ac.kr/cgim2008/MHKim_JKautz_CGIM2008s.pdf))          |
| Demosaic                            |   :white_check_mark:   | Malvar-He-Cutler ([MalvarHeCutler 2004](https://stanford.edu/class/ee367/reading/Demosaicing_ICASSP04.pdf))      |
| Color Correction Matrix             |   :white_check_mark:   |                                     |
| Contrast Enhancement                |           :x:          | [Contrast-limited AHE](https://en.wikipedia.org/wiki/Adaptive_histogram_equalization#Contrast_Limited_AHE) |
| Chroma Noise Filter                 |           :x:          |                                     |
| Color LUT                           |           :x:          |                                     |
| Gamma LUT                           |   :white_check_mark:   |                                     |
| Auto Exposure                       |           :x:          |                                     |
| Auto White Balance                  |           :x:          |                                     |

### Python framework

Mini-ISP comes with a Python framework for algorithm prototyping, simulation, and test benches.

## Install

Mini-ISP is only tested on Linux environments at the moment. In case you use Windows, you will probably want to work in a WSL VM such as Ubuntu. Make sure you have at least docker installed in WSL Ubuntu.

Clone the Mini-ISP repository as follows:

```
git clone git@github.com:amd/mini-isp.git
```

Use Visual Sudio Code to open the folder. Make sure to install the Remote SSH, Dev Containers and WSL extensions of Visual Studio. Visual Studio will then attempt to build and run the Dev Container. Within this container, all dependencies should come pre-installed, and you are ready to simulate and test Mini-ISP.

Verify the correct operation by running the simulation:

```
make sim
```

## Usage

The top-level Makefile contains the following targets:

* ```make sim``` To run the Verilator RTL test benches.
* ```make test``` To run the Python tests.
* ```make synth``` To run the Yosys synthesis.
* ```make docs``` To generate the documentation.
* ```make lint``` To lint all files.
* ```make clean``` To clean the build directory.

See [the documentation](https://amd.github.io/mini-isp) for further information.

## Acknowledgements

We want to thank the following individuals:

* Danny Pascale of [BabelColor](https://babelcolor.com) for letting us use their [spectral data](https://babelcolor.com/colorchecker-2.htm#CCP2_data) collected from ColorChecker charts.

## Contributing

Contributions are very welcome!

Mini-ISP is meant to be modified by the end-user - and chances are high that your modifications are valuable to others. Please consider contributing your changes back to the community.

See [the contributing file](CONTRIBUTING.md).

If you find any bugs, please open a [Github Issue](https://github.com/amd/mini-isp/issues).

## License

Mini-ISP is licensed under the MIT license. The project uses the [REUSE Specification 3.3](https://reuse.software/spec-3.3). Please find the detailled project configuration in [REUSE.toml](REUSE.toml).

Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
