#include <xs1.h>
#include <platform.h>
#include "jtag_pins.h"
#include <print.h>

extern buffered out port:32 jtag_pin_TDI;
extern buffered in port:32 jtag_pin_TDO;
extern buffered out port:4 jtag_pin_TMS;
extern buffered out port:32 jtag_pin_TCK;
extern out port jtag_pin_SRST;
extern out port jtag_pin_TRST;
extern clock tck_clk;
extern clock other_clk;

#ifdef XTAG_USE_COMBINED_MSEL_SRST

#define JTAG_SRST_PIN 1
#define JTAG_MSEL_PIN 19
#define JTAG_LED0_PIN 28
#define JTAG_LED1_PIN 29
#define JTAG_LED2_PIN 30
#define JTAG_LED3_PIN 31

extern out port jtag_pins_srst_dbg_msel;

void jtag_combined_pins(unsigned int bit, unsigned int enable) {
  unsigned int current_value = peek(jtag_pins_srst_dbg_msel);

  if (enable) {
    current_value |= (1 << bit);
  } else {
    current_value &= ~(1 << bit);
  }
  jtag_pins_srst_dbg_msel <: current_value;
}

#endif

#ifdef XTAG_USE_SOFT_MSEL_SRST

extern port jtag_pin_soft_msel;

void jtag_soft_srst(unsigned int enable) {
 // NOP
}

void jtag_soft_msel(unsigned int enable) {
  if (enable) {
    jtag_pin_soft_msel :> void;
  } else {
    jtag_pin_soft_msel <: enable;
  }
}

#endif


void jtag_drive_srst(unsigned int value) {
#ifdef XTAG_USE_COMBINED_MSEL_SRST
    jtag_combined_pins(JTAG_SRST_PIN, value);
#endif
#ifdef XTAG_USE_SOFT_MSEL_SRST
    jtag_soft_srst(value);
#endif
#ifdef XTAG_USE_PINS_MSEL_SRST
    jtag_pin_SRST <: value;
#endif
}

void jtag_drive_trst(unsigned int value) {
#ifdef XTAG_USE_COMBINED_MSEL_SRST
    jtag_combined_pins(JTAG_MSEL_PIN, value);
#endif
#ifdef XTAG_USE_SOFT_MSEL_SRST
    jtag_soft_msel(value);
#endif
#ifdef XTAG_USE_PINS_MSEL_SRST
    jtag_pin_TRST <: value;
#endif
}


int jtag_transition_pins(int pinvalues) {
  unsigned int tdo_output = 0;
  int tms_value = 0;
  int tdi_value = 0;

  clearbuf(jtag_pin_TMS);
  clearbuf(jtag_pin_TDO);
  clearbuf(jtag_pin_TDI);
  clearbuf(jtag_pin_TCK);

  if (pinvalues & 0x1) 
    tms_value = 0x1;

  if (pinvalues & 0x2) 
    tdi_value = 0x1;

  partout(jtag_pin_TMS, 1, tms_value);
  partout(jtag_pin_TDI, 1, tdi_value);

  // Output 1 TCK clk
  partout (jtag_pin_TCK, 2, 0x2);
  sync(jtag_pin_TCK);

  tdo_output = partin(jtag_pin_TDO, 1);

  return tdo_output;
}

void jtag_reset_srst_pins (chanend ?reset_chan) {
  unsigned s;
  timer tmr;

  sync (jtag_pin_TCK);
  clearbuf (jtag_pin_TMS);

  jtag_drive_srst(0);

  tmr:>s;
  tmr when timerafter (s + 40000):>s;

  jtag_drive_srst(1);

  tmr:>s;
  tmr when timerafter (s + 50000000):>s;

#if 0
  if (!isnull(reset_chan)) {
    outuchar(reset_chan, 0);
    outct(reset_chan, 1);
    chkct(reset_chan, 1);
  }
#endif

  return;
}

void jtag_reset_trst_pins (int use_tms) {

  if (use_tms) {
    sync (jtag_pin_TCK);
    clearbuf (jtag_pin_TMS);
    jtag_pin_TMS <:0xf;
    partout (jtag_pin_TCK, 8, 0xaa);
    jtag_pin_TMS <:0x7;
    partout (jtag_pin_TCK, 8, 0xaa);
    sync (jtag_pin_TCK);
  } else {
    unsigned s;
    timer tmr;
    jtag_drive_trst(0);
    tmr:>s;
    tmr when timerafter (s + 4000):>s;
    jtag_drive_trst(1);
    tmr when timerafter (s + 4000):>s;
  }

  return;
}

void jtag_reset_srst_trst_pins (chanend ?reset_chan) {
  unsigned s;
  timer tmr;

  sync (jtag_pin_TCK);
  clearbuf (jtag_pin_TMS);

// Dont do pin toggle for soft reset, just reset state machine
#ifndef XTAG_USE_SOFT_MSEL_SRST

  tmr:>s;
  tmr when timerafter (s + 4000):>s;
  jtag_drive_trst(0);

  tmr:>s;
  tmr when timerafter (s + 4000):>s;
  jtag_drive_srst(0);


  tmr:>s;
  tmr when timerafter (s + 40000):>s;
  jtag_drive_srst(1);

  tmr:>s;
  tmr when timerafter (s + 50000000):>s;

#if 0
  if (!isnull(reset_chan)) {
    outuchar(reset_chan, 0);
    outct(reset_chan, 1);
    chkct(reset_chan, 1);
  }
#endif


  tmr:>s;
  tmr when timerafter (s + 40000):>s;
  jtag_drive_trst(1);

  tmr:>s;
  tmr when timerafter (s + 4000):>s;
#endif

  jtag_pin_TMS <:0xf;
  partout (jtag_pin_TCK, 8, 0xaa);
  jtag_pin_TMS <:0x7;
  partout (jtag_pin_TCK, 8, 0xaa);

  return;
}

