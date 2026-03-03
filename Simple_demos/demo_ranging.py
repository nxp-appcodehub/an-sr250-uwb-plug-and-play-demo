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

DEMO_NAME = "Simple DS-TWR demo"
com_port = "COM77 " # default EVK VCOM port
device_role = 'controller'

CORE_DEVICE_INIT_CMD = [0x2E,0x00,0x00,0x02,0x00,0x00]

CORE_DEVICE_RESET_CMD = [0x20,0x00,0x00,0x01,0x00]

CORE_GET_DEV_INFO = [0x20,0x02,0x00,0x00]

InitCmds = [
    CORE_DEVICE_INIT_CMD,
    CORE_DEVICE_RESET_CMD,
    CORE_GET_DEV_INFO,
]

RANGING_SESSION_INIT_CMD = [0x21,0x00,0x00,0x05,0x44,0x33,0x22,0x11,0x00]

RANGING_SESSION_SET_APP_CONFIG_CMD = [0x21,0x03,0x00,0x38,0x01,0x00,0x00,0x80, 0x0F,
                                      0x00,0x01,0x01,                   # DEVICE_TYPE
                                      0x01,0x01,0x02,                   # RANGING_ROUND_USAGE
                                      0x03,0x01,0x01,                   # MULTI_NODE_MODE
                                      0x04,0x01,0x09,                   # CHANNEL_NUMBER
                                      0x05,0x01,0x01,                   # NUMBER_OF_CONTROLEES
                                      0x06,0x02,0xAA,0xAA,              # DEVICE_MAC_ADDRESS
                                      0x07,0x02,0x11,0x11,              # DST_MAC_ADDRESS
                                      0x08,0x02,0xB0,0x04,              # SLOT_DURATION (1200 rtsu = 1ms)
                                      0x09,0x04,0xC8,0x00,0x00,0x00,    # RANGING_DURATION
                                      0x11,0x01,0x01,                   # DEVICE_ROLE
                                      0x12,0x01,0x01,                   # RFRAME_CONFIG
                                      0x1B,0x01,0x14,                   # SLOTS_PER_RR
                                      0x22,0x01,0x01,                   # SCHEDULED_MODE
                                      0x2E,0x01,0x01,                   # RESULT_REPORT_CONFIG
                                      0x2F,0x01,0x00                    # IN_BAND_TERMINATION_ATTEMPT_COUNT
]

RANGING_SET_VENDOR_APP_CONFIG_CMD = [0x2F,0x00,0x00,0x08,0x01,0x00,0x00,0x80, 0x01,
                                     0x67,0x01,0x01                     # TX_POWER_TEMP_COMPENSATION
]

RANGING_SET_VENDOR_APP_CONFIG_EVK_CMD = [0x2F,0x00,0x00,4+len(Evk.RANGING_EVK_ANT_CONFIG),0x01,0x00,0x00,0x80] + Evk.RANGING_EVK_ANT_CONFIG

RANGING_START_CMD = [0x22,0x00,0x00,0x04,0x01,0x00,0x00,0x80]

ScenarioCmds = [
    RANGING_SESSION_INIT_CMD,
    RANGING_SESSION_SET_APP_CONFIG_CMD,
    RANGING_SET_VENDOR_APP_CONFIG_CMD,
    RANGING_SET_VENDOR_APP_CONFIG_EVK_CMD,
    RANGING_START_CMD
]

class SIGINThandler():
    def __init__(self):
        self.sigint = False
    
    def signal_handler(self, signal, frame):
        print("You pressed Ctrl+C!")
        self.sigint = True

def update_device_role(role):
    if(role == 'controlee'):
        RANGING_SESSION_SET_APP_CONFIG_CMD[11] = 0x00
        RANGING_SESSION_SET_APP_CONFIG_CMD[26] = 0x11
        RANGING_SESSION_SET_APP_CONFIG_CMD[27] = 0x11
        RANGING_SESSION_SET_APP_CONFIG_CMD[30] = 0xAA
        RANGING_SESSION_SET_APP_CONFIG_CMD[31] = 0xAA
        RANGING_SESSION_SET_APP_CONFIG_CMD[44] = 0x00
    else:
        RANGING_SESSION_SET_APP_CONFIG_CMD[11] = 0x01
        RANGING_SESSION_SET_APP_CONFIG_CMD[26] = 0xAA
        RANGING_SESSION_SET_APP_CONFIG_CMD[27] = 0xAA
        RANGING_SESSION_SET_APP_CONFIG_CMD[30] = 0x11
        RANGING_SESSION_SET_APP_CONFIG_CMD[31] = 0x11    
        RANGING_SESSION_SET_APP_CONFIG_CMD[44] = 0x01    

def main():
    global handler
    global com_port, device_role
    
    handler = SIGINThandler()
    signal.signal(signal.SIGINT, handler.signal_handler)
    
    for arg in sys.argv[1:]:
        if (str(arg).__contains__("COM")):
            com_port = arg
        if (str(arg).__contains__("controller")):
            device_role = 'controller'
        if (str(arg).__contains__("controlee")):
            device_role = 'controlee'

    print(f"\n~~ {DEMO_NAME} in {device_role} mode")
    print(f"~ This demo showcases how the SR250 can be configured to perform DS-TWR ranging with a peer UWB {"controlee" if device_role=='controller' else "controlee"} device.\n")

    UartIntf.serial_port_configure(com_port, 1)

    for cmd in InitCmds: UartIntf.command_queue.put(cmd)

    for cmd in Evk.EvkCommands: UartIntf.command_queue.put(cmd)

    update_device_role(device_role)
    for cmd in ScenarioCmds: UartIntf.command_queue.put(cmd)

    read_thread = Thread(target=UartIntf.read_from_serial_port, args=())
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