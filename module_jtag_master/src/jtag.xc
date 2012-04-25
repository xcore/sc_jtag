#include <xs1.h>
#include <platform.h>
#include <print.h>
#include <stdio.h>
#include <jtag.h>
#include <jtag_xs1_su.h>
#include <stdlib.h>

#define JTAG_MAX_TAPS 96
#define JTAG_DATA_BUFFER_WORDS 32   // TODO: relate to the above.

unsigned int jtag_data_buffer[JTAG_DATA_BUFFER_WORDS];

// CHIP TAP MUX STATES
#define MUX_NC 0
#define MUX_SSWITCH 1
#define MUX_XCORE0 2
#define MUX_XCORE1 3
#define MUX_XCORE2 4
#define MUX_XCORE3 5
#define MUX_XCOREALL 6

// CHIP TAP MUX VALUES
static unsigned char chip_tap_mux_values[7] =
  { 0x0, 0x1, 0x8, 0x9, 0xa, 0xb, 0xf };

// CHIP TAP COMMANDS
#define SETMUX_IR 0x4
#define GETMUX_IR 0x5
#define SET_TEST_MODE_IR 0x8
#define BYPASS_IR 0xf

// OTP TAP COMMANDS
#define OTP_TAP_CMD_LOAD_IR 0x0
#define OTP_TAP_DATA_SHIFT_IR 0x2

// Register lengths for each TAP.
#define BSCAN_TAP_IR_LEN 4
#define BSCAN_TAP_BYP_LEN 1
#define CHIP_TAP_IR_LEN 4
#define CHIP_TAP_BYP_LEN 1
#define XCORE_TAP_IR_LEN 10
#define XCORE_TAP_DR_LEN 32
#define XCORE_TAP_BYP_LEN 1
#define OTP_TAP_IR_LEN 2
// Length of DR for CMD_LOAD instruction.
#define OTP_TAP_CMD_LOAD_DR_LEN 3
// Length of DR for DATA_SHIFT instruction.
#define OTP_TAP_DATA_SHIFT_DR_LEN 32
#define OTP_TAP_BYP_LEN 1

// Length of the chain for one chip. This depends on the state of the mux control.
#define MUX_XCORE_IR_LEN (BSCAN_TAP_IR_LEN + CHIP_TAP_IR_LEN + XCORE_TAP_IR_LEN + OTP_TAP_IR_LEN)
#define MUX_XCORE_BYP_LEN (BSCAN_TAP_BYP_LEN + CHIP_TAP_BYP_LEN + XCORE_TAP_BYP_LEN + OTP_TAP_BYP_LEN)

#define TEST_MODE_OTP_SERIAL_ENABLE 0x4

/* JTAG TAP IMPLEMENTATION EXAMPLE
  TAP Chain --  XX - XX - G4 - L1 - SU - XX
  XCore ID                 0    1
  SU   ID                            0
*/

// JTAG TAP CHAIN
static unsigned int JTAG_NUM_TAPS = 0;
static unsigned int JTAG_TAP_INDEX = 0;
static unsigned int JTAG_NUM_TAPS_PREV = 0;
static unsigned int JTAG_NUM_TAPS_POST = 0;

static unsigned int JTAG_TAP_ID[JTAG_MAX_TAPS];
static unsigned int JTAG_NUM_XMOS_DEVS = 0;
static unsigned int JTAG_NUM_XMOS_XCORE = 0;
static unsigned int JTAG_NUM_XMOS_SU = 0;
static unsigned char JTAG_XMOS_DEV_MAP[JTAG_MAX_TAPS];
static int JTAG_TAP_SINGLE_XCORE = 0;

// XMOS JTAG SCAN CHAIN DETAILS
#define XCORE_MAX_CHAIN_LEN 16
#define XCORE_CHAIN_UNKNOWN 0
#define XCORE_CHAIN_G4_ID 0x104731
#define XCORE_CHAIN_G4_REVA 1
#define XCORE_CHAIN_G4_REVB 2
#define XCORE_CHAIN_G1_ID 0x2633
#define XCORE_CHAIN_G1_REVC 3
#define XCORE_CHAIN_SU_ID 0x3633


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

//#define ENABLE_DEBUG
#ifdef ENABLE_DEBUG
#include <stdio.h>
#define DEBUG(x) x
#else
#define DEBUG(x)
#endif

unsigned char chip_tap_mux_state = MUX_NC;

