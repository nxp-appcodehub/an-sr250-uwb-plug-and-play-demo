#!/usr/bin/perl
#
# Copyright 2023-2025 NXP
#
# NXP Proprietary. This software is owned or controlled by NXP and may only be
# used strictly in accordance with the applicable license terms. By expressly
# accepting such terms or by downloading, installing, activating and/or otherwise
# using the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to be
# bound by the applicable license terms, then you may not retain, install,
# activate or otherwise use the software.

use strict;
use warnings;
no warnings 'uninitialized';
# Add ANSI module for Perl on Windows
eval "use Win32::Console::ANSI" if ($^O eq "MSWin32");

# Exit when press Ctlc-C
use sigtrap qw/handler signal_handler normal-signals/;


#########################################################################################
# Global variables
#########################################################################################
my $this = "viki_SR250.pl";
my $date_version = "2025 October 1st - Spec Rev. 2.0.23";

my $MAX_LINE_SIZE = 112;     # For terminal with 115 carateres per line
my $session_info_ntf_enable = 1;
my $rframe_ntf_enable = 1;
my $enable_get_caps_info = 0;
# Escape sequences for Set Graphics Rendition
my $nocolor   = "\e[0m";
my $brown     = "\e[0;33m";
my $turquoise = "\e[0;36m";
my $grey      = "\e[1;30m";
my $red       = "\e[1;31m";
my $green     = "\e[1;32m";
my $yellow    = "\e[1;33m";
my $blue      = "\e[1;34m";
my $magenta   = "\e[1;35m";
my $cyan      = "\e[1;36m";
my $white     = "\e[1;37m";

my $comment_color = "\e[0;32m";
my $debug_color   = "\e[7;37m";

my $oops="OOPS!";
my $red_oops="\e[1;31m".$oops." ";

# Specific patterns to find the MW version
my $patMWVersion="(MW Version: .*)";

# Specific patterns to find the FW download
my $patFWDlStart="Start FW download";
my $patHIFImage="HIF Image (.*)";
my $patFWDlEnd="fw_download completed";

# Specific pattern to find extra keywords
my $patKeywords="";

# To store the current line to parse
my $line = "";

# To parse again the current line
my $parse_again = "";

# To store segment when PBF = 1
my $seg_mt_dpf = "";
my $seg_mt_gid_oid = "";
my $seg_payload = "";

# Indicators of the message direction
my $dh2uwbd   = " --> ";
my $uwbd2dh   = "     ";

# Indent of decoded lines 
my $tab_short = "     ";               # Without timestamp
my $tab_long  = "                 ";   # With timestamp hh:mm:ss.ddd

# Variables for display of the message decoding
my $color;                   # Color of the messages
my $device_msg;              # Device of the message
my $time;                    # Timestamp
my $indent;                  # Indent of decoding; according presence or not of timestamp
my $sens;                    # Indication of the message direction
my $bytes;                   # Number of bytes in the frame
my $frame;                   # UCI frame (hexadecimal string)
my $msg;                     # UCI command; response or notification name
my $decode;                  # Detail of decoded UCI message
my $csv_rangedata;           # Range data separated with ;
my $csv_ranging_type;        # Ranging type to add appropriate header in CSV file
my $csv_rframe;              # RFRAME data separated with ;
my $csv_rframe_first;        # RFRAME first data to add appropriate header in CSV file

# File headers
my $fh_input = *STDIN;       # Read input text (STDIN by default)
my $fh_logcat;               # Store all incoming lines
my $fh_decode;               # Store decoded messages without Escape sequences
my $fh_rangedata;            # Store data of ranging session in csv (; as separator)
my $fh_rangedata_vendor = "";     # Store vendor data of ranging session in csv (; as separator)
my $fh_rangedata_SWAP_ANT_PAIR_3D_AOA = "";     # Store data (RSSI, SNR) of CCC ranging session in csv (; as separator)
my $fh_rframe;               # Store data of RFRAME notification in csv (; as separator)
my $fh_dbg;                  # Store DBG messages without Escape sequences

# Store parsed frame to avoid repetition
my $isNoRepeat = 0;
my $frame_memo = "";

# Store ranging type to add appropriate header in Range data CSV file
my $csv_type_memo = "";

# Store FW download mode to avoid wrong parsing
my $isFwDownload = 0;

# To manage frame splitted on multiple lines
my %multi_line = (
"mode"   => "",              # Empty when not in block concatenation
"time"   => "",              # Storage of timestamp during block concatenation
"indent" => "",              # Indent of indent during block concatenation
"sens"   => "",              # Storage of direction frame during block concatenation
"buffer" => "",              # Storage of partial frame during block concatenation
);

# Statistics
my $disp_stat = 0;           # True to display statistics
my @oops_stats = ();         # List of oops

# Input duplication
my $tee = 0;                 # True to duplicate input to STDOUT
                             # Add lines <viki_start> and <wiki_end> to encapsulate decoding

# To manage debug traces
my $disp_debug = 0;          # True to display debug traces on terminal

# To manage UCI Generic Version
my $UciGenericVersion_Major = 0x01;
my $UciGenericVersion_Minor = 0x00;
my $UciGenericVersion_Patch = 0x00;

# To manage Wifi Coex Feature
my $WifiCoexFeature = 0x00;

my $Antenna_Config_Rx_mode = 0x00;

# Store device name
my $Device_Name = "";

# session type (0x00: ranging session, 0x01: ranging and in-band data session, 0x02: data transfer session)
my $session_type = 0x00;

my $payload_length = 0;
my $payload_length_RFRAME = 0;

my $number_times_add_RFRAME_Titles = 0; # Number of times we need to add a rframe measurement in titles

my $ft_status = "";         # Store the status of the frame

my $buffer_RFrame = "";     # Store the RFrame frame into a buffer

#########################################################################################
# Hash tables
#########################################################################################
# UCI Data Packets MT GID OID
my %uci_data_packet = (
# UCI Data Message
"03" => "DATA_MESSAGE_SND",
"04" => "DATA_MESSAGE_RCV",
"02" => "DATA_MESSAGE_RCV",
);

# UCI Control Packets MT GID OID
### RSP with Status only
my %uci_control_packet = (
########## FIRA ##########
# UCI Core Group
"2000" => "CORE_DEVICE_RESET_CMD",
"4000" => "CORE_DEVICE_RESET_RSP",
"6001" => "CORE_DEVICE_STATUS_NTF",
"2002" => "CORE_GET_DEVICE_INFO_CMD",
"4002" => "CORE_GET_DEVICE_INFO_RSP",
"2003" => "CORE_GET_CAPS_INFO_CMD",
"4003" => "CORE_GET_CAPS_INFO_RSP",
"2004" => "CORE_SET_CONFIG_CMD",
"4004" => "CORE_SET_CONFIG_RSP",
"2005" => "CORE_GET_CONFIG_CMD",
"4005" => "CORE_GET_CONFIG_RSP",
"6007" => "CORE_GENERIC_ERROR_NTF",
"2008" => "QUERY_UWBS_TIMESTAMP_CMD",
"4008" => "QUERY_UWBS_TIMESTAMP_RSP",
# UWB Session Config Group
"2100" => "SESSION_INIT_CMD",
"4100" => "SESSION_INIT_RSP",
"2101" => "SESSION_DEINIT_CMD",
"4101" => "SESSION_DEINIT_RSP",
"6102" => "SESSION_STATUS_NTF",
"2103" => "SESSION_SET_APP_CONFIG_CMD",
"4103" => "SESSION_SET_APP_CONFIG_RSP",
"2104" => "SESSION_GET_APP_CONFIG_CMD",
"4104" => "SESSION_GET_APP_CONFIG_RSP",
"2105" => "SESSION_GET_COUNT_CMD",
"4105" => "SESSION_GET_COUNT_RSP",
"2106" => "SESSION_GET_STATE_CMD",
"4106" => "SESSION_GET_STATE_RSP",
"2107" => "SESSION_UPDATE_CONTROLLER_MULTICAST_LIST_CMD",
"4107" => "SESSION_UPDATE_CONTROLLER_MULTICAST_LIST_RSP",
"6107" => "SESSION_UPDATE_CONTROLLER_MULTICAST_LIST_NTF",
"2108" => "SESSION_UPDATE_DT_ANCHOR_RANGING_ROUNDS_CMD",
"4108" => "SESSION_UPDATE_DT_ANCHOR_RANGING_ROUNDS_RSP",
"2109" => "SESSION_UPDATE_DT_TAG_RANGING_ROUNDS_CMD",
"4109" => "SESSION_UPDATE_ACTIVE_ROUNDS_RECEIVER_RSP",
"210B" => "SESSION_QUERY_DATA_SIZE_IN_RANGING_CMD",
"410B" => "SESSION_QUERY_DATA_SIZE_IN_RANGING_RSP",
"210E" => "SESSION_UPDATE_DTPCM_CMD",
"410E" => "SESSION_UPDATE_DTPCM_RSP",
"610E" => "SESSION_UPDATE_DTPCM_NTF",
##########################
########## CCC ##########
"2120" => "SESSION_GET_POSSIBLE_RAN_MULTIPLIER_VALUE_CMD",
"4120" => "SESSION_GET_POSSIBLE_RAN_MULTIPLIER_VALUE_RSP",
#########################
########## FIRA ##########
# UWB Session Control Group
"2200" => "SESSION_START_CMD",
"4200" => "SESSION_START_RSP",
"6200" => "SESSION_INFO_NTF",
"2201" => "SESSION_STOP_CMD",
"4201" => "SESSION_STOP_RSP",
"2207" => "LOGICAL_LINK_CREATE_CMD",
"4207" => "LOGICAL_LINK_CREATE_RSP",
"2208" => "LOGICAL_LINK_CLOSE_CMD",
"4208" => "LOGICAL_LINK_CLOSE_RSP",
"2203" => "SESSION_GET_RANGING_COUNT_CMD",
"4203" => "SESSION_GET_RANGING_COUNT_RSP",
"6204" => "SESSION_DATA_CREDIT_NTF",
"6205" => "SESSION_DATA_TRANSFER_STATUS_NTF",
"6206" => "SESSION_ROLE_CHANGE_NTF",
"6207" => "LOGICAL_LINK_CREATE_NTF",
"6208" => "LOGICAL_LINK_CLOSE_NTF",
"6209" => "LOGICAL_LINK_UWBS_CLOSE_NTF",
"620A" => "LOGICAL_LINK_UWBS_CREATE_NTF",
########## FIRA ##########
"6220" => "RANGE_CCC_DATA_NTF",
"2221" => "RANGE_RESUME_CMD",
"4221" => "RANGE_RESUME_RSP",
##########################
########## TEST ##########
"2D00" => "TEST_CONFIG_SET_CMD",
"4D00" => "TEST_CONFIG_SET_RSP",
"2D01" => "TEST_CONFIG_GET_CMD",
"4D01" => "TEST_CONFIG_GET_RSP",
"2D02" => "TEST_PERIODIC_TX_CMD",
"4D02" => "TEST_PERIODIC_TX_RSP",
"6D02" => "TEST_PERIODIC_TX_NTF",
"2D03" => "TEST_PER_RX_CMD",
"4D03" => "TEST_PER_RX_RSP",
"6D03" => "TEST_PER_RX_NTF",
"2D05" => "TEST_RX_CMD",
"4D05" => "TEST_RX_RSP",
"6D05" => "TEST_RX_NTF",
"2D06" => "TEST_LOOPBACK_CMD",
"4D06" => "TEST_LOOPBACK_RSP",
"6D06" => "TEST_LOOPBACK_NTF",
"2D07" => "TEST_STOP_SESSION_CMD",
"4D07" => "TEST_STOP_SESSION_RSP",
"2D08" => "TEST_SS_TWR_CMD",
"4D08" => "TEST_SS_TWR_RSP",
"6D08" => "TEST_SS_TWR_NTF",
"2D09" => "TEST_SR_RX_CMD",
"4D09" => "TEST_SR_RX_RSP",
"6D09" => "TEST_SR_RX_NTF",
##########################
# Proprietary Group 1
"2E00" => "CORE_DEVICE_INIT_CMD",
"4E00" => "CORE_DEVICE_INIT_RSP",
"2E02" => "DBG_GET_ERROR_LOG_CMD",
"4E02" => "DBG_GET_ERROR_LOG_RSP",
"2E03" => "SE_GET_BINDING_COUNT_CMD",
"4E03" => "SE_GET_BINDING_COUNT_RSP",
"2E04" => "SE_DO_TEST_LOOP_CMD",
"4E04" => "SE_DO_TEST_LOOP_RSP",
"6E04" => "SE_DO_TEST_LOOP_NTF",
"6E05" => "SE_COMM_ERROR_NTF",
"6E06" => "BINDING_STATUS_NTF",
"6E07" => "SCHEDULER_STATUS_NTF",
"6E08" => "UWB_SESSION_KDF_NTF",
"6E09" => "UWB_WIFI_COEX_IND_NTF",
"6E0A" => "WLAN_UWB_IND_ERR_NTF",
"2E0B" => "QUERY_TEMPERATURE_CMD",
"4E0B" => "QUERY_TEMPERATURE_RSP",
# "6E0C" => "SE_COMM_DATA_NTF",
"2E0E" => "GENERATE_TAG_CMD",
"4E0E" => "GENERATE_TAG_RSP",
"6E0E" => "GENERATE_TAG_NTF",
"2E0F" => "VERIFY_CALIB_DATA_CMD",
"4E0F" => "VERIFY_CALIB_DATA_RSP",
"6E0F" => "VERIFY_CALIB_DATA_NTF",
"2E10" => "CONFIGURE_AUTH_TAG_OPTIONS_CMD",
"4E10" => "CONFIGURE_AUTH_TAG_OPTIONS_RSP",
"6E10" => "CONFIGURE_AUTH_TAG_OPTIONS_NTF",
"2E11" => "CONFIGURE_AUTH_TAG_VERSION_CMD",
"4E11" => "CONFIGURE_AUTH_TAG_VERSION_RSP",
"2E12" => "CALIBRATION_INTEGRITY_PROTECTION_CMD",
"4E12" => "CALIBRATION_INTEGRITY_PROTECTION_RSP",
"6E13" => "UWB_WLAN_COEX_NTF",
# "6E14" => "UWB_WLAN_COEX_DATA_NTF",
# "6E15" => "UWB_WLAN_COEX_EXCEPTION_NTF",
"2E1C" => "TEST_NOISE_POWER_CMD",
"4E1C" => "TEST_NOISE_POWER_RSP",
"6E1C" => "TEST_NOISE_POWER_NTF",
"6E19" => "TRIGGER_HW_SECURITY_CHECK_ERROR_NTF",
"2E1A" => "SET_GPIO_PIN_STATE_CMD",
"4E1A" => "SET_GPIO_PIN_STATE_RSP",
"2E1B" => "GET_GPIO_PIN_STATE_CMD",
"4E1B" => "GET_GPIO_PIN_STATE_RSP",
"2E2B" => "SET_RDS_CMD",
"4E2B" => "SET_RDS_RSP",
"6E2B" => "SET_RDS_NTF",
"6E0C" => "SE_COMM_DATA_NTF",
# Proprietary Group 2
"2F00" => "SET_VENDOR_APP_CONFIG_CMD",
"4F00" => "SET_VENDOR_APP_CONFIG_RSP",
"2F01" => "URSK_DELETE_CMD",
"4F01" => "URSK_DELETE_RSP",
"6F01" => "URSK_DELETE_NTF",
"2F02" => "GET_ALL_UWB_SESSIONS_CMD",
"4F02" => "GET_ALL_UWB_SESSIONS_RSP",
"2F03" => "GET_VENDOR_APP_CONFIG_CMD",
"4F03" => "GET_VENDOR_APP_CONFIG_RSP",
"2F20" => "DO_CHIP_CALIBRATION_CMD",
"4F20" => "DO_CHIP_CALIBRATION_RSP",
"6F20" => "DO_CHIP_CALIBRATION_NTF",
"2F21" => "SET_DEVICE_CALIBRATION_CMD",
"4F21" => "SET_DEVICE_CALIBRATION_RSP",
"2F22" => "GET_DEVICE_CALIBRATION_CMD",
"4F22" => "GET_DEVICE_CALIBRATION_RSP",
"2F30" => "UWB_ESE_CONNECTIVITY_CMD",
"4F30" => "UWB_ESE_CONNECTIVITY_RSP",
"6F30" => "UWB_ESE_CONNECTIVITY_NTF",
"2F31" => "UWB_ESE_BINDING_CMD",
"4F31" => "UWB_ESE_BINDING_RSP",
"6F31" => "UWB_ESE_BINDING_NTF",
"2F32" => "UWB_ESE_BINDING_CHECK_CMD",
"4F32" => "UWB_ESE_BINDING_CHECK_RSP",
"6F32" => "UWB_ESE_BINDING_CHECK_NTF",
"6F33" => "PSDU_LOG_NTF",
"6F34" => "CIR_LOG_NTF",
# Proprietary Group 3
"690A" => "RADAR_RX_NTF",

# NXP Internal group
"6B22" => "DBG_RFRAME_LOG_NTF",
);

###################### STATUS CODE ####################################
my %status_code = (
# Generic Status Codes
"00" => "Ok",
"01" => "Rejected",
"02" => "Failed",
"03" => "Syntax error",
"04" => "Invalid param",
"05" => "Invalid range",
"06" => "Invalid message size",
"07" => "Unknown group id",
"08" => "Unknown opcode id",
"09" => "Read only",
"0A" => "UCI message retry",
"0B" => "Unknown",
"0C" => "Not applicable",
# UWB Session Specific Status Codes
"11" => "Session not exist",
"12" => "Session duplicated",
"13" => "Session active",
"14" => "Max sessions exceeded",
"15" => "Session not configured",
"16" => "Active sessions ongoing",
"17" => "Multicast list full",
"1A" => "Error UWB init time too old",
"1B" => "OK BUT Negative distance reported",
# UWB Ranging Session Specific Status Codes
"20" => "Ranging tx failed",
"21" => "Ranging rx timeout",
"22" => "Ranging rx phy dec failed",
"23" => "Ranging rx phy toa failed",
"24" => "Ranging rx phy sts failed",
"25" => "Ranging rx mac dec failed",
"26" => "Ranging rx mac ie dec failed",
"27" => "Ranging rx mac ie missing",
"28" => "Round index not activated",
"29" => "Error Number of active ranging round exceeded",
"2A" => "Error DL TDoA device address not matching in reply time list",
# Proprietary Status Codes
"53" => "Calibration in progress",
"54" => "Device temp reached thermal runway",
"55" => "Feature not supported",
"56" => "NUM_PACKET excceds 1000 for TEST_PER_RX",
"57" => "Calibration not configured",
"81" => "Ranging PHY RX SEC decoder failed",
"82" => "Ranging PHY RX RS decoder failed",
"83" => "Ranging PHY RX decode chain failed",
"84" => "Ranging PHY RX error failed",
"85" => "Ranging PHY RX PHR decoder failed",
"86" => "Ranging PHY RX SYNC or SFD timeout",
"87" => "Ranging PHY RX PHR data rate error",
"88" => "Ranging PHY RX PHR ranging error",
"89" => "Ranging PHY RX PHR preamble duration error",
"8A" => "STATUS_MAX_ACTIVE_GRANT_DURATION_EXCEEDED",
);
my %status_data_transfert_code = (
"00" => "OK Repetition",
"01" => "OK TWR sessions",
"02" => "Error Data Transfer",
"03" => "Error no credit available",
"04" => "Error rejected",
"05" => "Error session type not supported",
"06" => "Error data transfer is ongoing",
"07" => "Invalid format",
);
my %ccc_ranging_status = (
"0" => "Success",
"1" => "Timestamp overflow",
"2" => "Transaction took too long and expired",
"7" => "Frame too long",
"8" => "Unavailable key",
"9" => "Secure ranging mode not supported",
"D" => "Ranging mode not supported",
"F" => "Ranging Control Message Lost",
);
# propietary status code
my %se_status_code = (
"70" => "No SE",
"72" => "SE recoveru failure",
"73" => "SE recovery success",
"74" => "SE APDU CMD fail",
"75" => "SE authentication fail",
);
# ll status code
my %ll_status_code = (
"00" => "REMOTE",
"01" => "TIME_OUT",
"02" => "TRANSMISSION_ERROR",
"03" => "SECURE_COMPONENT",
"04" => "UNKNOWN_REASON",
"05" => "Host initiated",
);
# ll layer mode
my %ll_layer_mode = (
"00" => "Connection-less Non-Secure",
"01" => "Connection-less Secure",
"02" => "Connection-oriented Non-Secure",
"03" => "Connection-oriented Secure",
"04" => "Connection-less UWBS-UWBS",
"05" => "Connection-oriented UWBS-UWBS",
"B0" => "NXP_PROPRIETARY"
);
#######################################################################

# Device Configuration parameters
my %devparam = (
# Device Information Configurations
"00" => "DEVICE_STATE",
"01" => "LOW_POWER_MODE",
);

# Device Information Proprietary E3 parameters
my %devparam_E3 = (
"00" => "DEVICE_NAME",
"01" => "FIRMWARE_VERSION",
"02" => "PLL_VCO_CODE",
"03" => "NXP_UCI_VERSION",
"04" => "FW_BOOT_MODE",
);

# Device Capability parameters
my %capaparam = (
"00" => "MAX_DATA_MESSAGE_SIZE",
"01" => "MAX_DATA_PACKET_PAYLOAD_SIZE",
"02" => "FIRA_PHY_VERSION_RANGE",
"03" => "FIRA_MAC_VERSION_RANGE",
"04" => "DEVICE_TYPE",
"05" => "DEVICE_ROLES",
"06" => "RANGING_METHOD",
"07" => "STS_CONFIG",
"08" => "MULTI_NODE_MODE",
"09" => "RANGING_TIME_STRUCT",
"0A" => "SCHEDULE_MODE",
"0B" => "HOPPING_MODE",
"0C" => "BLOCK_STRIDING",
"0D" => "UWB_INITIATION_TIME",
"0E" => "CHANNELS",
"0F" => "RFRAME_CONFIG",
"10" => "CC_CONSTRAINT_LENGTH",
"11" => "BPRF_PARAMETER_SETS",
"12" => "HPRF_PARAMETER_SETS",
"13" => "AOA_SUPPORT",
"14" => "EXTENDED_MAC_ADDRESS",
"15" => "SUSPEND_RANG_SUPPORT",
"16" => "SESSION_KEY_LENGTH",
"17" => "DT_ANCHOR_MAX_ACTIVE_RR",
"18" => "DT_TAG_MAX_ACTIVE_RR",
"19" => "DT_TAG_BLOCK_SKIPPING",
"1A" => "PSDU_LENGTH_SUPPORT",
# SPEC CCC
"A0" => "SLOT_BITMASK",
"A1" => "SYNC_CODE_INDEX_BITMASK",
"A2" => "HOPPING_CONFIG_BITMASK",
"A3" => "CHANNEL_BITMASK",
"A4" => "SUPPORTED_PROTOCOL_VERSION",
"A5" => "SUPPORTED_UWB_CONFIG_ID",
"A6" => "SUPPORTED_PULSESHAPE_COMBO",
);

# Device Capability Proprietary E3 parameters
my %capaparam_E3 = (
"00" => "UWBS_MAX_UCI_PAYLOAD_LENGTH",
"01" => "UWBS_INBAND_DATA_BUFFER_BLOCK_SIZE",
"02" => "UWBS_INBAND_DATA_MAX_BLOCKS",
);

# Device Configuration Proprietary E4 parameters
my %devparam_E4 = (
"02" => "DPD_WAKEUP_SRC",
"03" => "WTX_COUNT_CONFIG",
"04" => "DPD_ENTRY_TIMEOUT",
"05" => "WIFI_COEX_FEATURE",
"06" => "GPIO_SELECTION_FOR_DUAL_AOA",
"07" => "SESSION_HANDLE_EN",
"26" => "TX_BASE_BAND_CONFIG",
"27" => "DDFS_TONE_CONFIG",
"28" => "TX_PULSE_SHAPE_CONFIG",
"3A" => "CLK_CONFIG_CTRL",
"31" => "HOST_MAX_UCI_PAYLOAD_LENGTH",
"32" => "UWB_CH5_WLAN_CHANNEL_INTERFERENCE_LIST",
"33" => "NXP_EXTENDED_NTF_CONFIG",
"34" => "CLOCK_PRESENT_WAITING_TIME",
"35" => "INITIAL_RX_ON_OFFSET_ABS",
"36" => "INITIAL_RX_ON_OFFSET_REL",
"46" => "PDOA_CALIB_TABLE_DEFINE",
"60" => "ANTENNA_RX_IDX_DEFINE",
"61" => "ANTENNA_TX_IDX_DEFINE", # SR1x0
"62" => "ANTENNAS_RX_PAIR_DEFINE",
"63" => "ANTENNA_TX_IDX_DEFINE_SR2x",  # SR2x0
"65" => "DEFAULT_SESSION_VENDOR_APP_CONFIG",
"40" => "AOA_CALIB_CTRL_RX_ANT_PAIR_1_CH5",
);

# Application Configuration parameters
my %appparam = (
"00" => "DEVICE_TYPE",
"01" => "RANGING_ROUND_USAGE",
"02" => "STS_CONFIG",
"03" => "MULTI_NODE_MODE",
"04" => "CHANNEL_NUMBER",
"05" => "NUMBER_OF_CONTROLEES",
"06" => "DEVICE_MAC_ADDRESS",
"07" => "DST_MAC_ADDRESS",
"08" => "SLOT_DURATION",
"09" => "RANGING_DURATION",
"0A" => "STS_INDEX",
"0B" => "MAC_FCS_TYPE",
"0C" => "RANGING_ROUND_CONTROL",
"0D" => "AOA_RESULT_REQ",
"0E" => "SESSION_INFO_NTF_CONFIG",
"0F" => "NEAR_PROXIMITY_CONFIG",
"10" => "FAR_PROXIMITY_CONFIG",
"11" => "DEVICE_ROLE",
"12" => "RFRAME_CONFIG",
"13" => "RSSI_REPORTING",
"14" => "PREAMBLE_CODE_INDEX",
"15" => "SFD_ID",
"16" => "PSDU_DATA_RATE",
"17" => "PREAMBLE_DURATION",
"18" => "LINK_LAYER_MODE",
"19" => "DATA_REPETITION_COUNT",
"1A" => "RANGING_TIME_STRUCT",
"1B" => "SLOTS_PER_RR",
"1C" => "RFU",
"1D" => "AOA_BOUND_CONFIG",
"1E" => "RFU",
"1F" => "PRF_MODE",
"20" => "CAP_SIZE_RANGE",
"21" => "TX_JITTER_WINDOW_SIZE",
"22" => "SCHEDULED_MODE",
"23" => "KEY_ROTATION",
"24" => "KEY_ROTATION_RATE",
"25" => "SESSION_PRIORITY",
"26" => "MAC_ADDRESS_MODE",
"27" => "VENDOR_ID",
"28" => "STATIC_STS_IV",
"29" => "NUMBER_OF_STS_SEGMENTS",
"2A" => "MAX_RR_RETRY",
"2B" => "UWB_INITIATION_TIME",
"2C" => "HOPPING_MODE",
"2D" => "BLOCK_STRIDE_LENGTH",
"2E" => "RESULT_REPORT_CONFIG",
"2F" => "IN_BAND_TERMINATION_ATTEMPT_COUNT",
"30" => "SUB_SESSION_ID",
"31" => "BPRF_PHR_DATA_RATE",
"32" => "MAX_NUMBER_OF_MEASUREMENTS",
"33" => "??",
"34" => "??",
"35" => "STS_LENGTH",
"36" => "??",
"37" => "??",
"38" => "??",
"39" => "??",
"3A" => "MIN_FRAMES_PER_RR",
"3B" => "MTU_SIZE",
"3C" => "INTER_FRAME_INTERVAL",
"3D" => "DL_TDOA_RANGING_METHOD",
"3E" => "DL_TDOA_TX_TIMESTAMP_CONF",
"3F" => "DL_TDOA_HOP_COUNT",
"40" => "DL_TDOA_ANCHOR_CFO",
"41" => "DL_TDOA_ANCHOR_LOCATION",
"42" => "DL_TDOA_TX_ACTIVE_RANGING_ROUNDS",
"43" => "DL_TDOA_BLOCK_STRIDING",
"44" => "DL_TDOA_TIME_REFERENCE_ANCHOR",
"45" => "SESSION_KEY",
"46" => "SUB_SESSION_KEY",
"47" => "SESSION_DATA_TRANSFER_STATUS_NTF_CONFIG",
"48" => "SESSION_TIME_BASE",
"49" => "DL_TDOA_RESPONDER_TOF",
"4A" => "SECURE_RANGING_NEFA_LEVEL",
"4B" => "SECURE_RANGING_CSW_LENGTH",
"4C" => "APPLICATION_DATA_ENDPOINT",
"4D" => "OWR_AOA_MEASUREMENT_NTF_PERIOD",
########## CCC ##########
"A0" => "HOP_MODE_KEY",
"A1" => "CCC_CONFIG_QUIRKS",
"A2" => "RESPONDER_SLOT_INDEX",
"A3" => "RANGING_PROTOCOL_VER",
"A4" => "UWB_CONFIG_ID",
"A5" => "PULSESHAPE_COMBO",
"A6" => "URSK_TTL",
"A7" => "RESPONDER_LISTEN_ONLY",
"A8" => "LAST_STS_INDEX_USED",
);

# Test Configuration parameters
my %testparam = (
"00" => "NUM_PACKETS",
"01" => "T_GAP",
"02" => "T_START",
"03" => "T_WIN",
"04" => "RANDOMIZE_PSDU",
"05" => "PHR_RANGING_BIT",
"06" => "RMARKER_TX_START",
"07" => "RMARKER_RX_START",
"08" => "STS_INDEX_AUTO_INCR",
"09" => "STS_DETECT_BITMAP_EN",
);

# Test Configuration Proprietary E5 parameters
my %testparam_E5 = (
# Test Configuration
"01" => "RSSI_CALIBRATION_OPTION",
"02" => "AGC_GAIN_VAL_RX",
"03" => "TEST_SESSION_STS_KEY_OPTION",
);


# Device Reset
my %dev_reset = (
"00" => "UWBD reset",
);

# Device Status
my %dev_status = (
"00" => "STATUS_INIT",
"01" => "STATUS_READY",
"02" => "STATUS_ACTIVE",
"FE" => $red_oops."STATUS_HW_RESET",
"FF" => $red_oops."STATUS_ERROR",
);

# FW Boot mode
my %fw_boot_mode= (
"00" => "Factory mode",
"01" => "User mode",
);

# Session Types
my %session_type = (
"00" => "Ranging session (no in-band data)",
"01" => "Ranging and in-band data session",
"02" => "Data Transfer session",
"03" => "Ranging only phase",
"04" => "Inband data phase",
"05" => "Ranging with data phase",
#vendor session type
"A0" => "CCC Ranging session",
"A2" => "Aliro Ranging session",
"B0" => "Data Transfer session",
"D0" => "Device test mode",
"F0" => "Radar",
"9F" => "HUS Primary Session"
);

# Session State
my %session_state = (
"00" => "Session initialized",
"01" => "Session deinitialized",
"02" => "Session active",
"03" => "Session idle",
);

# Session Reason
my %session_reason = (
########## FIRA ##########
"00" => "State change with session management commands",
"01" => "Max ranging round retry count reached",
"02" => "Max number of measurements reached",
"05" => "Stopped due to Inband Signal",
"1E" => "Error min Rframes per RR not supported",
"1F" => "Error inter Frame interval not supported",
"20" => "Error slot length not supported",
"21" => "Error insufficient slots per RR",
"22" => "Error MAC address mode not supported",
"23" => "Error invalid ranging interval",
"24" => "Error invalid STS configuration",
"25" => "Error invalid RFrame configuration",
"26" => "Error PRF Mode BPRF invalid PREAMBLE_CODE_INDEX",
"27" => "Error PRF Mode BPRF invalid SFD_ID",
"28" => "Error PRF Mode BPRF invalid PSDU_DATA_RATE",
"29" => "Error PRF Mode BPRF invalid PREAMBLE_DURATION",
"2A" => "Error Session Key not found",
"2B" => "Error Sub Session Key not found",
"2C" => "Error Invalid Preamble Code Index",
"2D" => "Error Invalid SFD_ID",
"2E" => "Error Invalid PSDU_DATA_RATE",
"2F" => "Error Invalid PHR_DATA_RATE",
"30" => "Error PREABLE_DURATION",
"31" => "Error STS_LEN",
"32" => "Error NUM_OF_STS_SEGMENTS",
"33" => "Error NUM_OF_CONTROLEES",
"34" => "Error MAX_RANGING_REPLY time exceeded",
"35" => "Error invalid DST_ADDRESS list",
"36" => "Error invalid or not found SUB_SESSION_ID",
"37" => "Error invalid RESULT_REPORT_CONFIG",
"38" => "Error invalid RANGING_ROUND_CONTROL confi",
"39" => "Error invalid RANGING_ROUND_USAGE",
"3A" => "Error invalid MULTI_NODE_MODE",
"3B" => "Error RDS fetch failure",
"3C" => "Error ref UWB_SESSION does not exist",
"3D" => "Error ref UWB_SESSION RANGING_DURATION mismatch",
"3E" => "Error ref UWB_SESSION invalid OFFSET_TIME",
"3F" => "Error ref UWB_SESSION lost",
"40" => "Error DT_ANCHOR RANGING_ROUNDS not configured",
"41" => "Error DT_TAG RANGING_ROUNDS not configured",
########## SPEC SR200 ##########
"80" => "Error invalid ANTENNA_CFG",
"81" => "Error invalid RX_MODE",
"82" => "Error fail DYNAMIC_STS not allowed",
"83" => "Error feature not supported for Model",
"84" => "Error RX_MODE TOA_MODE mismatch",
"85" => "Error insufficient memory for INBAND_DATA",
"86" => "Error invalid DATA_TRANSFER_MODE",
"87" => "Error invalid MAC_CFG",
"88" => "Error ANTENNA_DEFINES not configured",
"89" => "Error invalid MAX_TDOA session count reached",
"8A" => "Error LOOPBACK_MODE_TX_POWER too high",
"8B" => "Error wrong SESSION_TYPE for INBAND_DATA",
"8C" => "Error AoA not supported in SINGLE_RX",
"8D" => "Error dupplicate DST_MAC_ADDRESS detected",
"8E" => "Error invalid ADAPTIVE_HOPPING_THRESHOLD",
"8F" => "Error unsupported RANGING_LIMIT",
"90" => "Error invalid HOPPING_MODE",
"91" => "Error rng invalid DEVICE_ROLE",
"92" => "Error KEY_ROTATION not supported",
"93" => "Error TEST_KDF not supported",
"A0" => "Error URSK_TTL max value reached",
"A1" => "Error CCC termination on MAX_STS_INDEX",
"A2" => "Error session stopped due to FCC limit reached",
"B0" => "Error radar CIR_MAX_TAP_IDX exceeded",
"B1" => "Error radar ANTENNA_CONFIG_RX not OK",
"B2" => "Error radar Presence detection Range EXCEEED",
"B3" => "Error radar RX_GAIN_INDEX not OK",
"B4" => "Error radar drift compensation ANTENNA_CONFIG not OK",
);

# Session Update Action
my %update_action = (
"00" => "Add controlee short address",
"01" => "Delete controlee short address",
"02" => "Add controlee with its 16-octet Sub-Session Key to multicast list",
"03" => "Add controlee with its 32-octet Sub-Session Key to multicast list",
);

# Session Update Status
my %update_status = (
"00" => "OK Multicast list update",
"01" => $red_oops."Error multicast list full",
"02" => $red_oops."Error key fetch fail",
"03" => $red_oops."Error sub-session ID not found",
"04" => $red_oops."Error sub-session KEY not found",
"05" => $red_oops."Error sub-session KEY not applicable",
"06" => $red_oops."Error session KEY not found",
"07" => $red_oops."Error address not found",
"08" => $red_oops."Error address already present",
);

# Device Role
my %device_role = (
"00" => "Responder",
"01" => "Initiator",
"02" => "Master Anchor",
"03" => "Initiator & Responder",
"04" => "Receiver",
);

# RCR Indications
my %rcr_indication = (
"00" => "No RCR is sent/received",
"01" => "RCR is sent/received in current ranging round",
);

# Ranging Measurement Type
my %ranging_measurement_type = (
"00" => "One Way Ranging Measurement (TDoA)",
"01" => "Two Way Ranging Measurement (SS-TWR, DS-TWR)",
"02" => "Downlink TDoA Measurement",
"03" => "OWR for AoA Measurement",
);

# Wifi-CoEx Status Code
my %wifi_coex_status_code = (
"00" => "Medium Grant Request rejected",
"01" => "Medium Grant Request accepted",
"02" => "Medium Grant Request timeout",
"03" => "BREAK Condition is set",
"04" => "BREAK Condition is released",
"05" => "NBIC is enabled",
"06" => "NBIC is disabled",
"07" => "UART busy",
);

# Frame Type
my %frame_type = (
"00" => "BLINK",
"01" => "SYNC",
);

# Message Type
my %message_type = (
"00" => "Poll DTM",
"01" => "Response DTM",
"02" => "Final DTM",
);

