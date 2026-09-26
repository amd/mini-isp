# SPDX-FileCopyrightText: Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

setenv kernelname Image

setenv bootpartnum 1
setenv rootpartnum 3

echo "Checking for kernel:${kernelname}"
if test -e ${devtype} ${devnum}:${bootpartnum} ${kernelname}; then
       echo "Loading ${kernelname} at ${kernel_addr_r}"
       fatload ${devtype} ${devnum}:${bootpartnum} ${kernel_addr_r} ${kernelname};
else
       echo "kernel image ${kernelname} not found on ${devtype} ${devnum}:${bootpartnum}"
       exit
fi

fdt addr ${fdtcontroladdr}
fdt get value bootargs /chosen bootargs
setenv bootargs ${bootargs} root=/dev/mmcblk${devnum}p${rootpartnum} ro rootwait uio_pdrv_genirq.of_id=generic-uio
booti ${kernel_addr_r} - ${fdtcontroladdr}