on stdcore[0]:buffered out port:32 jtag_pin_TDI = XS1_PORT_1A;
on stdcore[0]:buffered in port:32 jtag_pin_TDO = XS1_PORT_1B;
on stdcore[0]:buffered out port:4 jtag_pin_TMS = XS1_PORT_1C;
on stdcore[0]:buffered out port:32 jtag_pin_TCK = XS1_PORT_1D;

on stdcore[0]:out port jtag_pin_SRST = XS1_PORT_1M;
on stdcore[0]:out port jtag_pin_TRST = XS1_PORT_1L;

on stdcore[0]:clock tck_clk = XS1_CLKBLK_1;
on stdcore[0]:clock other_clk = XS1_CLKBLK_2;

static void
jtag_reset_srst (void)
{
  unsigned s;
  timer tmr;

  sync (jtag_pin_TCK);
  clearbuf (jtag_pin_TMS);

  jtag_pin_SRST <:0;
  tmr:>s;
  tmr when timerafter (s + 40000):>s;
  jtag_pin_SRST <:1;

  tmr:>s;
  tmr when timerafter (s + 50000000):>s;

  return;
}

static void
jtag_reset_trst (void)
{
  unsigned s;
  timer tmr;

  sync (jtag_pin_TCK);
  clearbuf (jtag_pin_TMS);

  jtag_pin_TRST <:0;
  tmr:>s;
  tmr when timerafter (s + 4000):>s;
  jtag_pin_TRST <:1;
  tmr when timerafter (s + 4000):>s;

  jtag_pin_TMS <:0xf;
  partout (jtag_pin_TCK, 8, 0xaa);
  jtag_pin_TMS <:0x7;
  partout (jtag_pin_TCK, 8, 0xaa);

  return;
}

static void
jtag_reset_srst_trst (void)
{
  unsigned s;
  timer tmr;

  sync (jtag_pin_TCK);
  clearbuf (jtag_pin_TMS);

  tmr:>s;
  tmr when timerafter (s + 4000):>s;
  jtag_pin_TRST <:0;

  tmr:>s;
  tmr when timerafter (s + 4000):>s;
  jtag_pin_SRST <:0;

  tmr:>s;
  tmr when timerafter (s + 40000):>s;
  jtag_pin_SRST <:1;

  tmr:>s;
  tmr when timerafter (s + 50000000):>s;

  tmr:>s;
  tmr when timerafter (s + 40000):>s;
  jtag_pin_TRST <:1;

  tmr:>s;
  tmr when timerafter (s + 4000):>s;

  jtag_pin_TMS <:0xf;
  partout (jtag_pin_TCK, 8, 0xaa);
  jtag_pin_TMS <:0x7;
  partout (jtag_pin_TCK, 8, 0xaa);

  return;
}

void
jtag_rti_delay (void)
{
  int i = 0;

  //for (i = 0; i < 10; i++) {
jtag_pin_TMS <:0;
jtag_pin_TCK <:0xAAAAAAAA;	// 16 CLK's  
jtag_pin_TCK <:0xAAAAAAAA;	// 16 CLK's
  //}
}