# Line of Sight Type
my %los_type = (
"00" => "LoS",
"01" => "NLos",
"FF" => "Undet",
);

# Radar Data Type
my %radar_data_type = (
"00" => "CIR samples",
"01" => "Presence Detection",
"20" => "Antenna Isolation Report",
"21" => "LPRF Calibration Report",
);

# OCPD status
my %ocpd_status = (
"00" => "No presence detected",
"01" => "Presence detected",
);

# OCPD periodic report
my %ocpd_periodic_report = (
0 => "No periodic report",
1 => "Every 50ms",
2 => "Every 400ms",
3 => "Every 1600ms",
);

# Variant parameters
my %variant = (
"0000" => "Default value",
"0101" => "Board variant NXPREF v1",
"0102" => "Board variant NXPREF v2",
"2A03" => "Board variant Custom v3",
"7301" => "Board variant Rhodes v1",
"7302" => "Board variant Rhodes v2",
"7304" => "Board variant Rhodes v4",
);

# Binding State
my %binding_state = (
"00" => "No bound",
"01" => "Bound, unlocked",
"02" => "Bound, locked",
"03" => "Unknown",
);

# Exception Type
my %exception_type = (
"01" => "Hard Fault",
"02" => "Bus Fault",
"04" => "Secure Fault",
"08" => "Usage Fault",
"10" => "Watchdog",
"20" => "CoolFlux Fault",
"40" => "Assert Fault log",
);

# RF RX Test
my %rf_rx_test = (
"01" => "Hard Fault",
"02" => "Bus Fault",
"04" => "Secure Fault",
"08" => "Usage Fault",
"10" => "Watchdog",
"20" => "CoolFlux Fault",
"40" => "Assert Fault log",
);

# RFrame Dec Status
my %rframe_dec_status = (
"00" => "Signal acquisition failed",
"01" => "Single Error Correction decoding failed",
"02" => "Reed Solomon decoding failed",
"03" => "Generic error for packet decode failure",
"04" => "Packet decode success",
"05" => "No data frame received",
"06" => "Generic receive error",
"07" => "Generir error for STS mismatch failure",
"08" => "ToA detect failure",
"09" => "PHR decoding failure",
"0A" => "Sync or start frame delimiter is not received",
"0B" => "PHR data rate error",
"0C" => "PHR ranging error",
"0D" => "RX PUR preamble duration error"
);

# Binding available
my %binding_available = (
"00" => "Valid binding not available",
"01" => "Valid binding is available",
);

# Binding Status
my %binding_status = (
"00" => "Success",
"01" => "KO_BIND",
"02" => "KO_COUNT",
"74" => "APDU command rejected by eSE",
"75" => "Authentication eSE failed",
);

# Binding Status Check
my %binding_status_check = (
"00" => "Not bound",
"01" => "Bound, unlocked",
"02" => "Bound, locked",
"03" => "Unknown",
);

# SE Test Loop Status
my %se_test_loop_status = (
"00" => "Success",
"01" => "Test not present",
"FF" => "Error",
);

# SE Test Loop result
my %se_test_loop_result = (
"00" => "Test completed",
"01" => "Test aborted",
);

# SE Test Connectivity
my %se_test_connectivity_status = (
"00" => "Success",
"01" => "SE error",
"02" => "Infinite WTX (> WTX Max count)",
"03" => "I2C Write fail between UWB and eSE",
"04" => "I2C Read fail with IRQ Low (I2C NACK)",
"05" => "I2C Read fail with IRQ High (I2C NACK)",
"06" => "I2C timed out on communication",
"07" => "I2C Write timed out with IRQ High",
);

# Set Calibration parameter
my %set_calibration_param = (
"00" => "VCO_PLL",
"01" => "TX_POWER",
"02" => "38.4MHz_XTAL_CAP_GM_CTRL",
"03" => "RSSI_CALIB_CONSTANT1",
"04" => "RSSI_CALIB_CONSTANT2",
"05" => "SNR_CALIB_CONSTANT",
"06" => "MANUAL_TX_POW_CTRL",
"07" => "PDOA1_OFFSET",
"08" => "PA_PPA_CALIB_CTRL",
"09" => "TX_TEMPERATURE_COMP",
"0A" => "PDOA2_OFFSET",
"0B" => "AOA_MULTIPOINT_CALIB",
"0C" => "AOA_ANTENNAS_PDOA_CALIB",
"0D" => "AOA_ANTENNAS_MULTIPOINT_CALIB",
"0F" => "RX_ANT_DELAY_CALIB",
"10" => "PDOA_OFFSET_CALIB",
"11" => "PDOA_MANUFACT_ZERO_OFFSET_CALIB",
"12" => "AOA_THRESHOLD_PDOA",
"13" => "RSSI_CALIB_CONSTANT_HIGH_PWR",
"14" => "RSSI_CALIB_CONSTANT_LOW_PWR",
"15" => "SNR_CALIB_CONSTANT_PER_ANTENNA",
"17" => "TX_POWER_PER_ANTENNA",
"18" => "TX_TEMPERATURE_COMP_PER_ANTENNA",
);

# Calibration state
my %calibration_state = (
"00" => "Default value",
"01" => "Not integrity protected",
"02" => "Integrity check is pending",
"03" => "Integrity check is verified by Device specific tag",
"04" => "Integrity check is verified by Model specific tag",
);

# Scheduler Status
my %scheduler_status = (
"00" => "Success",
"01" => "Cannot schedule",
"02" => "Sync failure",
);

# KDF parameter
my %kdf_param = (
"00" => "KDF_BLOCK_INDEX",
"01" => "KDF_STS_INDEX",
"02" => "KDF_CONFIG_DIGEST",
"03" => "KDF_DERIVED_AUTH_IV",
"04" => "KDF_DERIVED_AUTH_KEY",
"05" => "KDF_DERIVED_PAYLOAD_KEY",
"06" => "KDF_FIRA_DATA_PROTECTION_KEY",
"08" => "KDF_FIRA_PRIVACY_KEY",
"09" => "KDF_FIRA_NOTIFICATION_KEY",
);

# WLAN UWB IND Status
my %wlan_uwb_ind_status = (
"00" => "WLAN UWB IND High at RR start",
"01" => "WLAN UWB IND High during RR",
);

# Do Calibration parameter
my %do_calibration_param = (
"00" => "VCO PLL",
"01" => "PA PPA CALIB CTRL",
);

# Tag option
my %tag_option = (
"00" => "Device specific tag",
"01" => "Model specific tag",
);

# Interface
my %interface = (
"00" => "I2C interface (eSE)",
);

# Interface Status
my %interface_status = (
"00" => "I2C interface is Idle",
"01" => "I2C interface is Busy",
);

# URSK Deletion Status
my %ursk_deletion_status = (
"00" => "RDS removed successfully",
"01" => "RDS not found",
"02" => "Interface error encountered",
);

# Endpoint
my %endpoint = (
"00" => "UWBS",
"01" => "Host connected to UWBS",
"02" => "Secure Component connected to UWBS",
);

# Data Transfert Status
my %data_transfert_status = (
"00" => "Ok",
"01" => "Unrecoverable error",
"02" => "No credit available",
"03" => "Rejected",
);

# Data Reception Status
my %data_reception_status = (
"00" => "Success",
"01" => "Error",
"02" => "Unknown",
);

# SET VENDOR APP CONFIG
my %set_vendor_app_config = (
"00" => "MAC_PAYLOAD_ENCRYPTION",
"02" => "ANTENNAS_CONFIGURATION_TX",
"03" => "ANTENNAS_CONFIGURATION_RX",
"20" => "RAN_MULTIPLIER",
"21" => "STS_LAST_INDEX_USED",
"30" => "CIR_LOG_NTF",
"31" => "PSDU_LOG_NTF",
"40" => "RSSI_AVG_FILT_CNT",
"60" => "CIR_CAPTURE_MODE",
"61" => "RX_ANTENNA_POLARIZATION_OPTION",
"62" => "SESSION_SYNC_ATTEMPTS",
"63" => "SESSION_SHED_ATTEMPTS",
"64" => "SCHED_STATUS_NTF",
"65" => "TX_POWER_DELTA_FCC",
"66" => "TEST_KDF_FEATURE",
"67" => "TX_POWER_TEMP_COMPENSATION",
"68" => "WIFI_COEX_MAX_TOLERANCE_COUNT",
"69" => "ADAPTIVE_HOPPING_THRESHOLD",
"6D" => "CONTENTION_PHASE_UPDATE_LENGTH",
"6E" => "AUTHENTICITY_TAG",
"6F" => "RX_NBIC_CONFIG",
"70" => "MAC_CFG",
"71" => "SESSION_INBAND_DATA_TX_BLOCKS",
"72" => "SESSION_INBAND_DATA_RX_BLOCKS",
"74" => "ANTENNAS_SCAN_CONFIGURATION",
"75" => "DATA_TRANSFER_TX_STATUS_CONFIG",
"76" => "ULTDOA_MAC_FRAME_FORMAT",
"7A" => "DATA_LOGGER_NTF", # HELIOS 1 != 2
"7B" => "RFRAME_LOG_NTF",
"7C" => "TEST_CONTENTION_RANGING_FEATURE",
"7D" => "CIR_CAPTURE_WINDOW",
"7E" => "RANGING_TIMESTAMP_NTF",
"7F" => "TX_ADAPTIVE_PAYLOAD_POWER",
"80" => "SWAP_ANTENNA_PAIR_3D_AOA",
"82" => "CSA_MAC_MODE",
"83" => "CSA_ACTIVE_RR_CONFIG",
"9E" => "EPOCH_TIME",
"9F" => "SET_USECASE_ID",
"A0" => "RADAR_MODE",
"A4" => "RADAR_RX_GAIN",
"A5" => "RADAR_SINGLE_FRAME_NTF",
"A7" => "RADAR_CIR_NUM_SAMPLES",
"A8" => "RADAR_CIR_START_OFFSET",
"A9" => "RADAR_RFRI",
"AA" => "RADAR_PRESENCE_DET_CFG",
"AD" => "RADAR_PERFORMANCE",
"B2" => "RADAR_DRIFT_COMPENSATION",
"B3" => "RADAR_CONFIG",
"D0" => "THREAD_SECURE",
"D1" => "THREAD_SECURE_ISR",
"D2" => "THREAD_NON_SECURE_ISR",
"D3" => "THREAD_SHELL",
"D4" => "THREAD_PHY",
"D5" => "THREAD_RANGING",
"D6" => "THREAD_SECURE_ELEMENT",
"D7" => "THREAD_UWB_WLAN_COEX",
);

my %CIR_MODE = (
"0" => "SYNC",
"1" => "STS",
"2" => "SYNC & STS",
);

my %CALIBRATION_PARAMETERS = (
"00" => "CHIP_CALIBRATION",
"01" => "RF_CLK_ACCURACY_CALIB",
"02" => "RX_ANT_DELAY_CALIB",
"03" => "PDOA_OFFSET_CALIB",
"04" => "TX_POWER_PER_ANTENNA",
"05" => "AOA_PHASEFLIP_ANTSPACING",
"5C" => "PLATFORM_ID",
"5D" => "CONFIG_VERSION",
"60" => "MANUAL_TX_POW_CTRL",
"62" => "AOA_ANTENNAS_PDOA_CALIB",
"64" => "TX_ANT_DELAY_CALIB",
"65" => "PDOA_MANUFACT_ZERO_OFFSET_CALIB",
"66" => "AOA_THRESHOLD_PDOA",
"67" => "TX_TEMPERATURE_COMP_PER_ANTENNA",
"68" => "SNR_CALIB_CONSTANT_PER_ANTENNA",
"69" => "RSSI_CALIB_CONSTANT_HIGH_PWR",
"6A" => "RSSI_CALIB_CONSTANT_LOW_PWR",
"80" => "TRA2_LOFT_CALIB",
"81" => "TRA1_LOFT_CALIB",
);

my %RXID_TO_RXANT = (
    "01" => "C",
    "02" => "B",
    "03" => "A2",
    "04" => "A1",
);

my %VENDOR_SPECIFIC_TYPE = (
    "00" => "Specific Data V1 for TWR",
    "A0" => "FoV Specific Data",
);

my %COEX_CONFIG_5G = (
    "00" => "NO COEX PROTOCOL",
    "01" => "ENABLED COEX PROTOCOL",
    "02" => "DISABLED COEX PROTOCOL",
    "04" => "ENABLED COEX PROTOCOL",
);

my %COEX_CONFIG_6E = (
    "00" => "ENABLED COEX PROTOCOL",
    "01" => "ENABLED COEX PROTOCOL",
    "02" => "ENABLED COEX PROTOCOL",
    "04" => "DISABLED COEX PROTOCOL",
);

my %WIFI_COEX_STATUS = (
    "00" => "WLAN_UWB_IND_LOW",
    "01" => "WLAN_UWB_IND_HIGH",
    "02" => "WLAN_UWB_IND_ERR",
);
my %AUTHENTICITY_INFO_PRESENCE = (
    "00" => "AUTHENTICITY_INFO_NOT_PRESENT",
    "01" => "AUTHENTICITY_INFO_PRESENT",
);

my %RX_MODE = (
    "00" => "ToA mode",
    "01" => "AoA mode",
    "02" => "Radar mode",
    "03" => "ToA RFM mode",
    "04" => "AoA RFM mode",
    "05" => "ToA CSA mode",
    "06" => "AoA CSA mode",
);

my %GPIO_DIRECTION = (
    "00" => "Pin direction input",
    "01" => "Pin direction output",
);

my %GPIO_VALUE = (
    "00" => "Set GPIO Pin state low",
    "01" => "Set GPIO Pin state high",
    "02" => "Hi-Z state",
);

my %CALIBRATION_PARAM_STATES = (
    "00" => "DEFAULT",
    "01" => "CUSTOM_NOT_INTEGRITY_PROTECTED",
    "02" => "CUSTOM_AUTH_PENDING",
    "03" => "CUSTOM_DEVICE_SPECIFIC_TAG_AUTHENTICATED",
    "04" => "CUSTOM_MODEL_SPECIFIC_TAG_AUTHENTICATED",
    "05" => "INVALID_STATE",
);

my %LINK_LAYER_SELECTOR = (
    "00" => "Connection-less Non-Secure",
    "01" => "Connection-less Secure",
    "02" => "Connection-oriented Non-Secure",
    "03" => "Connection-oriented Secure",
    "04" => "Connection-less UWBS-UWBS",
    "05" => "Connection-oriented UWBS-UWBS",
);


my %DTPCM_SLOT_BITMAP = (
    0 => 8,
    2 => 16,
    4 => 32,
    6 => 64,
    8 => 128,
    10 => 256,
    12 => 512,
    14 => 0,	
);

my %DTPCM_MAC_ADDRESS_MODE = (
    0 => "Short MAC",
    1 => "Ext MAC",
);

#########################################################################################
# Sub functions
#########################################################################################

