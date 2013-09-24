// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#ifndef DBG_CMD_H_
#define DBG_CMD_H_

// All in words
#define MAX_DBG_CMD_LEN 124 // TODO Why not 128???
#define MAX_DBG_CMD_DATA_LEN (MAX_DBG_CMD_LEN - 1)

#define DBG_CMD_FIRMWARE_VERSION_REQ 3
#define DBG_CMD_FIRMWARE_VERSION_ACK 4

enum dbg_cmd_type {
   DBG_CMD_NONE,
   DBG_CMD_CONNECT_REQ,
   DBG_CMD_CONNECT_ACK,
   DBG_CMD_DISCONNECT_REQ,
   DBG_CMD_DISCONNECT_ACK,
   DBG_CMD_GET_CORE_STATE_REQ,
   DBG_CMD_GET_CORE_STATE_ACK,
   DBG_CMD_ENABLE_THREAD_REQ,
   DBG_CMD_ENABLE_THREAD_ACK,
   DBG_CMD_DISABLE_THREAD_REQ,
   DBG_CMD_DISABLE_THREAD_ACK,
   DBG_CMD_READ_REGS_REQ,
   DBG_CMD_READ_REGS_ACK,
   DBG_CMD_WRITE_REGS_REQ,
   DBG_CMD_WRITE_REGS_ACK,
   DBG_CMD_READ_MEM_REQ = 100,
   DBG_CMD_READ_MEM_ACK,
   DBG_CMD_WRITE_MEM_REQ,
   DBG_CMD_WRITE_MEM_ACK,
   DBG_CMD_READ_OBJ_REQ,
   DBG_CMD_READ_OBJ_ACK,
   DBG_CMD_STEP_REQ,
   DBG_CMD_STEP_ACK,
   DBG_CMD_CONTINUE_REQ,
   DBG_CMD_CONTINUE_ACK,
   DBG_CMD_ADD_BREAK_REQ,
   DBG_CMD_ADD_BREAK_ACK,
   DBG_CMD_REMOVE_BREAK_REQ,
   DBG_CMD_REMOVE_BREAK_ACK,
   DBG_CMD_GET_STATUS_REQ,
   DBG_CMD_GET_STATUS_ACK,
   DBG_CMD_INTERRUPT_REQ,
   DBG_CMD_INTERRUPT_ACK,
   DBG_CMD_RESET_REQ,
   DBG_CMD_RESET_ACK, 
   DBG_CMD_READ_JTAG_REG_REQ,
   DBG_CMD_READ_JTAG_REG_ACK,
   DBG_CMD_WRITE_JTAG_REG_REQ,
   DBG_CMD_WRITE_JTAG_REG_ACK,
   DBG_CMD_GET_JTAG_CHAIN_REQ,
   DBG_CMD_GET_JTAG_CHAIN_ACK,
   DBG_CMD_GET_CHIP_INFO_REQ,
   DBG_CMD_GET_CHIP_INFO_ACK,
   DBG_CMD_JTAG_PINS_REQ,
   DBG_CMD_JTAG_PINS_ACK,
   DBG_CMD_JTAG_PC_SAMPLE_REQ,
   DBG_CMD_JTAG_PC_SAMPLE_ACK,
   DBG_CMD_UPLOAD_XSCOPE_DATA_REQ,
   DBG_CMD_UPLOAD_XSCOPE_DATA_ACK,
   DBG_CMD_CONNECT_XSCOPE_CHANNEL_REQ,
   DBG_CMD_CONNECT_XSCOPE_CHANNEL_ACK,
   DBG_CMD_FIRMWARE_REBOOT_REQ,
   DBG_CMD_FIRMWARE_REBOOT_ACK
};

typedef struct {
  enum dbg_cmd_type type;
  unsigned int data[MAX_DBG_CMD_LEN-1];
} dbg_cmd_packet;

typedef struct {
  int jtag_speed;
  unsigned int debug_enabled;
  unsigned int jtag_devs_pre;
  unsigned int jtag_bits_pre;
  unsigned int jtag_devs_post;
  unsigned int jtag_bits_post;
  unsigned int jtag_max_speed;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-7];
} dbg_cmd_type_connect;

