@echo off

REM
REM Copyright 2025 NXP
REM
REM NXP Proprietary. This software is owned or controlled by NXP and may only be
REM used strictly in accordance with the applicable license terms. By expressly
REM accepting such terms or by downloading, installing, activating and/or otherwise
REM using the software, you are agreeing that you have read, and that you agree to
REM comply with and are bound by, such license terms. If you do not agree to be
REM bound by the applicable license terms, then you may not retain, install,
REM activate or otherwise use the software.
REM

set comport=0x1FC9,0x0020
set timeout=-t 60000
set APP_NAME=pnp_FRDM-RW612+Shield.bin

blhost.exe -u %comport% %timeout% -- write-memory 0x20001000 fcb_WIN.bin
blhost.exe -u %comport% %timeout% -- configure-memory 0x9 0x20001000
blhost.exe -u %comport% %timeout% -- get-property 0x19 0x9
blhost.exe -u %comport% %timeout% -- flash-erase-region 0x08000000 0x1000
blhost.exe -u %comport% %timeout% -- fill-memory 0x20001000 0x04 0xf000000f
blhost.exe -u %comport% %timeout% -- configure-memory 0x9 0x20001000
blhost.exe -u %comport% %timeout% -- flash-erase-region 0x08000000 0x90000
blhost.exe -u %comport% %timeout% -- write-memory 0x08000000 %APP_NAME%
pause
