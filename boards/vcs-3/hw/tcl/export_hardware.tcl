# SPDX-FileCopyrightText: Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Brian Wiec (AMD)
# SPDX-FileCopyrightText: Copyright (c) 2026 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

set proj_name [lindex $argv 0]

open_project build/${proj_name}/${proj_name}.xpr
update_compile_order -fileset sources_1

write_hw_platform -fixed -include_bit -force -file build/${proj_name}/${proj_name}.xsa

exit