#
# Print argument on terminal
# And write the argument without Escape sequences
#     in case of option '-decode=[file_name]'
#
sub imprime {
    
    print "<viki_start>\n" if ($tee);
    
    print @_;
    
    print "<viki_end>\n" if ($tee);
    
    if (defined $fh_decode) {
        foreach (@_) {s/\e\[[0-9;]*m//g};
        print $fh_decode @_;
    }
}

#
# Write the DBG messages without Escape sequences
#     in case of option '-dbg=[file_name]'
#
sub dbg_store {
    foreach (@_) {s/\e\[[0-9;]*m//g};
    print $fh_dbg @_;
}

#
# Print debug traces on terminal, with specifc debug color
#
sub debug_print {
    if ($disp_debug) {
        print $debug_color;
        print @_;
        print $nocolor."\n";
    }
}

#
# Test Configuration parameters
#

sub TestConfigParam {
    my $item = shift;
    my $value = shift;

    my $tmp;

    $decode .= $item.": ";
    # 00
    if ($item eq "NUM_PACKETS") {
        $tmp = hex(substr($value,6,2));
        $tmp = (256*$tmp)+hex(substr($value,4,2));
        $tmp = (256*$tmp)+hex(substr($value,2,2));
        $tmp = (256*$tmp)+hex(substr($value,0,2));
        $decode .= $tmp."   ";
    }
    # 01
    elsif ($item eq "T_GAP") {
        $tmp = hex(substr($value,6,2));
        $tmp = (256*$tmp)+hex(substr($value,4,2));
        $tmp = (256*$tmp)+hex(substr($value,2,2));
        $tmp = (256*$tmp)+hex(substr($value,0,2));
        $decode .= $value."us   ";
    }
    # 02
    elsif ($item eq "T_START") {
        $tmp = hex(substr($value,6,2));
        $tmp = (256*$tmp)+hex(substr($value,4,2));
        $tmp = (256*$tmp)+hex(substr($value,2,2));
        $tmp = (256*$tmp)+hex(substr($value,0,2));
        $decode .= $value."us   ";
    }
    # 03
    elsif ($item eq "T_WIN") {
        $tmp = hex(substr($value,6,2));
        $tmp = (256*$tmp)+hex(substr($value,4,2));
        $tmp = (256*$tmp)+hex(substr($value,2,2));
        $tmp = (256*$tmp)+hex(substr($value,0,2));
        $decode .= $value."us   ";
    }
    # 04
    elsif ($item eq "RANDOMIZE_PSDU") {
        $value = substr($value,0,2);
        if ($value eq "00") {
            $decode .= "No randomization   ";
        } elsif ($value eq "01") {
            $decode .= "1st byte used for seed   ";
        }
    }
    # 05
    elsif ($item eq "PHR_RANGING_BIT") {
        $value = substr($value,0,2);
        if ($value eq "00") {
            $decode .= "Disabled   ";
        } elsif ($value eq "01") {
            $decode .= "Enabled   ";
        }
    }
    # 06
    elsif ($item eq "RMARKER_TX_START") {
        $tmp = hex(substr($value,6,2));
        $tmp = (256*$tmp)+hex(substr($value,4,2));
        $tmp = (256*$tmp)+hex(substr($value,2,2));
        $tmp = (256*$tmp)+hex(substr($value,0,2));
        $decode .= $value."us   ";
    }
    # 07
    elsif ($item eq "RMARKER_RX_START") {
        $tmp = hex(substr($value,6,2));
        $tmp = (256*$tmp)+hex(substr($value,4,2));
        $tmp = (256*$tmp)+hex(substr($value,2,2));
        $tmp = (256*$tmp)+hex(substr($value,0,2));
        $decode .= $value."us   ";
    }
    # 08
    elsif ($item eq "STS_INDEX_AUTO_INCR") {
        $value = substr($value,0,2);
        if ($value eq "00") {
            $decode .= "Disabled   ";
        } elsif ($value eq "01") {
            $decode .= "Enabled   ";
        }
    }
    # 09
    elsif ($item eq "STS_DETECT_BITMAP_EN") {
        $value = substr($value,0,2);
        if ($value eq "00") {
            $decode .= "Not reported   ";
        } elsif ($value eq "01") {
            $decode .= "Reported   ";
        }
    }
    else {
        $decode .= "0x".$value."   ";
    }
}


#
# Decore UCI message
# And fill variables $msg and $decode
#
sub UciParser {
    my $is_truncated = 0;
    
    # Payload length
    $payload_length = hex(substr($frame,6,2));
    
    # Extended Payload length
    if (hex(substr($frame,2,2)) & 0x80) {
        $payload_length = (256*$payload_length)+hex(substr($frame,4,2));
    }
        
    my $payload = substr($frame,8);
    
    # Packet Boundary Flag
    my $pbf = hex(substr($frame,0,1)) & 0x01;
    
    # UCI parser according the Message Type (MT) and
    # the Group Identifer (GID) and the Opcode Identifier (OID) for Control packets
    # the Data Packet Format (DPF) for Data packets
    # Hide Packet Boundary Flag (PBF) and Extended Payload Length flag
    my $mt_dpf = sprintf("%0.2X",hex(substr($frame,0,2)) & 0xEF);
    my $mt_gid_oid = $mt_dpf.sprintf("%0.2X",hex(substr($frame,2,2)) & 0x3F);
    # Check message type
    if ($mt_gid_oid !~ /^0|2|4|6/) {
        $decode .= "   ".$red_oops."Unknown Message Type".$nocolor;
        
        # Exit UCI Parser
        return;
    }
    
	# Frame length is coded differently for data packet GID OID LSB MSB
	if ( ($mt_gid_oid eq "0200") or ($mt_gid_oid eq "0400")  or ($mt_gid_oid eq "0300")){
		$payload_length = 256*hex(substr($frame,6,2))+hex(substr($frame,4,2));
	}

	# Check Payload length
	if ($payload_length != ((length($frame)/2)-4)) {
		$decode .= "   ".$red_oops."Message length error !!!".$nocolor;
		$is_truncated = 1;
	}
	
    # Check if the Group Identifer / Opcode Identifier is in the table
    if (exists($uci_control_packet{$mt_gid_oid})) {
        # Formating of $msg
        if ($mt_gid_oid =~ /^2/) {
            # UCI command
            $msg = $turquoise."   -=(".$uci_control_packet{$mt_gid_oid}.")=-".$nocolor;
        }
        elsif ($mt_gid_oid =~ /^4/) {
            # UCI response
            $msg = $turquoise."   ++[".$uci_control_packet{$mt_gid_oid}."]++".$nocolor;
        }
        elsif ($mt_gid_oid =~ /^6/) {
            # UCI notification
            $msg = $turquoise."   {{".$uci_control_packet{$mt_gid_oid}."}}".$nocolor;
        }
        
        # Check segmentation
        if ($pbf == 1) {
            if ($seg_mt_gid_oid ne $mt_gid_oid) {
                $seg_mt_gid_oid = $mt_gid_oid;
                
                # Copy payload in Segment
                $seg_payload = $payload;
            } else {
                # Concatenate payload in Segment
                $seg_payload .= $payload;
            }
            
            $decode .= "   Segment".$nocolor;
                
            # Exit UCI Parser
            return;
        } elsif (($seg_payload ne "") and ($seg_mt_gid_oid eq $mt_gid_oid)) {
            # Complete Segment
            $payload = $seg_payload.$payload;
        
            # Clear Segment
            $seg_mt_gid_oid = "";
            $seg_payload = "";
        }
        
        debug_print "\nPayload:".$payload;

        #################### UCI Core Group ####################
        # CORE_DEVICE_RESET_CMD
        if ($mt_gid_oid eq "2000") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Reset Config
            $decode .= $brown."   ".($dev_reset{substr($payload,$byte_idx,2)} || "???");
            
            $decode .= $nocolor;
        }
        
        # CORE_DEVICE_RESET_RSP
        elsif ($mt_gid_oid eq "4000") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Reset Config
            $decode .= $brown."   ".($status_code{substr($payload,$byte_idx,2)} || "???");
            
            $decode .= $nocolor;
        }

        # CORE_DEVICE_STATUS_NTF
        elsif ($mt_gid_oid eq "6001") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Status
            $decode .= $brown."   ".($dev_status{substr($payload,$byte_idx,2)} || "???");
            
            $decode .= $nocolor;
        }

        # CORE_GET_DEVICE_INFO_CMD
        elsif ($mt_gid_oid eq "2002") {
            # NOTHING TO SHOW
        }

        # CORE_GET_DEVICE_INFO_RSP
        elsif ($mt_gid_oid eq "4002") {
            # Put Byte index after Status
            my $byte_idx = 0;

            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
            } else {
                $byte_idx += 2;

                $decode .= "\n".$indent.$brown;
                
                # UCI Generic Version
                $UciGenericVersion_Major = hex(substr($payload,$byte_idx,2));
                $UciGenericVersion_Minor = hex(substr($payload,$byte_idx+2,1));
                $UciGenericVersion_Patch = hex(substr($payload,$byte_idx+3,1));
                $byte_idx += 4;
                            
                $decode .= " UCI Generic ".$UciGenericVersion_Major.".".$UciGenericVersion_Minor.".".$UciGenericVersion_Patch;
                
                # MAC Version
                my $MacVersion_Major = hex(substr($payload,$byte_idx,2));
                my $MacVersion_Minor = hex(substr($payload,$byte_idx+2,1));
                my $MacVersion_Patch = hex(substr($payload,$byte_idx+3,1));
                $byte_idx += 4;
                
                $decode .= "   MAC ".$MacVersion_Major.".".$MacVersion_Minor.".".$MacVersion_Patch;
                
                # PHY Version
                my $PhyVersion_Major = hex(substr($payload,$byte_idx,2));
                my $PhyVersion_Minor = hex(substr($payload,$byte_idx+2,1));
                my $PhyVersion_Patch = hex(substr($payload,$byte_idx+3,1));
                $byte_idx += 4;
                
                $decode .= "   PHY ".$PhyVersion_Major.".".$PhyVersion_Minor.".".$PhyVersion_Patch;
                
                # UCI Test Version
                my $UciTestVersion_Major = hex(substr($payload,$byte_idx,2));
                my $UciTestVersion_Minor = hex(substr($payload,$byte_idx+2,1));
                my $UciTestVersion_Patch = hex(substr($payload,$byte_idx+3,1));
                $byte_idx += 4;
                
                $decode .= "   UCI Test ".$UciTestVersion_Major.".".$UciTestVersion_Minor.".".$UciTestVersion_Patch;
                
                # Manufacturer Specific Information
                my $vendor_specific_length = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
                $decode .= "\n".$indent.$brown;
                my $line_length = length($indent);
                
                if ($vendor_specific_length > 0) {
                    while ($byte_idx < (($vendor_specific_length+10)*2)) {
                        my $param_id = substr($payload,$byte_idx,2);
                        $byte_idx += 2;
                        if ($param_id eq "E3") {
                            $param_id = substr($payload,$byte_idx,2);
                            $byte_idx += 2;
                        }
                        
                        my $param_length = hex(substr($payload,$byte_idx,2));
                        $byte_idx += 2;

                        my $value;
                        
                        if ($param_id eq "00") {
                            # DEVICE_NAME
                            $value = "DEVICE_NAME: \"";
                            foreach (1..$param_length) {
                                my $char = hex(substr($payload,$byte_idx,2));
                                $byte_idx += 2;
                                
                                # Display only printable characters (0x20 - 0x7E)
                                if (($char >= 0x20) && ($char <= 0x7E)) {
                                    $value .= chr($char);
                                }
                            }
                            $Device_Name = $value;
                            $value .= "\"";
                        } elsif ($param_id eq "01") {
                            # FIRMWARE_VERSION
                            my $fw_version = substr($payload,$byte_idx,$param_length*2);
                            $byte_idx += $param_length*2;
                            
                            $value .= "FW: ".substr($fw_version,0,2).".".substr($fw_version,2,2);
                            $value .= " (RC ".substr($fw_version,4,2).")";
                        } elsif ($param_id eq "02") {
                            # VENDOR_UCI_VERSION
                            my $nxp_uci_version = substr($payload,$byte_idx,$param_length*2);
                            $byte_idx += $param_length*2;
                            
                            $value .= "NXP UCI: ".substr($nxp_uci_version,0,2).".".substr($nxp_uci_version,2,2).".".substr($nxp_uci_version,4,2);
                        } elsif ($param_id eq "03") {
                            # UWB_CHIP_ID
                            my $nxp_chip_id = substr($payload,$byte_idx,$param_length*2);
                            $byte_idx += $param_length*2;
                            
                            $value .= "NXP Chip ID: ".$nxp_chip_id;
                        } elsif ($param_id eq "04") {
                            # UWBS_MAX_PPM_VALUE
                            my $uwbs_max_ppm_value = substr($payload,$byte_idx,$param_length*2);
                            $byte_idx += $param_length*2;
                            
                            $value .= "UWBS Max PPM value: ".$uwbs_max_ppm_value;
                        } elsif ($param_id eq "05") {
                            # TX_POWER (Q9.7 format)
                            my $tx_power = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                            $tx_power -= 0x10000 if ($tx_power > 32767);
                            $tx_power = $tx_power/128;

                            $byte_idx += $param_length*2;

                            $value .= "Tx Power:".$tx_power." dBm";
                        } elsif ($param_id eq "06") {
                            # UWBS_CAL_MODE
                            my $uwbs_cal_mode = substr($payload,$byte_idx,$param_length*2);
                            $byte_idx += $param_length*2;

                            if ($uwbs_cal_mode eq "55555555") {
                                $value .= "UWBS Calibration Mode: Protected mode";
                            } elsif ($uwbs_cal_mode eq "A5A5A5A5") {
                                $value .= "UWBS Calibration Mode: Customer mode";
                            } else {
                                $value .= "UWBS Calibration Mode: ?".$uwbs_cal_mode."?";
                            }
                        } elsif ($param_id eq "60") {
                            # FIRA_EXT_UCI_GENERIC_VERSION
                            my $nxp_fira_uci_generic_version = substr($payload,$byte_idx,$param_length*2);
                            $byte_idx += $param_length*2;
                            
                            $value .= "NXP FIRA UCI Generic: ".hex(substr($nxp_fira_uci_generic_version,0,2));
                            $value .= ".".hex(substr($nxp_fira_uci_generic_version,2,2));
                            $value .= " (Patch ".hex(substr($nxp_fira_uci_generic_version,4,2)).")";
                        } elsif ($param_id eq "61") {
                            # FIRA_EXT_UCI_TEST_VERSION
                            my $nxp_fira_uci_test_version = substr($payload,$byte_idx,$param_length*2);
                            $byte_idx += $param_length*2;
                            
                            $value .= "NXP FIRA UCI Test: ".hex(substr($nxp_fira_uci_test_version,0,2));
                            $value .= ".".hex(substr($nxp_fira_uci_test_version,2,2));
                            $value .= " (Patch ".hex(substr($nxp_fira_uci_test_version,4,2)).")";
                        } elsif ($param_id eq "62") {
                            # UWBS_FW_GIT_HASH
                            my $uwbs_fw_git_hash = substr($payload,$byte_idx,$param_length*2);
                            $byte_idx += $param_length*2;
                            
                            $value .= "UWBS FW GIT HASH: ";
                            for (my $i=0; $i<34; $i+=2) {
                                my $char = hex(substr($uwbs_fw_git_hash,$i,2));
                                if (($char >= 0x20) && ($char <= 0x7E)) {
                                    $value .= chr($char);
                                }
                            }
                        } elsif ($param_id eq "63") {
                            # FW_BOOT_MODE
                            my $nxp_fw_boot = substr($payload,$byte_idx,$param_length*2);
                            $byte_idx += $param_length*2;
                            
                            $value .= "FW Boot:".($fw_boot_mode{$nxp_fw_boot} || "???");
                        } elsif ($param_id eq "A0") {
                            # UCI_CCC_VERSION
                            my $uci_ccc_ver = substr($payload,$byte_idx,$param_length*2);
                            $byte_idx += $param_length*2;
                            
                            $value .= "UCI CCC Version: ".hex(substr($uci_ccc_ver,2,2)).".".hex(substr($uci_ccc_ver,0,2));
                        } elsif ($param_id eq "A1") {
                            # CCC_VERSION
                            my $ccc_ver = substr($payload,$byte_idx,$param_length*2);
                            $byte_idx += $param_length*2;
                            
                            $value .= "CCC Version: ";
                            for (my $i=$param_length*2-2; $i>=0; $i-=2) {
                                $value .= chr(hex(substr($ccc_ver,$i,2)));
                            }
                        } elsif ($param_id eq "A2") {
                            # ALIRO_VERSION
                            my $aliro_ver = substr($payload,$byte_idx,$param_length*2);
                            $byte_idx += $param_length*2;
                            
                            $value .= "Aliro Version: ";
                            #for (my $i=$param_length*2-2; $i>=0; $i-=2) {
							for (my $i=0; $i<=$param_length*2-2; $i+=2) {
                                $value .= chr(hex(substr($aliro_ver,$i,2)));
                            }
                        } 
						else {
                            my $raw_value = substr($payload,$byte_idx,$param_length*2);
                            $byte_idx += $param_length*2;
                            $value .= " [".$param_id."]:".$raw_value;
                        }

                        # Check if decoding exceeds the size of terminal width
                        $line_length += length($value)+4;

                        if ($line_length > $MAX_LINE_SIZE) {
                            # Add new line
                            $decode .= "\n".$indent;
                            $line_length = length($indent)+$param_length+length($value)+2;
                        }
                    
                        $decode .= " ".$value."  ";
                    }
                }
            }
        }

        # CORE_GET_CAPS_INFO_CMD
        elsif ($mt_gid_oid eq "2003") {
            # NOTHING TO SHOW
        }
        
        # CORE_GET_CAPS_INFO_RSP
        elsif ( ($mt_gid_oid eq "4003") and ( $enable_get_caps_info == 1)) {
            # Put Byte index after Status
            my $byte_idx = 0;

            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
            } else {
                $byte_idx += 2;
                $decode .= $brown."   Status OK";
                # $decode .= "\n".$indent;
                my $line_length = length($indent);
                
                # Number of Capability parameters
                my $nb_params = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
           
                foreach (1..$nb_params) {
                    my $param_id = substr($payload,$byte_idx,2);
                    $byte_idx += 2;

                    my $value = "";

                    if ($param_id eq "E3") {
                        $param_id = substr($payload,$byte_idx,2);
                        $byte_idx += 2;

                        $param_id = $capaparam_E3{$param_id} || "?".$param_id."?";

                        my $param_length = hex(substr($payload,$byte_idx,2));
                        $byte_idx += 2;

                        $value = substr($payload,$byte_idx,$param_length*2);
                        $byte_idx += $param_length*2;
                        #TODO correct
                        if ($value eq "E4"){
                            next;
                        }

                        if ($param_id eq "UWBS_MAX_UCI_PAYLOAD_LENGTH") {
                            $value = 256*hex(substr($value,2,2)) + hex(substr($value,0,2));
                        } elsif ($param_id eq "UWBS_INBAND_DATA_BUFFER_BLOCK_SIZE") {
                            $value = hex($value);
                        } elsif ($param_id eq "UWBS_INBAND_DATA_MAX_BLOCKS") {
                            $value = hex($value);
                        } 
                    } else {
                        # UCI Capability parameter
                        $param_id = $capaparam{$param_id} || "?".$param_id."?";
                        
                        my $param_length = hex(substr($payload,$byte_idx,2));
                        $byte_idx += 2;
                        
                        # Calculate length for indent, space, param id and colon
                        my $busy_space = length($indent)+length($param_id)+2;
                        
                        # Truncate the value if exceeds the size of terminal width
                        $value = substr($payload,$byte_idx,$param_length*2);
                        $byte_idx += $param_length*2;

                        if ($param_id eq "MAX_DATA_MESSAGE_SIZE") {
                            $value = 256*hex(substr($value,2,2)) + hex(substr($value,0,2));
                        } elsif ($param_id eq "MAX_DATA_PACKET_PAYLOAD_SIZE") {
                            $value = 256*hex(substr($value,2,2)) + hex(substr($value,0,2));
                        } elsif ($param_id eq "FIRA_PHY_VERSION_RANGE") {
                            $value = hex(substr($value,0,2)).".".hex(substr($value,2,2))." to ".hex(substr($value,4,2)).".".hex(substr($value,6,2));
                        } elsif ($param_id eq "FIRA_MAC_VERSION_RANGE") {
                            $value = hex(substr($value,0,2)).".".hex(substr($value,2,2))." to ".hex(substr($value,4,2)).".".hex(substr($value,6,2));
                        } elsif ($param_id eq "DEVICE_TYPE") {
                            my $tmp = "";
                            $value = hex($value);
                            if ($value & 0x01) {$tmp .= " Controller";}
                            if ($value & 0x02) {$tmp .= " Controllee";}
                            $value = $tmp;
                        } elsif ($param_id eq "DEVICE_ROLES") {
                            my $tmp = "";
                            $value = hex($value);
                            if($value & 0x0001) {$tmp .= " Responder";}
                            if($value & 0x0002) {$tmp .= " Initiator";}
                            if($value & 0x0004) {$tmp .= " UT-Synchronization Anchor";}
                            if($value & 0x0008) {$tmp .= " UT-Anchor";}
                            if($value & 0x0010) {$tmp .= " UT-TAG";}
                            if($value & 0x0020) {$tmp .= " Advertiser";}
                            if($value & 0x0040) {$tmp .= " Observer";}
                            if($value & 0x0080) {$tmp .= " DT-Anchor";}
                            if($value & 0x0100) {$tmp .= " DT-Tag";}
                            $value = $tmp;
                        } elsif ($param_id eq "RANGING_METHOD") {
                            my $tmp = "[";
                            $value = substr($value,2,2).substr($value,0,2);
                            $value = hex($value);
                            if($value & 0x0001) {$tmp .= "One Way Ranging aka TDoA - ";}
                            if($value & 0x0002) {$tmp .= "SS-TWR with Deferred Mode - ";}
                            if($value & 0x0004) {$tmp .= "DS-TWR with Deferred Mode - ";}
                            if($value & 0x0008) {$tmp .= "SS-TWR with Non-deferred Mode - ";}
                            if($value & 0x0010) {$tmp .= "DS-TWR with Non-deferred Mode - ";}
                            if($value & 0x0020) {$tmp .= "OWR DL-TdoA - ";}
                            if($value & 0x0040) {$tmp .= "OWR for AoA Measurement - ";}
                            if($value & 0x0080) {$tmp .= "eSS-TWR with Non-deferred Mode for Contention-based ranging - ";}
                            if($value & 0x0100) {$tmp .= "aDS-TWR for Contention-based ranging";}
                            $value = $tmp."]";
                        } elsif ($param_id eq "STS_CONFIG") {
                            my $tmp = "";
                            $value = hex($value);
                            if($value & 0x01) {$tmp .= " Static STS";}
                            if($value & 0x02) {$tmp .= " Dynamic STS";}
                            if($value & 0x04) {$tmp .= " Dynamic STS for Responder Specific Sub-session Key";}
                            if($value & 0x08) {$tmp .= " Provisioned STS";}
                            if($value & 0x10) {$tmp .= " Provisioned STS for Responder Specific Sub-session Key";}
                            $value = $tmp;
                        } elsif ($param_id eq "MULTI_NODE_MODE") {
                            my $tmp = "[";
                            if($value & 0x01) {$tmp .= "One 2 One - ";}
                            if($value & 0x02) {$tmp .= "One 2 Many";}
                            $value = $tmp."]";
                        } elsif ($param_id eq "RANGING_TIME_STRUCT") {
                            if($value eq "02") {$value = " Block Based Scheduling";}
                            else {$value = " NOT SUPPORTED";}
                        } elsif ($param_id eq "SCHEDULED_MODE") {
                            my $tmp = "";
                            $value = hex($value);
                            if($value & 0x01) {$tmp .= " Contention based ranging ";}
                            if($value & 0x02) {$tmp .= " Time scheduled ranging ";}
                            if($value & 0x04) {$tmp .= " Hybrid based ranging ";}
                            $value = $tmp;
                        } elsif ($param_id eq "HOPPING_MODE") {
                            if($value eq "01") {$value = " Preference of hopping";}
                            else {$value = " NOT SUPPORTED";}
                        } elsif ($param_id eq "BLOCK_STRIDING") {
                            if($value eq "01") {$value = " Preference of Block Striding";}
                            else {$value = " NOT SUPPORTED";}
                        } elsif ($param_id eq "UWB_INITIATION_TIME") {
                            if($value eq "00") {$value = " Not supported";}
                            elsif($value eq "01") {$value = " Supported";}
                            else {$value =  " UNKNOWN";}
                        } elsif ($param_id eq "CHANNELS") {
                            my $tmp = "";
                            $value = hex($value);
                            if($value & 0x01) {$tmp .= " 5";}
                            if($value & 0x02) {$tmp .= " 6";}
                            if($value & 0x04) {$tmp .= " 8";}
                            if($value & 0x08) {$tmp .= " 9";}
                            if($value & 0x10) {$tmp .= " 10";}
                            if($value & 0x20) {$tmp .= " 12";}
                            if($value & 0x40) {$tmp .= " 13";}
                            if($value & 0x80) {$tmp .= " 14";}
                            $value = $tmp;
                        } elsif ($param_id eq "RFRAME_CONFIG") {
                            my $tmp = "";
                            $value = hex($value);
                            if($value & 0x01) {$tmp .= " SP0";}
                            if($value & 0x02) {$tmp .= " SP1";}
                            if($value & 0x04) {$tmp .= " SP2";}
                            if($value & 0x08) {$tmp .= " SP3";}
                            $value = $tmp;
                        } elsif ($param_id eq "CC_CONSTRAINT_LENGTH") {
                            my $tmp = "";
                            $value = hex($value);
                            if($value & 0x01) {$tmp .= " k=3";}
                            if($value & 0x02) {$tmp .= " k=7";}
                            $value = $tmp;
                        } elsif ($param_id eq "BPRF_PARAMETER_SETS") {
                            $value = "0x".$value;
                        } elsif ($param_id eq "HPRF_PARAMETER_SETS") {
                            $value = "0x".$value;
                        } elsif ($param_id eq "AOA_SUPPORT") {
                            my $tmp = "";
                            $value = hex($value);
                            if($value & 0x01) {$tmp .= " Azimuth AoA -90deg to 90deg";}
                            if($value & 0x02) {$tmp .= " Azimuth AoA -180deg to 180deg";}
                            if($value & 0x04) {$tmp .= " Elevation AoA";}
                            if($value & 0x08) {$tmp .= " AoA FOM";}
                            $value = $tmp;
                        } elsif ($param_id eq "EXTENDED_MAC_ADDRESS") {
                            if($value eq "00") {$value = " Not supported";}
                            elsif($value eq "01") {$value = " Supported";}
                            else {$value = " UNKNOWN";}
                        } elsif ($param_id eq "SUSPEND_RANGING_SUPPORT") {
                            if($value eq "00") {$value = " Not supported";}
                            elsif($value eq "01") {$value = " Supported";}
                            else {$value = " UNKNOWN";}
                        } elsif ($param_id eq "SESSION_KEY_LENGTH") {
                            my $tmp = "";
                            $value = hex($value);
                            if($value & 0x00) {$tmp .= "256 bits key length for Dynamic STS ";}
                            if($value & 0x01) {$tmp .= "256 bits key length for Provisioned STS ";}
                            $value = $tmp;
                        } elsif ($param_id eq "DT_ANCHOR_MAX_ACTIVE_RR") {
                            if ($value eq "00") {$value = "NOT SUPPORTED";}
                            else {$value = hex($value);}
                        } elsif ($param_id eq "DT_TAG_MAX_ACTIVE_RR") {
                            if ($value eq "00") {$value = "NOT SUPPORTED";}
                            else {$value = hex($value);}
                        } elsif ($param_id eq "DT_TAG_BLOCK_SKIPPING") {
                            if ($value eq "00") {$value = "Not supported";}
                            elsif ($value eq "01") {$value = "Supported";}
                            else {$value = "UNKNOWN";}
                        } elsif ($param_id eq "PSDU_LENGTH_SUPPORT") {
                            my $tmp = "";
                            $value = hex($value);
                            if ($value & 0x01) {$tmp .= "[len (2047) is supported";}
                            else {$tmp .= "[len (2047) is not supported";}
                            if ($value & 0x02) {$tmp .= " - len (4095) is supported]";}
                            else {$tmp .= " - len (4095) is not supported]";}
                            $value = $tmp;
                        }
                        #SPEC CCC
                        elsif ($param_id eq "SLOT_BITMASK") {
                            my $tmp = "";
                            $value = hex($value);
                            if ($value & 0x01) {$tmp .= "3 ";}
                            if ($value & 0x02) {$tmp .= "4 ";}
                            if ($value & 0x04) {$tmp .= "6 ";}
                            if ($value & 0x08) {$tmp .= "8 ";}
                            if ($value & 0x10) {$tmp .= "9 ";}
                            if ($value & 0x20) {$tmp .= "12 ";}
                            if ($value & 0x40) {$tmp .= "24 (Test only) ";}
                            $value = $tmp;
                        } elsif ($param_id eq "SYNC_CODE_INDEX_BITMASK") {
                            $value = "0x".$value;
                        } elsif ($param_id eq "HOPPING_CONFIG_BITMASK") {
                            $value = hex($value);
                        } elsif ($param_id eq "CHANNEL_BITMASK") {
                            if($value eq "01") {$value = "5 ";}
                            if($value eq "02") {$value = "9 ";}
                        } elsif ($param_id eq "SUPPORTED_PROTOCOL_VERSION") {
                            $value = hex(substr($value,2,2)).".".hex(substr($value,0,2));
                        } elsif ($param_id eq "SUPPORTED_UWB_CONFIG_ID") {
                            $value = hex(substr($value,2,2)).".".hex(substr($value,0,2));
                        } elsif ($param_id eq "SUPPORTED_PULSESHAPE_COMBO") {
                            $value = hex(substr($value,4,2))."-".hex(substr($value,2,2))."-".hex(substr($value,0,2));
                        } else {
                            $value = "0x".$value;
                            next;
                        }
                    }                   
                    # Check if decoding exceeds the size of terminal width
                    $line_length += length($param_id)+length($value)+4;
                    
                    if ($line_length > $MAX_LINE_SIZE) {
                        # Add new line
                        $decode .= "\n".$indent;
                        $line_length = length($indent)+length($param_id)+length($value)+2;
                    }
                    
                    $decode .= $param_id.": ".$value."   ";
                }

            }
            
            # $decode .= $nocolor;
        }

        # CORE_SET_CONFIG_CMD or CORE_GET_CONFIG_RSP
        elsif (($mt_gid_oid eq "2004") || ($mt_gid_oid eq "4005")) {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            my $quit = 0;
            
            # Status of CORE_GET_CONFIG_RSP
            if ($mt_gid_oid eq "4005") {
                if (substr($payload,$byte_idx,2) ne "00") {
                    $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
                    $byte_idx += 2;
                    $quit = 1;
                } else {
                    $byte_idx += 2;
                    $decode .= $brown."   Status OK";
                }
            }
            
            if ($quit == 0) {
                # Number of parameters
                my $nb_params = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;

                $decode .= "\n".$indent;
                
                foreach (1..$nb_params) {
                    my $line_length = length($indent);
                    
                    my $param_id = substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    
                    if ($param_id eq "E3") {
                        # Device Extended E3 parameter
                        $param_id = substr($payload,$byte_idx,2);
                        $param_id = $devparam_E3{$param_id} || "?E3".$param_id."?";
                        $byte_idx += 2;
                    } elsif ($param_id eq "E4") {
                        # Device Extended E4 parameter
                        $param_id = substr($payload,$byte_idx,2);
                        $param_id = $devparam_E4{$param_id} || "?E4".$param_id."?";
                        $byte_idx += 2;

                        my $param_length = hex(substr($payload,$byte_idx,2));
                        $byte_idx += 2;
                        my $value = $brown;
                        if ($param_id eq "DPD_WAKEUP_SRC") {
                            $value .= $param_id.": ";
                            $value .= hex(substr($payload,$byte_idx,2));
                            $byte_idx += 2;
                        } elsif ($param_id eq "WTX_COUNT_CONFIG") {
                            $value .= $param_id.": ";
                            $value .= hex(substr($payload,$byte_idx,2));
                            $byte_idx += 2;
                        } elsif ($param_id eq "DPD_ENTRY_TIMEOUT") {
                            $value .= $param_id.": ";
                            $value .= 256*hex(substr($payload,$byte_idx+2,2))+hex(substr($payload,$byte_idx,2));
                            $byte_idx += 4;
                        } elsif ($param_id eq "WIFI_COEX_FEATURE") {
                            $value .= $param_id.": [";
                            my $byte1 = substr($payload,$byte_idx,2);
                            $WifiCoexFeature = $byte1;
                            if ($byte1 == 0x00) {
                                $value .= "DISABLED";
                            } elsif ($byte1 & 0x01) {
                                $value .= "ENABLED without Debug & warning verbose";
                            } elsif ($byte1 & 0x02) {
                                $value .= "ENABLED with DEBUG warning verbose ONLY";
                            } elsif ($byte1 & 0x03) {
                                $value .= "ENABLED with WARNING warning verbose ONLY";
                            } elsif ($byte1 & 0x04) {
                                $value .= "ENABLED with BOTH Debug and Warning verbose";
                            }
                            if ($byte1 & 0x10 == 0) {
                                $value .= " - GPIO Selected";
                            } else {
                                $value .= " - Unknown GPIO/UART Selection";
                            }
                            $value .= "]";

                            my $byte2 = substr($payload,$byte_idx+2,2);
                            $value .= " - MIN_GUARD_DURATION [".hex($byte2)."ms]";
                            my $byte3 = substr($payload,$byte_idx+4,2);
                            $value .= " - MAX_GRANT_DURATION [".hex($byte3)."ms]";
                            my $byte4 = substr($payload,$byte_idx+6,2);
                            $value .= " - ADVANCED_GRANT_DURATION [".hex($byte4)."ms]";

                            $byte_idx += 8;
                        } elsif ($param_id eq "GPIO_SELECTION_FOR_DUAL_AOA") {
                            $value .= $param_id.": ";
                            my $val = hex(substr($payload,$byte_idx,2));
                            $byte_idx += 2;
                            if ($val == 0) {
                                $value .= "EF2 based Ant Selection";
                            } elsif ($val == 1) {
                                $value .= "GPIO 14 based Ant Selection";
                            }
                        } elsif ($param_id eq "SESSION_HANDLE_EN") {
                            $value .= $param_id.": ";
                            my $val = hex(substr($payload,$byte_idx,2));
                            $byte_idx += 2;
                            if ($val == 0x00) {
                                $value .= "DISABLED";
                            } elsif ($val == 0x01) {
                                $value .= "ENABLED";
                            } else {
                                $value .= "UNKNOWN";
                            }
                        } elsif ($param_id eq "TX_BASE_BAND_CONFIG") {
                            $value .= $param_id.": ";
                            my $val = hex(substr($payload,$byte_idx,2));
                            $byte_idx += 2;
                            if ($val & 0x01 == 0) {
                                $value .= "[DISABLED DDFS";
                            } elsif ($val & 0x01) {
                                $value .= "[ENABLED DDFS";
                            } else {
                                $value .= "[UNKNOWN";
                            }
                            if ($val & 0x02 == 0) {
                                $value .= " - DISABLED DC suppression]";
                            } elsif ($val & 0x02) {
                                $value .= " - ENABLED DC suppression]";
                            } else {
                                $value .= " - UNKNOWN]";
                            }
                        } elsif ($param_id eq "DDFS_TONE_CONFIG") {
                            $value .= "\n".$indent.$param_id.": ";
                            for (my $i=0; $i<4; $i++) {
                                $value .= "\n".$indent.$indent."Block ".($i+1).": ";

                                my $val = hex(substr($payload,$byte_idx,2));
                                $byte_idx += 2;
                                $value .= "Channel ".$val;

                                $val = hex(substr($payload,$byte_idx,2));
                                $byte_idx += 2;
                                $value .= " - TX".$val." selected";

                                $val = hex(substr($payload,$byte_idx+6,2));
                                $val = (256*$val) + hex(substr($payload,$byte_idx+4,2));
                                $val = (256*$val) + hex(substr($payload,$byte_idx+2,2));
                                $val = (256*$val) + hex(substr($payload,$byte_idx,2));
                                $byte_idx += 8;
                                $val = $val * 0.975;
                                $value .= " - TX_DDFS _TONE_0_INC0_SET: ".$val."MHz";

                                $val = hex(substr($payload,$byte_idx+6,2));
                                $val = (256*$val) + hex(substr($payload,$byte_idx+4,2));
                                $val = (256*$val) + hex(substr($payload,$byte_idx+2,2));
                                $val = (256*$val) + hex(substr($payload,$byte_idx,2));
                                $byte_idx += 8;
                                $val = $val * 0.975;
                                $value .= " - TX_DDFS _TONE_1_INC1_SET: ".$val."MHz";

                                $val = hex(substr($payload,$byte_idx+6,2));
                                $val = (256*$val) + hex(substr($payload,$byte_idx+4,2));
                                $val = (256*$val) + hex(substr($payload,$byte_idx+2,2));
                                $val = (256*$val) + hex(substr($payload,$byte_idx,2));
                                $byte_idx += 8;
                                $val *= 8;
                                $value .= " - SPUR_DURATION: ".$val."ns";

                                $val = substr($payload,$byte_idx,2);
                                $byte_idx += 2;
                                $value .= " - GAINVAL_SET: 0x".$val;

                                $val = substr($payload,$byte_idx,2);
                                $byte_idx += 2;
                                $value .= " - DDFS_GAINBYPASS_ENBL: 0x".$val;

                                $val = substr($payload,$byte_idx,2);
                                $byte_idx += 2;
                                $value .= " - PERIODICITY OF SPUR: 1/".$val;
                            }
                        } elsif ($param_id eq "TX_PULSE_SHAPE_CONFIG") {
                            $value .= $param_id.": ";
                            $value .= "Preamble ID: ".hex(substr($payload,$byte_idx,2));
                            $value .= " - Payload ID: ".hex(substr($payload,$byte_idx+2,2));
                            $value .= " - STS ID: ".hex(substr($payload,$byte_idx+4,2));
                            # $value .= " - RFU: ".hex(substr($payload,$byte_idx+6,2));
                            $byte_idx += 8;
                        } elsif ($param_id eq "CLK_CONFIG_CTRL") {
							$value .= "\n".$indent.$param_id.": ";
							my $val = hex(substr($payload,$byte_idx,2));
							$byte_idx += 2;

							my $source_32k = ($val & 0x01);
							my $waveform_32k = (($val>>1) & 0x03);
							my $RF_clock_source = (($val>>3) & 0x01);
							my $RF_clock_freq = (($val>>4) & 0x03);		
							my $RF_clock_wave = (($val>>6) & 0x01);	
								
                            if ( $source_32k == 0) {
                                $value .= "Use on board crystal 32kHz\n";
                            } else {
                                $value .= "Use external 32k clock ";
								if ( $waveform_32k == 0 ){
									$value .= " Sinus \n";							
								}
								elsif ( $waveform_32k == 1 ){
									$value .= " 1.8V square \n";							
								}
								elsif ( $waveform_32k == 2 ){
									$value .= " 1.2V square \n";							
								}
								else{
									$value .= " Unknown waveform \n";		
								}
                            }
								
							if ( $RF_clock_source == 1) {
                                $value .= $indent.$indent."RF clock source Use external clock ";
								if ( $RF_clock_freq == 0 ){
									$value .= "38.4MHz ";
								}
								elsif ( $RF_clock_freq == 1 ){ 
									$value .= "26 MHz ";
								}		
								elsif ( $RF_clock_freq == 2 ){ 
									$value .= "19.2 MHz ";
								}	
								else{
									$value .= "Unknown frequency ";							
								}
								
								if ( $RF_clock_wave == 0 ){
									$value .= "Sinus\n";					
								}
								elsif ( $RF_clock_wave == 1 ){
									$value .= "Square\n";					
								}
								else{
									$value .= "Unknown wave\n";					
								}
                            } 
							else{
                                $value .= $indent.$indent."RF clock source Use on board crystal\n";							
							}
		
							$val = 256*hex(substr($payload,$byte_idx+2,2))+hex(substr($payload,$byte_idx,2));
							$byte_idx += 4;
							$value .= $indent.$indent."SLOW_CLK_WAITING_TIME: ".$val." us\n";
							
							$val = 256*hex(substr($payload,$byte_idx+2,2))+hex(substr($payload,$byte_idx,2));
							$byte_idx += 4;
							$value .= $indent.$indent."RF_CLK_WAITING_TIME: ".$val." us";	
							
                            #$value .= "\n".$indent.$indent;
                        } elsif ($param_id eq "HOST_MAX_UCI_PAYLOAD_LENGTH") {
                            $value .= $param_id.": ";
                            my $val = 256*hex(substr($payload,$byte_idx+2,2))+hex(substr($payload,$byte_idx,2));
                            $byte_idx += 4;
                        } elsif ($param_id eq "UWB_CH5_WLAN_CHANNEL_INTERFERENCE_LIST") {
                            $value .= $param_id.": ";
                            # RFU
                        } elsif ($param_id eq "NXP_EXTENDED_NTF_CONFIG") {
                            $value .= $param_id.": ";
                            my $val = hex(substr($payload,$byte_idx,2));
                            $byte_idx += 2;
                            if ($val == 0) {
                                $value .= "FIRA RSP/NTF"
                            } elsif ($val == 1) {
                                $value .= "VENDOR EX RSP/NTF"
                            } else {
                                $value .= "UNKNOWN"
                            }
                        } elsif ($param_id eq "CLOCK_PRESENT_WAITING_TIME") {
                            $value .= $param_id.": ";
                            my $val = 256*hex(substr($payload,$byte_idx+2,2))+hex(substr($payload,$byte_idx,2));
                            $byte_idx += 4;
                            $value .= $val."ms";
                        } elsif ($param_id eq "INITIAL_RX_ON_OFFSET_ABS") {
                            $value .= $param_id.": ";
                            my $val = 256*hex(substr($payload,$byte_idx+2,2))+hex(substr($payload,$byte_idx,2));
                            $byte_idx += 4;
                            $value .= $val."µs";
                        } elsif ($param_id eq "INITIAL_RX_ON_OFFSET_REL") {
                            $value .= $param_id.": ";
                            my $val = 256*hex(substr($payload,$byte_idx+2,2))+hex(substr($payload,$byte_idx,2));
                            $byte_idx += 4;
                            $value .= $val."ppm(".($val/10)."µs)";
                        } elsif ($param_id eq "PDOA_CALIB_TABLE_DEFINE") {
                            $value .= $param_id.": [";
                            my $val = hex(substr($payload,$byte_idx,2));
                            $byte_idx += 2;
                            $value .= $val."deg - ";
                            $val = hex(substr($payload,$byte_idx,2));
                            $byte_idx += 2;
                            $value .= "Num of steps: ".$val."]";
                        } elsif ($param_id eq "ANTENNA_RX_IDX_DEFINE") {
                            my $number_entries = hex(substr($payload,$byte_idx,2));
                            $byte_idx += 2;

                            $value .= "\n".$indent.$param_id." (*".$number_entries."):";

                            foreach (1..$number_entries) {
                                $value .= "\n".$indent.$indent."ANTENNA [ID".hex(substr($payload,$byte_idx,2))."]";
                                $byte_idx += 2;
                                my $val = $RXID_TO_RXANT{substr($payload,$byte_idx,2)} || "??";
                                $byte_idx += 2;
                                $value .= " RX".$val;
                                $value .= $indent."GPIO FILTER MASK [0x".substr($payload,$byte_idx+2,2);
                                $value .= substr($payload,$byte_idx,2)."]";
                                $byte_idx += 4;
                                $value .= " GPIO STATE/VALUE [0x".substr($payload,$byte_idx+2,2);
                                $value .= substr($payload,$byte_idx,2)."]";
                                $byte_idx += 4;
                            }
                        } elsif ($param_id eq "ANTENNA_TX_IDX_DEFINE") {
                            my $number_entries = hex(substr($payload,$byte_idx,2));
                            $byte_idx += 2;

                            $value .= "\n".$indent.$param_id." (*".$number_entries."):";
                            
                            foreach (1..$number_entries) {
                                $value .= "\n".$indent.$indent."ANTENNA [".hex(substr($payload,$byte_idx,2))."]";
                                $byte_idx += 2;
                                $value .= " GPIO FILTER MASK [0x".substr($payload,$byte_idx+2,2);
                                $value .= substr($payload,$byte_idx,2)."]";
                                $byte_idx += 4;
                                $value .= " GPIO STATE/VALUE [0x".substr($payload,$byte_idx+2,2);
                                $value .= substr($payload,$byte_idx,2)."]";
                                $byte_idx += 4;
                            }
                        } elsif ($param_id eq "ANTENNA_TX_IDX_DEFINE_SR2x") {
                            my $number_entries = hex(substr($payload,$byte_idx,2));
                            $byte_idx += 2;
                            $value .= "\n".$indent.$param_id." (*".$number_entries."):";
                            
                            foreach (1..$number_entries) {
                                my $ant_id = hex(substr($payload,$byte_idx,2));
                                $byte_idx += 2;
                                $value .= "\n".$indent.$indent."ANTENNA [".$ant_id."]";

                                my $tx_ant_port= hex(substr($payload,$byte_idx,2));
                                $byte_idx += 2;
                                if ($tx_ant_port == 0x01) {
                                    $value .= " TRA1";
                                } elsif ($tx_ant_port == 0x02) {
                                    $value .= " TRA2";
                                } else {
                                    $value .= " UNKNOWN";
                                }

                                $value .= " GPIO FILTER MASK [0x".substr($payload,$byte_idx+2,2);
                                $value .= substr($payload,$byte_idx,2)."]";
                                $byte_idx += 4;

                                $value .= " GPIO STATE/VALUE [0x".substr($payload,$byte_idx+2,2);
                                $value .= substr($payload,$byte_idx,2)."]";
                                $byte_idx += 4;
                            }
                        } elsif ($param_id eq "ANTENNAS_RX_PAIR_DEFINE") {
                            if(index($Device_Name,"SR1") > 0) {
                                # SR1xx TODO
                                my $number_entries = hex(substr($payload,$byte_idx,2));
                                $byte_idx += 2;

                                $value .= "\n".$indent.$param_id." (*".$number_entries."):";

                                foreach (1..$number_entries) {
                                    my $antenna_pair_id = hex(substr($payload,$byte_idx,2));
                                    $value .= "\n".$indent.$indent."ANTENNA PAIR [ID".$antenna_pair_id."]";
                                    $byte_idx += 2;

                                    my $Ant_ID1 = hex(substr($payload,$byte_idx,2));
                                    $byte_idx += 2;

                                    my $Ant_ID2 = hex(substr($payload,$byte_idx,2));
                                    $byte_idx += 2;

                                    $value .= " => Antenna [ID".$Ant_ID1."] & [ID".$Ant_ID2."]";

                                    # RFU
                                    $byte_idx += 2;
                                    #RFU
                                    $byte_idx += 4;
                                }
                            }
                            else {
                                # SR2xx
                                my $number_entries = hex(substr($payload,$byte_idx,2));
                                $byte_idx += 2;

                                $value .= "\n".$indent.$param_id." (*".$number_entries."):";

                                foreach (1..$number_entries) {
                                    my $antenna_pair_id = hex(substr($payload,$byte_idx,2));
                                    $value .= "\n".$indent.$indent."ANTENNA PAIR [ID".$antenna_pair_id."]";
                                    $byte_idx += 2;

                                    my $Ant_NB1 = hex(substr($payload,$byte_idx,2));
                                    $byte_idx += 2;

                                    my $Ant_NB2 = hex(substr($payload,$byte_idx,2));
                                    $byte_idx += 2;

                                    my $Ant_NB3 = hex(substr($payload,$byte_idx,2));
                                    $byte_idx += 2;

                                    if ($Ant_NB1 == 0x00) {
                                        $value .= " => Antenna [ID".$Ant_NB2."] & [ID".$Ant_NB3."]";
                                    } elsif ($Ant_NB2 == 0x00) {
                                        $value .= " => Antenna [ID".$Ant_NB1."] & [ID".$Ant_NB3."]";
                                    } elsif ($Ant_NB3 == 0x00) {
                                        $value .= " => Antenna [ID".$Ant_NB1."] & [ID".$Ant_NB2."]";
                                    } else {
                                        $value .= $red_oops." => ERROR: Antenna Pairing";
                                        $value .= $nocolor;
                                    }

                                    #RFU
                                    $byte_idx += 4;
                                }
                            }
                        } elsif ($param_id eq "DEFAULT_SESSION_VENDOR_APP_CONFIG") {
							$value .= "\n".$indent.$param_id.": ";
                            my $val = substr($payload,$byte_idx,$param_length);
                            $value .= "0x".$val;
                        } elsif ($param_id eq "AOA_CALIB_CTRL_RX_ANT_PAIR_1_CH5") {
                            $value .= $param_id.": ";
                            $value .= substr($payload,$byte_idx,2);
                            $value .= substr($payload,$byte_idx+2,2);
                            $value .= substr($payload,$byte_idx+4,2)."...";
                            $byte_idx += (11*11*2);
                        }
                        # Check if decoding exceeds the size of terminal width
                        $line_length += length($value)+4;
                        
                        if ($line_length > $MAX_LINE_SIZE && length($value) < $MAX_LINE_SIZE) {
                            # Add new line
                            $decode .= "\n".$indent;
                            $line_length = length($indent)+length($param_id)+length($value)+2;
                        }
                        
                        $decode .= $value."  ";
                        next;
                    } elsif ($param_id eq "E5") {
                        # Device Extended E5 parameter, Internal
                        $byte_idx += 6;
                        next;					
                    } else {
                        # UCI Device parameter
                        $param_id = $devparam{$param_id} || "?".$param_id."?";
                    }

                    $decode .= "\n".$indent.$brown;

                    my $param_length = hex(substr($payload,$byte_idx,2));
                    $byte_idx += 2;
                    
                    # Calculate length for indent, space, param id and colon
                    my $busy_space = length($indent)+length($param_id)+2;
                    
                    # Truncate the value if exceeds the size of terminal width
                    my $value = (($param_length*2) > ($MAX_LINE_SIZE-$busy_space)) ? substr($payload,$byte_idx,$MAX_LINE_SIZE-$busy_space-3)."..." : substr($payload,$byte_idx,$param_length*2);
                    $byte_idx += $param_length*2;
                    
                    # Check if decoding exceeds the size of terminal width
                    $line_length += length($param_id)+length($value)+4;
                    
                    if ($line_length > $MAX_LINE_SIZE && length($param_id)+length($value)+4 < $MAX_LINE_SIZE) {
                        # Add new line
                        $decode .= "\n".$indent;
                        $line_length = length($indent)+length($param_id)+length($value)+2;
                    }
                    
                    $decode .= $param_id.":".$value."   ";
                }
            }
            
            $decode .= $nocolor;
        }
        
        # CORE_SET_CONFIG_RSP or CORE_SET_CONFIG_CMD
        elsif ($mt_gid_oid eq "4004" || $mt_gid_oid eq "2005") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            my $quit = 0;
            
            # Status of CORE_SET_CONFIG_RSP
            if ($mt_gid_oid eq "4004") {
                if (substr($payload,$byte_idx,2) ne "00") {
                    $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
                    $byte_idx += 2;
                    $quit = 1;
                } else {
                    $byte_idx += 2;
                    $decode .= $brown."   Status OK";
                }
            }
            if ($quit == 0) {
                # Number of parameters
                my $nb_params = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
                
                foreach (1..$nb_params) {
                    $decode .= "\n".$indent.$red;
                    
                    my $param_id = substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    
                    if ($param_id eq "E3") {
                        # Device Extended E3 parameter
                        $param_id = substr($payload,$byte_idx,2);
                        $param_id = $devparam_E3{$param_id} || "?E3".$param_id."?";
                        $byte_idx += 2;
                    } elsif ($param_id eq "E4") {
                        # Device Extended E4 parameter
                        $param_id = substr($payload,$byte_idx,2);
                        $param_id = $devparam_E4{$param_id} || "?E4".$param_id."?";
                        $byte_idx += 2;
                    } else {
                        # UCI Device parameter
                        $param_id = $devparam{$param_id} || "?".$param_id."?";
                    }
                    
                    my $param_status = substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    
                    $decode .= $param_id.":".($status_code{$param_status} || "???")." ";
                }
            }
        }
        
        # CORE_GENERIC_ERROR_NTF
        elsif ($mt_gid_oid eq "6007") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= $brown."   Status OK";
            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }
            
            
            $decode .= $nocolor;
        }

        # QUERY_UWBS_TIMESTAMP_CMD
        elsif ($mt_gid_oid eq "2008") {
            # NOTHING TO SHOW
        }
        
        # QUERY_UWBS_TIMESTAMP_RSP
        elsif ($mt_gid_oid eq "4008") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
            } else {
                $byte_idx += 2;
                
                # UWB Timestamp
                my $uwb_ts = hex(substr($payload,$byte_idx+14,2));
                $uwb_ts = (256*$uwb_ts)+hex(substr($payload,$byte_idx+12,2));
                $uwb_ts = (256*$uwb_ts)+hex(substr($payload,$byte_idx+10,2));
                $uwb_ts = (256*$uwb_ts)+hex(substr($payload,$byte_idx+8,2));
                $uwb_ts = (256*$uwb_ts)+hex(substr($payload,$byte_idx+6,2));
                $uwb_ts = (256*$uwb_ts)+hex(substr($payload,$byte_idx+4,2));
                $uwb_ts = (256*$uwb_ts)+hex(substr($payload,$byte_idx+2,2));
                $uwb_ts = (256*$uwb_ts)+hex(substr($payload,$byte_idx,2));
                $byte_idx += 16;
                
                $decode .= "   ".$uwb_ts."us";
            }
            
            $decode .= $nocolor;
        }
        #################### UWB Session Config Group ####################
        # SESSION_INIT_CMD
        elsif ($mt_gid_oid eq "2100") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= "\n".$indent.$brown;
            
            # Session ID
            $decode .= " Session ID:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            # Session Type
            $decode .= "   Type:".($session_type{substr($payload,$byte_idx,2)} || "???");
            $session_type = substr($payload,$byte_idx,2);

            $decode .= $nocolor;
        }

        # SESSION_INIT_RSP
        elsif ($mt_gid_oid eq "4100") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= "   ".$brown;

            # Status
            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            } else {
                $byte_idx += 2;
                
                $decode .= "Session Handle: 0x";
                $decode .= substr($payload,$byte_idx+6,2);
                $decode .= substr($payload,$byte_idx+4,2);
                $decode .= substr($payload,$byte_idx+2,2);
                $decode .= substr($payload,$byte_idx,2);
                $byte_idx += 8;
            }
            
            $decode .= $nocolor;
        }
        
        # SESSION_DEINIT_CMD
        elsif ($mt_gid_oid eq "2101") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $brown;
            
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            
            $decode .= $nocolor;
        }
        
        # SESSION_DEINIT_RSP
        elsif ($mt_gid_oid eq "4101") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= $brown."   Status OK";
            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }
            
            
            $decode .= $nocolor;
        }
        
        # SESSION_STATUS_NTF
        elsif ($mt_gid_oid eq "6102") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;
            
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            $decode .= "\n".$indent;

            # Session Status
            $decode .= $red.($session_state{substr($payload,$byte_idx,2)} || "???");
            $byte_idx += 2;
            
            # Session Reason
            $decode .= "   ".($session_reason{substr($payload,$byte_idx,2)} || "???");
            
            $decode .= $nocolor;
        }
        
        # SESSION_SET_APP_CONFIG_CMD or SESSION_GET_APP_CONFIG_RSP
        elsif (($mt_gid_oid eq "2103") || ($mt_gid_oid eq "4104")) {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;
            
            if ($mt_gid_oid eq "2103") {
                $decode .= "   Session Handle:0x";
                $decode .= substr($payload,$byte_idx+6,2);
                $decode .= substr($payload,$byte_idx+4,2);
                $decode .= substr($payload,$byte_idx+2,2);
                $decode .= substr($payload,$byte_idx,2);
                $byte_idx += 8;
            } else {
                # Status
                if (substr($payload,$byte_idx,2) eq "00") {
                    $decode .= $brown."   Status OK";
                } else {
                    $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
                }
                
                $byte_idx += 2;
            }
            
            $decode .= "\n".$indent;
            my $line_length = length($indent);
            
            # Number of parameters
            my $nb_params = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            
            foreach (1..$nb_params) {
                my $param_id = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                
                # UCI Application Configuration parameter
                $param_id = $appparam{$param_id} || "?".$param_id."?";
                
                my $param_length = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
                
                # Calculate length for indent, space, param id and colon
                my $busy_space = length($indent)+length($param_id)+2;
                
                # Truncate the value if exceeds the size of terminal width
                my $value = (($param_length*2) > ($MAX_LINE_SIZE-$busy_space)) ? substr($payload,$byte_idx,$MAX_LINE_SIZE-$busy_space-3)."..." : substr($payload,$byte_idx,$param_length*2);
                $byte_idx += $param_length*2;
                
                # Check if decoding exceeds the size of terminal width
                $line_length += length($param_id)+length($value)+4;
                
                if ($line_length > $MAX_LINE_SIZE) {
                    # Add new line
                    $decode .= "\n".$indent;
                    $line_length = length($indent)+length($param_id)+length($value)+2;
                }
                
                $decode .= $param_id.": ".$value."   ";
            }
            
            $decode .= $nocolor;
        }
        
        # SESSION_SET_APP_CONFIG_RSP or SESSION_GET_APP_CONFIG_CMD
        elsif (($mt_gid_oid eq "4103") || ($mt_gid_oid eq "2104")) {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            my $status = "00";
            
            # SESSION_GET_APP_CONFIG_CMD
            if ($mt_gid_oid eq "2104") {
                $decode .= "   Session Handle:0x";
                $decode .= substr($payload,$byte_idx+6,2);
                $decode .= substr($payload,$byte_idx+4,2);
                $decode .= substr($payload,$byte_idx+2,2);
                $decode .= substr($payload,$byte_idx,2);
                $byte_idx += 8;
            } else {
                # Status
                $status = substr($payload,$byte_idx,2);
                $byte_idx += 2;

                if ($status eq "00") {
                    $decode .= $brown."   Status OK";
                } else {
                    $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
                }
            }
            
            # Number of parameters
            my $nb_params = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;

            if ($nb_params != 0) {
                $decode .= "\n".$indent;
            }
            
            foreach (1..$nb_params) {
                my $param_id = substr($payload,$byte_idx,2);
                $byte_idx += 2;

                # UCI Application Configuration parameter
                $param_id = $appparam{$param_id} || "?".$param_id."?";

                # SESSION_GET_APP_CONFIG_CMD
                if ($mt_gid_oid eq "2104") {
                    $decode .= $param_id."  ";
                } else {
                    my $param_status = substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    
                    $decode .= $red.$param_id.":".($status_code{$param_status} || "???")." ";
                }
            }
            
            $decode .= $nocolor;
        }
        
        # SESSION_GET_COUNT_CMD
        elsif ($mt_gid_oid eq "2105") {
            # NOTHING TO SHOW
        }
        
        # SESSION_GET_COUNT_RSP
        elsif ($mt_gid_oid eq "4105") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;

            # Status
            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
            } else {
                $byte_idx += 2;
                
                # Active Session Count
                my $session_count = hex(substr($payload,$byte_idx,2));
                
                $decode .= "   ".$session_count." active session".(($session_count > 1) ? "s" : "");
                
                $decode .= $nocolor;
            }
        }
        
        # SESSION_GET_STATE_CMD
        elsif ($mt_gid_oid eq "2106") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $brown;
            
            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            
            $decode .= $nocolor;
        }
        
        # SESSION_GET_STATE_RSP
        elsif ($mt_gid_oid eq "4106") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;

            # Status
            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
            } else {
                $byte_idx += 2;
                
                # Session Status
                $decode .= "   ".($session_state{substr($payload,$byte_idx,2)} || "???");

                $decode .= $nocolor;
            }
        }

        # SESSION_UPDATE_CONTROLLER_MULTICAST_LIST_CMD
        elsif ($mt_gid_oid eq "2107") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $brown;
            
            # Session ID
            $decode .= " Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            $decode .= "\n".$indent;

            # Action
            $decode .= "   ".($update_action{substr($payload,$byte_idx,2)} || "???");
            $byte_idx += 2;
            
            # Number of controlees
            my $nb_controlees = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            
            foreach (1..$nb_controlees) {
                $decode .= "\n".$indent.$red;
                
                $decode .= "   Short Addr:0x".substr($payload,$byte_idx+2,2).substr($payload,$byte_idx,2);
                $byte_idx += 4;
                
                $decode .= "   Sub-session ID:0x";
                $decode .= substr($payload,$byte_idx+6,2);
                $decode .= substr($payload,$byte_idx+4,2);
                $decode .= substr($payload,$byte_idx+2,2);
                $decode .= substr($payload,$byte_idx,2);
                $byte_idx += 8;
            }
            
            $decode .= $nocolor;
        }

        # SESSION_UPDATE_CONTROLLER_MULTICAST_LIST_RSP
        elsif ($mt_gid_oid eq "4107") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
            
                # Number of controlees
                my $nb_controlees = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
                
                foreach (1..$nb_controlees) {
                    $decode .= "\n".$indent.$red;
                    
                    $decode .= "   Short Addr:0x".substr($payload,$byte_idx+2,2).substr($payload,$byte_idx,2);
                    $byte_idx += 4;

                    $decode .= "   ".($update_status{substr($payload,$byte_idx,2)} || "???");
                    $byte_idx += 2;
                }
            }
            
            $decode .= $nocolor;
        }
        
        # SESSION_UPDATE_CONTROLLER_MULTICAST_LIST_NTF
        elsif ($mt_gid_oid eq "6107") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $brown;
            
            # Session ID
            $decode .= " Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            $decode .= "\n".$indent;
            
            # Number of controlees
            my $nb_controlees = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            
            foreach (1..$nb_controlees) {
                $decode .= "\n".$indent.$red;
                    
                $decode .= "   MAC address:0x";
                $decode .= substr($payload,$byte_idx+2,2);
                $decode .= substr($payload,$byte_idx,2);
                $byte_idx += 4;
                
                $decode .= "   ".($update_status{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
            }
            
            $decode .= $nocolor;
        }
        
        # SESSION_UPDATE_DT_ANCHOR_RANGING_ROUNDS_CMD
        elsif ($mt_gid_oid eq "2108") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;
            
            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            $decode .= "\n".$indent.$brown."   Ranging Round Index:";
            my $line_length = length($indent)+23;
            
            # Number of active ranging rounds
            my $nb_rounds = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            
            foreach (1..$nb_rounds) {
                my $round_idx = sprintf("%d",hex(substr($payload,$byte_idx,2)));
                $byte_idx += 2;
                
                my $round_role = ($device_role{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
                
                # Check if decoding exceeds the size of terminal width
                $line_length += length($round_idx)+length($round_role)+4;
                
                if ($line_length > $MAX_LINE_SIZE) {
                    # Add new line
                    $decode .= "\n".$indent."                       ";
                    $line_length = length($indent)+23+length($round_idx)+1+length($round_role);
                }
                
                $decode .= $round_idx." ".$round_role."   ";
            }
            
            $decode .= $nocolor;
        }
        
        # SESSION_UPDATE_DT_ANCHOR_RANGING_ROUNDS_RSP
        elsif ($mt_gid_oid eq "4108") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Status
            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
                
                # Number of ranging rounds
                my $nb_rounds = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
                
                if ($nb_rounds > 0) {
                    $decode .= "\n".$indent.$red."   Ranging Round Index:";
                    my $line_length = length($indent)+23;
                    
                    foreach (1..$nb_rounds) {
                        my $round_idx = sprintf("%d",hex(substr($payload,$byte_idx,2)));
                        $byte_idx += 2;
                        
                        # Check if decoding exceeds the size of terminal width
                        $line_length += length($round_idx)+3;
                        
                        if ($line_length > $MAX_LINE_SIZE) {
                            # Add new line
                            $decode .= "\n".$indent."                       ";
                            $line_length = length($indent)+23+length($round_idx);
                        }
                        
                        $decode .= $round_idx."   ";
                    }
                }
            }
            
            $decode .= $nocolor;
        }
        
        # SESSION_UPDATE_DT_TAG_RANGING_ROUNDS_CMD
        elsif ($mt_gid_oid eq "2109") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;
            
            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            $decode .= "\n".$indent."   Ranging Round Index:";
            my $line_length = length($indent)+23;
            
            # Number of active ranging rounds
            my $nb_rounds = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            
            foreach (1..$nb_rounds) {
                my $round_idx = sprintf("%d",hex(substr($payload,$byte_idx,2)));
                $byte_idx += 2;
                
                # Check if decoding exceeds the size of terminal width
                $line_length += length($round_idx)+3;
                
                if ($line_length > $MAX_LINE_SIZE) {
                    # Add new line
                    $decode .= "\n".$indent."                       ";
                    $line_length = length($indent)+23+length($round_idx);
                }
                
                $decode .= $round_idx."   ";
            }
            
            $decode .= $nocolor;
        }
        
        # SESSION_UPDATE_DT_TAG_RANGING_ROUNDS_RSP
        elsif ($mt_gid_oid eq "4109") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Status
            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
                
                # Number of ranging rounds
                my $nb_rounds = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
                
                if ($nb_rounds > 0) {
                    $decode .= "\n".$indent.$red."   Ranging Round Index:";
                    my $line_length = length($indent)+23;
                    
                    foreach (1..$nb_rounds) {
                        my $round_idx = sprintf("%d",hex(substr($payload,$byte_idx,2)));
                        $byte_idx += 2;
                        
                        # Check if decoding exceeds the size of terminal width
                        $line_length += length($round_idx)+3;
                        
                        if ($line_length > $MAX_LINE_SIZE) {
                            # Add new line
                            $decode .= "\n".$indent."                       ";
                            $line_length = length($indent)+23+length($round_idx);
                        }
                        
                        $decode .= $round_idx."   ";
                    }
                }
            }
            
            $decode .= $nocolor;
        }

        # SESSION_QUERY_DATA_SIZE_IN_RANGING_CMD
        elsif ($mt_gid_oid eq "210B") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $brown;
            
            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            
            $decode .= $nocolor;
        }

        # SESSION_QUERY_DATA_SIZE_IN_RANGING_RSP
        elsif ($mt_gid_oid eq "410B") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $brown;
            
            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;

            # Status
            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
                
                my $size = hex(substr($payload,$byte_idx+2,2).substr($payload,$byte_idx,2));

                $decode .= "    Max size: ".$size;
            }
            
            $decode .= $nocolor;
        }

        # SESSION_GET_POSSIBLE_RAN_MULTIPLAYER_VALUE_CMD
        elsif ($mt_gid_oid eq "2120") {
            # NOTHING TO SHOW
        }

        # SESSION_GET_POSSIBLE_RAN_MULTIPLAYER_VALUE_RSP
        elsif ($mt_gid_oid eq "4120") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $brown;

            # Status
            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
            } else {
                $byte_idx += 2;
                
                my $multiplayer = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
                $decode .= "\n".$indent."Multiplayer: ".$multiplayer;
            }
            
            $decode .= $nocolor;
        }
		# SESSION_UPDATE_DTPCM_CMD
        elsif ($mt_gid_oid eq "210E") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $yellow;
            
            # Session handle
            $decode .= "\n".$indent."Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            $decode .= "\n".$indent;

            # to be decoded
			$decode .= "Data Repetition: ";
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 2;
 			$decode .= $indent."Data Transfer Control: ";
			my $datatransferControl = (hex(substr($payload,$byte_idx,2)));
			my $slotbitmap = $DTPCM_SLOT_BITMAP{$datatransferControl&0xFE};	
			$decode .= $slotbitmap." slots ".$DTPCM_MAC_ADDRESS_MODE{$datatransferControl& 0x01};	
            $byte_idx += 2;  
	 		$decode .= $indent."DTPML Size: ";
			my $dtpmlsize = substr($payload,$byte_idx,2);
            $decode .= $dtpmlsize;
            $byte_idx += 2; 
			

		    $decode .= "\n".$indent;	
            $decode .= "Master MAC address: ";
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 4;
			
            $decode .= $indent;
            $decode .= "Master Slot assignement: ";
            $decode .= substr($payload,$byte_idx,$slotbitmap/4);
            $byte_idx += $slotbitmap/4;
			
	        $decode .= $indent."Stop Data Transfer: ";
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 2;
			
			foreach (2..$dtpmlsize) {
				$decode .= "\n".$indent;
				$decode .= "Slave MAC address : ";
				$decode .= substr($payload,$byte_idx+2,2);
				$decode .= substr($payload,$byte_idx,2);
				$byte_idx += 4;
		 
				$decode .= $indent;
				$decode .= "Slave Slot assignement:  ";
				$decode .= substr($payload,$byte_idx,$slotbitmap/4);
				$byte_idx += $slotbitmap/4; 
				
				$decode .= $indent."Stop Data Transfer: ";
				$decode .= substr($payload,$byte_idx,2);
				$byte_idx += 2;
				$decode .= $nocolor;
			}
        }

        # SESSION_UPDATE_DTPCM_RSP
        elsif ($mt_gid_oid eq "410E") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
            }
            
            $decode .= $nocolor;
        }
        
        # SESSION_UPDATE_DTPCM_NTF
        elsif ($mt_gid_oid eq "610E") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $brown;
            
            # Session Handle
            $decode .= " Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            $decode .= "\n".$indent;
                        
            $decode .= $nocolor;
        }
        
        # SESSION_START_CMD
        elsif ($mt_gid_oid eq "2200") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;
            
            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            
            $decode .= $nocolor;
        }
        
        # SESSION_START_RSP
        elsif ($mt_gid_oid eq "4200") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;
            
            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= $brown."   Status OK";
            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }
            
            $decode .= $nocolor;
        }
        
        # SESSION_INFO_NTF
        elsif ( ($mt_gid_oid eq "6200") and ( $session_info_ntf_enable == 1) ) {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= "\n".$indent.$brown;
            
            my $nb_meas = 0;
            
            # Sequence Number
            my $seq_number = hex(substr($payload,$byte_idx+6,2));
            $seq_number = (256*$seq_number) + hex(substr($payload,$byte_idx+4,2));
            $seq_number = (256*$seq_number) + hex(substr($payload,$byte_idx+2,2));
            $seq_number = (256*$seq_number) + hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;
            
            $decode .= " Sequence Number:".$seq_number;
            
            # Session ID
            my $session_id = substr($payload,$byte_idx+6,2);
            $session_id .= substr($payload,$byte_idx+4,2);
            $session_id .= substr($payload,$byte_idx+2,2);
            $session_id .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            $decode .= "   Session Handle:0x".$session_id;
            
            # RCR Indication (1 byte)
            $byte_idx += 2;
            
            $decode .= "\n".$indent.$brown;
            
            # Current Ranging Interval
            my $current_interval = hex(substr($payload,$byte_idx+6,2));
            $current_interval = (256*$current_interval) + hex(substr($payload,$byte_idx+4,2));
            $current_interval = (256*$current_interval) + hex(substr($payload,$byte_idx+2,2));
            $current_interval = (256*$current_interval) + hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;
            
            $decode .= " Interval:".$current_interval."ms";
            
            # Ranging Measurement Type
            my $meas_type = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            
            $decode .= "   Type:".($ranging_measurement_type{$meas_type} || "???");
            
            # RFU (1 byte)
            $byte_idx += 2;
            
            # MAC addressing mode
            my $mac_mode = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            
            # RFU (8 byte)
            $byte_idx += 16;
            
            # Number of ranging measurements
            $nb_meas = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            
            $csv_rangedata = "";
            $csv_ranging_type =  $meas_type;
            
            my $meas_idx = 0;
            my @csv_range_meas;

            my $frame_value;
            
			if ( $nb_meas != 0 ){
				foreach $meas_idx (1..$nb_meas) {
					$csv_range_meas[$meas_idx] = $meas_idx;
					
					$decode .= "\n".$indent.$brown;
					
					if ($device_msg ne "") {
						$csv_range_meas[$meas_idx] .= $device_msg.";";
					}
					
					# MAC Address
					my $mac_addr = 0x0000;
					if ($mac_mode eq "01") {
						$mac_addr = substr($payload,$byte_idx+14,2);
						$mac_addr .= substr($payload,$byte_idx+12,2);
						$mac_addr .= substr($payload,$byte_idx+10,2);
						$mac_addr .= substr($payload,$byte_idx+8,2);
						$mac_addr .= substr($payload,$byte_idx+6,2);
						$mac_addr .= substr($payload,$byte_idx+4,2);
						$mac_addr .= substr($payload,$byte_idx+2,2);
						$mac_addr .= substr($payload,$byte_idx,2);
						$byte_idx += 16;
					} else {
						$mac_addr = substr($payload,$byte_idx+2,2).substr($payload,$byte_idx,2);
						$byte_idx += 4;
					}
					
					$csv_range_meas[$meas_idx] .= ";0x".$mac_addr;
					
					$decode .= "   Addr:0x".$mac_addr;

					# Status
					$ft_status = substr($payload,$byte_idx,2);
					$byte_idx += 2;

					$csv_range_meas[$meas_idx] .= ";".$ft_status;
					
					if ($meas_type eq "00") {
						# Message Control (1 byte)
						$byte_idx += 2;

						# Frame Type 
						$frame_value = substr($payload,$byte_idx,2);
						$byte_idx += 2;

						# Frame Type
						$decode .= "   ".($frame_type{$frame_value} || "???");
					}

					if ((($meas_type eq "01") or ($meas_type eq "02")) and (($ft_status ne "00") and ($ft_status ne "1B"))) {
						#  Invalid Status
						$decode .= "   ".$red_oops.($status_code{$ft_status} || "???");
						
						if ($meas_type eq "01") {
							# Skip following fields (15 bytes)
							$byte_idx += 30;
							
							# Slot Index
							my $slot_idx = hex(substr($payload,$byte_idx,2));
							$byte_idx += 2;
							
							$csv_range_meas[$meas_idx] .= ";;;;;;;".$slot_idx;
							
							$decode .= "   Slot Idx:".$slot_idx;
							
							 # RSSI
							my $rssi = hex(substr($payload,$byte_idx,2));
							$byte_idx += 2;
							
							if ($mac_mode eq "00") {
								# RFU (11 bytes)
								$byte_idx += 22;
							} else {
								# RFU (5 bytes)
								$byte_idx += 10;
							}
						} else {
							# Skip following fields (33 bytes)
							$byte_idx += 66;
						}
					} elsif (($meas_type eq "03") and ($ft_status ne "00")) {
						# Invalid Status
						$decode .= "   ".$red_oops."Interframe interval timeout";
						
						# Skip following fields (10 bytes)
						$byte_idx += 20;
					} else {
						if ($meas_type eq "02") {
							# Message Type
							my $msg_type = substr($payload,$byte_idx,2);
							$byte_idx += 2;
							
							$csv_range_meas[$meas_idx] .= ";".$msg_type;
							
							$decode .= "   ".($message_type{$msg_type} || "???");

							# Message Control
							my $msg_ctrl = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
							$byte_idx += 4;

							$decode .= "\n";
							$decode .= $indent."Message Control: \n";
							$decode .= $indent.$indent;

							# b0
							if ($msg_ctrl & 0x0001) {
								$decode .= "TX timestamp local time based";
							} else {
								$decode .= "TX timestamp common time based";
							}
							# b1-b2
							if ($msg_ctrl & 0x0002) {
								$decode .= " - 64bit TX timestamp";
							} elsif ($msg_ctrl & 0x0004 || $msg_ctrl & 0x0006) {
								# RFU
							}  else {
								$decode .= " - 40bit TX timestamp";
							}
							# b4-b3
							if ($msg_ctrl & 0x0100) {
								$decode .= " - 64bit RX timestamp";
							} elsif ($msg_ctrl & 0x0080 || $msg_ctrl & 0x0180) {
								# RFU
							} else {
								$decode .= " - 40bit RX timestamp";
							}
							$decode .= "\n".$indent.$indent;
							# b6-b5
							if ($msg_ctrl & 0x0600) {
								# RFU
							} elsif ($msg_ctrl & 0x0200) {
								$decode .= " - DT_Anchor location included WGS-84";
							} elsif ($msg_ctrl & 0x0400) {
								$decode .= " - DT_Anchor location not included relative";
							} else {
								$decode .= " - DT_Anchor location not included";
							}
							# b7-b10
							my $num_rang_roun_act = ($msg_ctrl & 0x7800) >> 11;
							$decode .= " - Number of active ranging rounds: ".$num_rang_roun_act;
							# b11-b15 RFU

							# Block Index
							my $block_idx = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
							$byte_idx += 4;
							
							$csv_range_meas[$meas_idx] .= ";".$block_idx;
							
							$decode .= "   Block index:".$block_idx;
							
							# Round Index
							my $round_idx = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
							$byte_idx += 4;
							
							$csv_range_meas[$meas_idx] .= ";".$round_idx;
							
							$decode .= "   Round index:".$round_idx;
						}
						
						# Line of Sight
						my $nlos = substr($payload,$byte_idx,2);
						$byte_idx += 2;
						
						$csv_range_meas[$meas_idx] .= ";".$nlos;
						
						$decode .= "   ".($los_type{$nlos} || "???");
						
						if ($meas_type eq "01") {
							# Distance
							my $dist = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
							$byte_idx += 4;
							
							$csv_range_meas[$meas_idx] .= ";".$dist;
							if ($ft_status eq "1B") {
								$decode .= "   Dist: -".$dist."cm";
							}
							else {
								$decode .= "   Dist: ".$dist."cm";
							}
						}
						
						if ($meas_type eq "03") {
							# Frame Sequence Number
							my $frame_seq_number = hex(substr($payload,$byte_idx,2));
							$byte_idx += 2;
							
							$csv_range_meas[$meas_idx] .= ";".$frame_seq_number;
							
							$decode .= "   Frame Seq Number: ".$frame_seq_number;
							
							# Block Index
							my $block_idx = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
							$byte_idx += 4;
							
							$csv_range_meas[$meas_idx] .= ";".$block_idx;
							
							$decode .= "   Block index: ".$block_idx;
							
							$decode .= "\n".$indent.$brown."   ";
						}

						# Global Generic Meas. Data
						if (($meas_type eq "00") or ($meas_type eq "01") or ($meas_type eq "03")) {
							# Angle of Arrival Azimuth (signed Q9.7 value)
							my $aoa_azimuth = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
							$aoa_azimuth -= 0x10000 if ($aoa_azimuth > 32767);
							$aoa_azimuth = $aoa_azimuth/128;
							$byte_idx += 4;
							
							$csv_range_meas[$meas_idx] .= ";".sprintf("%.1f",$aoa_azimuth);
							
							$decode .= "   Azimuth: ".sprintf("%.1f",$aoa_azimuth)."deg";
							
							# Angle of Arrival Azimuth FOM
							my $aoa_azimuth_fom = hex(substr($payload,$byte_idx,2));
							$byte_idx += 2;
							
							$csv_range_meas[$meas_idx] .= ";".$aoa_azimuth_fom;
							
							$decode .= " (FOM:".$aoa_azimuth_fom."%)";
							#$decode .= " INDEX ".$byte_idx; #  PBE
							
							# Angle of Arrival Elevation (signed Q9.7 value)
							my $aoa_elevation = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
							$aoa_elevation -= 0x10000 if ($aoa_elevation > 32767);
							$aoa_elevation = $aoa_elevation/128;
							$byte_idx += 4;
							
							$csv_range_meas[$meas_idx] .= ";".sprintf("%.1f",$aoa_elevation);
							
							$decode .= "   Elevation: ".sprintf("%.1f",$aoa_elevation)."deg";
							
							# Angle of Arrival Elevation FOM
							my $aoa_elevation_fom = hex(substr($payload,$byte_idx,2));
							$byte_idx += 2;
							
							$csv_range_meas[$meas_idx] .= ";".$aoa_elevation_fom;
							
							$decode .= " (FOM:".$aoa_elevation_fom."%)";
						}

						# Generic Meas. Data
						if ($meas_type eq "00") {
							$decode .= "\n".$indent.$brown;
							
							# Timestamp
							my $timestamp = hex(substr($payload,$byte_idx+14,2));
							$timestamp = (256*$timestamp) + hex(substr($payload,$byte_idx+12,2));
							$timestamp = (256*$timestamp) + hex(substr($payload,$byte_idx+10,2));
							$timestamp = (256*$timestamp) + hex(substr($payload,$byte_idx+8,2));
							$timestamp = (256*$timestamp) + hex(substr($payload,$byte_idx+6,2));
							$timestamp = (256*$timestamp) + hex(substr($payload,$byte_idx+4,2));
							$timestamp = (256*$timestamp) + hex(substr($payload,$byte_idx+2,2));
							$timestamp = (256*$timestamp) + hex(substr($payload,$byte_idx,2));
							$byte_idx += 16;
							
							$csv_range_meas[$meas_idx] .= ";".$timestamp;
							
							$decode .= "      Timestamp: ".$timestamp;
							
							# Blink Frame Number
							my $blink_frame_nb = hex(substr($payload,$byte_idx+6,2));
							$blink_frame_nb = (256*$blink_frame_nb) + hex(substr($payload,$byte_idx+4,2));
							$blink_frame_nb = (256*$blink_frame_nb) + hex(substr($payload,$byte_idx+2,2));
							$blink_frame_nb = (256*$blink_frame_nb) + hex(substr($payload,$byte_idx,2));
							$byte_idx += 8;
							
							$csv_range_meas[$meas_idx] .= ";".$blink_frame_nb;
							
							$decode .= "   Blink Frame Number:".$blink_frame_nb;
							
							if ($mac_mode eq "00") {
								# RFU (12 bytes)
								$byte_idx += 24;
							} else {
								# RFU (6 bytes)
								$byte_idx += 12;
							}
							
							# Device Specific Information
							my $dev_spec_info_length = hex(substr($payload,$byte_idx,2));
							$byte_idx += 2;

							if ($dev_spec_info_length > 0) {
								$decode .= "\n".$indent.$brown."      Device Specific Data:";
								
								# Calculate space for indent and label
								my $busy_space = length($indent)+27;
								
								# Truncate the data if exceeds the size of terminal width
								my $dev_spec_info = (($dev_spec_info_length*2) > ($MAX_LINE_SIZE-$busy_space)) ? substr($payload,$byte_idx,$MAX_LINE_SIZE-$busy_space-3)."..." : substr($payload,$byte_idx,$dev_spec_info_length*2);
								$byte_idx += $dev_spec_info_length*2;
								
								$decode .= $dev_spec_info;
							}
							
							# Blink Payload Data
							my $blink_data_length = hex(substr($payload,$byte_idx,2));
							$byte_idx += 2;
							
							if ($blink_data_length > 0) {
							$decode .= "\n".$indent.$brown."      Blink Payload Data:";
							
							# Calculate space for indent and label
							my $busy_space = length($indent)+25;
							
							# Truncate the data if exceeds the size of terminal width
							my $blink_data = (($blink_data_length*2) > ($MAX_LINE_SIZE-$busy_space)) ? substr($payload,$byte_idx,$MAX_LINE_SIZE-$busy_space-3)."..." : substr($payload,$byte_idx,$blink_data_length*2);
							$byte_idx += $blink_data_length*2;
							
							$decode .= $blink_data;
							}
						}

						# Generic Meas. Data
						if ($meas_type eq "01") {
							$decode .= "\n".$indent.$brown;
							
							# Angle of Arrival Destination Azimuth (signed Q9.7 value)
							my $aoa_dest_azimuth = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
							$aoa_dest_azimuth -= 0x10000 if ($aoa_dest_azimuth > 32767);
							$aoa_dest_azimuth = $aoa_dest_azimuth/128;
							$byte_idx += 4;
							
							$csv_range_meas[$meas_idx] .= ";".sprintf("%.1f",$aoa_dest_azimuth);
							$decode .= "      Destination Azimuth: ".sprintf("%.1f",$aoa_dest_azimuth)."deg";
							
							# Angle of Arrival Destination Azimuth FoM
							my $aoa_dest_azimuth_fom = hex(substr($payload,$byte_idx,2));
							$byte_idx += 2;
							
							$csv_range_meas[$meas_idx] .= ";".$aoa_dest_azimuth_fom;
							$decode .= " (FoM:".$aoa_dest_azimuth_fom."%)";
							
							# Angle of Arrival Destination Elevation (signed Q9.7 value)
							my $aoa_dest_elevation = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
							$aoa_dest_elevation -= 0x10000 if ($aoa_dest_elevation > 32767);
							$aoa_dest_elevation = $aoa_dest_elevation/128;
							$byte_idx += 4;
							
							$csv_range_meas[$meas_idx] .= ";".sprintf("%.1f",$aoa_dest_elevation);
							$decode .= "   Destination Elevation: ".sprintf("%.1f",$aoa_dest_elevation)."deg";
							
							# Angle of Arrival Destination Elevation FoM
							my $aoa_dest_elevation_fom = hex(substr($payload,$byte_idx,2));
							$byte_idx += 2;
							
							$csv_range_meas[$meas_idx] .= ";".$aoa_dest_elevation_fom;
							$decode .= " (FoM:".$aoa_dest_elevation_fom."%)";
							
							# Slot Index
							my $slot_idx = hex(substr($payload,$byte_idx,2));
							$csv_range_meas[$meas_idx] .= ";".$slot_idx;
							$byte_idx += 2;

							# RSSI (Q7.1 format)
							my $rssi = hex(substr($payload,$byte_idx,2));
							$byte_idx += 2;

							if ($rssi == 0) {
								$decode .= "   RSSI: DISABLED";
								$csv_range_meas[$meas_idx] .= ";".-($rssi);
							} else {
								$decode .= "   RSSI: ".sprintf("%.1f",-(($rssi/2)+($rssi & 1)))."dBm";
								$csv_range_meas[$meas_idx] .= ";".sprintf("%.1f",-(($rssi/2)+($rssi & 1)));
							}
							
							if ($mac_mode eq "00") {
								# RFU (11 bytes)
								$byte_idx += 22;
							} else {
								# RFU (5 bytes)
								$byte_idx += 10;
							}
						}

						# Generic Meas. Data
						if ($meas_type eq "02") {
							$decode .= "\n".$indent.$brown;

							# RSSI (Q7.1 format)
							my $rssi = hex(substr($payload,$byte_idx,2));
							$byte_idx += 2;

							if ($rssi == 0) {
								$decode .= "   RSSI: DISABLED";
								$csv_range_meas[$meas_idx] .= ";".-($rssi);
							} else {
								$decode .= "   RSSI: ".sprintf("%.1f",-(($rssi/2)+($rssi & 1)))."dBm";
								$csv_range_meas[$meas_idx] .= ";".sprintf("%.1f",-(($rssi/2)+($rssi & 1)));
							}

							$decode .= "\n".$indent.$brown;
							
							# TX Timestamp
							my $tx_timestamp = hex(substr($payload,$byte_idx+14,2));
							$tx_timestamp = (256*$tx_timestamp) + hex(substr($payload,$byte_idx+12,2));
							$tx_timestamp = (256*$tx_timestamp) + hex(substr($payload,$byte_idx+10,2));
							$tx_timestamp = (256*$tx_timestamp) + hex(substr($payload,$byte_idx+8,2));
							$tx_timestamp = (256*$tx_timestamp) + hex(substr($payload,$byte_idx+6,2));
							$tx_timestamp = (256*$tx_timestamp) + hex(substr($payload,$byte_idx+4,2));
							$tx_timestamp = (256*$tx_timestamp) + hex(substr($payload,$byte_idx+2,2));
							$tx_timestamp = (256*$tx_timestamp) + hex(substr($payload,$byte_idx,2));
							$byte_idx += 16;
							
							$csv_range_meas[$meas_idx] .= ";".$tx_timestamp;
							
							$decode .= "      TX Timestamp:".$tx_timestamp;
							
							# RX Timestamp
							my $rx_timestamp = hex(substr($payload,$byte_idx+14,2));
							$rx_timestamp = (256*$rx_timestamp) + hex(substr($payload,$byte_idx+12,2));
							$rx_timestamp = (256*$rx_timestamp) + hex(substr($payload,$byte_idx+10,2));
							$rx_timestamp = (256*$rx_timestamp) + hex(substr($payload,$byte_idx+8,2));
							$rx_timestamp = (256*$rx_timestamp) + hex(substr($payload,$byte_idx+6,2));
							$rx_timestamp = (256*$rx_timestamp) + hex(substr($payload,$byte_idx+4,2));
							$rx_timestamp = (256*$rx_timestamp) + hex(substr($payload,$byte_idx+2,2));
							$rx_timestamp = (256*$rx_timestamp) + hex(substr($payload,$byte_idx,2));
							$byte_idx += 16;
							
							$csv_range_meas[$meas_idx] .= ";".$rx_timestamp;
							
							$decode .= "   RX Timestamp:".$rx_timestamp;
							
							$decode .= "\n".$indent.$brown;
							
							# CFO Anchor
							my $cfo_anchor = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
							$cfo_anchor -= 0x10000 if ($cfo_anchor > 32767);
							$cfo_anchor = $cfo_anchor/128;
							# $cfo_anchor = $cfo_anchor/2048;
							$byte_idx += 4;
							
							$csv_range_meas[$meas_idx] .= ";".$cfo_anchor;
							
							$decode .= "      CFO Anchor:".$cfo_anchor;
							
							# CFO
							my $cfo = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
							$cfo -= 0x10000 if ($cfo > 32767);
							$cfo = $cfo/128;
							# $cfo = $cfo/2048;
							$byte_idx += 4;
							
							$csv_range_meas[$meas_idx] .= ";".$cfo;
							
							$decode .= "   CFO:".$cfo;
							
							$decode .= "\n".$indent.$brown;
							
							# Reply Time of Initiator
							my $reply_time_initiator = hex(substr($payload,$byte_idx+6,2));
							$reply_time_initiator = (256*$reply_time_initiator) + hex(substr($payload,$byte_idx+4,2));
							$reply_time_initiator = (256*$reply_time_initiator) + hex(substr($payload,$byte_idx+2,2));
							$reply_time_initiator = (256*$reply_time_initiator) + hex(substr($payload,$byte_idx,2));
							$byte_idx += 8;
							
							$csv_range_meas[$meas_idx] .= ";".$reply_time_initiator;
							
							$decode .= "      Reply Time of Initiator:".$reply_time_initiator;
							
							# Reply Time of Responser
							my $reply_time_responder = hex(substr($payload,$byte_idx+6,2));
							$reply_time_responder = (256*$reply_time_responder) + hex(substr($payload,$byte_idx+4,2));
							$reply_time_responder = (256*$reply_time_responder) + hex(substr($payload,$byte_idx+2,2));
							$reply_time_responder = (256*$reply_time_responder) + hex(substr($payload,$byte_idx,2));
							$byte_idx += 8;
							
							$csv_range_meas[$meas_idx] .= ";".$reply_time_responder;
							
							$decode .= "   and of Responder:".$reply_time_responder;
						}
					}
				}
				
				# Vendor Specific Data
				my @csv_vs_ext_meas;
				my $vs_data_length = 0;
				my $ve_data_length = 0;

				my $writable_rangedata_vendor = 0;
				if ($fh_rangedata_vendor ne "") {
					$writable_rangedata_vendor = 1;
				}
				
				if (($byte_idx < length($payload)) && (($ft_status eq "00") or ($ft_status eq "1B"))) {
					$vs_data_length = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
					$byte_idx += 4;
				 
					if ($vs_data_length > 0) {
						$decode .= "\n".$indent.$brown." Vendor Specific Data";
						
						foreach $meas_idx (1..$nb_meas) {
							if ($vs_data_length > 0) {
								$decode .= "\n".$indent.$brown;
								
								if ($csv_ranging_type eq "00") {

									# Vendor Extension Length
									$ve_data_length = hex(substr($payload,$byte_idx,2));
									$byte_idx += 2;

									# RSSI (signed Q8.8)
									my $rssi_rx1 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
									$rssi_rx1 -= 0x10000 if ($rssi_rx1 > 32767);
									$rssi_rx1 = $rssi_rx1/256;
									$byte_idx += 4;
						
									my $rssi_rx2 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
									$rssi_rx2 -= 0x10000 if ($rssi_rx2 > 32767);
									$rssi_rx2 = $rssi_rx2/256;
									$byte_idx += 4;
						
									$decode .= "   RSSI RX1:".$rssi_rx1."   RSSI RX2:".$rssi_rx2;

									# PDoA Measurements
									my $nb_pdoa_meas = hex(substr($payload,$byte_idx,2));
									$byte_idx += 2;
						
									foreach my $idx (1..$nb_pdoa_meas) {
										$decode .= "\n".$indent.$brown;
							
										if ($idx == 1) {
											$decode .= "   PDoA:";
										} else {
											$decode .= "        ";
										}
							
										# Phase Differences of Arrival (signed Q9.7 value)
										my $pdoa = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
										$pdoa -= 0x10000 if ($pdoa > 32767);
										$pdoa = $pdoa/128;
										$byte_idx += 4;
							
										$decode .= sprintf("%+07.2f",$pdoa)."deg";
							
										# PDoA Index
										my $pdoa_idx = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
										$byte_idx += 4;
							
										$decode .= "   Index:".$pdoa_idx;
									}

									# RX Antenna Info
									my $rx_mode = substr($payload,$byte_idx,2);
									# my $num_ant = substr($payload,$byte_idx+2,2);
									$byte_idx += 2;

									$decode .= "\n".$indent."   Rx Mode: ".$RX_MODE{$rx_mode};

									if ($rx_mode eq "00" || $rx_mode eq "02" || $rx_mode eq "03") {
										my $ant_id = hex(substr($payload,$byte_idx,2));
										$decode .= "   Antenna ID: ".$ant_id;
										$byte_idx += 2;

										if ($writable_rangedata_vendor == 0) {
											$fh_rangedata_vendor .= ";AoA".$ant_id;
											$fh_rangedata_vendor .= ";PDoA".$ant_id;
										}
									} elsif ($rx_mode eq "01" || $rx_mode eq "04") {
										my $ant_id = hex(substr($payload,$byte_idx,2));
										$decode .= "   Antenna pair ID: ".$ant_id;
										$byte_idx += 2;

										$ant_id = hex(substr($payload,$byte_idx,2));
										$decode .= "   Antenna pair ID: ".$ant_id;
										$byte_idx += 2;

										if ($writable_rangedata_vendor == 0) {
											# $fh_rangedata_vendor .= ";AoA pair ID".$ant_id;
											# $fh_rangedata_vendor .= ";PDoA pair ID".$ant_id;
											}
									}

									# WIFI COEX
									my $wifi_coex = substr($payload,$byte_idx,2);
									$byte_idx += 2;
									$decode .= "\n".$indent."   Wifi Coex: ".$WIFI_COEX_STATUS{$wifi_coex};

									# AUTHENTICITY_INFO_PRESENCE
									my $val = substr($payload,$byte_idx,2);
									$decode .= "   Authenticity Info: ".$AUTHENTICITY_INFO_PRESENCE{$val};
									$byte_idx += 2;

								}

								if ($csv_ranging_type eq "01") {
									# NXP Specific Data Type
									my $vs_ext_type = substr($payload,$byte_idx,2);
									my $AntennaTxInfo = 0;
		
									if ($vs_ext_type eq "A1"){
										$byte_idx += 2;
										my $message_control = substr($payload,$byte_idx,2);	
										$byte_idx += 2;
										if ($message_control == "02"){									
											$AntennaTxInfo = 1;
										}
										$vs_ext_type = substr($payload,$byte_idx,2);									
									}
									
									$byte_idx += 2;
									
									$decode .= "   Type: ".$VENDOR_SPECIFIC_TYPE{$vs_ext_type};

									# NXP Specific FIXED PART
									# WIFI COEX
									my $wifi_coex = substr($payload,$byte_idx,2);
									$byte_idx += 2;
									$decode .= "   Wifi Coex: ".$WIFI_COEX_STATUS{$wifi_coex};
									
									# RX Antenna Info for AoA measure
									my $rx_mode = substr($payload,$byte_idx,2);
									my $num_ant = substr($payload,$byte_idx+2,2);
									my $RX_Antenna_Info = substr($payload,$byte_idx,8);
									my $Antenna_Config_Rx_mode = hex(substr($RX_Antenna_Info,0,2)); #GM April 16 2024
									$byte_idx += 4;
									
									$csv_vs_ext_meas[$meas_idx] .= ";".$RX_Antenna_Info;
									if ($writable_rangedata_vendor == 0) {
										#$fh_rangedata_vendor .= ";RX Antenna Info".$RX_Antenna_Info;
										$fh_rangedata_vendor .= ";RX Antenna Info";
									}

									$decode .= "\n".$indent."   Rx Mode: ".$RX_MODE{$rx_mode};

									if ($rx_mode eq "00" || $rx_mode eq "02" || $rx_mode eq "03") {
										foreach (1..$num_ant) {
											my $ant_id = hex(substr($payload,$byte_idx,2));
											$decode .= "   Antenna ID: ".$ant_id;
											$byte_idx += 2;

											if ($writable_rangedata_vendor == 0) {
												$fh_rangedata_vendor .= ";AoA".$ant_id;
												$fh_rangedata_vendor .= ";PDoA".$ant_id;
											}
										}
									} elsif ($rx_mode eq "01" || $rx_mode eq "04") {
										foreach (1..$num_ant) {
											my $ant_id = hex(substr($payload,$byte_idx,2));
											$decode .= "   Antenna pair ID: ".$ant_id;
											$byte_idx += 2;

											if ($writable_rangedata_vendor == 0) {
												$fh_rangedata_vendor .= ";AoA".$ant_id;
												$fh_rangedata_vendor .= ";PDoA".$ant_id;
											}
										}
									}

									# RX Antenna Info DEBUG NTF
									my $rx_mode_dbg = substr($payload,$byte_idx,2);
									my $num_ant_dbg = substr($payload,$byte_idx+2,2);
									$byte_idx += 4;

									# $decode .= "\n".$indent."   Rx Mode: ".$RX_MODE{$rx_mode};
									$decode .= "\n".$indent;

									if ($rx_mode eq "00" || $rx_mode eq "02" || $rx_mode eq "03") {
										foreach (1..$num_ant_dbg) {
											my $ant_id = hex(substr($payload,$byte_idx,2));
											$decode .= "   Antenna ID Debug: ".$ant_id;
											$byte_idx += 2;
											# $decode .= " INDEX PBE ".$byte_idx; #  PBE
											if ($writable_rangedata_vendor == 0) {
												$fh_rangedata_vendor .= ";SNR FP ant ID".$ant_id;
												$fh_rangedata_vendor .= ";SNR MP ant ID".$ant_id;
												$fh_rangedata_vendor .= ";SNR FP IDX ant ID".$ant_id;
												$fh_rangedata_vendor .= ";SNR MP IDX ant ID".$ant_id;
											}
										}
									} elsif ($rx_mode eq "01" || $rx_mode eq "04") {
										foreach (1..$num_ant_dbg) {
											my $ant_id = hex(substr($payload,$byte_idx,2));
											$decode .= "   Antenna ID Debug: ".$ant_id;
											$byte_idx += 2;

											if ($writable_rangedata_vendor == 0) {
												$fh_rangedata_vendor .= ";SNR FP pair ID".$ant_id;
												$fh_rangedata_vendor .= ";SNR MP pair ID".$ant_id;
												$fh_rangedata_vendor .= ";SNR FP IDX pair ID".$ant_id;
												$fh_rangedata_vendor .= ";SNR MP IDX pair ID".$ant_id;
											}
										}
									}

									# AoA/PDoA/FoV meas
									if (($rx_mode ne "00" || $num_ant != 1)
										&& ($Antenna_Config_Rx_mode == 1
											|| $Antenna_Config_Rx_mode == 3
											|| $Antenna_Config_Rx_mode == 4)) {
										for (my $i=0; $i<$num_ant; $i++) {
												#AoA Q9.7
											my $aoa = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
											$aoa -= 0x10000 if ($aoa > 32767);
											$aoa = $aoa/128;
											$byte_idx += 4;
											$decode .= "\n".$indent."   AoA: ".$aoa;
											$csv_vs_ext_meas[$meas_idx] .= ";".$aoa;
												#PDoA Q9.7
											my $pdoa = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
											$pdoa -= 0x10000 if ($pdoa > 32767);
											$pdoa = $pdoa/128;
											$byte_idx += 4;
											$decode .= "   PDoA: ".$pdoa;
											$csv_vs_ext_meas[$meas_idx] .= ";".$pdoa;
												#PDoA index in whole CIR
											my $pdoa_cir = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
											$byte_idx += 4;
											$decode .= "   PDoA idx (CIR): ".$pdoa_cir;
												#FoV
											if ($vs_ext_type eq "0A") {
												my $fov = hex(substr($payload,$byte_idx,2));
												$byte_idx += 2;
												$decode .= "   FoV: ".$fov;
											}                                 
										}
									} elsif  (($rx_mode ne "00" || $num_ant != 1)
										&& ($Antenna_Config_Rx_mode == 1)) {
										for (my $i=0; $i<$num_ant; $i++) {
												#AoA Q9.7
											my $aoa = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
											$aoa -= 0x10000 if ($aoa > 32767);
											$aoa = $aoa/128;
											$byte_idx += 4;
											$decode .= "\n".$indent."   AoA: ".sprintf("%.1f",$aoa)."deg";
											$csv_vs_ext_meas[$meas_idx] .= ";".$aoa;
												#PDoA Q9.7
											my $pdoa = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
											$pdoa -= 0x10000 if ($pdoa > 32767);
											$pdoa = $pdoa/128;
											$byte_idx += 4;
											$decode .="   PDoA: " .sprintf("%+07.2f",$pdoa)."deg";
											$csv_vs_ext_meas[$meas_idx] .= ";".$pdoa;

											# PDoA Index
											my $pdoa_idx = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
											$byte_idx += 4;
											$decode .= "   Index:".$pdoa_idx;

											# if ($writable_rangedata_vendor == 0) {
											#     my $ant_id = $i; $ant_id += 1;
											#     $fh_rangedata_vendor .= ";AoA".$ant_id;
											#     $fh_rangedata_vendor .= ";PDoA".$ant_id;
											#}                                         
										}
									} else {
										$csv_vs_ext_meas[$meas_idx] .= ";-;-;-";
									}

									if ( $AntennaTxInfo == 1){
										my $TxAntennaUsed = $wifi_coex = substr($payload,$byte_idx,2);
										 $byte_idx += 2;
										 $decode .= "   Tx Antenna Used:".$TxAntennaUsed;
									}

									# SNR
									for (my $i=0; $i<$num_ant_dbg; $i++) {
										my $snr_fp = hex(substr($payload,$byte_idx,2));
										$decode .= "\n".$indent."   SNR (First Path): ".$snr_fp;
										$csv_vs_ext_meas[$meas_idx] .= ";".$snr_fp;

										my $snr_mp = hex(substr($payload,$byte_idx+2,2));
										$decode .= "   SNR (Main Path): ".$snr_mp;
										$csv_vs_ext_meas[$meas_idx] .= ";".$snr_mp;
										
										# Q10.6
										my $snr_fp_idx = (256*hex(substr($payload,$byte_idx+6,2))) + hex(substr($payload,$byte_idx+4,2));
										$snr_fp_idx = $snr_fp_idx/64;
										$decode .= "   SNR (First Path) Index: ".sprintf("%.1f",$snr_fp_idx)."ns";
										$csv_vs_ext_meas[$meas_idx] .= ";".$snr_fp_idx;

										# Q10.6
										my $snr_mp_idx = (256*hex(substr($payload,$byte_idx+10,2))) + hex(substr($payload,$byte_idx+8,2));
										$snr_mp_idx = $snr_mp_idx/64;
										$decode .= "   SNR (Main Path) Index: ".sprintf("%.1f",$snr_mp_idx)."ns";
										$csv_vs_ext_meas[$meas_idx] .= ";".$snr_mp_idx;
										
										$byte_idx += 12;
									}

									# DISTANCE_2
									if ($rx_mode eq "03" || $rx_mode eq "04") {
										my $dist_2 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
										$byte_idx += 4;
										$decode .= "   DISTANCE_2: ".$dist_2;
									}
								} 

								if ($csv_ranging_type eq "03") {
									my $rssi_rx1 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
									$rssi_rx1 -= 0x10000 if ($rssi_rx1 > 32767);
									$rssi_rx1 = $rssi_rx1/256;
									$byte_idx += 4;
						
									$decode .= "   RSSI RX1:".$rssi_rx1;
								}
							}
						}
					}
				}
				
				foreach $meas_idx (1..$nb_meas) {
					$csv_rangedata .= $seq_number.";0x".$session_id;
					$csv_rangedata .= ";".$csv_range_meas[$meas_idx];
					
					if ($vs_data_length > 0 && $ft_status eq "00") {
						$csv_rangedata .= $csv_vs_ext_meas[$meas_idx];
					}
					
					$csv_rangedata .= "\n";
				}
			}else{
				$decode .= "\n      ";
				$decode .= $red_oops;
				$decode .= "No measurements";
			}
            
            $decode .= $nocolor;
        }
        
        # SESSION_STOP_CMD
        elsif ($mt_gid_oid eq "2201") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;
            
            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            
            $decode .= $nocolor;
        }
        
        # SESSION_STOP_RSP
        elsif ($mt_gid_oid eq "4201") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= $brown."   Status OK";
            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }
        }
        
		# LOGICAL_LINK_CREATE_CMD
		elsif ($mt_gid_oid eq "2207") {
			# Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $yellow;

            # Session Handle
            $decode .= "\n\tSession Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx = $byte_idx+8;
		    
			# Link Layer Mode Selector
			$decode .= "\t Link Layer Mode: ";
            $decode .= $ll_layer_mode{substr($payload,$byte_idx,2)};	
            $byte_idx = $byte_idx+2;
            $decode .= $nocolor;
		}
		# LOGICAL_LINK_CREATE_RSP
		elsif ($mt_gid_oid eq "4207") {
			# Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $yellow;
            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= "   Status OK";
            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }

            $byte_idx = $byte_idx+2;

            # LL Connection ID
            $decode .= "     LL Connection ID:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx = $byte_idx+8;

            $decode .= $nocolor;
		}
		# LOGICAL_LINK_CREATE_NTF
		elsif ($mt_gid_oid eq "6207") {
			# Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $yellow;

            # LL Connection ID
            $decode .= "     LL Connection ID:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx = $byte_idx+8;

            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= "   Link Accepted";
            } 
			elsif (substr($payload,$byte_idx,2) eq "01") {
                $decode .= $red."   Link Reject";
            }
			elsif (substr($payload,$byte_idx,2) eq "02") {
                $decode .= "   CO_LINK_CONNECTED";
            }
			elsif (substr($payload,$byte_idx,2) eq "03") {
                $decode .= "   LINK_ERROR";
            }
			else{
				$decode .= $red."   Unknown Error";
			}
            $byte_idx = $byte_idx+2;

            $decode .= $nocolor;
		}
		# LOGICAL_LINK_CLOSE_CMD
		elsif ($mt_gid_oid eq "2208") {
			# Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $yellow;

            # LL Connection ID
            $decode .= "   LL Connection ID:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx = $byte_idx+8;
            $decode .= $nocolor;
		}
		# LOGICAL_LINK_CLOSE_RSP
		elsif ($mt_gid_oid eq "4208") {
			# Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $yellow;

            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= "   Status OK";
            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }
            $decode .= $nocolor;
		}		
        # SESSION_GET_RANGING_COUNT_CMD
        elsif ($mt_gid_oid eq "2203") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $brown;

            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            
            $decode .= $nocolor;
        }
        
        # SESSION_GET_RANGING_COUNT_RSP
        elsif ($mt_gid_oid eq "4203") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            } else {
                $decode .= "\n".$indent.$brown;
                # Count
                my $count = hex(substr($payload,$byte_idx+6,2));
                $count += (256*hex(substr($payload,$byte_idx+4,2)));
                $count += (256*256*hex(substr($payload,$byte_idx+2,2)));
                $count += (256*256*256*hex(substr($payload,$byte_idx,2)));
                
                $decode .= "   count: ".$count;
            }
            
            $decode .= $nocolor;
        }
        
        # SESSION_DATA_CREDIT_NTF
        elsif ($mt_gid_oid eq "6204") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;
            
            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            # credit
            my $credit = substr($payload,$byte_idx,2);
            $byte_idx += 2;
				
            if ($credit eq "01") {
                $decode .= "   Credit is  available";
            } elsif ($credit eq "00") {
                $decode .= "   Credit is not available";
            }
            
            $decode .= $nocolor;
        }

        # SESSION_DATA_TRANSFER_STATUS_NTF
        elsif ($mt_gid_oid eq "6205") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;

            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;

            $decode .= "\n".$indent;

            # Data Sequence Number
            my $data_seq_nb = hex(substr($payload,$byte_idx,2));
            $data_seq_nb += 256*hex(substr($payload,$byte_idx+2,2));
            $byte_idx += 4;

            $decode .= "Data Sequence Number: ".$data_seq_nb;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($status ne "00" && $status ne "01") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                my $tx_count = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
                $decode .= "   Tx Count: ".$tx_count;
            }
            
        }
		# SESSION_ROLE_CHANGE_NTF
        elsif ($mt_gid_oid eq "6206") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;

            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;

            $decode .= "\n".$indent;

            # Role
            my $role = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($role ne "00" && $role ne "01") {
                $decode .= "   ".$red_oops.($status_code{$role} || "???");
            } else {
                $decode .= "New role: ".$device_role{$role};
            }
        }
		# LOGICAL_LINK_CREATE_NTF
        elsif ($mt_gid_oid eq "6207") {
            
        }
		# LOGICAL_LINK_CLOSE_NTF
        elsif ($mt_gid_oid eq "6208") {
            
        }
		# LOGICAL_LINK_UWBS_CLOSE_NTF
        elsif ($mt_gid_oid eq "6209") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $yellow;

            # LL_CONNECT_ID
            $decode .= "   LL_CONNECT_ID:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;

            $decode .= $indent;

            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;

            $decode .= ($ll_status_code{$status} || "???"); 
        }
		# LOGICAL_LINK_UWBS_CREATE_NTF
        elsif ($mt_gid_oid eq "620A") {
			# Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $magenta;
            $decode .= "\n".$indent;
            # SESSION_HANDLE
            $decode .= "SESSION_HANDLE:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;

            # LL_CONNECT_ID
            $decode .= "   LL_CONNECT_ID:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;



            my $ll_mode = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            $decode .= "   ".($ll_layer_mode{$ll_mode} || "???"); 
			
			# LL_SOURCE_ADDRESS
            $decode .= "   LL_SOURCE_ADDRESS:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
        }		
				
        #################### CCC Ranging Session Control Group (+) ####################
        # RANGE_CCC_DATA_NTF
        elsif ($mt_gid_oid eq "6220") {

            $csv_rangedata = "";
            my $nb_meas = 1;
            my $meas_idx = 1;
            my @csv_range_meas;

            # Store Ranging type for CsV creation
            $csv_ranging_type =  $mt_gid_oid;    

            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            my $writable_rangedata = 0;   # store Title for CSV file is SWAP_ANT_PAIR_3D_AOA =1 
            if ($fh_rangedata_SWAP_ANT_PAIR_3D_AOA ne "") {
                $writable_rangedata = 1;
            }

            $decode .= "\n".$indent.$brown;
            
            # Session ID
            my $session_id = substr($payload,$byte_idx+6,2);
            $session_id .= substr($payload,$byte_idx+4,2);
            $session_id .= substr($payload,$byte_idx+2,2);
            $session_id .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            $decode .= " Session Handle:0x".$session_id;
            
            
            # Ranging Status
            my $controlee_status = substr($payload,$byte_idx,1);
            my $controller_status = substr($payload,$byte_idx+1,1);
            $ft_status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
			$decode .= " Status:0x".$ft_status;
			$csv_range_meas[$meas_idx] .= $ft_status.";";

            # foreach $meas_idx (1..$nb_meas) {
                #$csv_range_meas[$meas_idx] = $meas_idx;
                
                # $decode .= "\n".$indent.$brown;
                
                if ($device_msg ne "") {
                    $csv_range_meas[$meas_idx] .= $device_msg.";";
                }

                if ($controlee_status ne "0") {
                    $decode .= " ".$red_oops.($ccc_ranging_status{$controlee_status} || "???");
                } elsif ($controller_status ne "0") {
                    $decode .= " ".$red_oops.($ccc_ranging_status{$controller_status} || "???");
                } else {

                    # STS index
                    my $sts_index = hex(substr($payload,$byte_idx+6,2));
                    $sts_index = (256*$sts_index)+hex(substr($payload,$byte_idx+4,2));
                    $sts_index = (256*$sts_index)+hex(substr($payload,$byte_idx+2,2));
                    $sts_index = (256*$sts_index)+hex(substr($payload,$byte_idx,2));
                    $byte_idx += 8;
                
                    $decode .= " STS index:".$sts_index;
                
                    # RR index
                    my $rr_index = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                    $byte_idx += 4;
                
                    $decode .= "   RR index:".$rr_index;
                
                    $decode .= "\n".$indent.$brown;
					$csv_range_meas[$meas_idx] .= "".$rr_index;

                    # Block Index (CSA)
                    $byte_idx += 4;
					
                    # Distance
                    my $dist = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                    $byte_idx += 4;
                    $csv_range_meas[$meas_idx] .= ";".$dist;
                    $decode .= " Dist:".$dist."cm";
                
                    # Anchor FOM
                    my $anchor_fom = hex(substr($payload,$byte_idx,2));
                    $byte_idx += 2;
                    
                    $decode .= "   Anchor FoM:".$anchor_fom;
                
                    # Initiator FOM
                    my $initiator_fom = hex(substr($payload,$byte_idx,2));
                    $byte_idx += 2;
                    
                    $decode .= "   Initiator FoM:".$initiator_fom;
                
                    # CCM TAG
                    $decode .= "   CCM TAG:".substr($payload,$byte_idx,16);
                    $byte_idx += 16;

                    $decode .= "\n".$indent.$brown;

                    # Angle of Arrival Azimuth (signed Q9.7 value)
                    my $aoa_dest_azimuth = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                    $aoa_dest_azimuth -= 0x10000 if ($aoa_dest_azimuth > 32767);
                    $aoa_dest_azimuth = $aoa_dest_azimuth/128;
                    $byte_idx += 4;   
                    $decode .= "   Azimuth: ".sprintf("%.1f",$aoa_dest_azimuth)."deg";
                    $csv_range_meas[$meas_idx] .= ";".sprintf("%.1f",$aoa_dest_azimuth); 

                    # Angle of Arrival Azimuth FoM
                    my $aoa_dest_azimuth_fom = hex(substr($payload,$byte_idx,2));
                    $byte_idx += 2;
                    $decode .= " (FoM:".$aoa_dest_azimuth_fom."%)";    
                    $csv_range_meas[$meas_idx] .= ";".$aoa_dest_azimuth_fom;

                        
                    # Angle of Arrival Elevation (signed Q9.7 value)
                    my $aoa_dest_elevation = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                    $aoa_dest_elevation -= 0x10000 if ($aoa_dest_elevation > 32767);
                    $aoa_dest_elevation = $aoa_dest_elevation/128;
                    $byte_idx += 4;
                    $decode .= "   Elevation: ".sprintf("%.1f",$aoa_dest_elevation)."deg";    
                    $csv_range_meas[$meas_idx] .= ";".sprintf("%.1f",$aoa_dest_elevation);
                        
                    # Angle of Arrival Elevation FoM
                    my $aoa_dest_elevation_fom = hex(substr($payload,$byte_idx,2));
                    $byte_idx += 2;
                    $decode .= " (FoM:".$aoa_dest_elevation_fom."%)";   
                    $csv_range_meas[$meas_idx] .= ";".$aoa_dest_elevation_fom;

                    $decode .= "\n".$indent.$brown;


                    # RX Antenna Info 
                    my $rx_mode = substr($payload,$byte_idx,2);
                    # my $num_ant = substr($payload,$byte_idx+2,2);
                    my $RX_Antenna_Info = substr($payload,$byte_idx,8);
                    $csv_range_meas[$meas_idx] .= ";".$RX_Antenna_Info;

                    $byte_idx += 2;

                    $decode .= "   Rx Mode: ".$RX_MODE{$rx_mode};

                    my $ant_id_x=0;
                    my $ant_id_y=0;
                    if ($rx_mode eq "00" || $rx_mode eq "02" || $rx_mode eq "03") {
                        # foreach (1..$num_ant) {
                        my $ant_id = hex(substr($payload,$byte_idx,2));
                        $decode .= "   Antenna ID: ".$ant_id;
                        $byte_idx += 2;
                    } elsif ($rx_mode eq "01" || $rx_mode eq "04" || $rx_mode eq "06") {
                        # foreach (1..$num_ant) {
                            my $ant_id = hex(substr($payload,$byte_idx,2));
                            $ant_id_x= $ant_id;
                            $decode .= "   Antenna pair ID: ".$ant_id;
                            $byte_idx += 2;

                            $ant_id = hex(substr($payload,$byte_idx,2));
                            $ant_id_y= $ant_id;
                            $decode .= "   Antenna pair ID: ".$ant_id;
                            $byte_idx += 2;

                    }

                    $byte_idx += 2;  # Octet[3] RFU

                    $decode .= "\n".$indent.$brown;

                    # PDoA Measurements
                    my $nb_pdoa_meas = hex(substr($payload,$byte_idx,2));
                    $byte_idx += 2;
                   
                    foreach my $idx (1..$nb_pdoa_meas) {
                        
                        if ($idx == 1) {
                            $decode .= "   PDoA:";
                        } else {
                                $decode .= "        ";
                        }
                        
                        # Phase Differences of Arrival (signed Q9.7 value)
                        my $pdoa = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                        $pdoa -= 0x10000 if ($pdoa > 32767);
                        $pdoa = $pdoa/128;
                        $byte_idx += 4;                       
                        $decode .= sprintf("%+07.2f",$pdoa)."deg";
                        $csv_range_meas[$meas_idx] .= ";".$pdoa;

                        # PDoA Index
                        my $pdoa_idx = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                        $byte_idx += 4;
                        $csv_range_meas[$meas_idx] .= ";".$pdoa_idx;                 
                        $decode .= "   Index:".$pdoa_idx;
                        $decode .= "\n".$indent.$brown;
                    }

                    # if(index($Device_Name,"SR1") > 0) {
                        # RSSI Measurements
                        my $nb_rssi_meas = hex(substr($payload,$byte_idx,2));
                        $byte_idx += 2;

                        foreach my $idx (1..$nb_rssi_meas) {
                            # RSSI (signed Q8.8)
                            my $rssi_rx1 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                            $rssi_rx1 -= 0x10000 if ($rssi_rx1 > 32767);
                            $rssi_rx1 = $rssi_rx1/256;
                            $byte_idx += 4;
                    
                            my $rssi_rx2 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                            $rssi_rx2 -= 0x10000 if ($rssi_rx2 > 32767);
                            $rssi_rx2 = $rssi_rx2/256;
                            $byte_idx += 4;

                            if ($writable_rangedata == 0) {
                                if  ($idx ==1 ) {
                                    $fh_rangedata_SWAP_ANT_PAIR_3D_AOA .= ";RSSI RX1 Pair ID".$ant_id_x;
                                    $fh_rangedata_SWAP_ANT_PAIR_3D_AOA .= ";RSSI RX2 Pair ID".$ant_id_x;
                                    }
                                elsif ($idx ==2 ) {
                                    $fh_rangedata_SWAP_ANT_PAIR_3D_AOA .= ";RSSI RX1 Pair ID".$ant_id_y;
                                    $fh_rangedata_SWAP_ANT_PAIR_3D_AOA .= ";RSSI RX2 Pair ID".$ant_id_y;
                                    }
                            }

                            $csv_range_meas[$meas_idx] .= ";".$rssi_rx1;
                            $csv_range_meas[$meas_idx] .= ";".$rssi_rx2;
                            $decode .= "   RSSI RX1: ".sprintf("%+06.2f",$rssi_rx1)."dB"."   RSSI RX2: ".sprintf("%+06.2f",$rssi_rx2)."dB";
                           
                        }

                        # SNR_RX Measurements
                        my $nb_snr_meas = hex(substr($payload,$byte_idx,2));
                        $byte_idx += 2;

                        foreach my $idx (1..$nb_snr_meas) {
                            # SNR_RX (signed Q8.8)
                            # Slot Index
                            my $slot_idx = hex(substr($payload,$byte_idx+1,1));
                            my $Ant_Map = hex(substr($payload,$byte_idx,1));

                            $csv_range_meas[$meas_idx] .= ";".$slot_idx;
                            $byte_idx += 2;

                            my $snr_mp = hex(substr($payload,$byte_idx,2));
                            # $decode .= "   SNR (Main Path): ".$snr_mp;
                            $csv_range_meas[$meas_idx] .= ";".$snr_mp;
                            $byte_idx += 2;

                            my $snr_fp = hex(substr($payload,$byte_idx,2));
                            # $decode .= "\n".$indent."   SNR (First Path): ".$snr_fp;
                            $csv_range_meas[$meas_idx] .= ";".$snr_fp;
                            $byte_idx += 2;

                            my $snr_total = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                            $snr_total -= 0x10000 if ($snr_total > 32767);
                            $snr_total = $snr_total/256;
                            # $decode .= "\n".$indent."   SNR (Total): ".$snr_total;
                            $csv_range_meas[$meas_idx] .= ";".$snr_total;
                            $byte_idx += 4;

                            if ($writable_rangedata == 0) {
                                if  ($Ant_Map ==0 ) {
                                    $fh_rangedata_SWAP_ANT_PAIR_3D_AOA .= ";Slot".$slot_idx." RX1";
                                    $fh_rangedata_SWAP_ANT_PAIR_3D_AOA .= ";SNR (MP)";
                                    $fh_rangedata_SWAP_ANT_PAIR_3D_AOA .= ";SNR (FP)";
                                    $fh_rangedata_SWAP_ANT_PAIR_3D_AOA .= ";SNR (Tot)";
                                    }
                                elsif ($Ant_Map ==8 ) {
                                    $fh_rangedata_SWAP_ANT_PAIR_3D_AOA .= ";Slot".$slot_idx." RX2";
                                    $fh_rangedata_SWAP_ANT_PAIR_3D_AOA .= ";SNR (MP)";
                                    $fh_rangedata_SWAP_ANT_PAIR_3D_AOA .= ";SNR (FP)";
                                    $fh_rangedata_SWAP_ANT_PAIR_3D_AOA .= ";SNR (Tot)";
                                    }
                            }

                            $decode .= "\n".$indent.$brown;
                            #$decode .= "   Slot Idx:".$slot_idx."   RX:".$Ant_Map;
                            if ($Ant_Map == 0) { $decode .= "   Slot Idx:".$slot_idx."   RX1";}
                            elsif 
                               ($Ant_Map == 8) { $decode .= "   Slot Idx:".$slot_idx."   RX2";} 
                            $decode .= "\n".$indent.$brown;
                            $decode .= "   SNR (Main Path): ".sprintf("%+05.2f",$snr_mp)."dB"."   SNR (First Path): ".sprintf("%+05.2f",$snr_fp)."dB"."   SNR (Total): ".sprintf("%+05.2f",$snr_total)."dB";
                        }

                        
                    # }
                    # else {
                        # SR2xx
                        # RSSI (signed Q8.8)
                        # foreach my $i (1..$num_ant) {
                        #     my $rssi_rx = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                        #     $rssi_rx -= 0x10000 if ($rssi_rx > 32767);
                        #     $rssi_rx = $rssi_rx/256;
                        #     $byte_idx += 4;
                        #     $decode .= "   RSSI RX$ant_names[$i-1]".": ".sprintf("%+06.2f",$rssi_rx)."dB";
                        # }

                        # $decode .= "\n".$indent.$brown;
                    
                        # SNR_RX (signed Q8.8)
                        # foreach my $i (1..$num_ant) {
                        #     my $snr_rx = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                        #     $snr_rx -= 0x10000 if ($snr_rx > 32767);
                        #     $snr_rx = $snr_rx/256;
                        #     $byte_idx += 4;
                        #     $decode .= "   SNR RX$ant_names[$i-1]".": ".sprintf("%+06.2f",$snr_rx)."dB";
                    # }
                    # }                   

                }         
            #}
            if ($controlee_status == "0" && $controller_status == "0") {
                foreach $meas_idx (1..$nb_meas) {
                    $csv_rangedata .= $session_id;
                    # $csv_rangedata .= $ft_status;
                    $csv_rangedata .= ";".$csv_range_meas[$meas_idx];
                             
                    $csv_rangedata .= "\n";
                }
            }

                    # $decode .= " rangedata PBE ".$fh_rangedata_SWAP_ANT_PAIR_3D_AOA; #  PBE  
             $decode .= $nocolor;

        }
        
        # RANGE_RESUME_CMD
        elsif ($mt_gid_oid eq "2221") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            $decode .= "\n".$indent.$brown;
            
            # STS index
            my $sts_index = hex(substr($payload,$byte_idx+6,2));
            $sts_index = (256*$sts_index)+hex(substr($payload,$byte_idx+4,2));
            $sts_index = (256*$sts_index)+hex(substr($payload,$byte_idx+2,2));
            $sts_index = (256*$sts_index)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;
            
            $decode .= " STS index:".$sts_index;
            
            $decode .= $nocolor;
        }
        
        # RANGE_RESUME_RSP
        elsif ($mt_gid_oid eq "4221") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }
            
            $decode .= $nocolor;
        }
        #################### Test Group Control Messages ####################
        # TEST_CONFIG_SET_CMD
        elsif ($mt_gid_oid eq "2D00") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            $decode .= "\n".$indent.$brown;

            # # Number of Test Configurations
            # my $nb_test_config = hex(substr($payload,$byte_idx,2));
            # $byte_idx += 2;

            # foreach (1..$nb_test_config) {
                # # Test Configuration ID
                # my $test_config_id = substr($payload,$byte_idx,2);
                # $test_config_id = ($testparam{$test_config_id} || "?".$test_config_id."?");
                # $byte_idx += 2;

                # my $len = hex(substr($payload,$byte_idx,2));
                # $byte_idx += 2;

                # my $value = substr($payload,$byte_idx,$len*2);
                # $byte_idx += $len*2;

                # TestConfigParam($test_config_id, $value);
            # }
			my $line_length = length($indent);
            
            # Number of parameters
            my $nb_params = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            
            foreach (1..$nb_params) {
                my $param_id = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                
                if ($param_id eq "E5") {
                    # Test Configuration Proprietary E5 parameters
                    $param_id = substr($payload,$byte_idx,2);
                    $param_id = $testparam_E5{$param_id} || "?E5".$param_id."?";
                    $byte_idx += 2;
                } else {
                    # UCI Test Configuration parameter
                    $param_id = $testparam{$param_id} || "?".$param_id."?";
                }
                
                my $param_length = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
                
                # Calculate length for indent, space, param id and colon
                my $busy_space = length($indent)+length($param_id)+2;
                
                # Truncate the value if exceeds the size of terminal width
                my $value = (($param_length*2) > ($MAX_LINE_SIZE-$busy_space)) ? substr($payload,$byte_idx,$MAX_LINE_SIZE-$busy_space-3)."..." : substr($payload,$byte_idx,$param_length*2);
                $byte_idx += $param_length*2;
                
                # Check if decoding exceeds the size of terminal width
                $line_length += length($param_id)+length($value)+4;
                
                if ($line_length > $MAX_LINE_SIZE) {
                    # Add new line
                    $decode .= "\n".$indent;
                    $line_length = length($indent)+length($param_id)+length($value)+2;
                }
                
                $decode .= " ".$param_id.":".$value."  ";
            }
            $decode .= $nocolor;
        }

        # TEST_CONFIG_SET_RSP
        elsif ($mt_gid_oid eq "4D00") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");

                # Number of Test Configurations
                my $nb_test_config = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;

                foreach (1..$nb_test_config) {
                    # Test Configuration ID
                    my $test_config_id = substr($payload,$byte_idx,2);
                    $test_config_id = ($testparam{$test_config_id} || "?".$test_config_id."?");
                    $byte_idx += 2;

                    $decode .= "\n".$indent.$test_config_id.": ".$status_code{substr($payload,$byte_idx,2)};
                    $byte_idx += 2;
                }
            } else {
                $decode .= $brown."   Status OK";
            }
        }

        # TEST_CONFIG_GET_CMD
        elsif ($mt_gid_oid eq "2D01") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            $decode .= "\n".$indent.$brown;

            # Number of Test Configurations
            my $nb_test_config = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;

            foreach (1..$nb_test_config) {
                # Test Configuration ID
                my $test_config_id = substr($payload,$byte_idx,2);
                $test_config_id = ($testparam{$test_config_id} || "?".$test_config_id."?");
                $byte_idx += 2;

                $decode .= $test_config_id."   ";
            }
        }

        # TEST_CONFIG_GET_RSP
        elsif ($mt_gid_oid eq "4D01") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;

            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }
            
            $decode .= "\n".$indent;

            # Number of Test Configurations
            my $nb_test_config = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;

            foreach (1..$nb_test_config) {
                # Test Configuration ID
                my $test_config_id = substr($payload,$byte_idx,2);
                $test_config_id = ($testparam{$test_config_id} || "?".$test_config_id."?");
                $byte_idx += 2;

                my $len = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;

                my $value = substr($payload,$byte_idx,$len*2);
                $byte_idx += $len*2;

                TestConfigParam($test_config_id, $value);
            }
        }

        # TEST_PERIODIC_TX_CMD
        elsif ($mt_gid_oid eq "2D02") {
            # NOTHING TO SHOW
        }

        # TEST_PERIODIC_TX_RSP
        elsif ($mt_gid_oid eq "4D02") {
            # Status
            my $status = substr($payload,0,2);

            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }
        }

        # TEST_PERIODIC_TX_NTF
        elsif ($mt_gid_oid eq "6D02") {
            # Status
            my $status = substr($payload,0,2);

            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }
        }

        # TEST_PER_RX_CMD
        elsif ($mt_gid_oid eq "2D03") {
            # NOTHING TO SHOW
        }

        # TEST_PER_RX_RSP
        elsif ($mt_gid_oid eq "4D03") {
            # Status
            my $status = substr($payload,0,2);

            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }
        }

        # TEST_PER_RX_NTF
        elsif ($mt_gid_oid eq "6D03") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;

            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }

            $decode .= "\n".$indent.$brown;

            # ATTEMPTS
            my $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= " RX ATTEMPTS: ".$value;

            # ACQ_DETECT
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "   ACQ_DETECT ".$value;

            # ACQ_REJECT
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "   ACQ_REJECT: ".$value;

            # RX_FAIL
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "   RX_FAIL: ".$value;

            $decode .= "\n".$indent;

            # SYNC_CIR_READY
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= " SYNC_CIR_READY: ".$value;

            # SFD_FAIL
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "   SFD_FAIL: ".$value;

            # SFD_FOUND
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "   SFD_FOUND: ".$value;

            $decode .= "\n".$indent;

            # PHR_DEC_ERROR
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= " PHR_DEC_errors: ".$value;

            # PHR_BIT_ERROR
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= " PHR_BIT_errors: ".$value;

            # PSDU_DEC_ERROR
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "   PSDU_DEC_errors: ".$value;

            # PSDU_BIT_ERROR
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "   PSDU_BIT_errors: ".$value;

            $decode .= "\n".$indent.$brown;

            # STS_FOUND
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= " STS_FOUND: ".$value;

            # EOF
            my $eof = hex(substr($payload,$byte_idx+6,2));
            $eof = (256*$eof)+hex(substr($payload,$byte_idx+4,2));
            $eof = (256*$eof)+hex(substr($payload,$byte_idx+2,2));
            $eof = (256*$eof)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;
            
            $decode .= "    End of Frame triggered:".$eof;

            # Vendor Specific Data
            if ($byte_idx < length($payload)) {
                my $vs_data_length = hex(substr($payload,$byte_idx,2));
                $byte_idx += 4;

                # NXP Specific Data type
                $byte_idx += 2;
                
                if ($vs_data_length > 0) {
                    $decode .= "\n".$indent.$brown." Vendor Specific Data";

                    # RX Antenna Info 
                    my $rx_mode = substr($payload,$byte_idx,2);
                    my $num_ant = substr($payload,$byte_idx+2,2);
                    $byte_idx += 4;

                    $decode .= "   Rx Mode: ".$RX_MODE{$rx_mode};

                    my @ant_names = ();
                    foreach (1..$num_ant) {
                        my $ant_id = hex(substr($payload,$byte_idx,2));
                        $decode .= "   Antenna ID: ".$ant_id;
                        $byte_idx += 2;
                        push(@ant_names, $ant_id); 
                        }

                    $decode .= "\n".$indent.$brown;

                    if(index($Device_Name,"SR1") > 0) {
                        # RSSI (signed Q8.8)
                        my $rssi_rx1 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                        $rssi_rx1 -= 0x10000 if ($rssi_rx1 > 32767);
                        $rssi_rx1 = $rssi_rx1/256;
                        $byte_idx += 4;
                    
                        my $rssi_rx2 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                        $rssi_rx2 -= 0x10000 if ($rssi_rx2 > 32767);
                        $rssi_rx2 = $rssi_rx2/256;
                        $byte_idx += 4;
                    
                        $decode .= "   RSSI RX1: ".sprintf("%+06.2f",$rssi_rx1)."dB"."   RSSI RX2: ".sprintf("%+06.2f",$rssi_rx2)."dB";

                        $decode .= "\n".$indent.$brown;

                        # SNR_RX (signed Q8.8)
                        my $snr_rx1 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                        $snr_rx1 -= 0x10000 if ($snr_rx1 > 32767);
                        $snr_rx1 = $snr_rx1/256;
                        $byte_idx += 4;
                    
                        my $snr_rx2 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                        $snr_rx2 -= 0x10000 if ($snr_rx2 > 32767);
                        $snr_rx2 = $snr_rx2/256;
                        $byte_idx += 4;
                    
                        $decode .= "   SNR RX1: ".sprintf("%+05.2f",$snr_rx1)."dB"."   SNR RX2: ".sprintf("%+05.2f",$snr_rx2)."dB";
    
                    }
                    else {
                        # SR2xx
                        # RSSI (signed Q8.8)
                        foreach my $i (1..$num_ant) {
                            my $rssi_rx = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                            $rssi_rx -= 0x10000 if ($rssi_rx > 32767);
                            $rssi_rx = $rssi_rx/256;
                            $byte_idx += 4;
                            $decode .= "   RSSI RX$ant_names[$i-1]".": ".sprintf("%+06.2f",$rssi_rx)."dB";
                        }

                        $decode .= "\n".$indent.$brown;
                    
                        # SNR_RX (signed Q8.8)
                        foreach my $i (1..$num_ant) {
                            my $snr_rx = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                            $snr_rx -= 0x10000 if ($snr_rx > 32767);
                            $snr_rx = $snr_rx/256;
                            $byte_idx += 4;
                            $decode .= "   SNR RX$ant_names[$i-1]".": ".sprintf("%+06.2f",$snr_rx)."dB";
                        }
                    }

                    # my $snr_rx1 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                    # $snr_rx1 -= 0x10000 if ($snr_rx1 > 32767);
                    # $snr_rx1 = $snr_rx1/256;
                    # $byte_idx += 4;
                    
                    # my $snr_rx2 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                    # $snr_rx2 -= 0x10000 if ($snr_rx2 > 32767);
                    # $snr_rx2 = $snr_rx2/256;
                    # $byte_idx += 4;
                    
                    # $decode .= "   SNR RX1: ".sprintf("%+05.2f",$snr_rx1)."dB"."   SNR RX2: ".sprintf("%+05.2f",$snr_rx2)."dB";
                    
                    $decode .= "\n".$indent.$brown;
                    
                    # RX CFO Estimation (signed Q5.11) PPM????
                    my $rx_cfo_est = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                    $rx_cfo_est -= 0x10000 if ($rx_cfo_est > 32767);
                    $rx_cfo_est = $rx_cfo_est/2048;
                    $byte_idx += 4;
                    
                    $decode .= "   RX CFO EST: ".sprintf("%+06.4f",$rx_cfo_est)."ppm";
                }
            }
        }

        # TEST_RX_CMD
        elsif ($mt_gid_oid eq "2D05") {
            # NOTHING TO SHOW
        }

        # TEST_RX_RSP
        elsif ($mt_gid_oid eq "4D05") {
            # Status
            my $status = substr($payload,0,2);

            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }
        }

        # TEST_RX_NTF
        elsif ($mt_gid_oid eq "6D05") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;

            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }

            $decode .= "\n".$indent.$brown;

            # RX_DONE_TS_INT
            my $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "RX_DONE_TS_INT: ".$value."ticks";

            # RX_DONE_TS_FRAC
            $value = hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 4;

            $decode .= "   RX_DONE_TS_FRAC: ".$value."ticks";

            # Aoa_Azimuth
            $value = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
            $value -= 0x10000 if ($value > 32767);
            $value = $value/128;
            $byte_idx += 4;

            $decode .= "   Aoa_Azimuth: ".$value."deg";

            # Aoa_Elevation
            $value = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
            $value -= 0x10000 if ($value > 32767);
            $value = $value/128;
            $byte_idx += 4;

            $decode .= "   Aoa_Elevation: ".$value."deg";

            # ToA Gap
            $value = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;

            $decode .= "   ToA Gap: ".$value."ns";

            # PHR
            $value = substr($payload,$byte_idx+2,2).substr($payload,$byte_idx,2);
            $byte_idx += 4;

            $decode .= "   PHR: 0x".$value;

            $decode .= "\n".$indent;

            # PSDU Data length
            $value = hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 4;

            # PSDU Data
            $decode .= "PSDU Data : 0x".substr($payload,$byte_idx,$value*2);
        }

        # TEST_LOOPBACK_CMD
        elsif ($mt_gid_oid eq "2D06") {
            # NOTHING TO SHOW
        }

        # TEST_LOOPBACK_RSP
        elsif ($mt_gid_oid eq "4D06") {
            # Status
            my $status = substr($payload,0,2);

            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }
        }

        # TEST_LOOPBACK_NTF
        elsif ($mt_gid_oid eq "6D06") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;

            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }

            $decode .= "\n".$indent.$brown;

            # TX Done Timestamp Integer
            my $tx_ts_int = hex(substr($payload,$byte_idx+6,2));
            $tx_ts_int = (256*$tx_ts_int)+hex(substr($payload,$byte_idx+4,2));
            $tx_ts_int = (256*$tx_ts_int)+hex(substr($payload,$byte_idx+2,2));
            $tx_ts_int = (256*$tx_ts_int)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;
            
            # TX Done Timestamp Fractional
            my $tx_ts_frac = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
            $byte_idx += 4;
            
            $decode .= "TX Timestamp:".$tx_ts_int.".".sprintf("%0.3u",$tx_ts_frac);
            
            # RX Done Timestamp Integer
            my $rx_ts_int = hex(substr($payload,$byte_idx+6,2));
            $rx_ts_int = (256*$rx_ts_int)+hex(substr($payload,$byte_idx+4,2));
            $rx_ts_int = (256*$rx_ts_int)+hex(substr($payload,$byte_idx+2,2));
            $rx_ts_int = (256*$rx_ts_int)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;
            
            # RX Done Timestamp Fractional
            my $rx_ts_frac = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
            $byte_idx += 4;
            
            $decode .= "   RX Timestamp:".$rx_ts_int.".".sprintf("%0.3u",$rx_ts_frac);
            
            $decode .= "\n".$indent.$brown;

            # Aoa_Azimuth
            my $value = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
            $value -= 0x10000 if ($value > 32767);
            $value = $value/128;
            $byte_idx += 4;

            $decode .= "Aoa_Azimuth: ".$value."deg";

            # Aoa_Elevation
            $value = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
            $value -= 0x10000 if ($value > 32767);
            $value = $value/128;
            $byte_idx += 4;

            $decode .= "   Aoa_Elevation: ".$value."deg";
            $decode .= "\n".$indent;

            # PHR
            $value = substr($payload,$byte_idx+2,2).substr($payload,$byte_idx,2);
            $byte_idx += 4;

            $decode .= "PHR: 0x".$value;

            $decode .= "\n".$indent;

            # PSDU Data length
            $value = hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 4;

            # PSDU Data
            $decode .= "PSDU Data : 0x".substr($payload,$byte_idx,$value*2);
            $byte_idx += $value*2;
            
            # Vendor Specific Data
            if ($byte_idx < length($payload)) {
                my $vs_data_length = hex(substr($payload,$byte_idx,2));
                $byte_idx += 4;
                
                # NXP Specific Data type
                $byte_idx += 2;
                
                if ($vs_data_length > 0) {
                    $decode .= "\n".$indent.$brown."Vendor Specific Data";
                    
                    # RX Antenna Info 
                    my $rx_mode = substr($payload,$byte_idx,2);
                    my $num_ant = substr($payload,$byte_idx+2,2);
                    $byte_idx += 4;

                    $decode .= "   Rx Mode: ".$RX_MODE{$rx_mode};
                   
                    my @ant_names = ();
                    foreach (1..$num_ant) {
                        my $ant_id = hex(substr($payload,$byte_idx,2));
                        $decode .= "   Antenna ID: ".$ant_id;
                        $byte_idx += 2;
                        push(@ant_names, $ant_id); 
                        }

                    $decode .= "\n".$indent.$brown;

                    if(index($Device_Name,"SR1") > 0) {
                        # RSSI (signed Q8.8)
                        my $rssi_rx1 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                        $rssi_rx1 -= 0x10000 if ($rssi_rx1 > 32767);
                        $rssi_rx1 = $rssi_rx1/256;
                        $byte_idx += 4;
                    
                        my $rssi_rx2 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                        $rssi_rx2 -= 0x10000 if ($rssi_rx2 > 32767);
                        $rssi_rx2 = $rssi_rx2/256;
                        $byte_idx += 4;
                    
                        $decode .= "   RSSI RX1: ".sprintf("%+06.2f",$rssi_rx1)."dB"."   RSSI RX2: ".sprintf("%+06.2f",$rssi_rx2)."dB";

                        $decode .= "\n".$indent.$brown;

                        # SNR_RX (signed Q8.8)
                        my $snr_rx1 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                        $snr_rx1 -= 0x10000 if ($snr_rx1 > 32767);
                        $snr_rx1 = $snr_rx1/256;
                        $byte_idx += 4;
                    
                        my $snr_rx2 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                        $snr_rx2 -= 0x10000 if ($snr_rx2 > 32767);
                        $snr_rx2 = $snr_rx2/256;
                        $byte_idx += 4;
                    
                        $decode .= "   SNR RX1: ".sprintf("%+05.2f",$snr_rx1)."dB"."   SNR RX2: ".sprintf("%+05.2f",$snr_rx2)."dB";
    
                    }
                    else {
                        # SR2xx
                        # RSSI (signed Q8.8)
                        foreach my $i (1..$num_ant) {
                            my $rssi_rx = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                            $rssi_rx -= 0x10000 if ($rssi_rx > 32767);
                            $rssi_rx = $rssi_rx/256;
                            $byte_idx += 4;
                            $decode .= "   RSSI RX$ant_names[$i-1]".": ".sprintf("%+06.2f",$rssi_rx)."dB";
                        }

                        $decode .= "\n".$indent.$brown;
                    
                        # SNR_RX (signed Q8.8)
                        foreach my $i (1..$num_ant) {
                            my $snr_rx = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                            $snr_rx -= 0x10000 if ($snr_rx > 32767);
                            $snr_rx = $snr_rx/256;
                            $byte_idx += 4;
                            $decode .= "   SNR RX$ant_names[$i-1]".": ".sprintf("%+06.2f",$snr_rx)."dB";
                        }
                    }

                    # my $snr_rx1 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                    # $snr_rx1 -= 0x10000 if ($snr_rx1 > 32767);
                    # $snr_rx1 = $snr_rx1/256;
                    # $byte_idx += 4;
                    
                    # my $snr_rx2 = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                    # $snr_rx2 -= 0x10000 if ($snr_rx2 > 32767);
                    # $snr_rx2 = $snr_rx2/256;
                    # $byte_idx += 4;
                    
                    # $decode .= "   SNR RX1: ".sprintf("%+05.2f",$snr_rx1)."dB"."   SNR RX2: ".sprintf("%+05.2f",$snr_rx2)."dB";
                    
                    $decode .= "\n".$indent.$brown;
                    
                    # RX CFO Estimation (signed Q5.11) PPM????
                    my $rx_cfo_est = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                    $rx_cfo_est -= 0x10000 if ($rx_cfo_est > 32767);
                    $rx_cfo_est = $rx_cfo_est/2048;
                    $byte_idx += 4;
                    
                    $decode .= "   RX CFO EST: ".sprintf("%+06.4f",$rx_cfo_est)."ppm";
                }
            }
        }

        # TEST_STOP_SESSION_CMD
        elsif ($mt_gid_oid eq "2D07") {
            # NOTHING TO SHOW
        }

        # TEST_STOP_SESSION_RSP
        elsif ($mt_gid_oid eq "4D07") {
            # Status
            my $status = substr($payload,0,2);

            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }
        }

        # TEST_SS_TWR_CMD
        elsif ($mt_gid_oid eq "2D08") {
            # NOTHING TO SHOW
        }

        # TEST_SS_TWR_RSP
        elsif ($mt_gid_oid eq "4D08") {
            # Status
            my $status = substr($payload,0,2);
            
            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }
        }

        # TEST_SS_TWR_NTF
        elsif ($mt_gid_oid eq "6D08") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            
            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }

            $decode .= "\n".$indent.$brown;

            # Measurement
            my $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "Measurement: ".$value."ticks";
        }

        # TEST_SR_RX_CMD
        elsif ($mt_gid_oid eq "2D09") {
            # NOTHING TO SHOW
        }

        # TEST_SR_RX_RSP
        elsif ($mt_gid_oid eq "4D09") {
            # Status
            my $status = substr($payload,0,2);
            
            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }
        }

        # TEST_SR_RX_NTF
        elsif ($mt_gid_oid eq "6D09") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;

            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }

            $decode .= "\n".$indent.$brown;

            # ATTEMPTS
            my $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "No RX ATTEMPTS: ".$value;

            # ACQ_DETECT
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "No times ACQ_DETECT ".$value;

            # ACQ_REJECT
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "No times ACQ_REJECT: ".$value;

            # RX_FAIL
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "No times RX_FAIL: ".$value;

            $decode .= "\n".$indent;

            # SYNC_CIR_READY
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "No times SYNC_CIR_READY: ".$value;

            # SFD_FAIL
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "No times SFD_FAIL: ".$value;

            # SFD_FOUND
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "No times SFD_FOUND: ".$value;

            # STS_FOUND
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "No times STS_FOUND: ".$value;

            # EOF
            $value = hex(substr($payload,$byte_idx+6,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+4,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx+2,2));
            $value = (256*$value)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;

            $decode .= "No times END_OF_FRAME: ".$value;
        }
        #################### SR200 Proprietary group ####################
        # RADAR_RX_NTF
        elsif ($mt_gid_oid eq "690A") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= $brown;

            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            
            if ($status ne "00") {
                $decode .= "\n".$indent." ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= "\n".$indent.$brown;
                
                # Radar Data Type
                my $type = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                
                $decode .= "Radar data type:".($radar_data_type{$type} || "???");
                
                if ($type eq "00") {
                    # CIR samples
                    $decode .= "\n".$indent.$brown;
                }
                elsif ($type eq "01") {
                    # TAP 0
                    my $pd_status = substr($payload,$byte_idx,2);
                    $decode .= "\n     Presence detection status:".($ocpd_status{$pd_status} || "???");
                    my $pd_mode = substr($payload,$byte_idx+2,2);
                    $decode .= "    Presence detection mode:".substr($payload,$byte_idx+2,2);
                    my $nb_detection = hex(substr($payload,$byte_idx+4,2));
                    $decode .= "    Number of detection:".$nb_detection;
                    $byte_idx += 8;

                    if ($pd_status eq "01") {
                        foreach (1..$nb_detection) {
                            my $dist = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                            $decode .= "\n     distance:".$dist."cm";
                            my $angle = (hex(substr($payload,$byte_idx+4,2)));
                            $angle -= 0x100 if ($angle > 127);
                            $decode .= "    angle:".$angle."deg";
                            my $snr_hex = substr($payload,$byte_idx+14,2).substr($payload,$byte_idx+12,2).substr($payload,$byte_idx+10,2).substr($payload,$byte_idx+8,2);
                            my $snr_bin = pack("H*", $snr_hex);
                            my $snr_float = unpack("f>", $snr_bin);
                            $decode .= "    snr:".sprintf("%.1f",$snr_float)."dB";
                            $byte_idx += 16;
                        }
                    }
                }
            }
            
            $decode .= $nocolor;
        }
        #################### SR200 Proprietary 1 group ####################
        # CORE_DEVICE_INIT_CMD
        elsif ($mt_gid_oid eq "2E00") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Version
            my $major_ver = hex(substr($payload,$byte_idx,2));
            my $minor_ver = hex(substr($payload,$byte_idx+2,2));
            
            $decode .= "   ".($variant{$major_ver.$minor_ver} || "Ver:".$major_ver.".".$minor_ver);
            
            $decode .= $nocolor;
        }

        # CORE_DEVICE_INIT_RSP
        elsif ($mt_gid_oid eq "4E00") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= $brown."   Status OK";
            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }
        }
        
        # DBG_GET_ERROR_LOG_CMD
        elsif ($mt_gid_oid eq "2E02") {
            # NOTHING TO SHOW
        }
        
        # DBG_GET_ERROR_LOG_RSP
        elsif ($mt_gid_oid eq "4E02") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Add name of OID to store in DBG
            $decode .= "DBG_GET_ERROR_LOG_RSP";
            
            $decode .= "\n".$indent.$brown;
            
            # Exception Type
            my $exception = substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            $decode .= " Exception:".($exception_type{$exception} || "???");
            
            $decode .= $nocolor;
        }
        
        # SE_GET_BINDING_COUNT_CMD
        elsif ($mt_gid_oid eq "2E03") {
            # NOTHING TO SHOW
        }

        # SE_GET_BINDING_COUNT_RSP
        elsif ($mt_gid_oid eq "4E03") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            } else {
                $decode .= "\n".$indent.$brown;
                
				my $status = substr($payload,$byte_idx,2);
				$byte_idx += 2;

                # Binding available
                $decode .= " ".($binding_available{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
                
                # SR200 Count
                $decode .= "   UWBS Remaining binding:".hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
                
                # SE Count
                $decode .= "   SE remaining binding:".hex(substr($payload,$byte_idx,2));
            }
            
            $decode .= $nocolor;
        }
        
        # SE_DO_TEST_LOOP_CMD
        elsif ($mt_gid_oid eq "2E04") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= "\n".$indent.$brown;
            
            # Number of tests
            my $nb_tests = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            
            $decode .= " Number of tests:".$nb_tests;
            
            # Interval
            my $interval = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            
            $decode .= "   Interval between two runs:".$interval."ms";
            
            $decode .= $nocolor;
        }
        
        # SE_DO_TEST_LOOP_RSP
        elsif ($mt_gid_oid eq "4E04") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Test status
            $decode .= "   ".($se_test_loop_status{substr($payload,$byte_idx,2)} || "???");
            
            $decode .= $nocolor;
        }
        
        # SE_DO_TEST_LOOP_NTF
        elsif ($mt_gid_oid eq "6E04") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= "\n".$indent.$brown;
            
            # Test status
            $decode .= " ".($se_test_loop_result{substr($payload,$byte_idx,2)} || "???");
            $byte_idx += 2;
            
            # Loop count
            my $loop_count = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
            $byte_idx += 4;
            
            $decode .= " Number of loops:".$loop_count;
            
            # Loop pass count
            my $pass_count = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
            $byte_idx += 4;
            
            $decode .= " Number of pass:".$pass_count;
            
            $decode .= $nocolor;
        }

        # SE_COMM_ERROR_NTF
        elsif ($mt_gid_oid eq "6E05") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;

            if ($status eq "74") {
                $decode .= "\n".$indent.$brown;

                # Binding status
                my $binding_status = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $decode .= " Binding status: ".($binding_available{$binding_status} || "???");

                # UWBS Binding count
                my $uwbs_binding_count = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
                $decode .= "   UWBS Binding count: ".$uwbs_binding_count;

                # SE Binding count
                my $se_binding_count = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
                $decode .= "   SE Binding count: ".$se_binding_count;
            } else {
                $decode .= "   ".$se_status_code{$status} || "???";
            }
        }
        
        # BINDING_STATUS_NTF
        elsif ($mt_gid_oid eq "6E06") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Binding state
            $decode .= "   State:".($binding_state{substr($payload,$byte_idx,2)} || "???");
            $byte_idx += 2;
            
            $decode .= $nocolor;
        }
        
        # SCHEDULER_STATUS_NTF
        elsif ($mt_gid_oid eq "6E07") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Number of sessions
            my $nb_sessions = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            
            foreach (1..$nb_sessions) {
                $decode .= "\n".$indent.$brown;
                
                # Session ID
                $decode .= " Session Handle:0x";
                $decode .= substr($payload,$byte_idx+6,2);
                $decode .= substr($payload,$byte_idx+4,2);
                $decode .= substr($payload,$byte_idx+2,2);
                $decode .= substr($payload,$byte_idx,2);
                $byte_idx += 8;
                
                # Scheduler Status
                $decode .= "   Status:".($scheduler_status{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
                
                # Successful scheduling
                my $success_sch = hex(substr($payload,$byte_idx+6,2));
                $success_sch = (256*$success_sch)+hex(substr($payload,$byte_idx+4,2));
                $success_sch = (256*$success_sch)+hex(substr($payload,$byte_idx+2,2));
                $success_sch = (256*$success_sch)+hex(substr($payload,$byte_idx,2));
                $byte_idx += 8;
                
                $decode .= "   Success:".$success_sch;
                
                # Unsuccessful scheduling
                my $unsuccess_sch = hex(substr($payload,$byte_idx+6,2));
                $unsuccess_sch = (256*$unsuccess_sch)+hex(substr($payload,$byte_idx+4,2));
                $unsuccess_sch = (256*$unsuccess_sch)+hex(substr($payload,$byte_idx+2,2));
                $unsuccess_sch = (256*$unsuccess_sch)+hex(substr($payload,$byte_idx,2));
                $byte_idx += 8;
                
                $decode .= "   Unsuccess:".$unsuccess_sch;
                
                # Priority
                $decode .= "   Priority:".hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
            }
            
            $decode .= $nocolor;
        }
        
        # UWB_SESSION_KDF_NTF
        elsif ($mt_gid_oid eq "6E08") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= "\n".$indent.$brown;
            my $line_length = length($indent);
            
            # Number of parameters
            my $nb_params = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            
            foreach (1..$nb_params) {
                my $param_id = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                
                # UCI Test Configuration parameter
                $param_id = $kdf_param{$param_id} || "?".$param_id."?";
                
                my $param_length = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
                
                # Calculate length for indent, space, param id and colon
                my $busy_space = length($indent)+length($param_id)+2;
                
                # Truncate the value if exceeds the size of terminal width
                my $value = (($param_length*2) > ($MAX_LINE_SIZE-$busy_space)) ? substr($payload,$byte_idx,$MAX_LINE_SIZE-$busy_space-3)."..." : substr($payload,$byte_idx,$param_length*2);
                $byte_idx += $param_length*2;
                
                # Check if decoding exceeds the size of terminal width
                $line_length += length($param_id)+length($value)+4;
                
                if ($line_length > $MAX_LINE_SIZE) {
                    # Add new line
                    $decode .= "\n".$indent;
                    $line_length = length($indent)+length($param_id)+length($value)+2;
                }
                
                $decode .= $param_id.": ".$value."   ";
            }
            
            $decode .= $nocolor;
        }
        
        # UWB_WIFI_COEX_IND_NTF
        elsif ($mt_gid_oid eq "6E09") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= "\n".$indent.$brown;
            
            # WIFI Co-existence Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            # GPIO based CoEX feature
            if ($WifiCoexFeature & 0x10 &&
                ($WifiCoexFeature & 0x01 ||
                 $WifiCoexFeature & 0x04) ) {
                $decode .= " Status: ";
                if ($status eq "00") {
                    $decode .= " High to Low";
                } elsif ($status eq "01") {
                    $decode .= "Low to High";
                } else {
                    $decode .= "???";
                }
            }
            # No Debug feature
            else {
                $decode .= " Status: ??? No debug feature";
            }
            
            # Slot index
            my $slot_index = hex(substr($payload,$byte_idx+6,2));
            $slot_index = (256*$slot_index)+hex(substr($payload,$byte_idx+4,2));
            $slot_index = (256*$slot_index)+hex(substr($payload,$byte_idx+2,2));
            $slot_index = (256*$slot_index)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;
            
            $decode .= "   Slot Index:".$slot_index;
            
            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            $decode .= $nocolor;
        }
        
        # WLAN_UWB_IND_ERR_NTF
        elsif ($mt_gid_oid eq "6E0A") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= "\n".$indent.$brown;
            
            # WLAN UWB IND Status
            $decode .= " Status:".($wlan_uwb_ind_status{substr($payload,$byte_idx,2)} || "???");
            $byte_idx += 2;
            
            # Slot index
            my $slot_index = hex(substr($payload,$byte_idx+6,2));
            $slot_index = (256*$slot_index)+hex(substr($payload,$byte_idx+4,2));
            $slot_index = (256*$slot_index)+hex(substr($payload,$byte_idx+2,2));
            $slot_index = (256*$slot_index)+hex(substr($payload,$byte_idx,2));
            $byte_idx += 8;
            
            $decode .= "   Slot Index:".$slot_index;
            
            $decode .= $nocolor;
        }

        # QUERY_TEMPERATURE_CMD
        elsif ($mt_gid_oid eq "2E0B") {
            # NOTHING TO SHOW
        }
        
        # QUERY_TEMPERATURE_RSP
        elsif ($mt_gid_oid eq "4E0B") {
            # Put Byte index after Status
            my $byte_idx = 2;
            
            # Temperature
            $decode .= "   ".hex(substr($payload,$byte_idx,2))." Celsius";
            $byte_idx += 2;
            
            $decode .= $nocolor;
        }
        
        # GENERATE_TAG_CMD
        elsif ($mt_gid_oid eq "2E0E") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;

            # Tag Option
            my $tag_option = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($tag_option & 0x01) {
                $decode .= "   Device Specific Tag";
            } elsif ($tag_option & 0x02) {
                $decode .= "   Model Specific Tag";
            } else {
                $decode .= "   ???";
            }
        }
        
        # GENERATE_TAG_RSP
        elsif ($mt_gid_oid eq "4E0E") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= $brown."   Status OK";
            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }
        }
        
        # GENERATE_TAG_NTF
        elsif ($mt_gid_oid eq "6E0E") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= $brown."   Status OK";
                $byte_idx += 2;

                # CMAC TAG
                $decode .= "\n".$indent;
                $decode .= $indent."CMAC TAG: 0x".substr($payload,$byte_idx,32);

            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }
        }

        # VERIFY_CALIB_DATA_CMD
        elsif ($mt_gid_oid eq "2E0F") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;

            # CMAC TAG
            $decode .= "\n".$indent;
            $decode .= $indent."CMAC TAG: 0x".substr($payload,$byte_idx,32);
            $byte_idx += 32;

            # Tag Option
            my $tag_option = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($tag_option & 0x01) {
                $decode .= "   Device Specific Tag";
            } elsif ($tag_option & 0x02) {
                $decode .= "   Model Specific Tag";
            } else {
                $decode .= "   Unknown Tag Option";
            }

            # Tag Version
            my $tag_version = substr($payload,$byte_idx+2,2).substr($payload,$byte_idx,2);
            $byte_idx += 4;
            $decode .= "   Tag Version: 0x".$tag_version;
        }

        # VERIFY_CALIB_DATA_RSP
        elsif ($mt_gid_oid eq "4E0F") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= $brown."   Status OK";
            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }
        }

        # VERIFY_CALIB_DATA_NTF
        elsif ($mt_gid_oid eq "6E0F") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= $brown."   Status OK";
            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }
        }

        # CONFIGURE_AUTH_TAG_OPTIONS_CMD
        elsif ($mt_gid_oid eq "2E10") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown."\n".$indent;

            # Configuration
            my $config_byte0 = substr($payload,$byte_idx+6,2);
            my $config_byte1 = substr($payload,$byte_idx+4,2);
            my $config_byte2 = substr($payload,$byte_idx+2,2);
            my $config_byte3 = substr($payload,$byte_idx,2);
            $byte_idx += 8;

            if ($config_byte0 eq "00" || $config_byte0 eq "FF") {
                $decode .= "Integrity NOT protected by Device Specific Tag";
            } else {
                $decode .= "Integrity protected by Device Specific Tag";
            }

            if ($config_byte1 eq "00" || $config_byte1 eq "FF") {
                $decode .= "\n".$indent."Integrity NOT protected by Model Specific Tag";
            } else {
                $decode .= "\n".$indent."Confidentiality protected by Model Specific Tag";
            }

            $decode .= "\n".$indent."Label: 0x".$config_byte3.$config_byte2;
        }

        # CONFIGURE_AUTH_TAG_OPTIONS_RSP
        elsif ($mt_gid_oid eq "4E10") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= $brown."   Status OK";
            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }
        }

        # CONFIGURE_AUTH_TAG_OPTIONS_NTF
        elsif ($mt_gid_oid eq "6E10") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= $brown."   Status OK";
            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }
        }

        # CONFIGURE_AUTH_TAG_VERSION_CMD
        elsif ($mt_gid_oid eq "2E11") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown."\n".$indent;

            # Tag Version
            my $tag_version = substr($payload,$byte_idx+2,2).substr($payload,$byte_idx,2);
            $byte_idx += 4;

            $decode .= "Tag Version: 0x".$tag_version;
        }

        # CONFIGURE_AUTH_TAG_VERSION_RSP
        elsif ($mt_gid_oid eq "4E11") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= $brown."   Status OK";
            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }
        }

        # CALIBRATION_INTEGRITY_PROTECTION_CMD
        elsif ($mt_gid_oid eq "2E12") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown."\n".$indent;

            # Configuration
                # Tag Option
            my $tag_option = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($tag_option & 0x01) {
                $decode .= "Device Specific Tag";
            } elsif ($tag_option & 0x02) {
                $decode .= "Model Specific Tag";
            } else {
                $decode .= "Unknown Tag Option";
            }

            # Calibration Parameters bitmask
            my $cal_param_bitmask = hex(substr($payload,$byte_idx+2,2));
            my $cal_param_bitmask2 = hex(substr($payload,$byte_idx,2));
            $byte_idx += 4;

            $decode .= "\n".$indent."Calibration Parameters bitmask:";

            if ($cal_param_bitmask & 0x01) {
                $decode .= "  VCO_PLL";
            }
            if ($cal_param_bitmask & 0x02) {
                $decode .= "  TX_POWER";
            }
            if ($cal_param_bitmask & 0x04) {
                $decode .= "  38.4MHz_XTAL_CAP";
            }
            if ($cal_param_bitmask & 0x08) {
                $decode .= "  RSSI_CALIB_CONSTANT1";
            }
            if ($cal_param_bitmask & 0x10) {
                $decode .= "  RSSI_CALIB_CONSTANT2";
            }
            if ($cal_param_bitmask & 0x20) {
                $decode .= "  RSSI_CALIB_CONSTANT";
            }
            if ($cal_param_bitmask & 0x40) {
                $decode .= "  MANUAL_TX_POW_CTRL";
            }
            if ($cal_param_bitmask & 0x80) {
                $decode .= "  PDOA1_OFFSET";
            }

            if ($cal_param_bitmask2 & 0x01) {
                $decode .= "  PA_PPA_CALIB_CTRL";
            }
            if ($cal_param_bitmask2 & 0x02) {
                $decode .= "  TX_TEMPERATURE_COMP";
            }
            if ($cal_param_bitmask2 & 0x04) {
                # RFU
            }
            if ($cal_param_bitmask2 & 0x08) {
                $decode .= "  DELAY_CALIB";
            }
            if ($cal_param_bitmask2 & 0x10) {
                $decode .= "  AOA_CALIB_CTRL";
            }
            if ($cal_param_bitmask2 & 0x20) {
                $decode .= "  PDOA2_OFFSET";
            }
            if ($cal_param_bitmask2 & 0x40) {
                # RFU
            }
            if ($cal_param_bitmask2 & 0x80) {
                # RFU
            }
        }

        # CALIBRATION_INTEGRITY_PROTECTION_RSP
        elsif ($mt_gid_oid eq "4E12") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= $brown."   Status OK";
            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }
        }

        # UWB_WLAN_COEX_NTF
        elsif ($mt_gid_oid eq "2E13") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= "\n".$indent.$brown;
            
            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($status eq "8A") {
                $decode .= " Status: MAX Active Grant Duration Exceeded Warning Notification";
            } else {
                $decode .= " Status: ???";
            }
        }

        # TEST_NOISE_POWER_CMD
        elsif ($mt_gid_oid eq "2E1C") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # RX_SELECTED
            my $rx_selected = hex(substr($payload,$byte_idx,2));
            $decode .= $indent.$brown."RX".$rx_selected." Selected";
        }

        # TEST_NOISE_POWER_RSP
        elsif ($mt_gid_oid eq "4E1C") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }
        }

        # TEST_NOISE_POWER_NTF
        elsif ($mt_gid_oid eq "6E1C") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            if (substr($payload,$byte_idx,2) ne "00") {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            } else {
                $decode .= $brown."   Status OK";
                $byte_idx += 2;

                $decode .= "\n".$indent;

                # Noise Power (Q7.8)
                my $noise_power = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                $noise_power -= 0x10000 if ($noise_power > 32767);
                $noise_power = $noise_power/256;
                $byte_idx += 4;
                $decode .= "Noise Power: ".$noise_power." dBm";
            }
        }

        # TRIGGER_HW_SECURITY_CHECK_ERROR_NTF
        elsif ($mt_gid_oid eq "6E19") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= "\n".$indent.$brown;
            
            # Status
            my $boot_reason = hex(substr($payload,$byte_idx+6,2));
            $boot_reason = (256*$boot_reason)+hex(substr($payload,$byte_idx+4,2));
            $boot_reason = (256*$boot_reason)+hex(substr($payload,$byte_idx+2,2));
            $boot_reason = (256*$boot_reason)+hex(substr($payload,$byte_idx,2));

            $decode .= " Boot Reason: ";
            if ($boot_reason == 0x00000080) {
                $decode .= "RESET_FIREWALL_EDC_ERROR";
            } elsif ($boot_reason == 0x00000100) {
                $decode .= "RESET_CRYPTOSS_EDC_ERROR";
            } elsif ($boot_reason == 0x00000200) {
                $decode .= "RESET_ARMSS_FA_EDC_ERROR";
            } elsif ($boot_reason == 0x00000400) {
                $decode .= "RESET_ARMSS_INGFID_ERROR";
            } elsif ($boot_reason == 0x00000800) {
                $decode .= "RESET_SEC_PCRM_EDC_ERROR";
            } elsif ($boot_reason == 0x00001000) {
                $decode .= "RESET_GLITCH_SENSOR_ERROR";
            } elsif ($boot_reason == 0x00002000) {
                $decode .= "SEC_PCRM_FREQ_MON_ERROR";
            }
        }

        # SET_GPIO_PIN_STATE_CMD
        elsif ($mt_gid_oid eq "2E1A") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= "\n".$indent.$brown;
            
            # GPIO Direction
            my $gpio_direction = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            $decode .= " GPIO Direction: ".($GPIO_DIRECTION{$gpio_direction} || "???");

            # GPIO Mask
            my $gpio_mask = substr($payload,$byte_idx+2,2);
            $gpio_mask .= substr($payload,$byte_idx,2);
            $byte_idx += 4;
            $decode .= "   GPIO Mask: 0x".$gpio_mask;

            # GPIO Value
            my $gpio_value = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            $decode .= "   GPIO Value: ".($GPIO_VALUE{$gpio_value} || "???");
        }
        
        # SET_GPIO_PIN_STATE_RSP
        elsif ($mt_gid_oid eq "4E1A") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # Status
            if (substr($payload,$byte_idx,2) eq "00") {
                $decode .= $brown."   Status OK";
            } else {
                $decode .= "   ".$red_oops.($status_code{substr($payload,$byte_idx,2)} || "???");
            }
        }
        
        # GET_GPIO_PIN_STATE_CMD
        elsif ($mt_gid_oid eq "2E1B") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            # GPIO Mask
            my $gpio_mask = substr($payload,$byte_idx+2,2);
            $gpio_mask .= substr($payload,$byte_idx,2);
            $byte_idx += 4;
        }

        # GET_GPIO_PIN_STATE_RSP
        elsif ($mt_gid_oid eq "4E1B") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= "\n".$indent.$brown;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($status ne "00") {
                $decode .= " Status: ".$red_oops.($status_code{$status} || "???");
            }
	        
			my $gpio_mask = substr($payload,$byte_idx,4);		
			$decode .= " GPIO Mask: 0x".$gpio_mask;
			
			$byte_idx += 4;
			my $gpio_dir = substr($payload,$byte_idx,2);
            if ($gpio_dir eq "00") {			
				$decode .= "	GPIO Direction: Input";
			}
            elsif ($gpio_dir eq "01") {			
				$decode .= "	GPIO Direction: Output";	
			}
			else{	
				$decode .= "	GPIO Direction: Unknown";		
			}	

			$byte_idx += 2;
			my $gpio_state = substr($payload,$byte_idx,2);
            if ($gpio_state eq "00") {			
				$decode .= "	GPIO Level: Low";
			}
            elsif ($gpio_state eq "01") {			
				$decode .= "	GPIO Level: High";	
			}
			else{	
				$decode .= "	GPIO Level: Unknown";		
			}				
			
        }
		# SESSION_SET_RDS_PARAM_CMD
        elsif ($mt_gid_oid eq "2E2B") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
			
			$decode .= "\n".$indent.$yellow;
			
			$decode .= "Number of element = ". substr($payload,$byte_idx,2);
			$byte_idx += 2;
			
			$decode .= $indent." Session Handle = ";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
			
			$decode .= $indent."MAC Address = ". substr($payload,$byte_idx,4);
			$byte_idx += 4;		

			$decode .= "\n".$indent."RDS = ". substr($payload,$byte_idx,56*2);
			$byte_idx += 56*2;

			$decode .= $indent."STS_INDEX = ". substr($payload,$byte_idx,8);
			$byte_idx += 8;
		}	
		# SESSION_SET_RDS_PARAM_RSP		
	    elsif ($mt_gid_oid eq "4E2B") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
			
			$decode .= $indent.$yellow;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($status ne "00") {
                $decode .= "Status: ".$red_oops.($status_code{$status} || "???");
            }
			else {
                $decode .= "Status OK";
            }

			$decode .= $indent."Last STS Index = ";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
		}		
		# SESSION_SET_RDS_PARAM_NTF	
	    elsif ($mt_gid_oid eq "6E2B") {
            # Put Byte index on the beginning of payload
			my $byte_idx = 0;
			$decode .= $indent.$yellow;
			
			$decode .= "Session Handle = ";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
			
			# Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
			if ($status ne "00") {
                $decode .= $indent."Key Derivation Failed";
            }
			else {
                $decode .= $indent."Key Derivation Success";
            }

		}		
		
        #################### SR200 Proprietary 2 group ####################
        # SET_VENDOR_APP_CONFIG_CMD
        elsif ($mt_gid_oid eq "2F00") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;
            
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            $decode .= "\n".$indent;
            my $line_length = length($indent);
            
            # Number of parameters
            my $nb_params = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            
            foreach (1..$nb_params) {
                my $param_id = substr($payload,$byte_idx,2);
                $byte_idx += 2;

                $param_id = $set_vendor_app_config{$param_id} || "?".$param_id."?";
                
                my $param_length = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
                
                # Calculate length for indent, space, param id and colon
                my $busy_space = length($indent)+length($param_id)+2;

                my $value = "";

                if ($param_id eq "MAC_PAYLOAD_ENCRYPTION") {
                    my $val .= substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    if ($val eq "00") {
                        $value = "PLAIN TEXT";
                    } elsif ($val eq "01") {
                        $value = "ENCRYPTED";
                    }
                } elsif ($param_id eq "ANTENNAS_CONFIGURATION_TX") {
                    my $number_antennas = hex(substr($payload,$byte_idx,2));
					$byte_idx = $byte_idx+2;
                    $value .= "[";
                    for (my $i=0; $i<$number_antennas; $i++) {
                        if ($i != 0) {
                            $value .= " - ";
                        }
                        $value .= "ID ".hex(substr($payload,$byte_idx,2));
						$byte_idx = $byte_idx+2;
                    }
                    $value .= "]";
                } elsif ($param_id eq "ANTENNAS_CONFIGURATION_RX") {
                    $Antenna_Config_Rx_mode = hex(substr($payload,$byte_idx,2)); 
					$byte_idx = $byte_idx+2;
                    my $number_ant_or_pairs = hex(substr($payload,$byte_idx,2));
					$byte_idx = $byte_idx+2;
                    # TOF
                    if ($Antenna_Config_Rx_mode == 0) {
                        $value .= "[";
                        for (my $i=0; $i<$number_ant_or_pairs; $i++) {
                            if ($i != 0) {
                                $value .= " - ";
                            }
                            $value .= "ID ".hex(substr($payload,$byte_idx,2));
							$byte_idx = $byte_idx + 2;
                        }
                        $value .= "]";
                        # AOA
                    } elsif ($Antenna_Config_Rx_mode == 1) {
                        for (my $i=0; $i<$number_ant_or_pairs; $i++) {
                            if ($i != 0) {
                                $value .= " - ";
                            }
                            $value .= "PAIR ID ".hex(substr($payload,$byte_idx,2));
							$byte_idx = $byte_idx + 2;
                        }
                    } elsif ($Antenna_Config_Rx_mode == 2) {
                        for (my $i=0; $i<$number_ant_or_pairs; $i++) {
                            $value .= "ID ".hex(substr($payload,$byte_idx,2))."  ";
							$byte_idx = $byte_idx + 2;
                        }
                    } elsif ($Antenna_Config_Rx_mode == 3) {
                        $value .= "RX1(Ranging) => ID ".hex(substr($payload,$byte_idx,2));
						$byte_idx = $byte_idx + 2;
                        $value .= " RX2(Ranging) => ID ".hex(substr($payload,$byte_idx,2));
						$byte_idx = $byte_idx + 2;
                        $value .= " RX1(RFM) => ID ".hex(substr($payload,$byte_idx,2));
						$byte_idx = $byte_idx + 2;
                        $value .= " RX2(RFM) => ID ".hex(substr($payload,$byte_idx,2));
                        $byte_idx += 8;
                    } elsif ($Antenna_Config_Rx_mode == 4) {
                        $value .= "Pair 1 (Horizontal) => ID ".hex(substr($payload,$byte_idx,2));
                        $byte_idx += 2;
                        $value .= " - Pair 2 (Vertical) => ID ".hex(substr($payload,$byte_idx,2));
                        $byte_idx += 2;
                        $value .= " - Pair 3 (during RFM) => ID ".hex(substr($payload,$byte_idx,2));
                        $byte_idx += 2;
                    }
                } elsif ($param_id eq "RAN_MULTIPLIER") {
                    $value .= hex(substr($payload,$byte_idx,2));
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "STS_LAST_INDEX_USED") {
                    $value .= hex(substr($payload,$byte_idx,2));
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "CIR_LOG_NTF") {
                    my $val = hex(substr($payload,$byte_idx,2));
                    $byte_idx += $param_length*2;
                    if ($val == 0) {
                        $value .= "DISABLED";
                    } elsif ($val == 1) {
                        $value .= "ENABLED";
                    }
                } elsif ($param_id eq "PSDU_LOG_NTF") {
                    my $val = hex(substr($payload,$byte_idx,2));
                    $byte_idx += $param_length*2;
                    if ($val == 0) {
                        $value .= "DISABLED";
                    } elsif ($val == 1) {
                        $value .= "ENABLED";
                    }
                } elsif ($param_id eq "RSSI_AVG_FILT_CNT") {
                    my $val = hex(substr($payload,$byte_idx+6,2));
                    $val = (256*$val) + hex(substr($payload,$byte_idx+4,2));
                    $val = (256*$val) + hex(substr($payload,$byte_idx+2,2));
                    $val = (256*$val) + hex(substr($payload,$byte_idx,2));
                    $byte_idx += $param_length*2;
                    $value .= $val;
                } elsif ($param_id eq "CIR_CAPTURE_MODE") {
                    my $CIR1 = hex(substr($payload,$byte_idx,1));
                    $value .= "CIR1 => ".($CIR_MODE{$CIR1} || "?".$CIR1."?");
                    my $CIR0 = hex(substr($payload,$byte_idx+1,1));
                    $value .= " - CIR0 => ".($CIR_MODE{$CIR0} || "?".$CIR0."?");

                    my $tmp = hex(substr($payload,$byte_idx+2,1));
                    #First Quartet is RFU
                    my $CIR2 = hex(substr($payload,$byte_idx+3,1));
                    $value .= " - CIR2 => ".($CIR_MODE{$CIR2} || "?".$CIR2."?");
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "RX_ANTENNA_POLARIZATION_OPTION") {
                    $value .= "0x".substr($payload,$byte_idx,2);
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "SESSION_SYNC_ATTEMPTS") {
                    $value .= hex(substr($payload,$byte_idx,2));
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "SESSION_SHED_ATTEMPTS") {
                    $value .= hex(substr($payload,$byte_idx,2));
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "SCHED_STATUS_NTF") {
                    my $val = hex(substr($payload,$byte_idx,2));
                    if ($val == 0) {
                        $value .= "DISABLED";
                    } elsif ($val == 1) {
                        $value .= "ENABLED all sessions infos";
                    } elsif ($val == 2) {
                        $value .= "ENABLED only failed sessions infos";
                    }
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "TX_POWER_DELTA_FCC") {
                    my $val = hex(substr($payload,$byte_idx,2));
                    if ($val == 0) {
                        $value .= "No offset";
                    } else {
                        $value .= ($value*0.25)."dB attenuation";
                    }
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "TEST_KDF_FEATURE") {
                    my $val = hex(substr($payload,$byte_idx,2));
                    if ($val == 0) {
                        $value .= "DISABLED";
                    } elsif ($val == 1) {
                        $value .= "ENABLED";
                    }
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "TX_POWER_TEMP_COMPENSATION") {
                    my $val = hex(substr($payload,$byte_idx,2));
                    if ($val == 0) {
                        $value .= "DISABLED";
                    } elsif ($val == 1) {
                        $value .= "ENABLED";
                    }
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "WIFI_COEX_MAX_TOLERANCE_COUNT") {
                    $value .= hex(substr($payload,$byte_idx,2));
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "ADAPTIVE_HOPPING_THRESHOLD") {
                    $value .= hex(substr($payload,$byte_idx,2));
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "CONTENTION_PHASE_UPDATE_LENGTH") {
                    $value .= hex(substr($payload,$byte_idx,2));
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "AUTHENTICITY_TAG") {
                    my $val = hex(substr($payload,$byte_idx,2));
                    if ($val == 0) {
                        $value .= "DISABLED";
                    } elsif ($val == 1) {
                        $value .= "ENABLED";
                    }
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "RX_NBIC_CONFIG") {
                    if (hex(substr($payload,$byte_idx,2)) & 0x01) {
                        $value .= "DISABLED";
                    } else {
                        $value .= "ENABLED";
                    }
                    my $tmp = substr($payload,$byte_idx,2) & 0x06;
                    $value .= " - MA_FILTER_BW_SET ".$tmp;
                    $tmp = substr($payload,$byte_idx,2) & 0x18;
                    $value .= " - MA_FILTER_BW_START_SET ".$tmp;

                    $value .= " - PSD_WEIGHT_SET ".substr($payload,$byte_idx+2,2);
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "MAC_CFG") {
                    my $val = hex(substr($payload,$byte_idx,2));
                    if ($val & 0x01) {
                        $value .= " MAC HEADER Present";
                    } else {
                        $value .= " MAC HEADER Not Present";
                    }
                    if($val & 0x02) {
                        $value .= " - MAC FOOTER Present";
                    } else {
                        $value .= " - MAC FOOTER Not Present";
                    }
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "SESSION_INBAND_DATA_TX_BLOCKS") {
                    $value .= hex(substr($payload,$byte_idx,2));
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "SESSION_INBAND_DATA_RX_BLOCKS") {
                    $value .= hex(substr($payload,$byte_idx,2));
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "ANTENNAS_SCAN_CONFIGURATION") {
                    $value .= "0x".substr($payload,$byte_idx,$param_length*2);
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "DATA_TRANSFER_TX_STATUS_CONFIG") {
                    my $val = hex(substr($payload,$byte_idx,2));
                    if ($val == 0) {
                        $value .= "Always ON";
                    } elsif ($val == 1) {
                        $value .= "Always OFF";
                    } elsif ($val == 2) {
                        $value .= "Notify when error";
                    }
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "ULTDOA_MAC_FRAME_FORMAT") {
                    my $val = hex(substr($payload,$byte_idx,2));
                    if ($val == 0) {
                        $value .= "FiRa format";
                    } elsif ($val == 1) {
                        $value .= "Vendor MAC format";
                    }
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "DATA_LOGGER_NTF") {
                    # helios 1
                    if ($param_length == 1) {
                        if (hex(substr($payload,$byte_idx,2)) == 0) {
                            $value .= "DISABLED";
                        } else {
                            $value .= "ENABLED";
                        }
                    }
                    # helios 2
                    else {
                        # 6 bytes
                        # first byte
                        my $val = hex(substr($payload,$byte_idx+10,2));
                        $value .= "".($val == 0 ? "DISABLED" : "ENABLED");
                        # second byte
                        $val = hex(substr($payload,$byte_idx+8,2));
                        if($val == 1) {
                            $value .= " - RX1 captured";
                        } elsif($val == 2) {
                            $value .= " - RX2 captured";
                        } elsif($val == 4) {
                            $value .= " - RX3 captured";
                        }
                        $val = hex(substr($payload,$byte_idx+6,2));
                        if ($val & 0x03 == 2) {
                            $value .= " - Trigger Mode Start";
                        } elsif ($val & 0x03 == 3) {
                            $value .= " - Trigger Mode Stop";
                        }
                        if ($val & 0x40 == 0) {
                            $value .= " - Sample rate 1GHz";
                        } else {
                            $value .= " - Sample rate 500MHz";
                        }
                        if ($val & 0x80 == 0) {
                            $value .= " - Loop mode acquisition";
                        } else {
                            $value .= " - One Shot acquisition";
                        }
                        $byte_idx += $param_length*2;
                    }
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "RFRAME_LOG_NTF") {
                    my $val = hex(substr($payload,$byte_idx,2));
                    if ($val == 0) {
                        $value .= "DISABLED";
                    } elsif ($val == 1) {
                        $value .= "ENABLED";
                    }
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "TX_ADAPTIVE_PAYLOAD_POWER") {
                    my $val = hex(substr($payload,$byte_idx,2));
                    if ($val == 0) {
                        $value .= "DISABLED";
                    } elsif ($val == 1) {
                        $value .= "ENABLED";
                    }
                    $byte_idx += $param_length*2;
                } elsif ($param_id eq "RADAR_MODE") {
                    $value .= hex(substr($payload,$byte_idx,2));
					$byte_idx += $param_length*2;
				} elsif ($param_id eq "RADAR_RX_GAIN") {
                    $value .= hex(substr($payload,$byte_idx,2));
					$byte_idx += $param_length*2;
				}elsif ($param_id eq "RADAR_SINGLE_FRAME_NTF") {
                    $value .= hex(substr($payload,$byte_idx,2));
					$byte_idx += $param_length*2;
				}elsif ($param_id eq "RADAR_CIR_NUM_SAMPLES") {
                    $value .= hex(substr($payload,$byte_idx,2));
					$byte_idx += $param_length*2;
				}elsif ($param_id eq "RADAR_CIR_START_OFFSET") {
                    $value .= hex(substr($payload,$byte_idx,2));
					$byte_idx += $param_length*2;
				}elsif ($param_id eq "RADAR_RFRI") {
                    $value .= hex(substr($payload,$byte_idx,2));
					$byte_idx += $param_length*2;
				}elsif ($param_id eq "RADAR_PRESENCE_DET_CFG") {
                    my $B0 = hex(substr($payload,$byte_idx,2));
                    my $B1 = hex(substr($payload,$byte_idx+2,2));
                    my $B2 = hex(substr($payload,$byte_idx+4,2));
                    my $B3 = hex(substr($payload,$byte_idx+6,2));
                    my $min_dist = hex(substr($payload,$byte_idx+8,2)) + 256 * hex(substr($payload,$byte_idx+10,2));
                    my $max_dist = hex(substr($payload,$byte_idx+12,2)) + 256 * hex(substr($payload,$byte_idx+14,2));
                    my $hold_delay = hex(substr($payload,$byte_idx+16,2)) + 256 * hex(substr($payload,$byte_idx+18,2));
                    my $min_angle = hex(substr($payload,$byte_idx+20,2));
                    $min_angle -= 0x100 if $min_angle > 128;
                    my $max_angle = hex(substr($payload,$byte_idx+22,2));
                    $max_angle -= 0x100 if $max_angle > 128;
                    $value .= " Presence detection enable=".($B0&1);
                    $value .= "    Distance and AoA=".($B0>>1&1);
                    $value .= "    Report all targets=".($B0>>2&1);
                    $value .= "    Detection trigger value reporting=".($B0>>4&1);
                    $value .= "\n     Sending raw CIRs to the host=".($B1&1);
                    $value .= "    Periodic data reporting=".($ocpd_periodic_report{$B1>>1&3} || "???");
                    $value .= "    Presence Detection Sensitivity=".sprintf("%.2f", $B2/16);
                    $value .= "    GPIO config=0x".sprintf("%02x", $B3);
                    $value .= "\n     min_dist=".$min_dist."cm";
                    $value .= "    max_dist=".$max_dist."cm";
                    $value .= "    hold_delay=".$hold_delay."ms";
                    $value .= "    min_angle=".$min_angle."deg";
                    $value .= "    max_angle=".$max_angle."deg";
					$byte_idx += $param_length*2;
				} elsif ($param_id eq "RADAR_PERFORMANCE") {
                    $value .= hex(substr($payload,$byte_idx,2));
					$byte_idx += $param_length*2;
				}elsif ($param_id eq "RADAR_DRIFT_COMPENSATION") {
                    $value .= hex(substr($payload,$byte_idx,2));
					$byte_idx += $param_length*2;
				}elsif ($param_id eq "RADAR_CONFIG ") {
                    $value .= hex(substr($payload,$byte_idx,2));
					$byte_idx += $param_length*2;
				}
				else {
                    $value .= "0x".substr($payload,$byte_idx,$param_length*2);
                    $byte_idx += $param_length*2;
                }
                
                # Check if decoding exceeds the size of terminal width
                $line_length += length($param_id)+length($value)+4;
                
                if ($line_length > $MAX_LINE_SIZE) {
                    # Add new line
                    $decode .= "\n".$indent;
                    $line_length = length($indent)+length($param_id)+length($value)+2;
                }
                
                $decode .= $param_id.": ".$value."   ";
            }
            
            $decode .= $nocolor;
        }

        # SET_VENDOR_APP_CONFIG_RSP
        elsif ($mt_gid_oid eq "4F00") {
            my $byte_idx = 0;
            my $status = substr($payload,$byte_idx,2);
            my $num_params;
            $byte_idx += 2;

            $decode .= $brown;
            
            if ($status == "00") {
                $decode .= "   Status OK";
                $byte_idx += 2;# number of vendor app config failed = 00
            } else {
                #$decode .= "   Status failed";
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
                $num_params = substr($payload,$byte_idx,2);
                $byte_idx += 2;

                foreach (1..$num_params) {
                    my $param_id = substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    my $param_status = substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    
                    $decode .= "\n".$indent.($set_vendor_app_config{$param_id} || "?".$param_id."?");
                    $decode .= " :".($status_code{$param_status} || "???");
                    #$decode .= $red.$param_id.":".($status_code{$param_status} || "???")." ";
                }
            }

            $decode .= $nocolor;
        }

        # URSK_DELETE_CMD
        elsif ($mt_gid_oid eq "2F01") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= "\n".$brown.$indent;

            my $num_sessions = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            $decode .= "Sessions to be removed (*".$num_sessions.")";
            $decode .= "\n".$indent.$indent;

            for (my $i=0; $i<$num_sessions; $i++) {
                $decode .= "Session ID:0x";
                $decode .= substr($payload,$byte_idx+6,2);
                $decode .= substr($payload,$byte_idx+4,2);
                $decode .= substr($payload,$byte_idx+2,2);
                $decode .= substr($payload,$byte_idx,2);
                $byte_idx += 8;
                $decode .= "  ";
            }
        }

        # URSK_DELETE_RSP
        elsif ($mt_gid_oid eq "4F01") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }
        }

        # URSK_GET_NTF
        elsif ($mt_gid_oid eq "6F01") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
                $decode .= "\n".$brown.$indent;

                my $num_sessions = hex(substr($payload,$byte_idx,2));
                $byte_idx += 2;
                $decode .= "Sessions to be removed (*".$num_sessions.")";

                for (my $i=0; $i<$num_sessions; $i++) {
                    $decode .= "\n".$indent.$indent."Session ID:0x";
                    $decode .= substr($payload,$byte_idx+6,2);
                    $decode .= substr($payload,$byte_idx+4,2);
                    $decode .= substr($payload,$byte_idx+2,2);
                    $decode .= substr($payload,$byte_idx,2);
                    $byte_idx += 8;

                    my $session_status = substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    $decode .= "  Status: ".($ursk_deletion_status{$session_status} || "???");
                }
            }
        }

        # GET_ALL_UWB_SESSIONS_CMD
        elsif ($mt_gid_oid eq "2F02") {
            # NOTHING TO SHOW
        }
        
        # GET_ALL_UWB_SESSIONS_RSP
        elsif ($mt_gid_oid eq "4F02") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            }
            
            # Number of sessions
            my $nb_sessions = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            
            foreach (1..$nb_sessions) {
                $decode .= "\n".$indent.$brown;
                
                # Session ID
                $decode .= " Session Handle:0x";
                $decode .= substr($payload,$byte_idx+6,2);
                $decode .= substr($payload,$byte_idx+4,2);
                $decode .= substr($payload,$byte_idx+2,2);
                $decode .= substr($payload,$byte_idx,2);
                $byte_idx += 8;
                
                # Session type
                $decode .= "   Type:".($session_type{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
                
                # Session state
                $decode .= "   ".($session_state{substr($payload,$byte_idx,2)} || "???");
                $byte_idx += 2;
            }
            
            $decode .= $nocolor;
        }

        # GET_VENDOR_APP_CONFIG_CMD
        elsif ($mt_gid_oid eq "2F03") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;

            # Session ID
            $decode .= "   Session Handle:0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;

            $decode .= "\n".$indent;

            # Number of parameters
            my $nb_params = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;

            foreach (1..$nb_params) {
                # Parameter ID
                my $param_id = substr($payload,$byte_idx,2);
                $byte_idx += 2;

                $param_id = $set_vendor_app_config{$param_id} || "?".$param_id."?";

                $decode .= " ".$param_id;
            }
        }
        
        # GET_VENDOR_APP_CONFIG_RSP
        elsif ($mt_gid_oid eq "4F03") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            
            $decode .= $brown;
            my $num_params;
            
            if ($status == "00") {
                $decode .= "   Status OK";
                $byte_idx += 2;# number of vendor app config failed = 00
            } else {
                #$decode .= "   Status failed";
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
                $num_params = substr($payload,$byte_idx,2);
                $byte_idx += 2;

                foreach (1..$num_params) {
                    my $param_id = substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    my $param_length = hex(substr($payload,$byte_idx,2));
                    $byte_idx += 2;
                    my $param_value = substr($payload,$byte_idx,$param_length*2);
                    $byte_idx += $param_length*2;
                    
                    $decode .= "\n".$indent.($set_vendor_app_config{$param_id} || "?".$param_id."?");
                    $decode .= ":".$param_value;
                }

            }
            
            $decode .= $nocolor;
        }

        # DO_CHIP_CALIBRATION_CMD
        elsif ($mt_gid_oid eq "2F20") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= "\n".$brown.$indent."Channel ID:".substr($payload,$byte_idx,2);
        }

        # DO_CHIP_CALIBRATION_RSP
        elsif ($mt_gid_oid eq "4F20") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            
            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            }
        }

        # DO_CHIP_CALIBRATION_NTF
        elsif ($mt_gid_oid eq "6F20") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;

            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
                $decode .= "\n".$brown.$indent;
                my $calib_code = substr($payload,$byte_idx,2);
                my $calib_status = substr($payload,$byte_idx+2,1);
                if ($calib_status & 0x8) {
                    $decode .= "  Calibration is valid";
                } else {
                    $decode .= "  Calibration is invalid";
                }
            }
        }

        # SET_DEVICE_CALIBRATION_CMD
        elsif ($mt_gid_oid eq "2F21") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;
            
            $decode .= "\n".$brown.$indent."Channel ID:".substr($payload,$byte_idx,2);
            $byte_idx += 2;

            my $calib_param = substr($payload,$byte_idx,2);
            $calib_param = $CALIBRATION_PARAMETERS{$calib_param} || "?".$calib_param."?";
            $byte_idx += 2;

            my $param_length = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;

            my $value;

            if ($calib_param eq "VCO_PLL") {
                $value .= $indent."0x".hex(substr($payload,$byte_idx,4));
                $byte_idx += 4;
            } elsif ($calib_param eq "RF_CLK_ACCURACY_CALIB") {
                $value .= $indent."RF_CLK_ACCURACY_CALIB ";
                $value .= "Number of register (must be 3): ".substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= "\n".$indent."Capacitors values:";
                my $val = substr($payload,$byte_idx+2,2).substr($payload,$byte_idx,2);
                $value .= "\n".$indent.$indent."38.4MHz XTAL CAP1: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 4;
                $val = substr($payload,$byte_idx+2,2).substr($payload,$byte_idx,2);
                $value .= "\n".$indent.$indent."38.4MHz XTAL CAP2: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 4;
                $val = substr($payload,$byte_idx+2,2).substr($payload,$byte_idx,2);
                $value .= "\n".$indent.$indent."38.4MHz XTAL GM CURRENT CTRL: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 4;
            } elsif ($calib_param eq "RX_ANT_DELAY_CALIB") {
                my $number_entries = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= $indent."RX_ANT_DELAY_CALIB (*".$number_entries."):\n";
                for (my $i=0; $i<$number_entries; $i++) {
                    $value .= $indent.$indent."RX".hex(substr($payload,$byte_idx,2));
                    $byte_idx += 2;
                    # UNSIGNED RX_DELAY (Q14.2 format)
                    my $rx_delay = substr($payload,$byte_idx,2).substr($payload,$byte_idx+2,2);
                    $value .= "  RX_DELAY: 0x".$rx_delay;
                    $byte_idx += 4;
                }
            } elsif ($calib_param eq "PDOA_OFFSET_CALIB") {
                my $number_entries = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= $indent."PDOA_OFFSET_CALIB (*".$number_entries."):";
                for (my $i=0; $i<$number_entries; $i++) {
                    $value .= "\n".$indent.$indent."RX".hex(substr($payload,$byte_idx,2));
                    $byte_idx += 2;
                    # SIGNED PDOA_OFFSET (Q9.7 format)
                    my $pdoa_offset = substr($payload,$byte_idx,2).substr($payload,$byte_idx+2,2);
                    $value .= "  PDOA_OFFSET: 0x".$pdoa_offset;
                    $byte_idx += 4;
                }
            } elsif ($calib_param eq "TX_POWER_PER_ANTENNA") {
                my $number_entries = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= $indent."TX_POWER_PER_ANTENNA (*".$number_entries."):";
                for (my $i=0; $i<$number_entries; $i++) {
                    $value .= "\n".$indent.$indent."TX".hex(substr($payload,$byte_idx,2));
                    $byte_idx += 2;
                    $value .= "  TX_POWER_DELTA_PEAK: 0x".substr($payload,$byte_idx,2);
                    $byte_idx += 4;
                    $value .= "  TX_POWER_ID_RMS: 0x".substr($payload,$byte_idx,2);
					$byte_idx += 4;
                }
            } elsif ($calib_param eq "AOA_PHASEFLIP_ANTSPACING") {
                my $number_entries = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= $indent."AOA_PHASEFLIP_ANTSPACING (*".$number_entries."):\n";
                for (my $i=0; $i<$number_entries; $i++) {
                    $value .= $indent."RX PAIR ID [".hex(substr($payload,$byte_idx,2))."]";
                    $byte_idx += 2;
                    my $val = substr($payload,$byte_idx,2).substr($payload,$byte_idx+2,2);
                    $val = hex($val)/2;
                    $value .= " ANTENNA_SPACING: 0x".$val;
                    $val = hex(substr($payload,$byte_idx+2,2));
                    $val = $val & 0x01;
                    $value .= " - PHASE_FLIP: 0x".$val;
                    $byte_idx += 2;
                }
            } elsif ($calib_param eq "PLATFORM_ID") {
                $value .= $indent."PLATFORM_ID: ";
				my $platform;
                for (my $i=0; $i<16; $i++) {
                    $platform .= substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                }
				$value .= pack( 'H*', $platform =~ s/^\\x//r );
            } elsif ($calib_param eq "CONFIG_VERSION") {
                $value .= $indent."CONFIG_VERSION: ";
                $value .= hex(substr($payload,$byte_idx,2)).".";
                $value .= hex(substr($payload,$byte_idx+2,2)).".";
                $value .= hex(substr($payload,$byte_idx+4,2)).".";
                $value .= hex(substr($payload,$byte_idx+6,2));
                $byte_idx += 8;
            } elsif ($calib_param eq "MANUAL_TX_POW_CTRL") {
                $value .= "MANUAL_TX_POW_CTRL:";
                $value .= "  TX_PA_GAIN: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= "  TX_PPA_GAIN: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= "  TX_DIG_GAIN: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= "  DAC_GAIN: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= "  TX_MIX_GAIN: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 2;
            } elsif ($calib_param eq "AOA_ANTENNAS_PDOA_CALIB") {
                my $number_entries = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= $indent."AOA_ANTENNAS_PDOA_CALIB: ";
                for (my $i=0; $i<$number_entries; $i++) {
                    $value .= $indent."RX PAIR ID [".hex(substr($payload,$byte_idx,2))."]";
                    $byte_idx += 2;
                }
            } elsif ($calib_param eq "TX_ANT_DELAY_CALIB") {
                my $number_entries = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= $indent."TX_ANT_DELAY_CALIB (*".$number_entries."):\n";
                for (my $i=0; $i<$number_entries; $i++) {
                    $value .= $indent."TX".hex(substr($payload,$byte_idx,2));
                    $byte_idx += 2;
                    # UNSIGNED TX_DELAY (Q14.2 format)
                    my $tx_delay = substr($payload,$byte_idx,2).substr($payload,$byte_idx+2,2);
                    $value .= "  TX_DELAY: 0x".$tx_delay;
                    $byte_idx += 4;
                }
            } elsif ($calib_param eq "PDOA_MANUFACT_ZERO_OFFSET_CALIB") {
                my $number_entries = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= $indent."PDOA_MANUFACT_ZERO_OFFSET_CALIB (*".$number_entries."):";
                for (my $i=0; $i<$number_entries; $i++) {
                    $value .= "\n".$indent.$indent."RX PAIR ID [".hex(substr($payload,$byte_idx,2))."]: ";
                    $byte_idx += 2;
                    $value .= "Manufacture PDoA1 Offset : 0x".substr($payload,$byte_idx,4);
                }
            } elsif ($calib_param eq "AOA_THRESHOLD_PDOA") {
                my $number_entries = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= $indent."AOA_THRESHOLD_PDOA (*".$number_entries."):";
                for (my $i=0; $i<$number_entries; $i++) {
                    $value .= "\n".$indent.$indent."RX PAIR ID [".hex(substr($payload,$byte_idx,2))."]: ";
                    $byte_idx += 2;
                    $value .= "Threshold value: 0x".substr($payload,$byte_idx,4);
                    $byte_idx += 4;
                }
            } elsif ($calib_param eq "TX_TEMPERATURE_COMP_PER_ANTENNA") {
                my $number_entries = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= $indent."TX_TEMPERATURE_COMP_PER_ANTENNA (*".$number_entries."):\n";
                for (my $i=0; $i<$number_entries; $i++) {
                    $value .= $indent."TX".hex(substr($payload,$byte_idx,2));
                    $byte_idx += 2;
                    $value .= "\n".$indent.$indent."RANGE1_TX_POWER_UPPER_BOUND: 0x".substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    $value .= "  RANGE1_TX_POWER_GAIN_BOUND:0x".substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    $value .= "\n".$indent.$indent."RANGE2_TX_POWER_UPPER_BOUND: 0x".substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    $value .= "  RANGE2_TX_POWER_GAIN_BOUND:0x".substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    $value .= "\n".$indent.$indent."RANGE3_TX_POWER_UPPER_BOUND: 0x".substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    $value .= "  RANGE3_TX_POWER_GAIN_BOUND:0x".substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    $value .= "\n".$indent.$indent."RANGE4_TX_POWER_UPPER_BOUND: 0x".substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                    $value .= "  RANGE4_TX_POWER_GAIN_BOUND: 0x".substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                }
            } elsif ($calib_param eq "SNR_CALIB_CONSTANT_PER_ANTENNA") {
                my $number_entries = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= $indent."SNR_CALIB_CONSTANT_PER_ANTENNA (*".$number_entries."):\n";
                for (my $i=0; $i<$number_entries; $i++) {
                    $value .= $indent."RX".hex(substr($payload,$byte_idx,2));
                    $byte_idx += 2;
                    $value .= "  SNR_CALIB: 0x".substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                }
            } elsif ($calib_param eq "RSSI_CALIB_CONSTANT_HIGH_PWR") {
                my $number_entries = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= $indent."RSSI_CALIB_CONSTANT_HIGH_PWR (*".$number_entries."):\n";
                for (my $i=0; $i<$number_entries; $i++) {
                    $value .= $indent."RX".hex(substr($payload,$byte_idx,2));
                    $byte_idx += 2;
                    $value .= "  RSSI_HIGH_CALIB: 0x".substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                }
            } elsif ($calib_param eq "RSSI_CALIB_CONSTANT_LOW_PWR") {
                my $number_entries = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= $indent."RSSI_CALIB_CONSTANT_LOW_PWR (*".$number_entries."):\n";
                for (my $i=0; $i<$number_entries; $i++) {
                    $value .= $indent."RX".hex(substr($payload,$byte_idx,2));
                    $byte_idx += 2;
                    $value .= "  RSSI_LOW_CALIB: 0x".substr($payload,$byte_idx,2);
                    $byte_idx += 2;
                }
            } elsif ($calib_param eq "TRA2_LOFT_CALIB") {
                $value .= $indent."TRA2_LOFT_CALIB:";
                $value .= "  TX_DAC_OFFSET_I_SET: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= "  TX_DAC_OFFSET_Q_SET: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= "  TX_DC_OFFSET_I_SET: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= "  TX_DC_OFFSET_Q_SET: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 2;
            } elsif ($calib_param eq "TRA1_LOFT_CALIB") {
                $value .= $indent."TRA1_LOFT_CALIB:";
                $value .= "  TX_DAC_OFFSET_I_SET: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= "  TX_DAC_OFFSET_Q_SET: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= "  TX_DC_OFFSET_I_SET: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 2;
                $value .= "  TX_DC_OFFSET_Q_SET: 0x".substr($payload,$byte_idx,2);
                $byte_idx += 2;
            } else {
                $value .= $indent."0x".substr($payload,$byte_idx,$param_length*2);
                $byte_idx += $param_length*2;
            }
                
            # Check if decoding exceeds the size of terminal width
            my $line_length += length($calib_param)+length($value)+4;
            
            if ($line_length > $MAX_LINE_SIZE) {
                # Add new line
                $decode .= "\n";
                $line_length = length($indent)+length($calib_param)+length($value)+2;
            }
            
            $decode .= $value."  ";
        }

        # SET_DEVICE_CALIBRATION_RSP
        elsif ($mt_gid_oid eq "4F21") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            }
        }

        # GET_DEVICE_CALIBRATION_CMD
        elsif ($mt_gid_oid eq "2F22") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= $brown;

            # Channel ID
            $decode .= "   Channel ID:".substr($payload,$byte_idx,2);
            $byte_idx += 2;

            # Calibration parameter
            my $calib_param = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            $decode .= "\n".$indent.($CALIBRATION_PARAMETERS{$calib_param} || "?".$calib_param."?");
        }

        # GET_DEVICE_CALIBRATION_RSP
        elsif ($mt_gid_oid eq "4F22") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            
            $decode .= $brown;
            
            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= "   Status OK";

                # Calibration state
                my $calib_state = substr($payload,$byte_idx,2);
                $byte_idx += 2;

                $decode .= "\n".$indent."Calibration state: ".($CALIBRATION_PARAM_STATES{$calib_state} || "???");

				if ($calib_state ne "08") {
					# Calibration parameter
					my $calib_param = substr($payload,$byte_idx,2);
					$byte_idx += 2;
					$decode .= "\n".$indent.($CALIBRATION_PARAMETERS{$calib_param} || "?".$calib_param."?").": ";

					# Calibration param length
					my $param_length = hex(substr($payload,$byte_idx,2));
					$byte_idx += 2;

					my $platform;
					for (my $i=0; $i<$param_length; $i++) {
						$platform .= substr($payload,$byte_idx,2);
						$byte_idx += 2;
					}

					# Calibration param value
					if ($calib_state ne "05") {
						#$decode .= "0x".substr($payload,$byte_idx,$param_length*2);
						$decode .= pack( 'H*', $platform =~ s/^\\x//r );
					} else {
						$decode .= "Invalid state";
					}
				}
            }
            
            $decode .= $nocolor;
        }

        # UWB_ESE_BINDING_CMD
        elsif ($mt_gid_oid eq "2F31") {
            # NOTHING TO SHOW
        }

        # UWB_ESE_BINDING_RSP
        elsif ($mt_gid_oid eq "4F31") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }
        }

        # UWB_ESE_BINDING_NTF
        elsif ($mt_gid_oid eq "6F31") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            
            if ($status ne "00") {
                $decode .= "   ".$red_oops.($binding_status{$status} || "???");
            }

            # UWBS Binding Count
            my $binding_count = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            $decode .= "\n".$brown.$indent."UWBS Binding Remaining Count: ".$binding_count;

            # Binding state
            my $binding_state = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            $decode .= "   Binding State: ".($binding_state{$binding_state} || "???");

            # SE Instruction Code
            $decode .= "   SE Instruction Code: 0x".substr($payload,$byte_idx+2,2).substr($payload,$byte_idx,2);
            $byte_idx += 4;

            # SE Error status
            $decode .= "   SE Error Status: 0x".substr($payload,$byte_idx+2,2).substr($payload,$byte_idx,2);
            $byte_idx += 4;
        }

        # UWB_ESE_BINDING_CHECK_CMD
        elsif ($mt_gid_oid eq "2F32") {
            # NOTHING TO SHOW
        }

        # UWB_ESE_BINDING_CHECK_RSP
        elsif ($mt_gid_oid eq "4F32") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Status
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            if ($status ne "00") {
                $decode .= "   ".$red_oops.($status_code{$status} || "???");
            } else {
                $decode .= $brown."   Status OK";
            }
        }

        # UWB_ESE_BINDING_CHECK_NTF
        elsif ($mt_gid_oid eq "6F32") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Binding status check
            my $status = substr($payload,$byte_idx,2);
            $byte_idx += 2;
            $decode .= "   ".$red_oops.($binding_status_check{$status} || "???");

            # SE Binding count
            my $binding_count = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            $decode .= "\n".$brown.$indent."SE Binding Remaining Count: ".$binding_count;

            # UWBS Binding count
            $binding_count = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            $decode .= "   UWBS Binding Remaining Count: ".$binding_count;

            $decode .= "\n".$indent;

            # SE Instruction Code
            $decode .= "   SE Instruction Code: 0x".substr($payload,$byte_idx+2,2).substr($payload,$byte_idx,2);
            $byte_idx += 4;

            # SE Error status
            $decode .= "   SE Error Status: 0x".substr($payload,$byte_idx+2,2).substr($payload,$byte_idx,2);
            $byte_idx += 4;
        }

        # PSDU_LOG_NTF
        elsif ($mt_gid_oid eq "6F33") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Session ID
            $decode .= $brown."   Session Handle: 0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
        }

        # CIR_LOG_NTF
        elsif ($mt_gid_oid eq "6F34") {
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            # Session ID
            $decode .= $brown."   Session Handle: 0x";
            $decode .= substr($payload,$byte_idx+6,2);
            $decode .= substr($payload,$byte_idx+4,2);
            $decode .= substr($payload,$byte_idx+2,2);
            $decode .= substr($payload,$byte_idx,2);
            $byte_idx += 8;

            # Slot Index
            $decode .= "\n".$indent."Slot Index: ".hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;

            # RX Antenna ID
            $decode .= "   RX Antenna ID: ".hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;

            # Number of CIR
            my $num_cir = 256*hex(substr($payload,$byte_idx+2,2));
            $num_cir += hex(substr($payload,$byte_idx,2));
            $byte_idx += 4;

            $decode .= "   Number of CIR: ".$num_cir;

            $decode .= "   CIR Start with: 0x".substr($payload,$byte_idx+8,2);
        }

        ################### NXP Internal group ####################
        elsif ( ($mt_gid_oid eq "6B22") and ( $rframe_ntf_enable == 1) ) {
            # DBG_RFRAME_LOG_NTF

            $payload_length_RFRAME = $payload_length;
            
            # Put Byte index on the beginning of payload
            my $byte_idx = 0;

            $decode .= "\n".$indent.$brown;
            
            # Session ID
            my $session_id = substr($payload,$byte_idx+6,2);
            $session_id .= substr($payload,$byte_idx+4,2);
            $session_id .= substr($payload,$byte_idx+2,2);
            $session_id .= substr($payload,$byte_idx,2);
            $byte_idx += 8;
            
            # $decode .= "\n".$indent.$brown."   Payload: ".$payload;

            $decode .= "   Session Handle:0x".$session_id;
            #$decode .= " INDEX PBE ".$byte_idx; #  PBE

            #my $Seq_coutner = substr($payload,$byte_idx+6,2);
            #$Seq_coutner .= substr($payload,$byte_idx+4,2);
            #$Seq_coutner .= substr($payload,$byte_idx+2,2);
            #$Seq_coutner .= substr($payload,$byte_idx,2);
            $byte_idx += 8;

            # TX antenna 
			my $Tx_Antenna_ID = substr($payload,$byte_idx,2);
			$decode .= "   Tx Antenna:0x".$Tx_Antenna_ID;
            $byte_idx += 2;

            # Number of measurements
            my $nb_meas = hex(substr($payload,$byte_idx,2));
            $byte_idx += 2;
            #size of RFRAME
            $byte_idx += 2;

            #RFU
            $byte_idx += 2;

            $csv_rframe = "";

			$csv_rframe .= "0x".$session_id; #GM July 1 2024
            
            $number_times_add_RFRAME_Titles = $nb_meas;
            foreach (1..$nb_meas) {
                $decode .= "\n".$indent.$brown;
                
                if ($device_msg ne "") {
                    $csv_rframe .= $device_msg.";";
                }
                
                # Mapping
                my $rframe_rx;
                my $rframe_slot_idx;
                if (index($Device_Name,"SR1") > 0) {
                    $rframe_rx = ((hex(substr($payload,$byte_idx,2)) & 0x80) ? "  RX2  " : "  RX1  ");
                    $rframe_slot_idx = hex(substr($payload,$byte_idx,2)) & 0x7F;
                }
                else {
                    # SR2xx
                    if ((hex(substr($payload,$byte_idx,2)) & 0xC0) == 0x00) {
					    $rframe_rx = "  RXC  ";
				    } elsif ((hex(substr($payload,$byte_idx,2)) & 0xC0) == 0x40) {
					    $rframe_rx = "  RXB  ";
				    } else {
					    $rframe_rx = "  RXA  ";
				    }
                    $rframe_slot_idx = hex(substr($payload,$byte_idx,2)) & 0x3F;
                }
                $byte_idx += 2;
                
                $csv_rframe .= ";".$rframe_rx;
                $csv_rframe .= ";".$rframe_slot_idx;
                
                $decode .= " ".$rframe_rx." slot idx:".$rframe_slot_idx;
                
                # Status
                my $status = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                
                $csv_rframe .= ";".$status;
                
                $decode .= "   Status: ".($rframe_dec_status{$status} || "???");
                
                # Line of Sight
                my $nlos = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                
                $csv_rframe .= ";".$nlos;
                
                $decode .= "   ".($los_type{$nlos} || "???");
                
                $decode .= "\n".$indent.$brown;
                
                # First path index (unsigned Q10.6 format)
                my $first_path_index = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                $first_path_index = $first_path_index/64;
                $byte_idx += 4;
                
                $csv_rframe .= ";".$first_path_index;
                
                $decode .= "   First path:".$first_path_index."ns";
                
                # Main path index (unsigned Q10.6 format)
                my $main_path_index = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                $main_path_index = $main_path_index/64;
                $byte_idx += 4;
                
                $csv_rframe .= ";".$main_path_index;
                
                $decode .= "   Main path:".$main_path_index."ns";
                
                # SNR main and first paths
                my $snr_main = hex(substr($payload,$byte_idx,2));
                my $snr_first = hex(substr($payload,$byte_idx+2,2));
                $byte_idx += 4;
                
                $csv_rframe .= ";".$snr_main.";".$snr_first;
                
                $decode .= "\n".$indent.$brown;
                
                $decode .= "   SNR main path:".$snr_main."dB";
                $decode .= "   SNR first path:".$snr_first."dB";
                
                # SNR Total (unsigned Q8.8 format)
                my $snr_total = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                $snr_total = $snr_total/256;
                $byte_idx += 4;
                
                $csv_rframe .= ";".$snr_total;
                
                $decode .= "   SNR total:".$snr_total."dB";
                
                # RSSI (signed Q8.8 format)
                my $rssi = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                $rssi -= 0x10000 if ($rssi > 32767);
                $rssi = $rssi/256;
                $byte_idx += 4;
                
                $csv_rframe .= ";".$rssi;
                
                $decode .= "   RSSI:".$rssi."dB";
                
                $decode .= "\n".$indent.$brown;
                
                # CIR main power
                my $cir_main_power = hex(substr($payload,$byte_idx+6,2));
                $cir_main_power = (256*$cir_main_power)+hex(substr($payload,$byte_idx+4,2));
                $cir_main_power = (256*$cir_main_power)+hex(substr($payload,$byte_idx+2,2));
                $cir_main_power = (256*$cir_main_power)+hex(substr($payload,$byte_idx,2));
                $byte_idx += 8;
                
                $csv_rframe .= ";".$cir_main_power;
                
                $decode .= "   CIR main power:".$cir_main_power;
                
                # CIR first path power
                my $cir_first_power = hex(substr($payload,$byte_idx+6,2));
                $cir_first_power = (256*$cir_first_power)+hex(substr($payload,$byte_idx+4,2));
                $cir_first_power = (256*$cir_first_power)+hex(substr($payload,$byte_idx+2,2));
                $cir_first_power = (256*$cir_first_power)+hex(substr($payload,$byte_idx,2));
                $byte_idx += 8;
                
                $csv_rframe .= ";".$cir_first_power;
                
                $decode .= "   CIR first path power:".$cir_first_power;
                
                # Noise variance
                # my $noise_variance = (65536*hex(substr($payload,$byte_idx+4,2)))+(256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                my $noise_variance = hex(substr($payload,$byte_idx+6,2));
                $noise_variance = (256*$noise_variance) + hex(substr($payload,$byte_idx+4,2));
                $noise_variance = (256*$noise_variance) + hex(substr($payload,$byte_idx+2,2));
                $noise_variance = (256*$noise_variance) + hex(substr($payload,$byte_idx,2));
                $byte_idx += 8;
                
                $csv_rframe .= ";".$noise_variance;
                
                $decode .= "   Noise variance:".$noise_variance;
                
                $decode .= "\n".$indent.$brown;
                
                # CFO (signed 16-bits integer)
                #my $cfo = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                #$cfo -= 0x10000 if ($cfo > 32767);
                #$byte_idx += 4;
                
                #$csv_rframe .= ";".$cfo;
                
                #$decode .= "   CFO:".$cfo;

                # CFO (signed Q5.11) PPM????
                my $cfo = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                $cfo -= 0x10000 if ($cfo > 32767);
                $cfo = $cfo/2048;
                $byte_idx += 4;
                $csv_rframe .= ";".$cfo;    
                $decode .= "   CFO : ".sprintf("%+06.4f",$cfo)."ppm";
                
                # AoA Phase (signed Q9.7 value)
                my $aoa_phase = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                $aoa_phase -= 0x10000 if ($aoa_phase > 32767);
                $aoa_phase = $aoa_phase/128;
                $byte_idx += 4;
                
                $csv_rframe .= ";".$aoa_phase;
                
                $decode .= "   AoA Phase:".$aoa_phase."deg";
                
                $decode .= "\n".$indent.$brown."   CIR samples:";
                
                # CIR samples (signed 16-bits complex)
				$csv_rframe .= ";{"; #GM July 1 2024
                foreach my $cir_idx (1..16) {
                    my $cir_real = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                    my $cir_imaginary = (256*hex(substr($payload,$byte_idx+6,2)))+hex(substr($payload,$byte_idx+4,2));
                    $cir_real -= 0x10000 if ($cir_real > 32767);
                    $cir_imaginary -= 0x10000 if ($cir_imaginary > 32767);
                    $byte_idx += 8;
                    
                    my $cir_sample = sprintf("%+06d",$cir_real).sprintf("%+06d",$cir_imaginary)."i";
                    
                    $csv_rframe .= "|".$cir_sample;
                    
                    $decode .= $cir_sample;
                    
                    if (($cir_idx == 5) || ($cir_idx == 11)) {
                        $decode .= "\n".$indent.$brown."     ";
                    } else {
                        $decode .= "   ";
                    }
                }
				$csv_rframe .= "}"; #GM July 1 2024
                
                # RX Timestamp
                my $rx_timestamp_Frac = hex(substr($payload,$byte_idx+10,2));
                $rx_timestamp_Frac = (256*$rx_timestamp_Frac) + hex(substr($payload,$byte_idx+8,2));
				
                my $rx_timestamp_int = hex(substr($payload,$byte_idx+6,2));
                $rx_timestamp_int = (256*$rx_timestamp_int) + hex(substr($payload,$byte_idx+4,2));
                $rx_timestamp_int = (256*$rx_timestamp_int) + hex(substr($payload,$byte_idx+2,2));
                $rx_timestamp_int = (256*$rx_timestamp_int) + hex(substr($payload,$byte_idx,2));
                $byte_idx += 12;

                $decode .= "\n".$indent.$brown."   RX Timestamp_Int:".$rx_timestamp_int;

                # RX_timestamp_Frac Phase (signed Q7.9 value)
                $rx_timestamp_Frac -= 0x10000 if ($rx_timestamp_Frac > 32767);
                $rx_timestamp_Frac = $rx_timestamp_Frac/512;
                $decode .= "   RX Timestamp_Frac:".$rx_timestamp_Frac;
				$csv_rframe .= ";".$rx_timestamp_int; 
				$csv_rframe .= ";".$rx_timestamp_Frac; 

				my $timestamp = $rx_timestamp_int + $rx_timestamp_Frac;
				$decode .= "   RX Timestamp:".$timestamp;
				$decode .= "   RX Timestamp (ms):".$timestamp/(3.25*38.4e6);
				$csv_rframe .= ";".$timestamp; 	
				
			    $csv_rframe .= ";";	
			    $byte_idx += 2;
            }
            $csv_rframe .= "\n"; #GM April 16 2024
            $decode .= $nocolor;
        }

    }
    
    elsif (exists($uci_data_packet{$mt_dpf})) {
        # Formating of $msg
        # UCI Data
        $msg = "   ".$uci_data_packet{$mt_dpf};
        
        # Check segmentation
        if ($pbf == 1) {
            if ($seg_mt_dpf ne $mt_dpf) {
                $seg_mt_dpf = $mt_dpf;
                
                # Copy payload in Segment
                $seg_payload = $payload;
            } else {
                # Concatenate payload in Segment
                $seg_payload .= $payload;
            }
            
            $decode .= "   Data Segment".$nocolor;
            
            # Exit UCI Parser
            return;
        } elsif (($seg_payload ne "") and ($seg_mt_dpf eq $mt_dpf)) {
            # Complete Segment
            $payload = $seg_payload.$payload;
            
            # Clear Segment
            $seg_mt_dpf = "";
            $seg_payload = "";
        }
        
        # Decoding UCI payload
        if ( $mt_dpf eq "03") {
            # DATA_MESSAGE_SND
            if ($payload_length > 0) {
                # Put Byte index on the beginning of payload
                my $byte_idx = 0;
                
                $decode .= "\n".$indent.$magenta;
                
                # Session ID
                $decode .= " Logical Link Layer:0x";
                $decode .= substr($payload,$byte_idx+6,2);
                $decode .= substr($payload,$byte_idx+4,2);
                $decode .= substr($payload,$byte_idx+2,2);
                $decode .= substr($payload,$byte_idx,2);
                $byte_idx += 8;
                
                # Sequence Number
                #my $seq_number = sprintf("%d", hex(substr($payload,$byte_idx,4)));
				my $seq_number = hex(substr($payload,$byte_idx,2));
				$byte_idx += 2;
				$seq_number += 256*hex(substr($payload,$byte_idx,2));
                $decode .= "   Sequence Number:".$seq_number;
                $byte_idx += 2;
                
                # Application Data Length
                my $app_data_length = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                $byte_idx += 4;
				
                # Calculate length for indent and Sequence Number
                my $busy_space = length($indent)+19+length($seq_number)+8;
                
                # Truncate the data if exceeds the size of terminal width
                my $app_data = ((2*$app_data_length) > ($MAX_LINE_SIZE-$busy_space)) ? substr($payload,$byte_idx,$MAX_LINE_SIZE-$busy_space-3)."..." : substr($payload,$byte_idx,2*$app_data_length);
                
				$app_data =  pack( 'H*', $app_data =~ s/^\\x//r );
                $decode .= "   Data:".$app_data;
            }
            
            $decode .= $nocolor;
        }
        
        elsif ( ($mt_dpf eq "02")){
            # DATA_MESSAGE_RCV
            if ($payload_length > 0) {
                # Put Byte index on the beginning of payload
                my $byte_idx = 0;
                
                $decode .= "\n".$indent.$magenta;
                
                # Session ID
                $decode .= " Session Handle:0x";
                $decode .= substr($payload,$byte_idx+6,2);
                $decode .= substr($payload,$byte_idx+4,2);
                $decode .= substr($payload,$byte_idx+2,2);
                $decode .= substr($payload,$byte_idx,2);
                $byte_idx += 8;
                
                # Status
                my $rcv_status = substr($payload,$byte_idx,2);
                $byte_idx += 2;
                
                if ($rcv_status ne "00") {
                    #  Invalid Status
                    $decode .= "   ".$red_oops.($data_reception_status{$rcv_status} || "???");
                } else {
					# Destination Address
                    $decode .= "   Source Addr:0x";
                    $decode .= substr($payload,$byte_idx+14,2);
                    $decode .= substr($payload,$byte_idx+12,2);
                    $decode .= substr($payload,$byte_idx+10,2);
                    $decode .= substr($payload,$byte_idx+8,2);
                    $decode .= substr($payload,$byte_idx+6,2);
                    $decode .= substr($payload,$byte_idx+4,2);
                    $decode .= substr($payload,$byte_idx+2,2);
                    $decode .= substr($payload,$byte_idx,2);
                    $byte_idx += 16;
					
                    # Sequence Number
                    my $seq_number =  hex(substr($payload,$byte_idx+2,2));
                    $seq_number = (256*$seq_number) + hex(substr($payload,$byte_idx,2));
                    $byte_idx += 4;
                    
                    $decode .= "   Sequence Number:".$seq_number;
                    $decode .= "\n".$indent.$magenta;

                    # Application Data Length
                    my $app_data_length = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                    $byte_idx += 4;
                    
					if ( $app_data_length == 6 ){
						$byte_idx += 8;
						my $distance = (256*hex(substr($payload,$byte_idx+2,2)))+(hex(substr($payload,$byte_idx,2)));
						$byte_idx += 4;
						$decode .= "   Distance:".$distance;
					}
					else{				
						# Calculate length for indent and Sequence Number
						my $busy_space = length($indent)+8;
						
						# Truncate the data if exceeds the size of terminal width
						my $app_data = ((2*$app_data_length) > ($MAX_LINE_SIZE-$busy_space)) ? substr($payload,$byte_idx,$MAX_LINE_SIZE-$busy_space-3)."..." : substr($payload,$byte_idx,2*$app_data_length);
						
						$app_data =  pack( 'H*', $app_data =~ s/^\\x//r );
						$decode .= "   Data:".$app_data;
					}
                }
            }
            
            $decode .= $nocolor;
        }
		elsif ( $mt_dpf eq "04") {
			# DATA_MESSAGE_RCV FiRa 3.0
            if ($payload_length > 0) {
                # Put Byte index on the beginning of payload
                my $byte_idx = 0;
                
                $decode .= "\n".$indent.$magenta;

                # LL_CONNECT_ID
                $decode .= "Logical Link layer:0x";
                $decode .= substr($payload,$byte_idx+6,2);
                $decode .= substr($payload,$byte_idx+4,2);
                $decode .= substr($payload,$byte_idx+2,2);
                $decode .= substr($payload,$byte_idx,2);
                $byte_idx += 8;

                # Data sequence number
				$decode .= "   Sequence number: ";
                $decode .= (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                $byte_idx += 4;

                # Application Data length
                my $data_length_ll = (256*hex(substr($payload,$byte_idx+2,2)))+hex(substr($payload,$byte_idx,2));
                $byte_idx += 4;

				# Calculate length for indent and Sequence Number
				my $busy_space = length($indent)+8;

				# Truncate the data if exceeds the size of terminal width
				my $app_data = ((2*$data_length_ll) > ($MAX_LINE_SIZE-$busy_space)) ? substr($payload,$byte_idx,$MAX_LINE_SIZE-$busy_space-3)."..." : substr($payload,$byte_idx,2*$data_length_ll);
				$app_data =  pack( 'H*', $app_data =~ s/^\\x//r );
				
						
				$decode .= "   Data:".$app_data;
            }
            
            $decode .= $nocolor;
		}

    }
    $decode .= $nocolor;
}


sub signal_handler {
    close $fh_input if defined $fh_input;
    close $fh_logcat if defined $fh_logcat;
    close $fh_decode if defined $fh_decode;
    close $fh_rangedata if defined $fh_rangedata;
    close $fh_dbg if defined $fh_dbg;
    
    die $nocolor."Caught interrupt signal\n";
}


#########################################################################################
print $nocolor."usage:
. live decoding              > adb logcat | $this
. with timing                > adb logcat -v time | $this
. with logcat store          > adb logcat | $this -logcat=[file_name]
. with decoded store         > adb logcat | $this -decode=[file_name]
. with range data store      > adb logcat | $this -rangedata=[file_name]
. with rframe data store     > adb logcat | $this -rframe=[file_name]
. with DBG store             > adb logcat | $this -dbg=[file_name]
. with repeated frame filter > adb logcat | $this -norepeat
. with debug traces          > adb logcat | $this -debug
. without stats              > adb logcat | $this -nostat
. with input on STDOUT       > adb logcat | $this -tee
. with specific keyword      > adb logcat | $this keyword
. with Nfc stack             > adb logcat | $this Nfc
. decode a file              > $this -input=[file_name]
Default modules: NxpUciX and NxpUciR
$date_version\n\n";

#
# Check options (file recording; debug)
#
foreach my $request (@ARGV) {
    if ($request =~ /^-input=([\w\-\+\.:\\\/\s]+)/) {
        open($fh_input, "<", $1) or die "(".$!.") Could not open file '".$1."'\n";
        print "input: '".$1."' opened\n\n";
    }
    elsif ($request =~ /^-logcat=([\w\-\+\.:\\\/\s]+)/) {
        open($fh_logcat, ">", $1) or die "(".$!.") Could not open file '".$1."'\n";
        print "logcat: '".$1."' opened\n\n";
    }
    elsif ($request =~ /^-decode=([\w\-\+\.:\\\/\s]+)/) {
        open($fh_decode, ">", $1) or die "(".$!.") Could not open file '".$1."'\n";
        print "decode: '".$1."' opened\n\n";
    }
    elsif ($request =~ /^-rangedata=([\w\-\+\.:\\\/\s]+)/) {
        open($fh_rangedata, ">", $1) or die "(".$!.") Could not open file '".$1."'\n";
        print "rangedata: '".$1."' opened\n\n";
    }
    elsif ($request =~ /^-rframe=([\w\-\+\.:\\\/\s]+)/) {
        open($fh_rframe, ">", $1) or die "(".$!.") Could not open file '".$1."'\n";
        print "rframe: '".$1."' opened\n\n";
        $csv_rframe_first = 1;
    }
    elsif ($request =~ /^-dbg=([\w\-\+\.:\\\/\s]+)/) {
        open($fh_dbg, ">", $1) or die "(".$!.") Could not open file '".$1."'\n";
        print "dbg: '".$1."' opened\n\n";
    }
    elsif ($request =~ /^-norepeat/) {
        $isNoRepeat = 1;
    }
    elsif ($request =~ /^-debug/) {
        $disp_debug = 1;
    }
    elsif ($request =~ /^-nostat/) {
        $disp_stat = 0;
    }
    elsif ($request =~ /^-tee/) {
        $tee = 1;
    }
    else {
        $patKeywords .= "|" if $patKeywords;
        $patKeywords .= $request;
    }
}

if ($patKeywords) {
    debug_print "patKeywords:".$patKeywords."\n";
} else {
    debug_print "No patKeywords\n";
}

while ($parse_again || ($line = <$fh_input>))
{
    if ($parse_again) {
        $line = $parse_again;    
        $parse_again = "";
    } else {
        # Store line in file
        print $fh_logcat $line if defined $fh_logcat;
    }
    
    debug_print "line:".$line;
    
    # Duplicate input to STDOUT
    print $line if ($tee);
    
    # Exit while is word "exit" or "EXIT"
    # last if /exit/i;
    
    # Skip blank lines
    next if ($line =~ /^\s*$/);
    
    # Skip comment lines
    print $comment_color.$line.$nocolor if ($line =~/^#=>/);
    next if ($line =~ /^#/);
    
    
    # Initialize all variables used for display
    $color = $nocolor;
    $device_msg = "";
    $sens = "";
    $bytes = "";
    $frame = "";
    $msg = "";
    $decode = "";
    $csv_rangedata = "";
    $csv_rframe = "";
    
    # Extract timestamp
    if ($line =~ /(\d{2}:\d{2}:\d{2}\.\d{3})/) {
        $time = $1;
        $indent = $tab_long;
    }
    elsif ($line =~ /\[\w\x20(\d{1,12})\x20\d+\]/) {
        # Extract time from boot
        $time = $1.(" " x (12-length($1)));
        $indent = $tab_long;
    }
    else {
        $time = "";
        $indent = $tab_short;
    }
    
    # Extract partial frame in case of multiple lines block
    if ($multi_line{"mode"}) {
        if (($multi_line{"mode"} eq "Rhodes_RX") && ($line =~ /\[DUT_RX\]\x20{1,3}\d{1,4}\x20:\x20([0-9A-Fa-f\x20]+)/)) {
            # From Rhodes USB log (reception)
            
            # Store payload
            $multi_line{"buffer"} .= $1;
            
            # Force end of concatanation
            $multi_line{"mode"} = "End";
            
            # Go to next line
            next;
        }
        else {
            # End of concatenation
            
            # Store the current lien to parse it again later
            $parse_again = $line;
            
            # Put timestamp, indent and direction from multi_line storage
            $time = $multi_line{"time"};
            $indent = $multi_line{"indent"};
            $sens = $multi_line{"sens"};
            
            # Put buffer into UCI frame, with uppercase
            $frame = uc $multi_line{"buffer"};
            
            # Remove spaces and new line
            $frame =~ s/\s+//g;
            
            # Reset multiple line mode
            $multi_line{"mode"} = "";
        }
    }
    
    if (!(($sens) && ($frame))) {
        # Extract the direction from multiple lines block and start concatenation
        if ($line =~ /\[DUT_RX\]\x20{1,3}\d{1,4}\x20:\x20([0-9A-Fa-f\x20]+)/) {
            # from Rhodes USB log (reception)
            
            $multi_line{"mode"} = "Rhodes_RX";
            
            # Store direction
            $multi_line{"sens"} = $uwbd2dh;
            
            # Store header
            $multi_line{"buffer"} = $1;
            
            # Store timestamp and indent
            $multi_line{"time"} = $time;
            $multi_line{"indent"} = $indent;
        }
        
        # Extract the direction and the UCI frame from the current line
        if ($line =~ /NxpUci([XR]).+len\x20=\x20{1,4}(\d{1,4})\x20{1,4}(?:<|<=|=>|>)\x20([0-9A-Fa-f\x20]+)/) {
            # from 'adb logcat [-v brief | -v tag | -v time | -v threadtime]'
            
            # "X" for transmission and "R" for reception
            $sens = ($1 eq "X") ? $dh2uwbd : $uwbd2dh;
            
            # Store the number of bytes
            #$bytes = $2;
            
            # Store UCI frame with uppercase
            $frame = uc $3;
            
            # Remove spaces and new line
            $frame =~ s/\s+//g;
        }
        elsif ($line =~ /NXPUCI([XR])\x20(?:<=|=>)\x20{1,3}((?:[0-9A-Fa-f][0-9A-Fa-f]\x20{0,2})+)/) {
            # from Python scripts
            
            # "X" for transmission and "R" for reception
            $sens = ($1 eq "X") ? $dh2uwbd : $uwbd2dh;
            
            # Store UCI frame with uppercase
            $frame = uc $2;
            
            # Remove spaces and new line
            $frame =~ s/\s+//g;
        }
        elsif ($line =~ /\[DUT_TX\]\x20{1,3}\d{1,4}\x20:\x20(?:01)\x20(?:00)\x20(?:[0-9A-Fa-f][0-9A-Fa-f])\x20([0-9A-Fa-f\x20]+)/) {
            # from Rhodes USB log (transmission)
            # Skip header 01 00 Len
            
            # Store direction
            $sens = $dh2uwbd;
            
            # Store the UCI frame with uppercase
            $frame = uc $1;
            
            # Remove spaces and new line
            $frame =~ s/\s+//g;
        }
        elsif ($line =~ /TMLUWB\x20\x20:(TX|RX).+\x20:([0-9A-Fa-f\x20]+)/) {
            # from SR150
            
            # "TX" for transmission and "RX" for reception
            $sens = ($1 eq "TX") ? $dh2uwbd : $uwbd2dh;
            
            # Store UCI frame with uppercase
            $frame = uc $2;
            
            # Remove spaces and new line
            $frame =~ s/\s+//g;
        }
		elsif ($line =~ /HALUCI\x20\x20:(TX|RX).+\x20:([0-9A-Fa-f\x20]+)/) {
            # from SR150
            
            # "TX" for transmission and "RX" for reception
            $sens = ($1 eq "TX") ? $dh2uwbd : $uwbd2dh;
            
            # Store UCI frame with uppercase
            $frame = uc $2;
            
            # Remove spaces and new line
            $frame =~ s/\s+//g;
        }
        elsif ($line =~ /TMLUWB\x20\x20:(TX|RX).+\[\x20{0,2}(\d{1,3})\]:\x20([0-9A-Fa-f\x20]+)/) {
            # from SR040
            
            # "TX" for transmission and "RX" for reception
            $sens = ($1 eq "TX") ? $dh2uwbd : $uwbd2dh;
            
            # Store the number of bytes
            #$bytes = $2;
            
            # Store UCI frame with uppercase
            $frame = uc $3;
            
            # Remove spaces and new line
            $frame =~ s/\s+//g;
        }
        elsif ($line =~ /\[(MASTER|ANCHOR\d)\]\x20(TX|RX):\x20+((?:[0-9A-Fa-f][0-9A-Fa-f]:{0,1})+)/) {
            # from FW Testbench
            
            # Device of the message
            $device_msg = "[".uc $1."]".(($1 eq "MASTER") ? "  " : " ");
            
            # "TX" for transmission and "RX" for reception
            $sens = ($2 eq "TX") ? $dh2uwbd : $uwbd2dh;
            
            # Store UCI frame with uppercase
            $frame = uc $3;
            
            # Remove colon and new line
            $frame =~ s/:+//g;
        }
        
        # Clear reparsing because current line is just parsed
        $parse_again = "";
    }
    
    # Start decoding
    if ((!$isFwDownload) && ($sens) && ($frame) && ($frame ne $frame_memo)) {
        # Check frame length
        if ($bytes ne "" && length($frame) != (2*$bytes)) {
            imprime $red.$time.$sens."Mismatch in frame length".$nocolor."\n";
        }
        
        if ($frame eq "040000") {
            # SR040 Reset short command
            $decode = "   SR040 Hardreset";
        }
        elsif ($frame eq "01020304") {
            # SR040 Reset short response
            $decode = "";
        } else {
            UciParser();
        }
        
        # Statistics
        if ($decode =~ $oops) {
            push (@oops_stats, $nocolor.$time.":".$decode."\n".$nocolor);
        }
        
        # Highligth lines ended with "///"
        if ($line =~ /\/\/\/$/) {
            $color = $comment_color;
        }
        
        # Display the decoded frame
        imprime $color.$device_msg.$time.$sens.$frame.$msg.$decode.$nocolor."\n";


        if ($csv_rframe ne "") {
            $buffer_RFrame = $csv_rframe;
        }
        
        # Rframe TITLES store
        if ((defined $fh_rframe) && ($ft_status eq "00")) {
            if (($csv_rframe_first > 0) && ($payload_length_RFRAME > 0)) {
                if ($device_msg ne "") {
                    print $fh_rframe "Device;";
                }
                print $fh_rframe "Session ID;";
                foreach (1..$number_times_add_RFRAME_Titles) {
                    # print $fh_rframe "RX;Slot Index;Status;NLoS;First Path Index;Main Path Index;SNR Main Path;SNR First Path;SNR Total;RSSI;CIR Main Power;CIR First Path Power;Noise Variance;CFO;AoA Phase;CIR samples;;;;;;;;;;;;;;;;";
                    print $fh_rframe "RX;Slot Index;Status;NLoS;First Path Index;Main Path Index;SNR Main Path;SNR First Path;SNR Total;RSSI;CIR Main Power;CIR First Path Power;Noise Variance;CFO;AoA Phase;CIR samples;Rx timestamp;";; #GM July 1 2024
                }
                print $fh_rframe "\n";
                $csv_rframe_first = 0;
            }
        }

        # Range Titles store and range/rframe data store
        if ((defined $fh_rangedata) && ($csv_rangedata ne "") && $ft_status eq "00") {
            if ($csv_ranging_type ne $csv_type_memo) {
                if ($csv_ranging_type eq "00") {
                    print $fh_rangedata "Ranging Measurement Type 0x00: One Way Ranging Measurement (TDoA)\n";
                    if ($device_msg ne "") {
                        print $fh_rangedata "Device;";
                    }
                    print $fh_rangedata "Seq Number;Session ID;RMT;Meas Idx;MAC Addr;Frame Type;NLoS;AoA Azimuth;AoA Azimuth FoM; AoA Elevation;AoA Elevation FoM;Timestamp;Blink Frame Number;Antenna Pair;Authenticity Tag;RSSI RX1; RSSI RX2;PDoA...\n"; #GM April 16 2024
                } elsif ($csv_ranging_type eq "01") {
                    print $fh_rangedata "Ranging Measurement Type 0x01: Two Way Ranging Measurement (SS-TWR DS-TWR)\n";
                    if ($device_msg ne "") {
                        print $fh_rangedata "Device;";
                    }
                    print $fh_rangedata "Seq Number;Session ID;Meas Idx;MAC Addr;Status;NLoS;Distance;AoA Azimuth;AoA Azimuth FoM; AoA Elevation;AoA Elevation FoM;Dest AoA Azimuth;Dest AoA Azimuth FoM; Dest AoA Elevation;Dest AoA Elevation FoM;Slot Index;RSSI".$fh_rangedata_vendor."\n";
                } elsif ($csv_ranging_type eq "02") {
                    print $fh_rangedata "Ranging Measurement Type 0x02: Downlink TDoA Measurement\n";
                    if ($device_msg ne "") {
                        print $fh_rangedata "Device;";
                    }
                    print $fh_rangedata "Seq Number;Session ID;RMT;Meas Idx;Msg Type;MAC Addr;Status;Block Idx;Round Idx;NLoS;TX Timestamp, RX Timestamp;CFO Anchor;CFO;Reply Time Initiator;Reply Time Responder;VS...\n";
                } elsif ($csv_ranging_type eq "03") {
                    print $fh_rangedata "Ranging Measurement Type 0x03: OWR for AoA Measurement\n";
                    if ($device_msg ne "") {
                        print $fh_rangedata "Device;";
                    }
                    print $fh_rangedata "Seq Number;Session ID;RMT;Meas Idx;MAC Addr;Status;NLoS;Frame Seq Number;Block Idx;AoA Azimuth;AoA Azimuth FoM; AoA Elevation;AoA Elevation FoM;VS...\n";
                } elsif ($csv_ranging_type eq "6220") {
                    print $fh_rangedata "Ranging Measurement Type CCC\n";
                    if ($device_msg ne "") {
                        print $fh_rangedata "Device;";
                    }
                    print $fh_rangedata "Session ID;Distance;AoA Azimuth;AoA Azimuth FoM;AoA Elevation;AoA Elevation FoM;AntennaPairInfo;PDoA1;Index1;PDoA2;Index2".$fh_rangedata_SWAP_ANT_PAIR_3D_AOA."\n";    
                    # print $fh_rangedata_SWAP_ANT_PAIR_3D_AOA "Session ID.\n";           
                } else {
                    print $fh_rangedata "Unknown Ranging Measurement Type\n";
                }
                
                $csv_type_memo = $csv_ranging_type;
            }

            # Store the rframe data in the range data file
            if ($buffer_RFrame ne "") {
                print $fh_rframe $buffer_RFrame;
            }
            
            print $fh_rangedata $csv_rangedata;
        }
        
        # DBG store
        if ((defined $fh_dbg) && ($msg =~ /DBG_/)) {
            dbg_store $color.$time.$sens.$frame.$msg.$decode.$nocolor."\n";
        }
        
        # Store last parse frame
        $frame_memo = ($isNoRepeat ? $frame : "");
    }
    
    # FW Download mode
    if (($isFwDownload) && ($sens) && ($frame) && ($frame ne $frame_memo)) {
        # Display the frame without any decoding
        imprime $nocolor.$time.$sens.$frame.$nocolor."\n";
    }
    
    
    # Check if the current line contains MW or FW information
    if ($line =~ /$patMWVersion/) {
        # MW Version
        imprime $yellow.$1.$nocolor."\n";
    }
    elsif ($line =~ /$patFWDlStart/) {
        # Start FW Download
        $isFwDownload = 1;
        imprime $grey.$time."   Start FW download".$nocolor."\n";
    }
    elsif ($line =~ /$patHIFImage/) {
        # HIF Image
        imprime $grey.$time."   HIF Image ".$1.$nocolor."\n";
        
        if ($1 =~ /Transfer Complete/) {
            $isFwDownload = 0;
        }
    }
    elsif ($line =~ /$patFWDlEnd/) {
        # FW Download completed
        $isFwDownload = 0;
        imprime $grey.$time."   FW download completed".$nocolor."\n";
    }
    
    # Check if the current line contains one of the word in argument list
    if ($patKeywords && $line =~ /$patKeywords/) {
        # Remove newline
        chomp($frame = $line);
        
        # Truncate line if exceed the width of the terminal
        if (length($frame) > $MAX_LINE_SIZE) {
            $frame = substr($frame, 0, $MAX_LINE_SIZE)."...";
        }
        
        imprime $nocolor.$frame.$nocolor."\n";
    }
}

close $fh_input if defined $fh_input;
close $fh_logcat if defined $fh_logcat;

if ($disp_stat) {
    imprime $white."\n----------------------------------\n\nOverall stats:\n--------------".$nocolor."\n";
    if (scalar @oops_stats > 0) {
        imprime $white."\n* Errors: ".scalar @oops_stats.$nocolor."\n";
        imprime @oops_stats;
    }
}

imprime $nocolor."\n\n";

close $fh_decode if defined $fh_decode;
close $fh_rangedata if defined $fh_rangedata;
close $fh_dbg if defined $fh_dbg;
