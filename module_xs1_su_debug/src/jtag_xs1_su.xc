#include <jtag_xs1_su.h>
#include <jtag.h>
#include <stdio.h>

extern unsigned int jtag_data_buffer[32];

static unsigned int jtag_xs1_su_mux_enabled = 0; // 0 - NC, 1 - Debug Tap Enabled

void jtag_xs1_su_enable_mux(void) {
  if (!jtag_xs1_su_mux_enabled) {
   // IR Scan (4 bits, command 0x4)
   jtag_data_buffer[0] = 0xf4;
   jtag_irscan(jtag_data_buffer, 4);

   // DR Scan (32 bits, 0x1)
   jtag_data_buffer[0] = 0x1;
   jtag_drscan(jtag_data_buffer, 32);
   jtag_rti_delay();

   jtag_data_buffer[0] = 0xffffffff;
   jtag_irscan(jtag_data_buffer, 22);

   jtag_xs1_su_mux_enabled = 1;
  }
}

void jtag_xs1_su_disable_mux(void) {
  if (jtag_xs1_su_mux_enabled) {

    // IR Scan (4 bits, command 0x4)
    // DR Scan (32 bits, 0x1)

    jtag_data_buffer[0] = 0xffffffff;

    jtag_irscan(jtag_data_buffer, 22);

    jtag_data_buffer[0] = 0xff13ffff;

    jtag_irscan(jtag_data_buffer, 22);
    jtag_rti_delay();

    jtag_data_buffer[0] = 0x0;

    jtag_drscan(jtag_data_buffer, 32);
    jtag_rti_delay();

    jtag_data_buffer[0] = 0xffffffff;
  
    jtag_irscan(jtag_data_buffer, 4);

    jtag_xs1_su_mux_enabled = 0;
  }
}

unsigned int jtag_xs1_su_read_reg(unsigned int address) {
  unsigned char xs1_su_data[4];
  unsigned int result = 0;

  // Set MUX to DBG Tap if not set
  jtag_xs1_su_enable_mux();

  // Tap state now SU + DBG
  // 22 Bit shift for command, top 4 bits are bypass for SU Tap
  // SU(4)  Addr(16)         CMD(2)
  // 1111    0000000000000001 01 (read)

  xs1_su_data[0] = (address << 2 & 0xfc) | 0x1;
  xs1_su_data[1] = (address >> 6 & 0xff);
  xs1_su_data[2] = (address >> 14 & 0x3) | 0xfc;
  xs1_su_data[3] = 0xff;

  jtag_data_buffer[0] = xs1_su_data[0] | xs1_su_data[1] << 8 | xs1_su_data[2] << 16 | xs1_su_data[3] << 24;

  jtag_irscan(jtag_data_buffer, 22);
  jtag_rti_delay();

  // 32 Bit DR shift of read result
  jtag_drscan(jtag_data_buffer, 32);

  result = jtag_data_buffer[0];
   
  jtag_xs1_su_disable_mux();

  return result; 

}

unsigned int jtag_xs1_su_write_reg(unsigned int address, unsigned int value) {
  unsigned char xs1_su_data[4];

  // Set MUX to DBG Tap
  jtag_xs1_su_enable_mux();

  // Tap state now SU + DBG
  // 22 Bit shift for command, top 4 bits are bypass for SU Tap
  // SU(4)  Addr(16)         CMD(2)
  // 1111    0000000000000001 10 (write)

  xs1_su_data[0] = (address << 2 & 0xfc) | 0x2;
  xs1_su_data[1] = (address >> 6 & 0xff);
  xs1_su_data[2] = (address >> 14 & 0x3) | 0xfc;
  xs1_su_data[3] = 0xff;

  jtag_data_buffer[0] = xs1_su_data[0] | xs1_su_data[1] << 8 | xs1_su_data[2] << 16 | xs1_su_data[3] << 24;

  jtag_irscan(jtag_data_buffer, 22);
  jtag_rti_delay();

  xs1_su_data[0] = value & 0xff;
  xs1_su_data[1] = (value >> 8) & 0xff;
  xs1_su_data[2] = (value >> 16) & 0xff;
  xs1_su_data[3] = (value >> 24) & 0xff;

  jtag_data_buffer[0] = xs1_su_data[0] | xs1_su_data[1] << 8 | xs1_su_data[2] << 16 | xs1_su_data[3] << 24;

  // 33 Bit DR shift of write data (goes through SU Tap in bypass)
  jtag_drscan(jtag_data_buffer, 33);
  jtag_rti_delay();

  jtag_xs1_su_disable_mux();

}

void jtag_xs1_su_bypass(void) {

  if (jtag_xs1_su_mux_enabled) {
    // Bypass All - SU + DBG
    // 22 Bit IR shift of all 1's
  } else {
    // Bypass All -SU 
  }

  jtag_xs1_su_mux_enabled = 0;
}
