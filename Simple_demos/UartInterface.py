# Copyright 2022-2025 NXP
#
# NXP Proprietary. This software is owned or controlled by NXP and may only be
# used strictly in accordance with the applicable license terms. By expressly
# accepting such terms or by downloading, installing, activating and/or otherwise
# using the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to be
# bound by the applicable license terms, then you may not retain, install,
# activate or otherwise use the software.

from threading import Condition, Event
import queue
import serial
import sys
import time

DATA_STRUCT_SZ = 14

debug_trace = 0
debug_timestamp = 0

LOG_MAX_LEN = 10000

def LOG(trace):
    if(debug_trace):
        timestamp = int(time.time() * 1000)
        if len(trace) > LOG_MAX_LEN: trace = trace[0:LOG_MAX_LEN] + "..."
        print((f"{timestamp} - " if debug_timestamp else "") + trace)

stop_write_thread = False
stop_read_thread = False
command_queue = queue.Queue(maxsize=100)
go_stop = Event()
write_wait = Condition()
retry_cmd = False
serial_port = serial.Serial()

def send_ResetCmd(com_port):
    try:
        InitCmd = [0x04,0x00,0x00]
        LOG("#=> INIT_CMD: " + "".join("{:02x} ".format(h) for h in InitCmd))
        serial_port.write(InitCmd)
    except:  
        LOG("#=> Fail to Write Board Init CMD on " + com_port)
        return 1
    time.sleep(0.2)
    
    rx = serial_port.read(serial_port.in_waiting)
    if (len(rx) != 4):
        LOG("#=> Fail to Read Board Init RSP ")
        LOG("############ Please RESET the Board and re-run the script ############")
        return 1
    else:
        LOG("#<= INIT_RSP: " + "".join("{:02x} ".format(h) for h in rx))

    return 0

def serial_port_configure(com_port, debug):
    global debug_trace, debug_timestamp

    debug_trace = 1 if (debug & 0x1) else 0
    debug_timestamp = 1 if (debug & 0x4) else 0

    serial_port.baudrate = 3000000
    serial_port.timeout = 1                 # To avoid endless blocking read
    serial_port.port = com_port
    serial_port.rtscts = True

    if serial_port.isOpen(): serial_port.close()
    
    try:
        serial_port.open()
    except:
        LOG("#=> Fail to open " + com_port)
        sys.exit(1)

    if (send_ResetCmd(com_port) != 0):
        # Retry
        if (send_ResetCmd(com_port) != 0):
            sys.exit(1)
        
    try:
        InitCmd = [0x12,0x00,0x00]
        LOG("#=> HDLL_TO_UCI_CMD: " + "".join("{:02x} ".format(h) for h in InitCmd))
        serial_port.write(InitCmd)
    except:  
        LOG("#=> Fail to Write HDLL to UCI CMD on " + com_port)
        sys.exit(1)
     
    time.sleep(0.2)
    
    rx = serial_port.read(serial_port.in_waiting)
    if (len(rx) != 5):
        LOG("#=> Fail to Read Write HDLL to UCI CMD " )
        LOG("############ Please RESET the Board and re-run the script ############")
        sys.exit(1)
    else:
        LOG("#<= HDLL_TO_UCI_RSP: " + "".join("{:02x} ".format(h) for h in rx))

def write_to_serial_port():
    global retry_cmd
    usb_out_packet = bytearray()
    
    LOG("Write to serial port started")
    while (not stop_write_thread):
        if (retry_cmd): retry_cmd = False
        else: uci_command = command_queue.get()
        
        if (uci_command[0] == 0xFF and uci_command[1] == 0xFF):
            break
        if (uci_command[0] == 0xFF and uci_command[1] == 0x00):
            time.sleep(uci_command[2])
            continue

        if uci_command[0] == 0x21 and uci_command[1] == 0x03 and uci_command[3] == 0x3b:
            retry_cmd = False

        usb_out_packet.clear()
        usb_out_packet.append(0x01)
        usb_out_packet.append(int(len(uci_command) / 256))
        usb_out_packet.append(len(uci_command) % 256)
        usb_out_packet.extend(uci_command)
        
        write_wait.acquire()                          # Acquire Lock to avoid mixing in print
        if serial_port.isOpen():
            LOG("NXPUCIX => " + "".join("{:02x} ".format(x) for x in uci_command))
            
            try:
                serial_port.write(serial.to_bytes(usb_out_packet))
            except:
                LOG("Fail to write on serial port")
            
            # Wait the reception of RSP or timeout of 0.5s before allowing send of new CMD
            notified = write_wait.wait(0.5)  
            if (not (notified)): retry_cmd = True     # Repeat command if timeout
        write_wait.release()
    LOG("Write to serial port exited")

