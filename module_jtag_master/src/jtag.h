// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#ifndef JTAG_H_
#define JTAG_H_

// CHIP TAP MUX STATES
#define MUX_NC 0
#define MUX_SSWITCH 1
#define MUX_XCORE0 2
#define MUX_XCORE1 3
#define MUX_XCORE2 4
#define MUX_XCORE3 5
#define MUX_XCOREALL 6

// RESET TYPES
#define XMOS_JTAG_RESET_TRST_SRST 0
#define XMOS_JTAG_RESET_TRST 1
#define XMOS_JTAG_RESET_TRST_SRST_JTAG 2
#define XMOS_JTAG_RESET_TRST_SRST_SPI 3
#define XMOS_JTAG_RESET_TRST_DRIVE_LOW 4
#define XMOS_JTAG_RESET_TRST_DRIVE_HIGH 5

void jtag_init(void);
void jtag_deinit(void);
void jtag_speed(int divider);
void jtag_chain(unsigned int jtag_devs_pre, unsigned int jtag_bits_pre,
                unsigned int jtag_devs_post, unsigned int jtag_bits_post,
                unsigned int jtag_max_speed);
void jtag_reset(int reset_type, chanend ?reset_chan);
int jtag_get_num_xcores(void);
int jtag_get_xcore_type(int chip_id);
int jtag_get_num_cores_per_xcore(int chip_id);
int jtag_get_num_threads_per_xcore(int chip_id);
int jtag_get_num_regs_per_xcore_thread(int chip_id);
void jtag_select_xmos_tap(int chip_id, unsigned int type);
unsigned int jtag_read_reg(unsigned int chipmodule, unsigned int regIndex);
void jtag_write_reg(unsigned int chipmodule, unsigned int regIndex, unsigned int data);
void jtag_enable_serial_otp_access(void);
void jtag_disable_serial_otp_access(void);
void jtag_module_otp_write_test_port_cmd(unsigned int chipmodule, unsigned int cmd);
unsigned int jtag_module_otp_shift_data(unsigned int chipmodule, unsigned int oldData);

void jtag_rti_delay(void);
void jtag_irscan(unsigned int scandata[], unsigned int numbits);
void jtag_drscan(unsigned int scandata[], unsigned int numbits);
int jtag_pin_transition(int pinvalues);
void jtag_pin_srst(int pinvalue);
void jtag_pin_trst(int pinvalue);

// JTAG chain info functions
int jtag_get_num_taps(void);
int jtag_get_tap_id(unsigned int index);
int jtag_select_tap(unsigned int index);

#endif /*JTAG_H_*/
