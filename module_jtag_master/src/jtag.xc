// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <xs1.h>
#include <platform.h>
#include <print.h>

static unsigned int jtag_data_buffer[32]; 

// CHIP TAP MUX STATES
#define MUX_NC 0
#define MUX_SSWITCH 1
#define MUX_XCORE0 2
#define MUX_XCORE1 3
#define MUX_XCORE2 4
#define MUX_XCORE3 5
#define MUX_XCOREALL 6

// CHIP TAP MUX VALUES
static unsigned char chip_tap_mux_values[7] = {0x0, 0x1, 0x8, 0x9, 0xa, 0xb, 0xf};

// CHIP TAP COMMANDS
#define SETMUX_IR 0x4
#define GETMUX_IR 0x5
#define BYPASS_IR 0xf

// Register lengths for each TAP.
#define BSCAN_TAP_IR_LEN 4
#define BSCAN_TAP_BYP_LEN 1
#define CHIP_TAP_IR_LEN 4
#define CHIP_TAP_BYP_LEN 1
#define XCORE_TAP_IR_LEN 10
#define XCORE_TAP_DR_LEN 32
#define XCORE_TAP_BYP_LEN 1
#define OTP_TAP_IR_LEN 2
#define OTP_TAP_DR_LEN 3
#define OTP_TAP_BYP_LEN 1

// Length of the chain for one chip. This depends on the state of the mux control.
#define MUX_NC_IR_LEN (BSCAN_TAP_IR_LEN + CHIP_TAP_IR_LEN)
#define MUX_XCORE_BYP_LEN (BSCAN_TAP_BYP_LEN + CHIP_TAP_BYP_LEN)
#define MUX_XCORE_IR_LEN (BSCAN_TAP_IR_LEN + CHIP_TAP_IR_LEN + XCORE_TAP_IR_LEN + OTP_TAP_IR_LEN)
#define MUX_XCORE_BYP_LEN (BSCAN_TAP_BYP_LEN + CHIP_TAP_BYP_LEN + XCORE_TAP_BYP_LEN + OTP_TAP_BYP_LEN)

// XMOS JTAG SCAN CHAIN DETAILS
#define XCORE_MAX_CHAIN_LEN 16
#define XCORE_CHAIN_UNKNOWN 0
#define XCORE_CHAIN_G4_ID 0x104731
#define XCORE_CHAIN_G4_REVA 1
#define XCORE_CHAIN_G4_REVB 2
#define XCORE_CHAIN_G1_ID 0x2633
#define XCORE_CHAIN_G1_REVC 3

static int XCORECHAIN = 0;
static int XCOREID = -1;
static int XCORESPREV = 0;
static int XCORESPOST = 0;
static int XCORETYPE = XCORE_CHAIN_UNKNOWN;
static int XCORETYPES[XCORE_MAX_CHAIN_LEN];
static int XCOREJTAGIDS[XCORE_MAX_CHAIN_LEN];

// User provided scan chain parameters
static int NUMDEVSPREV = 0;
static int NUMBITSPREV = 0;
static int NUMDEVSPOST = 0;
static int NUMBITSPOST = 0;
static int MAXJTAGCLKSPEED = 0;

// RESET TYPES
#define XMOS_JTAG_RESET_TRST_SRST 0
#define XMOS_JTAG_RESET_TRST 1
#define XMOS_JTAG_RESET_TRST_SRST_JTAG 2
#define XMOS_JTAG_RESET_TRST_SRST_SPI 3

unsigned char chip_tap_mux_state = MUX_NC;

on stdcore[0] : buffered out port:32 jtag_pin_TDI  = XS1_PORT_1A;
on stdcore[0] : buffered in port:32 jtag_pin_TDO  = XS1_PORT_1B;
on stdcore[0] : buffered out port:4 jtag_pin_TMS  = XS1_PORT_1C;
on stdcore[0] : buffered out port:32 jtag_pin_TCK  = XS1_PORT_1D;

on stdcore[0] : out port jtag_pin_SRST = XS1_PORT_1M;
on stdcore[0] : out port jtag_pin_TRST = XS1_PORT_1L;