typedef struct {
  unsigned int data[MAX_DBG_CMD_DATA_LEN];
} dbg_cmd_type_disconnect;

typedef struct {
  unsigned int xcore;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-1];
} dbg_cmd_type_get_core_state;

typedef struct {
  unsigned int xcore;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-1];
} dbg_cmd_type_enable_thread;

typedef struct {
  unsigned int xcore;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-1];
} dbg_cmd_type_disable_thread;

typedef struct {
  unsigned int xcore;
  unsigned int thread_mask;
  unsigned int upper_block;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-3];
} dbg_cmd_type_read_regs;

typedef struct {
  unsigned int xcore;
  unsigned int thread_mask;
  unsigned int upper_block;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-3];
} dbg_cmd_type_write_regs;

#define MAX_DBG_MEM_TFR_BLOCK (MAX_DBG_CMD_DATA_LEN-3)

typedef struct {
  unsigned int xcore;
  unsigned int addr;
  unsigned int len;
  unsigned int data[MAX_DBG_MEM_TFR_BLOCK];
} dbg_cmd_type_read_mem;

typedef struct {
  unsigned int xcore;
  unsigned int addr;
  unsigned int len;
  unsigned int data[MAX_DBG_MEM_TFR_BLOCK];
} dbg_cmd_type_write_mem;

typedef struct {
  unsigned int xcore;
  unsigned int type;
  unsigned int address;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-3];
} dbg_cmd_type_read_obj;

typedef struct {
  unsigned int xcore;
  unsigned int thread;
  unsigned int allcores;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-3];
} dbg_cmd_type_step;

typedef struct {
  unsigned int xcore;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-1];
} dbg_cmd_type_continue;

// Breakpoint types
#define DBG_MEM_BREAK 0
#define DBG_W_WATCH_BREAK 1
#define DBG_R_WATCH_BREAK 2
#define DBG_A_WATCH_BREAK 3
#define DBG_RES_WATCH_BREAK 4 

typedef struct {
  unsigned int xcore;
  unsigned int thread;
  unsigned int address;
  unsigned int length;
  unsigned int type;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-5];
} dbg_cmd_type_add_break;

typedef struct {
  unsigned int xcore;
  unsigned int thread;
  unsigned int address;
  unsigned int length;
  unsigned int type;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-5];
} dbg_cmd_type_remove_break;

typedef struct {
  unsigned int data[MAX_DBG_CMD_DATA_LEN];
} dbg_cmd_type_get_status;

typedef struct {
  unsigned int xcore;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-1];
} dbg_cmd_type_interrupt;

typedef struct {
  unsigned int xcore;
  unsigned int type;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-2];
} dbg_cmd_type_reset;

typedef struct {
  unsigned int data[MAX_DBG_CMD_DATA_LEN];
} dbg_cmd_type_firmware_version;

typedef struct {
  unsigned int data[MAX_DBG_CMD_DATA_LEN];
} dbg_cmd_type_firmware_reboot;

typedef struct {
  unsigned int address;
  unsigned int tapid;
  unsigned int tapmodule;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-3];
} dbg_cmd_type_read_jtag_reg;

typedef struct {
  unsigned int address;
  unsigned int tapid;
  unsigned int tapmodule;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-3];
} dbg_cmd_type_write_jtag_reg;

typedef struct {
  int tapid;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-1];
} dbg_cmd_type_get_jtag_chain;

typedef struct {
  unsigned int len;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-1];
} dbg_cmd_type_upload_xscope_data;

typedef struct {
  unsigned int channelEnd;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-1];
} dbg_cmd_type_connect_xscope_channel;

typedef struct {
  int chipid;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-1];
} dbg_cmd_type_get_chip_info;

typedef struct {
  int pinvalues;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-1];
} dbg_cmd_type_jtag_pins;

typedef struct {
  unsigned int xcore;
  unsigned int data[MAX_DBG_CMD_DATA_LEN-1];
} dbg_cmd_type_jtag_pc_sample;

#endif /*DBG_CMD_H_*/
