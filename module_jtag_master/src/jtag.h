// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#ifndef JTAG_H_
#define JTAG_H_

void jtag_init(void);
void jtag_deinit(void);
void jtag_speed(int divider);
void jtag_chain(unsigned int jtag_devs_pre, unsigned int jtag_bits_pre,
                unsigned int jtag_devs_post, unsigned int jtag_bits_post,
                unsigned int jtag_max_speed);
void jtag_reset(int reset_type);
int jtag_get_num_chips(void);
int jtag_get_chip_type(int chip_id);
int jtag_get_num_cores_per_chip(int chip_id);
int jtag_get_num_threads_per_core(int chip_id);
int jtag_get_num_regs_per_thread(int chip_id);
void jtag_select_chip(int chip_id);
unsigned int jtag_read_reg(unsigned int chipmodule, unsigned int regIndex);
void jtag_write_reg(unsigned int chipmodule, unsigned int regIndex, unsigned int data);

#endif /*JTAG_H_*/