on stdcore[0] : clock tck_clk = XS1_CLKBLK_1;
on stdcore[0] : clock other_clk = XS1_CLKBLK_2;

static void jtag_reset_srst(void) {
	unsigned s;
	timer tmr;
      
	sync(jtag_pin_TCK);
        clearbuf(jtag_pin_TMS);
	
	jtag_pin_SRST <: 0;
	tmr :> s;
	tmr when timerafter(s + 40000) :> s;
	jtag_pin_SRST <: 1;

        return;
}

static void jtag_reset_trst(void) {
	unsigned s;
        timer tmr;

        sync(jtag_pin_TCK);
	clearbuf(jtag_pin_TMS);
    
	jtag_pin_TRST <: 0;
	tmr :> s;
	tmr when timerafter(s + 4000) :> s;
	jtag_pin_TRST <: 1;
	tmr when timerafter(s + 4000) :> s;

	jtag_pin_TMS <: 0xf;
	partout(jtag_pin_TCK, 8, 0xaa);
	jtag_pin_TMS <: 0x7;
	partout(jtag_pin_TCK, 8, 0xaa);
 
        return;
}

static void jtag_reset_srst_trst(void) {
	unsigned s;
	timer tmr;

	sync(jtag_pin_TCK);
    clearbuf(jtag_pin_TMS);
    
    tmr :> s;
    tmr when timerafter(s + 4000) :> s;
    jtag_pin_TRST <: 0;
    
    tmr :> s;
    tmr when timerafter(s + 4000) :> s;
    jtag_pin_SRST <: 0;
	
	tmr :> s;
	tmr when timerafter(s + 40000) :> s;
	jtag_pin_SRST <: 1;
	
	tmr :> s;
    tmr when timerafter(s + 40000) :> s;
	jtag_pin_TRST <: 1;
	
	tmr :> s;
	tmr when timerafter(s + 4000) :> s;

	jtag_pin_TMS <: 0xf;
	partout(jtag_pin_TCK, 8, 0xaa);
	jtag_pin_TMS <: 0x7;
	partout(jtag_pin_TCK, 8, 0xaa);

    return;
}

#pragma unsafe arrays
static void jtag_irscan_pins(unsigned int scandata[], short num_bits) {
    unsigned short chunks = --num_bits >> 5;
    unsigned short remainder = num_bits & 31;
    
    sync(jtag_pin_TCK);
    clearbuf(jtag_pin_TMS);
    
    // Move to SHIFT_IR
    jtag_pin_TMS <: 3;          // 1100
    partout(jtag_pin_TCK, 8, 0xAA);     // 4 CLK's RTI->SelectDR->SelectIR->CaptureIR->ShiftIR
    sync(jtag_pin_TCK);
      
    jtag_pin_TDI <: scandata[0];  
   
    // Do 32 bit chunks
    for (int i = 1; i <= chunks; i++) {
      jtag_pin_TCK <: 0xAAAAAAAA;  // 16 CLK's	
      jtag_pin_TCK <: 0xAAAAAAAA;  // 16 CLK's
      jtag_pin_TDI <: scandata[i];
    }
      
    if (remainder > 16) {
       jtag_pin_TCK <: 0xAAAAAAAA;
       partout(jtag_pin_TCK, (2*(remainder-16)), 0xAAAAAAAA);  
    } else if (remainder) {
       partout(jtag_pin_TCK, (2*remainder), 0xAAAAAAAA);
    }
 
    sync(jtag_pin_TCK);
    jtag_pin_TMS <: 3;          // 1100
   
    partout(jtag_pin_TCK, 10, 0xAAA);     // 3 CLK's ShiftIR->Exit1IR->UpdateIR->RTI + 2 In RTI (Crossing clock domains!)
    clearbuf(jtag_pin_TDI);
}


