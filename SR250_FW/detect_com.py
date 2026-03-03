# Copyright 2025 NXP
#
# NXP Proprietary. This software is owned or controlled by NXP and may only be
# used strictly in accordance with the applicable license terms. By expressly
# accepting such terms or by downloading, installing, activating and/or otherwise
# using the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to be
# bound by the applicable license terms, then you may not retain, install,
# activate or otherwise use the software.

import serial.tools.list_ports

VID = 0x1FC9
PID = 0x0095

for p in serial.tools.list_ports.comports():
    if p.vid == VID and p.pid == PID:
        print(p.device)
        break