def null_fct(null_param):
    return

def read_from_serial_port(extract_cirs=null_fct, extract_presence=null_fct, extract_ranging=null_fct, extract_cross_ranging=null_fct):
    global retry_cmd
    LOG("Read from serial port started")
    while (not stop_read_thread):
        if serial_port.isOpen():
            if serial_port.isOpen():
                uci_hdr = serial_port.read(4)    # Read header of UCI frame
                write_wait.acquire()             # Acquire Lock to avoid mixing in print
                if len(uci_hdr) == 4:
                    count = uci_hdr[3]
                    if (uci_hdr[1] & 0x80) == 0x80 or (uci_hdr[0] & 0xE0) == 0x00:
                        # Extended length
                        count = int((uci_hdr[3] << 8) + uci_hdr[2])
                    
                    if count > 0:
                        if serial_port.isOpen():
                            uci_payload = serial_port.read(count)    # Read payload of UCI frame

                            LOG("NXPUCIR <= " + "".join("{:02x} ".format(h) for h in uci_hdr) + "".join("{:02x} ".format(p) for p in uci_payload))
                            
                            if len(uci_payload) == count:
                                if (uci_hdr[0] & 0xF0) == 0x40: write_wait.notify()      # Notify the reception of RSP
                                
                                if (uci_hdr[0] == 0x60 and uci_hdr[1] == 0x07 and uci_hdr[3] == 0x01 and \
                                        uci_payload[0] == 0x0A):
                                    # Command retry without wait response
                                    retry_cmd = True
                                    write_wait.notify()

                                if (uci_hdr[0] == 0x02 and uci_hdr[1] == 0x00):
                                    ntf_sz = uci_payload[15] + (uci_payload[16]>>8)
                                    ptr=0
                                    while ptr < ntf_sz:
                                        extract_cross_ranging(uci_payload[17+ptr:])
                                        ptr += 3 + uci_payload[19+ptr]*DATA_STRUCT_SZ
                                        
                                if (uci_hdr[0] == 0x62 and uci_hdr[1] == 0x00):
                                    if(extract_ranging != null_fct):
                                        range_data = bytearray()
                                        range_data.extend(uci_payload)
                                        for i in range (0, uci_payload[24]): extract_ranging(i, uci_payload[27+(31*i):])

                                if (uci_hdr[0] == 0x69 and uci_hdr[1] == 0x0A):
                                    if(extract_presence != null_fct):
                                        extract_presence(uci_payload[6:])

                                if (uci_hdr[0] & 0xEF == 0x69 and uci_hdr[1] == 0x8A):
                                    if(extract_cirs != null_fct):
                                        session_id = uci_payload[0] + (uci_payload[1] << 8) + (uci_payload[2] << 16) + (uci_payload[3] << 24)
                                        extract_cirs(session_id, uci_payload[4:])
                            else:
                                LOG("\nExpected Payload bytes is " + str(count) + \
                                      ", Actual Paylod bytes received is " + str(len(uci_payload)))
                        else:
                            LOG("Port is not opened")
                    else:
                        LOG("\nUCI Payload Size is Zero")
                write_wait.release()
            else:
                LOG("Port is not opened (2)")
        else:
            LOG("Port is not opened (1)")
    if serial_port.isOpen(): serial_port.close()
    LOG("Read from serial port exited")