#pragma unsafe arrays
static void jtag_drscan_pins(unsigned int scandata[], short num_bits) {
    int i = 1;
    unsigned short chunks = --num_bits >> 5;
    unsigned short remainder = num_bits & 31;
    unsigned int temp;

    sync(jtag_pin_TCK);
    clearbuf(jtag_pin_TMS);
    
    // Move to SHIFT_DR
    jtag_pin_TMS <: 1;          // 1000
    partout(jtag_pin_TCK, 6, 0xAA);     // 3 CLK's RTI->SelectDR->CaptureDR->ShiftDR
    sync(jtag_pin_TCK);

    jtag_pin_TDI <: scandata[0];

    clearbuf(jtag_pin_TDO);

    // Do 8 bit chunks
    for (i = 1; i <= chunks; i++) {
      jtag_pin_TCK <: 0xAAAAAAAA;  // 16 CLK's
      jtag_pin_TCK <: 0xAAAAAAAA;  // 16 CLK's
      jtag_pin_TDO :> scandata[i-1];
      jtag_pin_TDI <: scandata[i];
    }
 
    if (remainder > 16) {
       jtag_pin_TCK <: 0xAAAAAAAA;
       partout(jtag_pin_TCK, (2*(remainder-16)), 0xAAAAAAAA);   
    } else if (remainder) {
       partout(jtag_pin_TCK, (2*remainder), 0xAAAAAAAA);
    }

    sync(jtag_pin_TCK);

    jtag_pin_TMS <: 3;          // 1100
    partout(jtag_pin_TCK, 2, 0x2);      // 1 CLK ShiftDR->Exit1DR
    sync(jtag_pin_TCK);
    i = endin(jtag_pin_TDO);
    jtag_pin_TDO :> temp;
    scandata[chunks] = temp >> (32 - i);
    partout(jtag_pin_TCK, 4, 0xA);      // 2 CLK's Exit1DR->UpdateDR->RTI
    clearbuf(jtag_pin_TDI);
}

#pragma unsafe arrays
void jtag_irscan(unsigned int scandata[], unsigned int numbits) {
	if (XCORECHAIN > 1) {
		int i = 0;
		unsigned int extra_bits = 8;
		unsigned int pindata[32]; // 1024 bits
		int total_bits = ((XCORECHAIN - 1) * extra_bits) + numbits;
		int num_words = (total_bits >> 5) + 1;
		int data_bit_word = (XCORESPOST * extra_bits) >> 5;
		int data_bit_loc = (XCORESPOST * extra_bits) - (data_bit_word * 32);
		int data_index = 0;

		int remaining_words = 0;
		int remaining_bits = 0;
		int remaining_word_val = 0;
#if 0
		printintln(total_bits);
		printintln(num_words);
		printintln(data_bit_word);
		printintln(data_bit_loc);
#endif

		// Scan in all bypass
		for (i = 0; i < num_words; i++) {
			pindata[i] = 0xffffffff;
		}

		remaining_bits = numbits;

		// First word
		if (numbits > 32 - data_bit_loc) {
			pindata[data_bit_word] = pindata[data_bit_word] >> 32 - data_bit_loc | scandata[data_index] << data_bit_loc;
			data_bit_word++;
			remaining_bits = numbits - (32 - data_bit_loc);
		} else {
			int mask = 0xffffffff & (0xffffffff >> (32 - remaining_bits));
			pindata[data_bit_word] = ((pindata[data_bit_word] & ~(mask << data_bit_loc)) | ((scandata[data_index] & mask) << data_bit_loc));
			data_bit_word++;
			remaining_bits -= remaining_bits;
		}

		remaining_words = remaining_bits >> 5;

		// Middle words
		while (remaining_words) {
			pindata[data_bit_word] = scandata[data_index] >> 32 - data_bit_loc | scandata[data_index + 1] << data_bit_loc;
			data_index++;
			data_bit_word++;
			remaining_words--;
			remaining_bits -= 32;
		}

		// End word
		if (remaining_bits) {
			remaining_word_val = scandata[data_index] >> 32 - data_bit_loc | scandata[data_index + 1] << data_bit_loc;
			pindata[data_bit_word] = (remaining_word_val & (0xffffffff >> (32 - remaining_bits))) | (pindata[data_bit_word] & (0xffffffff << remaining_bits));
		}
#if 0
		printstrln("");
		for (int j = 0; j < 5; j++) {
			printhexln(pindata[j]);
		}
#endif
		
		jtag_irscan_pins(pindata, total_bits);
	
#if 0
		printstrln("");
	    for (int j = 0; j < 5; j++) {
		  printhexln(pindata[j]);
		}
#endif

	} else {
		// just scan in data
		jtag_irscan_pins(scandata, numbits);
	}
}

