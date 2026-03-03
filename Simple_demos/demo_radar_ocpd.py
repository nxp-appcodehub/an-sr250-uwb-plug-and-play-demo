# Copyright 2022-2025 NXP
#
# NXP Proprietary. This software is owned or controlled by NXP and may only be
# used strictly in accordance with the applicable license terms. By expressly
# accepting such terms or by downloading, installing, activating and/or otherwise
# using the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to be
# bound by the applicable license terms, then you may not retain, install,
# activate or otherwise use the software.

import sys
import signal
import UartInterface as UartIntf
import UwbConfig_SR250ARD as Evk
from threading import Thread

DEMO_NAME = "Simple radar On-Chip Presence Detection demo"
com_port = "COM77" # default EVK VCOM port

CORE_DEVICE_INIT_CMD = [0x2E,0x00,0x00,0x02,0x00,0x00]

CORE_DEVICE_RESET_CMD = [0x20,0x00,0x00,0x01,0x00]

CORE_GET_DEV_INFO = [0x20,0x02,0x00,0x00]

CORE_SET_CONFIG_CMD_LOW_POWER_MODE = [0x20,0x04,0x00,0x04,0x01, 0x01,0x01,0x00]

InitCmds = [
    CORE_DEVICE_INIT_CMD,
    CORE_DEVICE_RESET_CMD,
    CORE_GET_DEV_INFO,
    CORE_SET_CONFIG_CMD_LOW_POWER_MODE
]

RADAR_SESSION_INIT_CMD = [0x21,0x00,0x00,0x05,0x44,0x33,0x22,0x11,0xF0]

RADAR_SESSION_SET_APP_CONFIG_CMD = [0x21,0x03,0x00,0x0B,0x01,0x00,0x00,0xF0, 0x02, 
                                    0x04,0x01,0x09,     # CHANNEL_NUMBER
                                    0x14,0x01,0x1A      # PREAMBLE_CODE_INDEX
]

RADAR_SET_VENDOR_APP_CONFIG_CMD = [0x2F,0x00,0x00,0x27,0x01,0x00,0x00,0xF0, 0x07,
                                   0xA0,0x01,0x01,                                  # RADAR_MODE
                                   0xA5,0x01,0x00,                                  # RADAR_SINGLE_FRAME_NTF
                                   0xA8,0x07,0x03,0x76,0x02,0x76,0x02,0x76,0x02,    # RADAR_CIR_START_OFFSET
                                   0xA9,0x07,0x32,0x00,0x00,0x00,0xE0,0x2E,0x01,    # RADAR_RFRI
                                   0xAD,0x01,0x01,                                  # RADAR_PERFORMANCE
                                   0xAE,0x01,0x32,                                  # RADAR_PULSE_SHAPE
                                   0xB2,0x02,0xCD,0x0C                              # RADAR_DRIFT_COMPENSATION
]

RADAR_OCPD_CMD = [0x2F,0x00,0x00,0x13,0x01,0x00,0x00,0xF0, 0x01,
    0xAA,0x0C,
        0x13,      # Mode
        0x02,      # Raw + report frequency 
        0x34,      # snr: 0x34-->52/16(Q4) = 3.25
        0x00,      # GPIO
        0x32,0x00, # Min distance
        0x90,0x01, # Max distance
        0x40,0x06, # Hold delay
        0xa6,      # Min angle
        0x5a       # Max angle
]

RADAR_SET_VENDOR_APP_CONFIG_EVK_CMD = [0x2F,0x00,0x00,4+len(Evk.RADAR_EVK_ANT_CONFIG),0x01,0x00,0x00,0xF0] + Evk.RADAR_EVK_ANT_CONFIG

RADAR_START_CMD = [0x22,0x00,0x00,0x04,0x01,0x00,0x00,0xF0]

ScenarioCmds = [
    RADAR_SESSION_INIT_CMD,
    RADAR_SESSION_SET_APP_CONFIG_CMD,
    RADAR_SET_VENDOR_APP_CONFIG_CMD,
    RADAR_OCPD_CMD,
    RADAR_SET_VENDOR_APP_CONFIG_EVK_CMD,
    RADAR_START_CMD
]

class SIGINThandler():
    def __init__(self):
        self.sigint = False
    
    def signal_handler(self, signal, frame):
        print("You pressed Ctrl+C!")
        self.sigint = True

import time
import datetime
import csv
from ctypes import c_short
import os

datetime_now = time.time()
filename = 'radar_ocpd_results/ocpd_results_' + datetime.datetime.fromtimestamp(time.time()).strftime("%Y-%m-%d_T_%H-%M-%S") + '.csv'
current_ts = 0

def extract_detection(ntf):
    id = ntf[3]
    distance = ntf[0] + (ntf[1] << 8)    
    angle = c_short(ntf[2] << 8).value >> 8
    snr = ntf[4] + (ntf[5] << 8) + (ntf[6] << 16) + (ntf[7] << 24) 
    return id, distance, angle, snr

def get_ocpd_period():
    configured_period = (RADAR_OCPD_CMD[12] >> 1) & 0x03
    return 50 if configured_period==1 else 400 if configured_period==2 else 1600 if configured_period==3 else 0

def handle_ocpd_ntf(ocpd_ntf):
    global current_ts

    current_ts = current_ts + get_ocpd_period()
    if(ocpd_ntf[0] == 1):
        nb_of_detection = ocpd_ntf[2]
        for i in range (0, nb_of_detection):
            id, distance, angle, snr = extract_detection(ocpd_ntf[8*i+4:8*i+12])
            writer.writerow([current_ts, 1, id, distance, angle, snr])
    else:
            writer.writerow([current_ts, 0, 0, 0, 0, 0])

def main():
    global handler
    global com_port
    global writer
    
    handler = SIGINThandler()
    signal.signal(signal.SIGINT, handler.signal_handler)

    os.makedirs('radar_ocpd_results', exist_ok=True)
    file = open(filename, 'w', encoding='utf-8', newline='')
    writer = csv.writer(file, delimiter=";")
    writer.writerow(["time_ms", "presence_status", "presence_id", "presence_distance", "presence_angle", "presence_snr"])

    for arg in sys.argv[1:]:
        if (str(arg).__contains__("COM")):
            com_port = arg

    print(f"\n~~ {DEMO_NAME}")
    print("~ This demo showcases how the SR250 can be configured to report presence detection using its On-Chip Presence Detection (OCPD) feature.")
    print("~ During execution, the OCPD UCI notification outputs are recorded automatically in radar_ocpd_results\\ocpd_results_xxx.csv file for further analysis.\n")

    UartIntf.serial_port_configure(com_port, 1)

    for cmd in InitCmds: UartIntf.command_queue.put(cmd)

    for cmd in Evk.EvkCommands: UartIntf.command_queue.put(cmd)

    for cmd in ScenarioCmds: UartIntf.command_queue.put(cmd)

    read_thread = Thread(target=UartIntf.read_from_serial_port, args=(UartIntf.null_fct, handle_ocpd_ntf, UartIntf.null_fct, UartIntf.null_fct))
    read_thread.start()
    
    write_thread = Thread(target=UartIntf.write_to_serial_port, args=())
    write_thread.start()    

    while (1):
        if handler.sigint:
            break

    UartIntf.stop_write_thread = True
    UartIntf.stop_read_thread  = True  
    # Unblock the waiting in the write thread
    UartIntf.command_queue.put([0xFF, 0xFF])

if __name__ == "__main__":
    main()