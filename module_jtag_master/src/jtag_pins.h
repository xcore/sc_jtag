#ifndef _JTAG_PINS_H_
#define _JTAG_PINS_H_

int jtag_transition_pins(int pinvalues);
void jtag_reset_srst_pins (chanend ?reset_chan);
void jtag_reset_trst_pins (int use_tms);
void jtag_reset_srst_trst_pins (chanend ?reset_chan);
void jtag_rti_delay_pins (void);
void jtag_irscan_pins (unsigned int scandata[], short num_bits);
void jtag_drscan_pins (unsigned int scandata[], short num_bits);
void jtag_init_pins (void);
void jtag_clear_pins(void);
void jtag_drive_srst(unsigned int value);
void jtag_drive_trst(unsigned int value);

#endif