#pragma unsafe arrays
void jtag_drscan(unsigned int scandata[], unsigned int numbits) {
	if (XCORECHAIN > 1) {
		int i = 0;
		unsigned int extra_bits = 2;
		unsigned int pindata[32]; // 1024 bits
		int total_bits = ((XCORECHAIN - 1) * extra_bits) + numbits;
		int num_words = (total_bits >> 5) + 1;
		int data_bit_word = (XCORESPOST * extra_bits) >> 5;
		int data_bit_loc = (XCORESPOST * extra_bits) - (data_bit_word * 32);
		int data_index = 0;

		int remaining_words = 0;
		int remaining_bits = 0;
		int remaining_word_val = 0;

#if 0
		printstrln("DRSCAN");
		printintln(total_bits);
		printintln(num_words);
		printintln(data_bit_word);
		printintln(data_bit_loc);
#endif

		// Scan in all bypass
		for (i = 0; i < num_words; i++) {
			pindata[i] = 0xffffffff;
		}

		remaining_bits = numbits;

		// First word
		if (numbits > 32 - data_bit_loc) {
			pindata[data_bit_word] = pindata[data_bit_word] >> 32 - data_bit_loc | scandata[data_index] << data_bit_loc;
			data_bit_word++;
			remaining_bits = numbits - (32 - data_bit_loc);
		} else {
			int mask = 0xffffffff & (0xffffffff >> (32 - remaining_bits));
			pindata[data_bit_word] = ((pindata[data_bit_word] & ~(mask << data_bit_loc)) | ((scandata[data_index] & mask) << data_bit_loc));
			data_bit_word++;
			remaining_bits -= remaining_bits;
		}

		remaining_words = remaining_bits >> 5;

		// Middle words
		while (remaining_words) {
			pindata[data_bit_word] = scandata[data_index] >> 32 - data_bit_loc | scandata[data_index + 1] << data_bit_loc;
			data_index++;
			data_bit_word++;
			remaining_words--;
			remaining_bits -= 32;
		}

		// End word
		if (remaining_bits) {
			remaining_word_val = scandata[data_index] >> 32 - data_bit_loc | scandata[data_index + 1] << data_bit_loc;
			pindata[data_bit_word] = (remaining_word_val & (0xffffffff >> (32 - remaining_bits))) | (pindata[data_bit_word] & (0xffffffff << remaining_bits));
		}
		
		jtag_drscan_pins(pindata, total_bits);

#if 0
		printstrln("");
		for (int j = 0; j < 5; j++) {
			printhexln(pindata[j]);
		}
#endif
		
		// copy back to original array
		data_bit_word = (XCORESPOST * extra_bits) >> 5;
		for (int j = 0; j < num_words; j++) {
			remaining_word_val = pindata[data_bit_word] >> data_bit_loc | pindata[data_bit_word + 1] << 32 - data_bit_loc;
			scandata[j] = remaining_word_val;
			data_bit_word++;
		}

	} else {
		// just scan in data
		jtag_drscan_pins(scandata, numbits);
	}
}

static void jtag_read_idcode(void) {
    unsigned idcode = 0x0;
	
    jtag_data_buffer[0] = 0xf3;
    jtag_irscan(jtag_data_buffer, 8);
  
    jtag_drscan(jtag_data_buffer, 32);
  
    idcode = jtag_data_buffer[0];
    //printstr("IDCODE - ");
    //printhexln(idcode);
    return;
}