#pragma unsafe arrays
static void
jtag_irscan_pins (unsigned int scandata[], short num_bits)
{
  unsigned short chunks = --num_bits >> 5;
  unsigned short remainder = num_bits & 31;

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
static void
jtag_drscan_pins (unsigned int scandata[], short num_bits)
{
  int i = 1;
  unsigned short chunks = --num_bits >> 5;
  unsigned short remainder = num_bits & 31;
  unsigned int temp;

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

// ---- TAP --- PREV
static unsigned int
jtag_get_num_taps_post (unsigned int tap_id)
{
  return tap_id;
}

// --- POST --- TAP
static unsigned int
jtag_get_num_taps_prev (unsigned int tap_id)
{
  // If TAP is L or G series XCore combine 2 taps
  if ((JTAG_TAP_ID[tap_id] == XCORE_CHAIN_G4_ID)
      || (JTAG_TAP_ID[tap_id] == XCORE_CHAIN_G1_ID)) {
    return JTAG_NUM_TAPS - tap_id - 2;
  }
  else {
    return JTAG_NUM_TAPS - tap_id - 1;
  }
}

#pragma unsafe arrays
void
jtag_irscan (unsigned int scandata[], unsigned int numbits)
{
  if (!JTAG_TAP_SINGLE_XCORE) {
    int i = 0;
    unsigned int extra_bits = 4;
    unsigned int pindata[32];	// 1024 bits
    int total_bits =
      ((jtag_get_num_taps_prev (JTAG_TAP_INDEX) +
	jtag_get_num_taps_post (JTAG_TAP_INDEX)) * extra_bits) + numbits;
    int num_words = (total_bits >> 5) + 1;
    int data_bit_word =
      (jtag_get_num_taps_post (JTAG_TAP_INDEX) * extra_bits) >> 5;
    int data_bit_loc =
      (jtag_get_num_taps_post (JTAG_TAP_INDEX) * extra_bits) -
      (data_bit_word * 32);

    int data_index = 0;

    int remaining_words = 0;
    int remaining_bits = 0;
    int remaining_word_val = 0;

#if 0
    printintln (total_bits);
    printintln (num_words);
    printintln (data_bit_word);
    printintln (data_bit_loc);
    printf ("TAP INDEX = %d, PRE = %d, POST = %d\n", JTAG_TAP_INDEX,
	    jtag_get_num_taps_prev (JTAG_TAP_INDEX),
	    jtag_get_num_taps_post (JTAG_TAP_INDEX));

#endif
    // Scan in all bypass
    for (i = 0; i < num_words; i++) {
      pindata[i] = 0xffffffff;
    }

    remaining_bits = numbits;

    // First word
    if (numbits > 32 - data_bit_loc) {
      pindata[data_bit_word] =
	pindata[data_bit_word] >> 32 -
	data_bit_loc | scandata[data_index] << data_bit_loc;
      data_bit_word++;
      remaining_bits = numbits - (32 - data_bit_loc);
    }
    else {
      int mask = 0xffffffff & (0xffffffff >> (32 - remaining_bits));
      pindata[data_bit_word] =
	((pindata[data_bit_word] & ~(mask << data_bit_loc)) |
	 ((scandata[data_index] & mask) << data_bit_loc));
      data_bit_word++;
      remaining_bits -= remaining_bits;
    }

    remaining_words = remaining_bits >> 5;

    // Middle words
    while (remaining_words) {
      pindata[data_bit_word] =
	scandata[data_index] >> 32 - data_bit_loc | scandata[data_index +
							     1] <<
	data_bit_loc;
      data_index++;
      data_bit_word++;
      remaining_words--;
      remaining_bits -= 32;
    }

    // End word
    if (remaining_bits) {
      remaining_word_val =
	scandata[data_index] >> 32 - data_bit_loc | scandata[data_index +
							     1] <<
	data_bit_loc;
      pindata[data_bit_word] =
	(remaining_word_val & (0xffffffff >> (32 - remaining_bits))) |
	(pindata[data_bit_word] & (0xffffffff << remaining_bits));
    }
#if 0
    printstrln ("");
    for (int j = 0; j < 2; j++) {
      printhexln (pindata[j]);
    }
    printstrln ("");
#endif

    jtag_irscan_pins (pindata, total_bits);
#if 0
    printstrln ("");
    for (int j = 0; j < 5; j++) {
      printhexln (pindata[j]);
    }
    printstrln ("");
#endif

  }
  else {
    // just scan in data
    jtag_irscan_pins (scandata, numbits);
  }
}

#pragma unsafe arrays
void
jtag_drscan (unsigned int scandata[], unsigned int numbits)
{
  if (!JTAG_TAP_SINGLE_XCORE) {
    int i = 0;
    unsigned int extra_bits = 1;
    unsigned int pindata[32] = { 0 };	// 1024 bits
    int total_bits =
      ((jtag_get_num_taps_prev (JTAG_TAP_INDEX) +
	jtag_get_num_taps_post (JTAG_TAP_INDEX)) * extra_bits) + numbits;
    int num_words = (total_bits >> 5) + 1;
    int data_bit_word =
      (jtag_get_num_taps_post (JTAG_TAP_INDEX) * extra_bits) >> 5;
    int data_bit_loc =
      (jtag_get_num_taps_post (JTAG_TAP_INDEX) * extra_bits) -
      (data_bit_word * 32);
    int data_index = 0;

    int remaining_words = 0;
    int remaining_bits = 0;
    int remaining_word_val = 0;

#if 0
//#if 0
    printf ("DRSCAN -- taps prev / taps post [%d/%d]\n",
	    jtag_get_num_taps_prev (JTAG_TAP_INDEX),
	    jtag_get_num_taps_post (JTAG_TAP_INDEX));
//#endif


//#if 0
    printstrln ("DRSCAN");
    printintln (total_bits);
    printintln (num_words);
    printintln (data_bit_word);
    printintln (data_bit_loc);
//#endif
#endif

    // Scan in all bypass
    for (i = 0; i < num_words; i++) {
      pindata[i] = 0xffffffff;
      //printf("SCANDATA %d = 0x%x\n", i, scandata[i]);
    }

    remaining_bits = numbits;

    // First word
    if (numbits > 32 - data_bit_loc) {
      pindata[data_bit_word] =
	pindata[data_bit_word] >> 32 -
	data_bit_loc | scandata[data_index] << data_bit_loc;
      data_bit_word++;
      remaining_bits = numbits - (32 - data_bit_loc);
    }
    else {
      int mask = 0xffffffff & (0xffffffff >> (32 - remaining_bits));
      pindata[data_bit_word] =
	((pindata[data_bit_word] & ~(mask << data_bit_loc)) |
	 ((scandata[data_index] & mask) << data_bit_loc));
      data_bit_word++;
      remaining_bits -= remaining_bits;
    }

    remaining_words = remaining_bits >> 5;

    // Middle words
    while (remaining_words) {
      pindata[data_bit_word] =
	scandata[data_index] >> 32 - data_bit_loc | scandata[data_index +
							     1] <<
	data_bit_loc;
      data_index++;
      data_bit_word++;
      remaining_words--;
      remaining_bits -= 32;
    }

    // End word
    if (remaining_bits) {
      remaining_word_val =
	scandata[data_index] >> 32 - data_bit_loc | scandata[data_index +
							     1] <<
	data_bit_loc;
      pindata[data_bit_word] =
	(remaining_word_val & (0xffffffff >> (32 - remaining_bits))) |
	(pindata[data_bit_word] & (0xffffffff << remaining_bits));
    }


#if 0
    printstrln ("");
    for (int j = 0; j < 5; j++) {
      printhexln (pindata[j]);
    }
    printstrln ("");
#endif

    jtag_drscan_pins (pindata, total_bits);

#if 0
    printstrln ("");
    for (int j = 0; j < 5; j++) {
      printhexln (pindata[j]);
    }
    printstrln ("");
#endif

    // copy back to original array
    data_bit_word =
      (jtag_get_num_taps_post (JTAG_TAP_INDEX) * extra_bits) >> 5;
    for (int j = 0; j < num_words; j++) {
      remaining_word_val =
	pindata[data_bit_word] >> data_bit_loc | pindata[data_bit_word +
							 1] << 32 -
	data_bit_loc;
      scandata[j] = remaining_word_val;
      data_bit_word++;
    }

  }
  else {
    // just scan in data
    jtag_drscan_pins (scandata, numbits);
  }
}

static void
jtag_read_idcode (void)
{
  unsigned idcode = 0x0;

  jtag_data_buffer[0] = 0xf3;

  if (JTAG_TAP_ID[JTAG_TAP_INDEX] == XCORE_CHAIN_SU_ID) {
    jtag_irscan (jtag_data_buffer, 4);
  }
  else {
    jtag_irscan (jtag_data_buffer, 8);
  }

  jtag_drscan (jtag_data_buffer, 32);

  idcode = jtag_data_buffer[0];
  printstr ("IDCODE - ");
  printhexln (idcode);

  return;
}

// Set all to bypass (Up to 64 chips)
// Write test pattern 0xff through all chips
// Check how many missing bits there are (2 per Xcore)
#pragma unsafe arrays
static void
jtag_query_chain_len (void)
{
  int i = 0;
  int num_taps = 0;
  unsigned int xmos_device_map_index = 0;

  JTAG_NUM_TAPS = 0;
  JTAG_NUM_XMOS_DEVS = 0;
  JTAG_NUM_XMOS_XCORE = 0;
  JTAG_NUM_XMOS_SU = 0;
  JTAG_TAP_SINGLE_XCORE = 0;

  for (i = 0; i < JTAG_DATA_BUFFER_WORDS; i++) {
    jtag_data_buffer[i] = 0xffffffff;
  }

  jtag_irscan_pins (jtag_data_buffer, JTAG_DATA_BUFFER_WORDS * 32);

  jtag_data_buffer[0] = 1;

  for (i = 1; i < JTAG_DATA_BUFFER_WORDS; i++) {
    jtag_data_buffer[i] = 0x0;
  }

  jtag_drscan_pins (jtag_data_buffer, JTAG_DATA_BUFFER_WORDS * 32);

#if 0
    for (i = 15; i >= 0; i--) {
        printf("%08x\n",jtag_data_buffer[i]);
    }
#endif

  if (jtag_data_buffer[0] != 0xffffffff) {
    for (i = 15; i >= 0; i--) {
        int zeroes;
        asm("clz %0,%1" : "=r" (zeroes) : "r" (jtag_data_buffer[i]));
        if (zeroes < 32) {
            num_taps = (i * 32) + (31-zeroes);
            break;
        }
    }
  }

#if 0
  printstr("Number of JTAG TAPS = ");
  printintln(num_taps);
#endif
  if (num_taps ==  0) {      
      return;              // No taps found, or too many.
  }

  JTAG_NUM_TAPS = num_taps;
  // Setup idcode read for each tap
  for (i = 0; i < JTAG_NUM_TAPS; i++) {
    unsigned int word_index = i / 8;
    unsigned int subword_index = i % 8;
    unsigned int idcode_1 = 0;
    unsigned int idcode_2 = 0;
    unsigned int xcore_chain_type = 0;
    unsigned int j = 0;

    for (j = 0; j < JTAG_DATA_BUFFER_WORDS; j++) {
      jtag_data_buffer[j] = 0xffffffff;
    }

#if 0
    printf ("Addressing tap %d, word %d, subword %d\n", i, word_index,
	    subword_index);
    printf ("Taps prev = %d\n", JTAG_NUM_TAPS - (JTAG_NUM_TAPS - i));;
    printf ("Taps post = %d\n", (JTAG_NUM_TAPS - i) - 1);
#endif

    // Add IDCODE for tap
    jtag_data_buffer[word_index] = ~(0xc << (subword_index * 4));

    // printf("IR in %08x  %08x\n", jtag_data_buffer[0], jtag_data_buffer[1]);

    jtag_irscan_pins (jtag_data_buffer, JTAG_NUM_TAPS * 4);

    // DR scan(num_taps_found * 4)

    jtag_drscan_pins (jtag_data_buffer, ((JTAG_NUM_TAPS+31)&~31) + 32);

    xcore_chain_type = jtag_data_buffer[(i>>5)] >> (i&31) |
        jtag_data_buffer[(i>>5)+1] << (32 - (i&31));
#if 0
    printf("%08x  %08x  %08x --> 0x%x chain type\n", jtag_data_buffer[0], 
           jtag_data_buffer[1], jtag_data_buffer[2], xcore_chain_type);
#endif
    JTAG_TAP_ID[i] = xcore_chain_type;

    // reset to bypass

  }

  // Set up XMOS device map
  for (i = 0; i < JTAG_NUM_TAPS; i++) {

    if ((JTAG_TAP_ID[i] == XCORE_CHAIN_G4_ID)
	|| (JTAG_TAP_ID[i] == XCORE_CHAIN_G1_ID)) {
      JTAG_XMOS_DEV_MAP[JTAG_NUM_XMOS_DEVS] = i;
      // Skip other TAP
      i++;
      JTAG_NUM_XMOS_DEVS++;
      JTAG_NUM_XMOS_XCORE++;
    }
    if (JTAG_TAP_ID[i] == XCORE_CHAIN_SU_ID) {
      JTAG_XMOS_DEV_MAP[JTAG_NUM_XMOS_DEVS] = i;
      JTAG_NUM_XMOS_DEVS++;
      JTAG_NUM_XMOS_SU++;
    }
  }

  for (i = 0; i < JTAG_NUM_XMOS_DEVS; i++) {
    //printf("XMOS JTAG DEVICE %d at location %d with ID 0x%x\n", i, JTAG_XMOS_DEV_MAP[i], JTAG_TAP_ID[JTAG_XMOS_DEV_MAP[i]]);
  }

  if ((JTAG_NUM_TAPS == 2) && (JTAG_NUM_XMOS_SU == 0)
      && (JTAG_NUM_XMOS_XCORE == 1)) {
    //printf("Single Xcore detected\n");
    JTAG_TAP_SINGLE_XCORE = 1;
  } 

  JTAG_TAP_INDEX = 0;
  JTAG_NUM_TAPS_PREV = 0;
  JTAG_NUM_TAPS_POST = JTAG_NUM_TAPS - 1;

}

static void
jtag_shift_bypass_to_all (void)
{

  if ((JTAG_TAP_ID[JTAG_TAP_INDEX] == XCORE_CHAIN_G4_ID)
      || (JTAG_TAP_ID[JTAG_TAP_INDEX] == XCORE_CHAIN_G1_ID)) {
    // CHIP TAP SETMUX COMMAND
    jtag_data_buffer[0] = 0x0;
    jtag_data_buffer[1] = 0xf4;
    jtag_irscan (jtag_data_buffer, 40);

    // CHIP TAP MUX VALUE 1111
    jtag_data_buffer[0] = 0x0f;
    jtag_data_buffer[1] = 0x00;
    jtag_drscan (jtag_data_buffer, 33);

    // SHIFT ALL TO BYPASS 
    jtag_data_buffer[0] = 0xffffffff;
    jtag_irscan (jtag_data_buffer, 21);

    // SETMUX NC
    jtag_data_buffer[0] = 0x00fe9fff;
    jtag_irscan (jtag_data_buffer, 21);

    // MUX VALUE 0
    jtag_data_buffer[0] = 0x0;
    jtag_drscan (jtag_data_buffer, 5);

    jtag_data_buffer[0] = 0xffffffff;
    jtag_irscan (jtag_data_buffer, 9);

    chip_tap_mux_state = 0;
  }

  if (JTAG_TAP_ID[JTAG_TAP_INDEX] == XCORE_CHAIN_SU_ID) {
    jtag_data_buffer[0] = 0xffffffff;
    jtag_irscan (jtag_data_buffer, 8);
  }
}

static void
jtag_chip_tap_reg_access (unsigned int command, unsigned int data,
			  unsigned int prevData)
{
  //printstr("Command "); printhex(command); printstr(" Data "); printhex(data); printstrln("");

  if (chip_tap_mux_state != MUX_NC) {
    jtag_data_buffer[0] = 0x00fc3fff | command << 14;
    jtag_irscan (jtag_data_buffer, 22);
    jtag_data_buffer[0] = data << 2;
    jtag_data_buffer[1] = 0x0;
    jtag_drscan (jtag_data_buffer, 35);
  }
  else {
    jtag_data_buffer[0] = 0xf << 4 | command;
    jtag_irscan (jtag_data_buffer, 8);
    jtag_data_buffer[0] = data;	//(unsigned char)data;
    jtag_data_buffer[1] = 0x0;
    jtag_drscan (jtag_data_buffer, 33);
  }

  if (command == SETMUX_IR)
    chip_tap_mux_state = data & 0xf;

  jtag_data_buffer[0] = 0xffffffff;
  jtag_irscan (jtag_data_buffer, 22);
}

static void
conditionally_set_mux_for_chipmodule (int chipmodule)
{
  if (chip_tap_mux_values[chipmodule] != chip_tap_mux_state) {
    jtag_chip_tap_reg_access (SETMUX_IR, chip_tap_mux_values[chipmodule], 0);

    // TODO -- Find out why this work around is required!!!
    jtag_data_buffer[0] = 0xffffffff;
    jtag_irscan (jtag_data_buffer, MUX_XCORE_IR_LEN);
    jtag_drscan (jtag_data_buffer, MUX_XCORE_BYP_LEN);
  }
}

static void
jtag_module_reg_access (unsigned int chipmodule, unsigned int regIndex,
			unsigned int data)
{

  conditionally_set_mux_for_chipmodule (chipmodule);
  jtag_data_buffer[0] = 0x00ffc00f | regIndex << 4;
  jtag_irscan (jtag_data_buffer, 22);
  jtag_data_buffer[0] = data << 1;
  jtag_data_buffer[1] = data >> 31;
  jtag_drscan (jtag_data_buffer, 35);
}

unsigned int
jtag_read_reg (unsigned int chipmodule, unsigned int regIndex)
{
  unsigned int value = 0;

  if (JTAG_TAP_ID[JTAG_TAP_INDEX] == XCORE_CHAIN_SU_ID) {
    value = jtag_xs1_su_read_reg (regIndex);
  }
  else {
    int TapIR = ((regIndex & 0xff) << 2) | 0x1;
    TapIR = ((regIndex & 0xff) << 2) | 0x1;
    jtag_module_reg_access (chipmodule, TapIR, 0);
    if (chipmodule == MUX_SSWITCH) {
      value = jtag_data_buffer[0];
    } else {
      value = jtag_data_buffer[0] >> 1 | jtag_data_buffer[1] << 31;
    }
  }

  return value;
}

void
jtag_write_reg (unsigned int chipmodule, unsigned int regIndex,
		unsigned int data)
{

  if (JTAG_TAP_ID[JTAG_TAP_INDEX] == XCORE_CHAIN_SU_ID) {
    jtag_xs1_su_write_reg (regIndex, data);
  }
  else {
    int TapIR = ((regIndex & 0xff) << 2) | 0x2;
    jtag_module_reg_access (chipmodule, TapIR, data);
  }
}

void
jtag_enable_serial_otp_access (void)
{
  jtag_chip_tap_reg_access (SET_TEST_MODE_IR,
			    (0xFACED00 << 4) | TEST_MODE_OTP_SERIAL_ENABLE,
			    0);
}

void
jtag_disable_serial_otp_access (void)
{
  jtag_chip_tap_reg_access (SET_TEST_MODE_IR, (0xFACED00 << 4), 0);
}

void
jtag_module_otp_write_test_port_cmd (unsigned int chipmodule,
				     unsigned int cmd)
{
  DEBUG (printf ("jtag_module_otp_write_test_port_cmd() cmd=0x%x\n", cmd);)
    conditionally_set_mux_for_chipmodule (chipmodule);
  jtag_data_buffer[0] = 0x000ffffc | OTP_TAP_CMD_LOAD_IR;
  DEBUG (printf
	 ("IR: 0x%x (%d bits)\n", jtag_data_buffer[0], MUX_XCORE_IR_LEN);)
    jtag_irscan (jtag_data_buffer, MUX_XCORE_IR_LEN);
  jtag_data_buffer[0] = cmd;
  DEBUG (printf
	 ("DR: 0x%x (%d bits)\n", jtag_data_buffer[0],
	  (MUX_XCORE_BYP_LEN - OTP_TAP_BYP_LEN) + OTP_TAP_CMD_LOAD_DR_LEN);)
    jtag_drscan (jtag_data_buffer,
		 (MUX_XCORE_BYP_LEN - OTP_TAP_BYP_LEN) +
		 OTP_TAP_CMD_LOAD_DR_LEN);
}

unsigned int
jtag_module_otp_shift_data (unsigned int chipmodule, unsigned int data)
{
  DEBUG (printf ("jtag_module_otp_shift_data() data=0x%x\n", data);)
    conditionally_set_mux_for_chipmodule (chipmodule);

  jtag_data_buffer[0] = 0x000ffffc | OTP_TAP_DATA_SHIFT_IR;
  DEBUG (printf
	 ("IR: 0x%x (%d bits)\n", jtag_data_buffer[0], MUX_XCORE_IR_LEN);)
    jtag_irscan (jtag_data_buffer, MUX_XCORE_IR_LEN);
  jtag_data_buffer[0] = data;
  DEBUG (printf
	 ("DR: 0x%x (%d bits)\n", jtag_data_buffer[0],
	  (MUX_XCORE_BYP_LEN - OTP_TAP_BYP_LEN) + OTP_TAP_DATA_SHIFT_DR_LEN);)
    jtag_drscan (jtag_data_buffer,
		 (MUX_XCORE_BYP_LEN - OTP_TAP_BYP_LEN) +
		 OTP_TAP_DATA_SHIFT_DR_LEN);
  DEBUG (printf ("Output: 0x%x\n", jtag_data_buffer[0]);)
    return jtag_data_buffer[0];
}

void
jtag_select_xmos_tap (int chip_id, unsigned int type)
{
  int i = 0;
  unsigned int loc_id = 0;

  jtag_shift_bypass_to_all ();

  for (i = JTAG_NUM_XMOS_DEVS - 1; i >= 0; i--) {
    unsigned int tap_id = JTAG_TAP_ID[JTAG_XMOS_DEV_MAP[i]];
    if ((tap_id == XCORE_CHAIN_G4_ID) || (tap_id == XCORE_CHAIN_G1_ID)) {
      if (loc_id == chip_id) {
	JTAG_TAP_INDEX = JTAG_XMOS_DEV_MAP[i];
	//printf("SELECTING CHIP %d .... TAP INDEX %d\n", chip_id, JTAG_TAP_INDEX);
	break;
      }
      loc_id++;
    }
  }

  //jtag_read_idcode();
}

// JTAG chain info functions

int
jtag_get_num_taps (void)
{
  return JTAG_NUM_TAPS;
}

int
jtag_get_tap_id (unsigned int index)
{
  if (index < JTAG_NUM_TAPS) {
    return JTAG_TAP_ID[index];
  }
  else {
    return -1;
  }
}

int
jtag_select_tap (unsigned int index)
{
  if (index < JTAG_NUM_TAPS) {
    int current_tap = JTAG_TAP_INDEX;
    jtag_shift_bypass_to_all ();
    JTAG_TAP_INDEX = index;
    return current_tap;
  }
}

// XCore info functions
int
jtag_get_num_xcores (void)
{
  return JTAG_NUM_XMOS_XCORE;
}

int
jtag_get_xcore_type (int chip_id)
{

  if (chip_id > (JTAG_NUM_XMOS_XCORE - 1)) {
    return -1;
  }

  if (JTAG_TAP_ID[JTAG_XMOS_DEV_MAP[chip_id]] == XCORE_CHAIN_G4_ID) {
    return XCORE_CHAIN_G4_REVB;
  }

  if (JTAG_TAP_ID[JTAG_XMOS_DEV_MAP[chip_id]] == XCORE_CHAIN_G1_ID) {
    return XCORE_CHAIN_G1_REVC;
  }

  return XCORE_CHAIN_UNKNOWN;
}

int
jtag_get_num_cores_per_xcore (int chip_id)
{

  if (chip_id > (JTAG_NUM_XMOS_XCORE - 1)) {
    return -1;
  }

  if (JTAG_TAP_ID[JTAG_XMOS_DEV_MAP[chip_id]] == XCORE_CHAIN_G4_ID) {
    return 4;
  }

  if (JTAG_TAP_ID[JTAG_XMOS_DEV_MAP[chip_id]] == XCORE_CHAIN_G1_ID) {
    return 1;
  }

  return 4;
}

int
jtag_get_num_threads_per_xcore (int chip_id)
{
  // TODO read from hardware
  return 8;
}

int
jtag_get_num_regs_per_xcore_thread (int chip_id)
{
  // TODO read from hardware
  return 25;
}

void
jtag_reset (int reset_type)
{
  unsigned int saved_tap_index = JTAG_TAP_INDEX;
  unsigned s;
  timer tmr;

  //printf ("JTAG RESET %d\n", reset_type);


  if (reset_type == XMOS_JTAG_RESET_TRST_SRST) {
    jtag_reset_srst ();
    jtag_reset_trst ();
  }
  else if (reset_type == XMOS_JTAG_RESET_TRST) {
    jtag_reset_trst ();
  }
  else if (reset_type == XMOS_JTAG_RESET_TRST_SRST_JTAG) {
    jtag_reset_srst_trst ();
  }
  else {
    return;
  }

  chip_tap_mux_state = MUX_NC;
  jtag_query_chain_len ();
  jtag_shift_bypass_to_all ();

  if (saved_tap_index != -1) {
    JTAG_TAP_INDEX = saved_tap_index;
  }
  else {
    JTAG_TAP_INDEX = 0;
  }
}

// USER OVERRIDE ON CLOCK SPEED
static int JTAG_TCK_SPEED_DIV = -1;

static void
jtag_tck_speed (int divider)
{
  stop_clock (tck_clk);
  // Max 25MHz
  configure_clock_ref (tck_clk, divider + 2);
  start_clock (tck_clk);
}

void
jtag_speed (int divider)
{
  JTAG_TCK_SPEED_DIV = divider;
  jtag_tck_speed (divider);
}

void
jtag_chain (unsigned int jtag_devs_pre, unsigned int jtag_bits_pre,
	    unsigned int jtag_devs_post, unsigned int jtag_bits_post,
	    unsigned int jtag_max_speed)
{
  NUMDEVSPREV = jtag_devs_pre;
  NUMBITSPREV = jtag_bits_pre;
  NUMDEVSPOST = jtag_devs_post;
  NUMBITSPOST = jtag_bits_post;
  MAXJTAGCLKSPEED = jtag_max_speed;

}

static int jtag_started = 0;

void
jtag_init (void)
{
  unsigned s;
  timer tmr;

  if (!jtag_started) {
    if (JTAG_TCK_SPEED_DIV == -1) {
      configure_clock_rate (tck_clk, 100, 6);
    }
    configure_out_port (jtag_pin_TCK, tck_clk, 0xffffffff);

    configure_clock_src (other_clk, jtag_pin_TCK);
    configure_out_port (jtag_pin_TDI, other_clk, 0);
    configure_in_port (jtag_pin_TDO, other_clk);
    configure_out_port (jtag_pin_TMS, other_clk, 0);

    //configure_out_port(jtag_pin_TRST, tck_clk, 0);
    configure_out_port (jtag_pin_SRST, tck_clk, 1);

    if (JTAG_TCK_SPEED_DIV == -1) {
      start_clock (tck_clk);
    }
    start_clock (other_clk);

  tmr:>s;
    tmr when timerafter (s + 400):>s;
    //tmr when timerafter (s + 50000000):>s;

    jtag_started = 1;
  }

  clearbuf (jtag_pin_TDI);
  clearbuf (jtag_pin_TDO);

  if (JTAG_TCK_SPEED_DIV == -1) {
    jtag_tck_speed (4);		// Speed down to 6 MHz on before first reset
  }

  jtag_reset (XMOS_JTAG_RESET_TRST);

  if (JTAG_NUM_XMOS_XCORE <= 4) {
    if (JTAG_TCK_SPEED_DIV == -1) {
      jtag_tck_speed (0);	// Put speed back up if there is a small chain (25MHz)
    }
  }

  return;
}

void
jtag_deinit (void)
{
  jtag_shift_bypass_to_all ();
  JTAG_TCK_SPEED_DIV = -1;
}
