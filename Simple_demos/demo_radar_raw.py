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

DEMO_NAME = "Simple radar raw CIRs demo"
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

RADAR_SET_VENDOR_APP_CONFIG_CMD = [0x2F,0x00,0x00,0x24,0x01,0x00,0x00,0xF0, 0x06,
                                   0xA0,0x01,0x01,                                  # RADAR_MODE
                                   0xA5,0x01,0x00,                                  # RADAR_SINGLE_FRAME_NTF
                                   0xA8,0x07,0x03,0x76,0x02,0x76,0x02,0x76,0x02,    # RADAR_CIR_START_OFFSET
                                   0xA9,0x07,0x32,0x00,0x00,0x00,0xE0,0x2E,0x01,    # RADAR_RFRI
                                   0xAD,0x01,0x01,                                  # RADAR_PERFORMANCE
                                   0xB2,0x02,0xCD,0x0C                              # RADAR_DRIFT_COMPENSATION
]

RADAR_SET_VENDOR_APP_CONFIG_EVK_CMD = [0x2F,0x00,0x00,4+len(Evk.RADAR_EVK_ANT_CONFIG),0x01,0x00,0x00,0xF0] + Evk.RADAR_EVK_ANT_CONFIG

RADAR_START_CMD = [0x22,0x00,0x00,0x04,0x01,0x00,0x00,0xF0]