// Set all to bypass (Up to 64 chips)
// Write test pattern 0xff through all chips
// Check how many missing bits there are (2 per Xcore)
#pragma unsafe arrays
static void jtag_query_chain_len(void) {
  int i = 0;
  int num_chips = 0;
  int num_external_jtag_devs = NUMDEVSPREV + NUMDEVSPOST;

  for (i = 0; i < XCORE_MAX_CHAIN_LEN; i++) {
    XCORETYPES[i] = XCORE_CHAIN_UNKNOWN;
  }
 
  for (i = 0; i < 16; i++) {
	jtag_data_buffer[i] = 0xffffffff;  
  }
  
  jtag_irscan_pins(jtag_data_buffer, 16*32);  
  
  jtag_data_buffer[0] = 1;
  
  for (i = 1; i < 16; i++) {
  	 jtag_data_buffer[i] = 0x0;  
  }
  
  jtag_drscan_pins(jtag_data_buffer, 16*32);

  // Remove data from external devices
  for (i = 0; i < 16; i++) {
    jtag_data_buffer[i] = jtag_data_buffer[i] >> num_external_jtag_devs | jtag_data_buffer[i+1]  << (32 - num_external_jtag_devs);

  }

  if (jtag_data_buffer[0] != 0xffffffff) {
    for (i = 15; i >= 0; i--) {
      //printhexln(jtag_data_buffer[i]);
      if (jtag_data_buffer[i] != 0) {
        for (int j = 15; j >= 0; j--) {
          if (jtag_data_buffer[i] & (1 << (2 * j))) {
            num_chips = (i * 16) + j;
            i = -1;
            break;
          }
        }
      }
    }
  }

  //printstr("JTAG scan chain length of ");
  //printintln(num_chips);

  // Currently only supporting up to 16 chips
  for (i = 0; i < num_chips; i++) {
    unsigned int xcore_chain_type = 0;
    unsigned int idcode_1 = 0;
    unsigned int idcode_2 = 0;

    for (int j = 0; j < 16; j++) {
   	  jtag_data_buffer[j] = 0xffffffff;  
    }

    jtag_data_buffer[i >> 2] = 0xfffffff3 << (i%4)*8 | 0xffffffff >> 32-((i%4)*8);

    jtag_irscan_pins(jtag_data_buffer, num_chips*8);
    
    for (int j = 0; j < 16; j++) {
      jtag_data_buffer[j] = 0x0;  
    }
    
    jtag_drscan_pins(jtag_data_buffer, 64);
    
    idcode_1 = jtag_data_buffer[0];
    idcode_2 = jtag_data_buffer[1];
    
    xcore_chain_type = idcode_1 >> i*2 | idcode_2 << (32 - (i*2));

    XCOREJTAGIDS[i] = xcore_chain_type;

    if (xcore_chain_type == XCORE_CHAIN_G4_ID) {
      XCORETYPES[i] = XCORE_CHAIN_G4_REVB;
    }
    if (xcore_chain_type == XCORE_CHAIN_G1_ID) {
      XCORETYPES[i] = XCORE_CHAIN_G1_REVC;
    }
  }

  XCORECHAIN = num_chips;
  XCOREID = -1;
  XCORESPREV = 0;
  XCORESPOST = XCORECHAIN - 1;
}

static void jtag_shift_bypass_to_all(void) {
	
	// CHIP TAP SETMUX COMMAND -- All these 0's seem odd??
	jtag_data_buffer[0] = 0x0;
	jtag_data_buffer[1] = 0xf4;
	jtag_irscan(jtag_data_buffer, 40);
	
	// CHIP TAP MUX VALUE 1111
	jtag_data_buffer[0] = 0x0f;
	jtag_data_buffer[1] = 0x00;
	jtag_drscan(jtag_data_buffer, 33);
	
	// SHIFT ALL TO BYPASS -- Why 21 bits???
	jtag_data_buffer[0] = 0xffffffff;
	jtag_irscan(jtag_data_buffer, 21);
	
	// SETMUX NC
	jtag_data_buffer[0] = 0x00fe9fff;
	jtag_irscan(jtag_data_buffer, 21);
	
	// MUX VALUE 0
	jtag_data_buffer[0] = 0x0;
    jtag_drscan(jtag_data_buffer, 5);
    
    jtag_data_buffer[0] = 0xffffffff;
    jtag_irscan(jtag_data_buffer, 9);
    
    chip_tap_mux_state = 0;
}