void jtag_rti_delay_pins (void) {
  jtag_pin_TMS <:0;
  jtag_pin_TCK <:0xAAAAAAAA;	// 16 CLK's  
  jtag_pin_TCK <:0xAAAAAAAA;	// 16 CLK's
}

#pragma unsafe arrays
void jtag_irscan_pins (unsigned int scandata[], short num_bits) {
  unsigned short chunks = --num_bits >> 5;
  unsigned short remainder = num_bits & 31;

  //printf("IRSCAN PINS %d bits\n", num_bits + 1);

  sync (jtag_pin_TCK);
  clearbuf (jtag_pin_TMS);

  // Move to SHIFT_IR
  jtag_pin_TMS <:3;		// 1100
  partout (jtag_pin_TCK, 8, 0xAA);	// 4 CLK's RTI->SelectDR->SelectIR->CaptureIR->ShiftIR
  sync (jtag_pin_TCK);

  jtag_pin_TDI <:scandata[0];

  // Do 32 bit chunks
  for (int i = 1; i <= chunks; i++) {
  jtag_pin_TCK <:0xAAAAAAAA;	// 16 CLK's  
  jtag_pin_TCK <:0xAAAAAAAA;	// 16 CLK's
  jtag_pin_TDI <:scandata[i];
  }

  if (remainder > 16) {
  jtag_pin_TCK <:0xAAAAAAAA;
    partout (jtag_pin_TCK, (2 * (remainder - 16)), 0xAAAAAAAA);
  }
  else if (remainder) {
    partout (jtag_pin_TCK, (2 * remainder), 0xAAAAAAAA);
  }

  sync (jtag_pin_TCK);
  jtag_pin_TMS <:3;		// 1100

  partout (jtag_pin_TCK, 10, 0xAAA);	// 3 CLK's ShiftIR->Exit1IR->UpdateIR->RTI + 2 In RTI (Crossing clock domains!)
  sync (jtag_pin_TCK);
  clearbuf (jtag_pin_TDI);
}


#pragma unsafe arrays
void jtag_drscan_pins (unsigned int scandata[], short num_bits) {
  int i = 1;
  unsigned short chunks = --num_bits >> 5;
  unsigned short remainder = num_bits & 31;
  unsigned int temp;

  //printf("DRSCAN PINS %d bits\n", num_bits + 1);

  sync (jtag_pin_TCK);
  clearbuf (jtag_pin_TMS);

  // Move to SHIFT_DR
jtag_pin_TMS <:1;		// 1000
  partout (jtag_pin_TCK, 6, 0xAA);	// 3 CLK's RTI->SelectDR->CaptureDR->ShiftDR
  sync (jtag_pin_TCK);

jtag_pin_TDI <:scandata[0];

  clearbuf (jtag_pin_TDO);

  // Do 8 bit chunks
  for (i = 1; i <= chunks; i++) {
  jtag_pin_TCK <:0xAAAAAAAA;	// 16 CLK's
  jtag_pin_TCK <:0xAAAAAAAA;	// 16 CLK's
  jtag_pin_TDO:>scandata[i - 1];
  jtag_pin_TDI <:scandata[i];
  }

  if (remainder > 16) {
  jtag_pin_TCK <:0xAAAAAAAA;
    partout (jtag_pin_TCK, (2 * (remainder - 16)), 0xAAAAAAAA);
  }
  else if (remainder) {
    partout (jtag_pin_TCK, (2 * remainder), 0xAAAAAAAA);
  }

  sync (jtag_pin_TCK);

jtag_pin_TMS <:3;		// 1100
  partout (jtag_pin_TCK, 2, 0x2);	// 1 CLK ShiftDR->Exit1DR
  sync (jtag_pin_TCK);
  i = endin (jtag_pin_TDO);
jtag_pin_TDO:>temp;
  scandata[chunks] = temp >> (32 - i);
  partout (jtag_pin_TCK, 4, 0xA);	// 2 CLK's Exit1DR->UpdateDR->RTI
  clearbuf (jtag_pin_TDI);
}


void jtag_init_pins (void) {
  configure_out_port (jtag_pin_TCK, tck_clk, 0xffffffff);
  configure_clock_src (other_clk, jtag_pin_TCK);
  configure_out_port (jtag_pin_TDI, other_clk, 0);
  configure_in_port (jtag_pin_TDO, other_clk);
  configure_out_port (jtag_pin_TMS, other_clk, 0);


#ifdef XTAG_USE_COMBINED_MSEL_SRST
  jtag_pins_srst_dbg_msel <: 0x0fffffff;
#endif
#ifdef XTAG_USE_SOFT_MSEL_SRST
  // Do something here?
#endif
#ifdef XTAG_USE_PINS_MSEL_SRST
  //configure_out_port(jtag_pin_TRST, tck_clk, 0);
  configure_out_port (jtag_pin_SRST, tck_clk, 1);
#endif
}

void jtag_clear_pins(void) {
  clearbuf (jtag_pin_TDI);
  clearbuf (jtag_pin_TDO);
}