ScenarioCmds = [
    RADAR_SESSION_INIT_CMD,
    RADAR_SESSION_SET_APP_CONFIG_CMD,
    RADAR_SET_VENDOR_APP_CONFIG_CMD,
    [0x2f,0x03,0x00,0x06,0x01,0x00,0x00,0xf0,0x01,0xb3],
#   [0x2f,0x00,0x00,0x2C,0x01,0x00,0x00,0xf0,0x01,0xb3,0x25,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00],
    [0x2f,0x00,0x00,0x1A,0x01,0x00,0x00,0xf0,0x01,0xb3,0x13,0x01,0x01,0x1a,0x01,0x76,0x02,0x76,0x02,0x76,0x02,0x01,0x02,0x00,0x00,0x00,0x00,0x00,0x00,0x00],
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
import random
import string
import os

datetime_now = time.time()
filename = 'radar_cirs/radar_cirs_' + datetime.datetime.fromtimestamp(datetime_now).strftime("%Y-%m-%d_T_%H-%M-%S") + '.radar_table_csv'
deviceName = "CRETE"
meas_id = random.randint(0, 4294967295)

class CirTableEntry:
    meas_idx: int
    device_name: string
    session_id: int
    status: int
    ts: float
    sequence_number: int
    receiver: int
    rx_antenna_idx: int
    tx_antenna_idx: int
    rx_gain_idx: int
    radar_mode: int
    dc_freeze: int
    single_pin: int
    cir_start_offset: int
    cir_header: string
    cir_data: string
    groundtruth_distance_cm: string
    groundtruth_aoa_azimuth_deg: string
    groundtruth_aoa_elevation_deg: string
    groundtruth_amplitude_cm: string
    groundtruth_frequency_hz: string

    def getCSVField(self):
        return [str(self.meas_idx), str(self.device_name), str(self.session_id), str(self.status), str(self.ts), str(self.sequence_number), str(self.receiver), str(self.rx_antenna_idx), str(self.tx_antenna_idx), str(self.rx_gain_idx), str(self.radar_mode), str(self.dc_freeze), str(self.single_pin), str(self.cir_start_offset), str(self.cir_header), str(self.cir_data), str(self.groundtruth_distance_cm), str(self.groundtruth_aoa_azimuth_deg), str(self.groundtruth_aoa_elevation_deg), str(self.groundtruth_amplitude_cm), str(self.groundtruth_frequency_hz)]

    def __init__(self, meas_idx, device_name, session_id, status, ts, sequence_number, receiver, rx_antenna_idx, tx_antenna_idx, rx_gain_idx, radar_mode, dc_freeze, single_pin, cir_start_offset, cir_header, cir_data, groundtruth_distance_cm, groundtruth_aoa_azimuth_deg, groundtruth_aoa_elevation_deg, groundtruth_amplitude_cm, groundtruth_frequency_hz):
        self.meas_idx = meas_idx
        self.device_name = device_name
        self.session_id = session_id
        self.status = status
        self.ts = ts
        self.sequence_number = sequence_number
        self.receiver = receiver
        self.rx_antenna_idx = rx_antenna_idx
        self.tx_antenna_idx = tx_antenna_idx
        self.rx_gain_idx = rx_gain_idx
        self.radar_mode = radar_mode
        self.dc_freeze = dc_freeze
        self.single_pin = single_pin
        self.cir_start_offset = cir_start_offset
        self.cir_header = cir_header
        self.cir_data = cir_data
        self.groundtruth_distance_cm = groundtruth_distance_cm
        self.groundtruth_aoa_azimuth_deg = groundtruth_aoa_azimuth_deg
        self.groundtruth_aoa_elevation_deg = groundtruth_aoa_elevation_deg
        self.groundtruth_amplitude_cm = groundtruth_amplitude_cm
        self.groundtruth_frequency_hz = groundtruth_frequency_hz

def save_cirs(session_id, radar_rx_ntf):
    status = radar_rx_ntf[0]
    nb_cirs = radar_rx_ntf[2] + (radar_rx_ntf[3] >> 8)
    cir_size = radar_rx_ntf[4] * 4
    if (status == 0):
        timestamp = float(round(time.time() * 1000,3))
        payload = radar_rx_ntf[6:]
        for i in range (0, nb_cirs):
            cir = payload[i*cir_size:i*cir_size+cir_size]
            seq_nb = int(cir[0] + (cir[1]<<8) + (cir[2]<<16) + (cir[3]<<24))
            rx_gain = int(cir[8])
            receiver = int(cir[16])
            radar_mode = int(cir[17] & 0x0f)
            single_pin = int(1 if (cir[17] & 0x10) else 0)
            dc_freeze = int(1 if (cir[17] & 0x20) else 0)
            rx_antenna = int(cir[18])
            tx_antenna = int(cir[19])
            cir_start = int(cir[30] + (cir[31]<<8))
            cir_header = cir[0:32].hex().upper()
            cir_data = cir[32:cir_size].hex().upper()
            writer.writerow(CirTableEntry(meas_id, deviceName, session_id, 0, timestamp, seq_nb, receiver, rx_antenna, tx_antenna, rx_gain, radar_mode, dc_freeze, single_pin, cir_start, cir_header, cir_data, '', '', '', '', '').getCSVField())

def main():
    global handler
    global com_port
    global writer

    os.makedirs('radar_cirs', exist_ok=True)
    cir_file = open(filename, 'w', encoding='utf-8', newline='')
    writer = csv.writer(cir_file, delimiter=";")
    writer.writerow(["measurement_idx", "device_name", "session_id", "status", "ts", "sequence_number", "receiver", "rx_antenna_idx", "tx_antenna_idx", "rx_gain_idx", "radar_mode", "dc_freeze", "single_pin", "cir_start_offset", "cir_header", "cir_data", "groundtruth_distance_cm", "groundtruth_aoa_azimuth_deg", "groundtruth_aoa_elevation_deg", "groundtruth_amplitude_cm", "groundtruth_frequency_hz"])

    handler = SIGINThandler()
    signal.signal(signal.SIGINT, handler.signal_handler)
    
    for arg in sys.argv[1:]:
        if (str(arg).__contains__("COM")):
            com_port = arg

    print(f"\n~~ {DEMO_NAME}")
    print(f"~ This demo showcases how the SR250 can be configured to capture UWB radar Channel Impulse Responses (CIRs).")
    print(f"~ During the capture process, the CIR data is automatically recorded in radar_cirs\\radar_cirs_xxx.csv file for further post-processing.\n")

    UartIntf.serial_port_configure(com_port, 1)

    for cmd in InitCmds: UartIntf.command_queue.put(cmd)

    for cmd in Evk.EvkCommands: UartIntf.command_queue.put(cmd)

    for cmd in ScenarioCmds: UartIntf.command_queue.put(cmd)

    read_thread = Thread(target=UartIntf.read_from_serial_port, args=(save_cirs,))
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