static void jtag_chip_tap_reg_access(unsigned int command, unsigned int data, unsigned int prevData) {
	//printstr("Command "); printhex(command); printstr(" Data "); printhex(data); printstrln("");
	
	if (chip_tap_mux_state != MUX_NC) {
	   jtag_data_buffer[0] = 0x00fc3fff | command << 14;
	   jtag_irscan(jtag_data_buffer, 22);
	   jtag_data_buffer[0] = data << 2;
	   jtag_data_buffer[1] = 0x0;
	   jtag_drscan(jtag_data_buffer, 35);
	} else {
	   jtag_data_buffer[0] = 0xf << 4 | command;
           jtag_irscan(jtag_data_buffer, 8);
	   jtag_data_buffer[0] = data; //(unsigned char)data;
	   jtag_data_buffer[1] = 0x0;
	   jtag_drscan(jtag_data_buffer, 33);   
	}
	
	if (command == SETMUX_IR)
		chip_tap_mux_state = data & 0xf;
	
	jtag_data_buffer[0] = 0xffffffff;
	jtag_irscan(jtag_data_buffer, 22);
}

static void conditionally_set_mux_for_chipmodule(int chipmode) {
  if (chip_tap_mux_values[chipmodule] != chip_tap_mux_state) {
    jtag_chip_tap_reg_access(SETMUX_IR, chip_tap_mux_values[chipmodule], 0);

    // TODO -- Find out why this work around is required!!!
    jtag_data_buffer[0] = 0x00ffc00f | regIndex << 4;
    jtag_irscan(jtag_data_buffer, 22);
    jtag_data_buffer[0] = data << 1;
    jtag_data_buffer[1] = data >> 31;
    jtag_drscan(jtag_data_buffer, 35);
  }
}

static void jtag_module_reg_access(unsigned int chipmodule, unsigned int regIndex, unsigned int data) {
	conditionally_set_mux_for_chipmodule(chipmodule);
	
	jtag_data_buffer[0] = 0x00ffc00f | regIndex << 4;	
	jtag_irscan(jtag_data_buffer, 22);	
	jtag_data_buffer[0] = data << 1;
	jtag_data_buffer[1] = data >> 31; 
	jtag_drscan(jtag_data_buffer, 35);	
}

unsigned int jtag_read_reg(unsigned int chipmodule, unsigned int regIndex) {
	int TapIR = ((regIndex & 0xff) << 2) | 0x1;
	unsigned int value = 0;
	
	TapIR = ((regIndex & 0xff) << 2) | 0x1;
	jtag_module_reg_access(chipmodule, TapIR, 0);
	//printstrln("READ REG");
	//printhexln(jtag_data_buffer[0]);
	//printhexln(jtag_data_buffer[1]);
	value = jtag_data_buffer[0] >> 1 | jtag_data_buffer[1] << 31;
	
	return value;
}

void jtag_write_reg(unsigned int chipmodule, unsigned int regIndex, unsigned int data) {
	int TapIR = ((regIndex & 0xff) << 2) | 0x2;
	jtag_module_reg_access(chipmodule, TapIR, data);	
}

void jtag_select_chip(int chip_id) {
    if (chip_id > (XCORECHAIN - 1)) {
		return;
	}

	// TODO jtag_select_chip() not complete
	//return;

	//printstrln("Select chip");
	//printintln(chip_id);

	if (chip_id != XCOREID) {
		// Reset current chip to bypass
		jtag_shift_bypass_to_all();
		XCOREID = chip_id;
		XCORESPREV = XCOREID;
		XCORESPOST = XCORECHAIN - XCOREID - 1;
		XCORETYPE = XCORETYPES[XCOREID];
		//printintln(XCORESPOST);
		//printintln(XCORESPREV);
		//printf("XCOREID = %d, XCORESPREV = %d, XCORESPOST = %d\n", XCOREID, XCORESPREV, XCORESPOST);
	}

	jtag_read_idcode();
	//jtag_read_idcode();
}

int jtag_get_num_chips(void) {
	return XCORECHAIN;
}

int jtag_get_chip_type(int chip_id) {
	if (chip_id > (XCORECHAIN -1)) {
		return -1;
	}
	return XCORETYPES[chip_id];
}

