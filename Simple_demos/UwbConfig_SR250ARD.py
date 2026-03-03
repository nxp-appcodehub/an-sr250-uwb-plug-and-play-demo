# Copyright 2023-2025 NXP
#
# NXP Proprietary. This software is owned or controlled by NXP and may only be
# used strictly in accordance with the applicable license terms. By expressly
# accepting such terms or by downloading, installing, activating and/or otherwise
# using the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to be
# bound by the applicable license terms, then you may not retain, install,
# activate or otherwise use the software.

print("SR250-ARD shield loaded as EVK")

CORE_SET_CONFIG_CMD_ANTENNA_DEFINITION = [0x20,0x04,0x00,0x3D, 0x03,
    0xE4,0x60,0x19,0x04,                # ANTENNA_RX_IDX_DEFINE
         0x01, 0x01, 0x00, 0x00, 0x00, 0x00,         # RXC  = AoA Antenna (Horizontal)
         0x02, 0x02, 0x00, 0x00, 0x00, 0x00,         # RXB  = AoA Antenna (Central)
         0x03, 0x03, 0x00, 0x00, 0x00, 0x00,         # TRA2 = AoA Antenna (Vertical)
         0x04, 0x04, 0x00, 0x00, 0x00, 0x00,         # TRA1 = Radar Antenna
    0xE4,0x62,0x0D,0x02,                # ANTENNA_RX_PAIR_DEFINE (Ranging only)
         0x01, 0x01, 0x02, 0x00, 0x00, 0x00,         # RXC and RXB = Horizontal pair
         0x02, 0x00, 0x02, 0x03, 0x00, 0x00,         # RXB and TRA2 = Vertical pair
    0xE4,0x63,0x0D,0x02,                # ANTENNA_TX_IDX_DEFINE
         0x01, 0x01, 0x00, 0x00, 0x00, 0x00,         # TRA1
         0x02, 0x02, 0x00, 0x00, 0x00, 0x00          # TRA2
]

InvertAoASign = False

RADAR_EVK_ANT_CONFIG = [0x02,
    0x02,0x02, 0x01, 0x01,                   # ANTENNAS_CONFIGURATION_TX
    0x03,0x05, 0x02, 0x03, 0x01,0x02,0x00    # ANTENNAS_CONFIGURATION_RX
]

RANGING_EVK_ANT_CONFIG = [0x02,
    0x02,0x02, 0x01, 0x02,                   # ANTENNAS_CONFIGURATION_TX
    0x03,0x04, 0x01, 0x02, 0x01,0x02         # ANTENNAS_CONFIGURATION_RX
]

EvkCommands = [
    CORE_SET_CONFIG_CMD_ANTENNA_DEFINITION,
]