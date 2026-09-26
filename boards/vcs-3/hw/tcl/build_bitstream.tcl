# SPDX-FileCopyrightText: Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Brian Wiec (AMD)
# SPDX-FileCopyrightText: Copyright (c) 2026 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

set PROJ_NAME [lindex $argv 0]
open_project build/${PROJ_NAME}/${PROJ_NAME}.xpr

# enable mask file generation
set_property STEPS.WRITE_BITSTREAM.ARGS.MASK_FILE true [get_runs impl_1]

launch_runs impl_1 -to_step write_bitstream -jobs 24
wait_on_run impl_1

# Copy bit and mask file to build/ directory
exec cp ./build/${PROJ_NAME}/${PROJ_NAME}.runs/impl_1/design_1_wrapper.bit ./build/${PROJ_NAME}.bit
exec cp ./build/${PROJ_NAME}/${PROJ_NAME}.runs/impl_1/design_1_wrapper.msk ./build/${PROJ_NAME}.msk

exit