int jtag_get_num_cores_per_chip(int chip_id) {
	if (XCORETYPES[chip_id] == XCORE_CHAIN_G1_REVC) {
		return 1;
	}
	if ((XCORETYPES[chip_id] == XCORE_CHAIN_G4_REVA) || (XCORETYPES[chip_id] == XCORE_CHAIN_G4_REVB)) {
		return 4;
	}
	return 4;
}

int jtag_get_num_threads_per_core(int chip_id) {
	// Currently all cores have 8 threads!
	return 8;
}

int jtag_get_num_regs_per_thread(int chip_id) {
	// Currently all threads have 22 regs!
	return 22;
}

void jtag_reset(int reset_type) {
	int saved_xcore_id = XCOREID;
	
	if (reset_type == XMOS_JTAG_RESET_TRST_SRST) {
	    jtag_reset_srst();
	    jtag_reset_trst();
	} else if (reset_type == XMOS_JTAG_RESET_TRST) {
	    jtag_reset_trst();
	} else if (reset_type == XMOS_JTAG_RESET_TRST_SRST_JTAG) {
   	   jtag_reset_srst_trst();
	} else {
		return;
	}
	
	chip_tap_mux_state = MUX_NC;
	jtag_query_chain_len();
	
	if (saved_xcore_id != -1) {
	    jtag_select_chip(saved_xcore_id);
	} else {
	    jtag_select_chip(0);
	}
}

// USER OVERRIDE ON CLOCK SPEED
static int JTAG_TCK_SPEED_DIV = -1;

static void jtag_tck_speed(int divider) {
	stop_clock(tck_clk);
        // Max 25MHz
        configure_clock_ref(tck_clk, divider + 2);
	start_clock(tck_clk);
}

void jtag_speed(int divider) {
        JTAG_TCK_SPEED_DIV = divider;
        jtag_tck_speed(divider);
}

void jtag_chain(unsigned int jtag_devs_pre, unsigned int jtag_bits_pre,
                unsigned int jtag_devs_post, unsigned int jtag_bits_post,
                unsigned int jtag_max_speed) {
  NUMDEVSPREV = jtag_devs_pre;
  NUMBITSPREV = jtag_bits_pre;
  NUMDEVSPOST = jtag_devs_post;
  NUMBITSPOST = jtag_bits_post;
  MAXJTAGCLKSPEED = jtag_max_speed;

}

static int jtag_started = 0;

void jtag_init(void) {
	unsigned s;
	timer tmr;
	
	if (!jtag_started) {
                if (JTAG_TCK_SPEED_DIV == -1) {
                  configure_clock_rate(tck_clk, 100, 6);
                }
		configure_out_port(jtag_pin_TCK, tck_clk, 0xffffffff);

		configure_clock_src(other_clk, jtag_pin_TCK);
		configure_out_port(jtag_pin_TDI, other_clk, 0);
		configure_in_port(jtag_pin_TDO, other_clk);
		configure_out_port(jtag_pin_TMS, other_clk, 0);

		//configure_out_port(jtag_pin_TRST, tck_clk, 0);
		configure_out_port(jtag_pin_SRST, tck_clk, 1);

                if (JTAG_TCK_SPEED_DIV == -1) {
		  start_clock(tck_clk);
                }
		start_clock(other_clk);

		tmr :> s;
		tmr when timerafter(s + 400) :> s;
		
		jtag_started = 1;
	}
	
	clearbuf(jtag_pin_TDI);
	clearbuf(jtag_pin_TDO);
	
        if (JTAG_TCK_SPEED_DIV == -1) {
	  jtag_tck_speed(6); // Speed down to 6 MHz on before first reset
        }
	
	//jtag_reset(XMOS_JTAG_RESET_TRST_SRST_JTAG);
	jtag_reset(XMOS_JTAG_RESET_TRST);	

	if (XCORECHAIN <= 4) {
          if (JTAG_TCK_SPEED_DIV == -1) {
	    jtag_tck_speed(0); // Put speed back up if there is a small chain (25MHz)
          }
	}

        return;
}

void jtag_deinit(void) {
  jtag_shift_bypass_to_all();
  JTAG_TCK_SPEED_DIV = -1;
}

