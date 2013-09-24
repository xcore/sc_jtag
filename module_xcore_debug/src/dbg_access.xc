#include <xs1.h>
#include <xclib.h>
#include "jtag.h"
#include "jtag_otp_access.h"
#include "dbg_access.h"
#include "dbg_soft_reset_code.h"
#include <stdio.h>
#include <xs1.h>

#define DBG_SSWITCH 1
#define DBG_XCORE0 2
#define DBG_XCORE1 3
#define DBG_XCORE2 4
#define DBG_XCORE3 5

#define DBG_SUCCESS 1
#define DBG_FAILURE 0

#define JTAG_LED0_PIN 28
#define JTAG_LED1_PIN 29
#define JTAG_LED2_PIN 30
#define JTAG_LED3_PIN 31

#ifdef XTAG_U8
out port LEDS = XS1_PORT_4C;
#endif

extern void jtag_combined_pins(unsigned int bit, unsigned int enable);

unsigned short current_xcore_id;

unsigned short current_module = DBG_XCORE0;

unsigned short current_chip = 0;

static void dbg_drive_status_leds(unsigned int mask) {
#ifdef XTAG_U8
  LEDS <: mask;
#endif
}

static void dbg_delay(unsigned int delay) {
  unsigned s;
  timer tmr;
  tmr:>s;
  tmr when timerafter(s + delay):>s;
}

void dbg_select_chip(int chip_id, int chip_type)
{

    jtag_select_xmos_tap(chip_id, chip_type);

    current_chip = chip_id;

}

int dbg_get_num_chips()
{

    return jtag_get_num_xcores();

}

int dbg_get_chip_type(int chip_id)
{

    return jtag_get_xcore_type(chip_id);

}

int dbg_get_num_cores_per_chip(int chip_id)
{

    return jtag_get_num_cores_per_xcore(chip_id);

}

int dbg_get_num_threads_per_core(int chip_id)
{

    return jtag_get_num_threads_per_xcore(chip_id);

}

int dbg_get_num_regs_per_thread(int chip_id)
{

    return jtag_get_num_regs_per_xcore_thread(chip_id);

}

void dbg_select_xcore(int xcore)
{

    switch (xcore) {

    case 0:

	current_module = DBG_XCORE0;

	current_xcore_id = 0;

	break;

    case 1:

	current_module = DBG_XCORE1;

	current_xcore_id = 1;

	break;

    case 2:

	current_module = DBG_XCORE2;

	current_xcore_id = 2;

	break;

    case 3:

	current_module = DBG_XCORE3;

	current_xcore_id = 3;

	break;

    default:

	current_module = DBG_XCORE0;

	current_xcore_id = 0;

	break;

    }

}

void dbg_speed(int divider)
{

    jtag_speed(divider);

}

#ifdef XTAG_USE_SOFT_MSEL_SRST

extern out port external_io_reset_port;

static void dbg_soft_reset() {
  unsigned int soft_reset_code_start_addr = 0x10000;
  unsigned int soft_reset_code_words = sizeof(dbg_soft_reset_code)/4;

  // Select chip 0
  dbg_select_chip(0,0);

  // Select xcore 0
  dbg_select_xcore(0);

  // Make sure tile is in dbg mode
  dbg_enter_debug_mode();

  // Load reset code into tile
  for (int i = 0; i < soft_reset_code_words; i++) {
    dbg_write_mem_word(soft_reset_code_start_addr + (i * 4), dbg_soft_reset_code[i]);
  }

  // Set PC to start of reset code
  dbg_write_core_reg(0, XS1_DBG_T_REG_PC_NUM, soft_reset_code_start_addr);

  // Disable interupts and events for return from debug mode
  dbg_write_core_reg(0, XS1_DBG_T_REG_SR_NUM, 0x0);

  // Trigger the external io reset pin
  external_io_reset_port <: 0;
  dbg_delay(100000);
  external_io_reset_port <: 1;

  // Take tile out of debug mode 
  dbg_exit_debug_mode();

  // Give the reset code some time to complete
  dbg_delay(10000000);


  return;
}
#endif

void dbg_reset(int reset_type, chanend ?reset_chan)
{
#ifdef XTAG_USE_SOFT_MSEL_SRST
    // Soft reset by loading code handled at xcore debug level not at pin level due to loading code to perform reset
    if (reset_type == XMOS_JTAG_RESET_TRST_SRST) {
      dbg_soft_reset();
      // This can go through, TRST / MSEL always wired and SRST is a nop at JTAG level
      jtag_reset(reset_type, reset_chan);
    } else if (reset_type == XMOS_JTAG_RESET_TRST) {
      // This can go through, TRST / MSEL always wired
      jtag_reset(reset_type, reset_chan);
    } else if (reset_type == XMOS_JTAG_RESET_TRST_SRST_JTAG) {
      jtag_pin_trst(0);
      dbg_soft_reset();
      jtag_pin_trst(1);
      // This can go through, soft reset only resets tap state with combined reset
      jtag_reset(reset_type, reset_chan);
    } else if (reset_type == XMOS_JTAG_RESET_TRST_DRIVE_LOW) {
      jtag_pin_trst(0);
    } else if (reset_type == XMOS_JTAG_RESET_TRST_DRIVE_HIGH) {
      jtag_pin_trst(1);
    } else {
      return;
    }
#else
    jtag_reset(reset_type, reset_chan);
#endif
}

int dbg_get_num_jtag_taps(void) {
  return jtag_get_num_taps();
}

int dbg_get_jtag_tap_id(int index) {
  return jtag_get_tap_id(index);
}

int dbg_jtag_transition(int pinvalues) {
  return jtag_pin_transition(pinvalues);
}

void dbg_jtag_pc_sample(unsigned int samples[], unsigned int &index) {
  samples[index] = jtag_read_reg(2, 0x40); 
  index++;
  samples[index] = jtag_read_reg(2, 0x41); 
  index++;
  samples[index] = jtag_read_reg(2, 0x42); 
  index++;
  samples[index] = jtag_read_reg(2, 0x43); 
  index++;
  samples[index] = jtag_read_reg(2, 0x44); 
  index++;
  samples[index] = jtag_read_reg(2, 0x45); 
  index++;
  samples[index] = jtag_read_reg(2, 0x46); 
  index++;
  samples[index] = jtag_read_reg(2, 0x47); 
  index++;
}

// Core debug mode access
void dbg_enter_debug_mode()
{

    dbg_drive_status_leds(0xa);
    jtag_write_reg(current_module, XS1_PSWITCH_DBG_INT_NUM, 1);

}

void dbg_exit_debug_mode()
{

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_INT_NUM, 0);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_COMMAND_NUM,
		   XS1_DBG_CMD_RFDBG);
    dbg_drive_status_leds(0x5);

}

int dbg_in_debug_mode()
{

    unsigned int dbg_int_reg = 0x0;

    dbg_int_reg = jtag_read_reg(current_module, XS1_PSWITCH_DBG_INT_NUM);

    if (XS1_DBG_INT_IN_DBG(dbg_int_reg) == 1) {
        dbg_drive_status_leds(0xa);
	return DBG_SUCCESS;
    }

    dbg_drive_status_leds(0x5);
    return DBG_FAILURE;

}


// Processor state access
static unsigned int dbg_read_proc_state(unsigned int res_type,
					unsigned int res_reg_id,
					unsigned int res_num)
{

    unsigned int resourceId =
	((res_type << XS1_RES_ID_TYPE_SHIFT) & XS1_RES_ID_TYPE_MASK) |
	((res_reg_id << XS1_RES_ID_REGID_SHIFT) & XS1_RES_ID_REGID_MASK) |
	((res_num << XS1_RES_ID_RESNUM_SHIFT) & XS1_RES_ID_RESNUM_MASK);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG0_NUM, resourceId);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_COMMAND_NUM,
		   (unsigned int) XS1_DBG_CMD_GETPS);

    return jtag_read_reg(current_module, XS1_PSWITCH_DBG_ARG2_NUM);

}

static void dbg_write_proc_state(unsigned int res_type,
				 unsigned int res_reg_id,
				 unsigned int res_num, unsigned int data)
{

    unsigned int resourceId =
	((res_type << XS1_RES_ID_TYPE_SHIFT) & XS1_RES_ID_TYPE_MASK) |
	((res_reg_id << XS1_RES_ID_REGID_SHIFT) & XS1_RES_ID_REGID_MASK) |
	((res_num << XS1_RES_ID_RESNUM_SHIFT) & XS1_RES_ID_RESNUM_MASK);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG0_NUM, resourceId);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG2_NUM, data);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_COMMAND_NUM,
		   (unsigned int) XS1_DBG_CMD_SETPS);

}

// Thread state access
static unsigned int dbg_read_thread_state(unsigned int thread_num,
					  unsigned int state_num)
{

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG0_NUM, thread_num);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG1_NUM, state_num);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_COMMAND_NUM,
		   (unsigned int) XS1_DBG_CMD_GETSTATE);

    return jtag_read_reg(current_module, XS1_PSWITCH_DBG_ARG2_NUM);

}

static void dbg_write_thread_state(unsigned int thread_num,
				   unsigned int state_num,
				   unsigned int data)
{

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG0_NUM, thread_num);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG1_NUM, state_num);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG2_NUM, data);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_COMMAND_NUM,
		   (unsigned int) XS1_DBG_CMD_SETSTATE);

}
int dbg_set_thread_mask(int thread_mask)
{

    int previous_mask =
	dbg_read_proc_state(XS1_RES_TYPE_PS, 0, (XS1_PS_DBG_RUN_CTRL >> 8) & 0xff);

    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, (XS1_PS_DBG_RUN_CTRL >> 8) & 0xff,
			 thread_mask);

    return previous_mask;

}


// Resource types
#define DBG_XCORE_CHANEND_RES 0
#define DBG_XCORE_OTP_RES 1
#define DBG_XCORE_CTRL_RES 2
#define DBG_XCORE_THREAD_CTRL_RES 3
#define DBG_XCORE_TIMER_CTRL_RES 4

int dbg_read_object(unsigned int objectType, unsigned int address)
{

    if (objectType == DBG_XCORE_CHANEND_RES) {

	// Must divide the passed addr by 4 to get the actual resource id.
	unsigned int resourceId = address >> 2;

	return dbg_read_proc_state(XS1_RES_TYPE_CHANEND, XS1_RES_PS_DATA,
				   XS1_RES_ID_RESNUM(resourceId));

    }

    if (objectType == DBG_XCORE_CTRL_RES) {

	// Must divide the passed addr by 4 to get the actual resource id.
	unsigned int resourceId = address >> 2;

	return dbg_read_proc_state(XS1_RES_TYPE_CHANEND, XS1_RES_PS_CTRL0,
				   XS1_RES_ID_RESNUM(resourceId));

    }

    if (objectType == DBG_XCORE_THREAD_CTRL_RES) {

	// Must divide the passed addr by 4 to get the actual resource id.
	unsigned int resourceId = address >> 2;

	return dbg_read_proc_state(XS1_RES_TYPE_THREAD, XS1_RES_PS_CTRL0,
				   XS1_RES_ID_RESNUM(resourceId));

    }

    if (objectType == DBG_XCORE_TIMER_CTRL_RES) {

	// Must divide the passed addr by 4 to get the actual resource id.
	unsigned int resourceId = address >> 2;

	return dbg_read_proc_state(XS1_RES_TYPE_TIMER, XS1_RES_PS_CTRL0,
				   XS1_RES_ID_RESNUM(resourceId));

    }

    if (objectType == DBG_XCORE_OTP_RES) {
      unsigned int otp_data = 0;
      dbg_select_chip(current_chip, 0);
      jtag_enable_serial_otp_access();
      otp_data = jtag_otp_read_word(MUX_XCORE0, address);
      dbg_select_chip(current_chip, 0);
      return otp_data;
    }

    return 0;

}

// JTAG register access
int dbg_read_jtag_reg(unsigned int address, unsigned int index, unsigned int chipmodule) {
      unsigned int value = 0;
      unsigned int current_tap = 0;

      // select JTAG tap ID based on index 0..n
      current_tap = jtag_select_tap(index);
 
      // read JTAG register from specified chip module
      value = jtag_read_reg(chipmodule, address);

      // select current chip to return state to as debugger expects
      jtag_select_tap(current_tap);

      return value;
}

int dbg_write_jtag_reg(unsigned int address, unsigned int index, unsigned int chipmodule, unsigned int data) {
      unsigned int current_tap = 0;

      // select JTAG tap ID based on index 0..n
      current_tap = jtag_select_tap(index);

      // read JTAG register from specified chip module
      jtag_write_reg(chipmodule, address, data);

      // select current chip to return state to as debugger expects
      jtag_select_tap(current_tap);

      return 0;
}

// Register access

#define NUM_GENERAL_REGS 12
#define XS1_PSWITCH_DBG_SPC_STACK_OFFSET 1
#define XS1_PSWITCH_DBG_SSR_STACK_OFFSET 2
#define XS1_PSWITCH_DBG_SED_STACK_OFFSET 3
#define XS1_PSWITCH_DBG_ET_STACK_OFFSET  4
#define XS1_PSWITCH_DBG_REG_STACK_OFFSET 5

static unsigned int dbg_register_stack_loc(unsigned int NUM)
{

    unsigned int address =
	XS1_RAM_BASE + XS1_RAM_SIZE - (XS1_DBG_BUFFER_WORDS * 4);

    if ((NUM >= 0) && (NUM < NUM_GENERAL_REGS)) {

	address += (XS1_PSWITCH_DBG_REG_STACK_OFFSET * 4) + (NUM * 4);

    } else if (NUM == XS1_DBG_T_REG_LR_NUM) {

	address +=
	    (XS1_PSWITCH_DBG_REG_STACK_OFFSET * 4) +
	    (NUM_GENERAL_REGS * 4);

    } else if (NUM == XS1_DBG_T_REG_SPC_NUM) {

	address += (XS1_PSWITCH_DBG_SPC_STACK_OFFSET * 4);

    } else if (NUM == XS1_DBG_T_REG_SSR_NUM) {

	address += (XS1_PSWITCH_DBG_SSR_STACK_OFFSET * 4);

    } else if (NUM == XS1_DBG_T_REG_SED_NUM) {

	address += (XS1_PSWITCH_DBG_SED_STACK_OFFSET * 4);

    } else if (NUM == XS1_DBG_T_REG_ET_NUM) {

	address += (XS1_PSWITCH_DBG_REG_STACK_OFFSET * 4) - 0x4;

    } else {

	address = 0;

    }

    return address;

}

int dbg_read_sys_reg(unsigned int reg_addr)
{

    return jtag_read_reg(current_module, reg_addr);

}

void dbg_write_sys_reg(unsigned int reg_addr, unsigned int data)
{

    jtag_write_reg(current_module, reg_addr, data);

}

#define XS1_PS_DBG_SPC_NUM 0x11
#define XS1_PS_DBG_SSR_NUM 0x10
#define XS1_PS_DBG_SSP_NUM 0x12

int dbg_read_core_reg(unsigned short thread, unsigned short NUM)
{

    if (thread == 0) {

	// Some register values are saved in hardware..
	if (NUM == XS1_DBG_T_REG_PC_NUM) {

	    return dbg_read_proc_state(XS1_RES_TYPE_PS, 0,
				       XS1_PS_DBG_SPC_NUM);

	} else if (NUM == XS1_DBG_T_REG_SR_NUM) {

	    return dbg_read_proc_state(XS1_RES_TYPE_PS, 0,
				       XS1_PS_DBG_SSR_NUM);

	} else if (NUM == XS1_DBG_T_REG_SP_NUM) {

	    return dbg_read_proc_state(XS1_RES_TYPE_PS, 0,
				       XS1_PS_DBG_SSP_NUM);

	} else if (NUM == XS1_DBG_T_REG_ED_NUM) {

	    return dbg_read_thread_state(thread, NUM);

	} else if (NUM == XS1_DBG_T_REG_KEP_NUM) {

	    return dbg_read_thread_state(thread, 6);

	} else if (NUM == XS1_DBG_T_REG_KSP_NUM) {

	    return dbg_read_thread_state(thread, NUM);

	} else if (NUM == XS1_DBG_T_REG_CP_NUM) {

	    return dbg_read_thread_state(thread, NUM);

	} else if (NUM == XS1_DBG_T_REG_DP_NUM) {

	    return dbg_read_thread_state(thread, NUM);

	} else if (NUM == XS1_DBG_T_REG_SED_NUM) {

	    return dbg_read_thread_state(thread, NUM);

	} else {

	    // The rest are saved by software and must be read from the debug stack.
	    unsigned int reg_stack_loc = dbg_register_stack_loc(NUM);

	    if (!reg_stack_loc)

		return DBG_FAILURE;

	    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG0_NUM,
			   reg_stack_loc);

	    jtag_write_reg(current_module, XS1_PSWITCH_DBG_COMMAND_NUM,
			   XS1_DBG_CMD_READ);

	    return jtag_read_reg(current_module, XS1_PSWITCH_DBG_ARG2_NUM);

	}

    } else {

	return dbg_read_thread_state(thread, NUM);

    }

}

void dbg_write_core_reg(unsigned short thread, unsigned short NUM,
			unsigned int data)
{

    // Special case for writing to thread 0 registers..
    if (thread == 0) {

	// Some register values are saved in hardware..
	if (NUM == XS1_DBG_T_REG_PC_NUM) {

	    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, XS1_PS_DBG_SPC_NUM, data);

	} else if (NUM == XS1_DBG_T_REG_SR_NUM) {

	    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, XS1_PS_DBG_SSR_NUM, data);

	} else if (NUM == XS1_DBG_T_REG_SP_NUM) {

	    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, XS1_PS_DBG_SSP_NUM, data);

	} else {

	    // The rest are saved by software and must be written to the debug stack.
	    unsigned int reg_stack_loc = dbg_register_stack_loc(NUM);

	    if (!reg_stack_loc)

		return;

	    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG0_NUM,
			   reg_stack_loc);

	    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG2_NUM, data);

	    jtag_write_reg(current_module, XS1_PSWITCH_DBG_COMMAND_NUM,
			   XS1_DBG_CMD_WRITE);

	}

    } else {

	dbg_write_thread_state(thread, NUM, data);

    }

}


// Memory access
unsigned int dbg_read_mem_word(unsigned int address)
{

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG0_NUM, address);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_COMMAND_NUM,
		   XS1_DBG_CMD_READ);

    return jtag_read_reg(current_module, XS1_PSWITCH_DBG_ARG2_NUM);

}

void dbg_write_mem_word(unsigned int address, unsigned int data)
{

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG0_NUM, address);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG2_NUM, data);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_COMMAND_NUM,
		   XS1_DBG_CMD_WRITE);

}

{
unsigned int, unsigned int, unsigned int,
	unsigned int} dbg_read_mem_quad(unsigned int address)
{

    unsigned int val0, val1, val2, val3;

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG0_NUM, address);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_COMMAND_NUM,
		   XS1_DBG_CMD_READ4PI);

    val0 = jtag_read_reg(current_module, XS1_PSWITCH_DBG_ARG2_NUM);

    val1 = jtag_read_reg(current_module, XS1_PSWITCH_DBG_ARG3_NUM);

    val2 = jtag_read_reg(current_module, XS1_PSWITCH_DBG_ARG4_NUM);

    val3 = jtag_read_reg(current_module, XS1_PSWITCH_DBG_ARG5_NUM);

    return {
    val0, val1, val2, val3};

}

void dbg_write_mem_quad(unsigned int address, unsigned int data[4])
{

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG0_NUM, address);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG2_NUM, data[0]);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG3_NUM, data[1]);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG4_NUM, data[2]);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_ARG5_NUM, data[3]);

    jtag_write_reg(current_module, XS1_PSWITCH_DBG_COMMAND_NUM,
		   XS1_DBG_CMD_WRITE4PI);

}

// Breakpoints

#define XS1_PS_DBG_IBREAK_CTRL_0_NUM 0x40
#define XS1_PS_DBG_IBREAK_CTRL_1_NUM 0x41
#define XS1_PS_DBG_IBREAK_CTRL_2_NUM 0x42
#define XS1_PS_DBG_IBREAK_CTRL_3_NUM 0x43

#define XS1_PS_DBG_IBREAK_ADDR_0_NUM 0x30
#define XS1_PS_DBG_IBREAK_ADDR_1_NUM 0x31
#define XS1_PS_DBG_IBREAK_ADDR_2_NUM 0x32
#define XS1_PS_DBG_IBREAK_ADDR_3_NUM 0x33

#define XS1_PS_DBG_DWATCH_CTRL_0_NUM 0x70
#define XS1_PS_DBG_DWATCH_CTRL_1_NUM 0x71
#define XS1_PS_DBG_DWATCH_CTRL_2_NUM 0x72
#define XS1_PS_DBG_DWATCH_CTRL_3_NUM 0x73

#define XS1_PS_DBG_DWATCH_ADDR1_0_NUM 0x50
#define XS1_PS_DBG_DWATCH_ADDR1_1_NUM 0x51
#define XS1_PS_DBG_DWATCH_ADDR1_2_NUM 0x52
#define XS1_PS_DBG_DWATCH_ADDR1_3_NUM 0x53

#define XS1_PS_DBG_DWATCH_ADDR2_0_NUM 0x60
#define XS1_PS_DBG_DWATCH_ADDR2_1_NUM 0x61
#define XS1_PS_DBG_DWATCH_ADDR2_2_NUM 0x62
#define XS1_PS_DBG_DWATCH_ADDR2_3_NUM 0x63

#define XS1_PS_DBG_RWATCH_CTRL_0_NUM 0x9c
#define XS1_PS_DBG_RWATCH_CTRL_1_NUM 0x9d
#define XS1_PS_DBG_RWATCH_CTRL_2_NUM 0x9e
#define XS1_PS_DBG_RWATCH_CTRL_3_NUM 0x9f

#define XS1_PS_DBG_RWATCH_ADDR1_0_NUM 0x80
#define XS1_PS_DBG_RWATCH_ADDR1_1_NUM 0x81
#define XS1_PS_DBG_RWATCH_ADDR1_2_NUM 0x82
#define XS1_PS_DBG_RWATCH_ADDR1_3_NUM 0x83

#define XS1_PS_DBG_RWATCH_ADDR2_0_NUM 0x90
#define XS1_PS_DBG_RWATCH_ADDR2_1_NUM 0x91
#define XS1_PS_DBG_RWATCH_ADDR2_2_NUM 0x92
#define XS1_PS_DBG_RWATCH_ADDR2_3_NUM 0x93

static unsigned int dbg_ibreak_crtl[4] = {
    XS1_PS_DBG_IBREAK_CTRL_0_NUM,
    XS1_PS_DBG_IBREAK_CTRL_1_NUM,
    XS1_PS_DBG_IBREAK_CTRL_2_NUM,
    XS1_PS_DBG_IBREAK_CTRL_3_NUM
};

static unsigned int dbg_ibreak_addr[4] = {
    XS1_PS_DBG_IBREAK_ADDR_0_NUM,
    XS1_PS_DBG_IBREAK_ADDR_1_NUM,
    XS1_PS_DBG_IBREAK_ADDR_2_NUM,
    XS1_PS_DBG_IBREAK_ADDR_3_NUM
};

static unsigned int dbg_dwatch_crtl[4] = {
    XS1_PS_DBG_DWATCH_CTRL_0_NUM,
    XS1_PS_DBG_DWATCH_CTRL_1_NUM,
    XS1_PS_DBG_DWATCH_CTRL_2_NUM,
    XS1_PS_DBG_DWATCH_CTRL_3_NUM
};

static unsigned int dbg_dwatch_addr1[4] = {
    XS1_PS_DBG_DWATCH_ADDR1_0_NUM,
    XS1_PS_DBG_DWATCH_ADDR1_1_NUM,
    XS1_PS_DBG_DWATCH_ADDR1_2_NUM,
    XS1_PS_DBG_DWATCH_ADDR1_3_NUM
};

static unsigned int dbg_dwatch_addr2[4] = {
    XS1_PS_DBG_DWATCH_ADDR2_0_NUM,
    XS1_PS_DBG_DWATCH_ADDR2_1_NUM,
    XS1_PS_DBG_DWATCH_ADDR2_2_NUM,
    XS1_PS_DBG_DWATCH_ADDR2_3_NUM
};

static unsigned int dbg_rwatch_crtl[4] = {
    XS1_PS_DBG_RWATCH_CTRL_0_NUM,
    XS1_PS_DBG_RWATCH_CTRL_1_NUM,
    XS1_PS_DBG_RWATCH_CTRL_2_NUM,
    XS1_PS_DBG_RWATCH_CTRL_3_NUM
};

static unsigned int dbg_rwatch_addr1[4] = {
    XS1_PS_DBG_RWATCH_ADDR1_0_NUM,
    XS1_PS_DBG_RWATCH_ADDR1_1_NUM,
    XS1_PS_DBG_RWATCH_ADDR1_2_NUM,
    XS1_PS_DBG_RWATCH_ADDR1_3_NUM
};

static unsigned int dbg_rwatch_addr2[4] = {
    XS1_PS_DBG_RWATCH_ADDR2_0_NUM,
    XS1_PS_DBG_RWATCH_ADDR2_1_NUM,
    XS1_PS_DBG_RWATCH_ADDR2_2_NUM,
    XS1_PS_DBG_RWATCH_ADDR2_3_NUM
};


// For the moment
#define MAX_CHIPS 1024
#define MAX_CORES_PER_CHIP 4

// There are 4 physical, reserve 1 for hardware stepping (id 3)
#define NUM_BREAKPOINTS 3

#define NUM_WATCHPOINTS 4

// There are 4 physical, reserve 1 for on chip storage (id 3)
#define NUM_RESOURCE_WATCHPOINTS 3

unsigned int dbg_get_step_thread(void) {
  unsigned int regValue = dbg_read_proc_state(XS1_RES_TYPE_PS, 0, XS1_PS_DBG_IBREAK_CTRL_3_NUM); 
  
  if (!regValue)
    return 0xdead;

  return clz(bitrev(regValue >> 16));
}

void dbg_set_pre_step_thread_mask(unsigned int mask) {
    // Using resource watchpoint 3 address 1 register to store thread mask
    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, XS1_PS_DBG_RWATCH_ADDR1_3_NUM, mask);
}

unsigned int dbg_get_pre_step_thread_mask(void) {
    // Using resource watchpoint 3 address 1 register to store thread mask
    return dbg_read_proc_state(XS1_RES_TYPE_PS, 0, XS1_PS_DBG_RWATCH_ADDR1_3_NUM);
}

// Using breakpoint 0;
void dbg_add_single_step_break(int thread, unsigned int pc) {
    unsigned int ibreakCtrl = ((1 << thread) << 16) | 0x3;

    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, XS1_PS_DBG_IBREAK_CTRL_3_NUM,
			 ibreakCtrl);

    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, XS1_PS_DBG_IBREAK_ADDR_3_NUM, pc);

    // Save stepping state
    dbg_set_pre_step_thread_mask(dbg_read_proc_state(XS1_RES_TYPE_PS, 0, (XS1_PS_DBG_RUN_CTRL >> 8) & 0xff));
}

void dbg_remove_single_step_break() {
    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, XS1_PS_DBG_IBREAK_CTRL_3_NUM, 0);
    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, XS1_PS_DBG_IBREAK_ADDR_3_NUM, 0);
    // Restore pre-step state
    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, (XS1_PS_DBG_RUN_CTRL >> 8) & 0xff, dbg_get_pre_step_thread_mask());
}

int dbg_hw_break_at_address(unsigned int address, unsigned int breakNum) {
    unsigned int regValue = 0;

    if (breakNum > NUM_BREAKPOINTS)
      return DBG_FAILURE;

    // Checks to see if this breakpoint exists
    regValue = dbg_read_proc_state(XS1_RES_TYPE_PS, 0, dbg_ibreak_addr[breakNum]);

    if (regValue == address)
      return DBG_SUCCESS;

    return DBG_FAILURE;
}

unsigned int dbg_add_mem_break(unsigned int address)
{
    // Finds the first un-used breakpoint..
    unsigned int ibreakCtrl = ((0xFF) << 16) | 0x1;
    unsigned int breakpointIndex = NUM_BREAKPOINTS;

    for (unsigned int breakNum = 0; breakNum < NUM_BREAKPOINTS; ++breakNum) {
      if (dbg_hw_break_at_address(0, breakNum) == DBG_SUCCESS) {
        breakpointIndex = breakNum;
        break;
      }
    }

    if (breakpointIndex == NUM_BREAKPOINTS)
      return DBG_FAILURE;

    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_ibreak_crtl[breakpointIndex], ibreakCtrl);
    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_ibreak_addr[breakpointIndex], address);

    return DBG_SUCCESS;
}

void dbg_remove_all_mem_breaks()
{
    for (unsigned int breakNum = 0; breakNum < NUM_BREAKPOINTS; ++breakNum) {
	dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_ibreak_crtl[breakNum], 0);
	dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_ibreak_addr[breakNum], 0);
    }
}

void dbg_remove_mem_break(unsigned int address)
{
    // Checks to see if this breakpoint exists
    for (unsigned int breakNum = 0; breakNum < NUM_BREAKPOINTS; ++breakNum) {
        if (dbg_hw_break_at_address(address, breakNum) == DBG_SUCCESS) {
        	dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_ibreak_crtl[breakNum], 0);
	        dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_ibreak_addr[breakNum], 0);
	}
    }
}

void dbg_disable_mem_breakpoints()
{
    for (unsigned int breakNum = 0; breakNum < NUM_BREAKPOINTS; ++breakNum) {
      dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_ibreak_crtl[breakNum], 0);
    }
}

void dbg_enable_mem_breakpoints()
{
    unsigned int ibreakCtrl = ((0xFF) << 16) | 0x1;

    for (unsigned int breakNum = 0; breakNum < NUM_BREAKPOINTS; ++breakNum) {
        // Checking for address 0 returns unset breakpoints
        if (dbg_hw_break_at_address(0, breakNum) == DBG_FAILURE) {
	    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_ibreak_crtl[breakNum], ibreakCtrl);
	}
    }
}

int dbg_hw_watchpoint_at_address(unsigned int address1, unsigned int address2, unsigned int watchpointNum)
{   
    unsigned int regValue1 = 0;
    unsigned int regValue2 = 0;

    if (watchpointNum > NUM_WATCHPOINTS)
      return DBG_FAILURE;

    // Checks to see if this watchpoint exists
    regValue1 = dbg_read_proc_state(XS1_RES_TYPE_PS, 0, dbg_dwatch_addr1[watchpointNum]);
    regValue2 = dbg_read_proc_state(XS1_RES_TYPE_PS, 0, dbg_dwatch_addr2[watchpointNum]);

    if ((regValue1 == address1) && (regValue2 == address2))
      return DBG_SUCCESS;

    return DBG_FAILURE;
}


unsigned int dbg_add_memory_watchpoint(unsigned int address1,
				       unsigned int address2,
				       enum WatchpointType watchpointType)
{

    // Finds the first un-used watchpoint..
    unsigned int watchpointIndex = NUM_WATCHPOINTS;

    unsigned int dbgWatchCtrl = ((0xFF) << 16) | 0x1;

    for (unsigned int watchNum = 0; watchNum < NUM_WATCHPOINTS; ++watchNum) {
      if (dbg_hw_watchpoint_at_address(0, 0, watchNum) == DBG_SUCCESS) {
        watchpointIndex = watchNum;
        break;
      }
    }

    if (watchpointIndex == NUM_WATCHPOINTS)
      return DBG_FAILURE;

    switch (watchpointType) {
      case WATCHPOINT_READ:
	dbgWatchCtrl |= 0x4;
	break;
      case WATCHPOINT_WRITE:
	break;
      case WATCHPOINT_ACCESS:
      default:
	return DBG_FAILURE;
	break;
    }

    dbg_write_proc_state(XS1_RES_TYPE_PS, 0,
			 dbg_dwatch_crtl[watchpointIndex], dbgWatchCtrl);

    dbg_write_proc_state(XS1_RES_TYPE_PS, 0,
			 dbg_dwatch_addr1[watchpointIndex], address1);

    dbg_write_proc_state(XS1_RES_TYPE_PS, 0,
			 dbg_dwatch_addr2[watchpointIndex], address2);

    return DBG_SUCCESS;

}

void dbg_remove_memory_watchpoint(unsigned int address1,
				  unsigned int address2,
				  enum WatchpointType watchpointType)
{
  // Checks to see if this watchpoint exists
  for (unsigned int watchNum = 0; watchNum < NUM_WATCHPOINTS; ++watchNum) {
    if (dbg_hw_watchpoint_at_address(address1, address2, watchNum) == DBG_SUCCESS) {
      dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_dwatch_crtl[watchNum], 0);
      dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_dwatch_addr1[watchNum], 0);
      dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_dwatch_addr2[watchNum], 0);
      break;
    }
  }
}

int dbg_hw_res_watchpoint_at_address(unsigned int resId, unsigned int mask, unsigned int resWatchNum)
{
    unsigned int regValue1 = 0;
    unsigned int regValue2 = 0;

    if (resWatchNum > NUM_RESOURCE_WATCHPOINTS)
      return DBG_FAILURE;

    // Checks to see if this watchpoint exists
    regValue1 = dbg_read_proc_state(XS1_RES_TYPE_PS, 0, dbg_rwatch_addr1[resWatchNum]);
    regValue2 = dbg_read_proc_state(XS1_RES_TYPE_PS, 0, dbg_rwatch_addr2[resWatchNum]);

    if ((regValue2 == resId) && (regValue1 == mask))
      return DBG_SUCCESS;

    return DBG_FAILURE;
}


unsigned int dbg_add_resource_watchpoint(unsigned int resourceId)
{
    // Finds the first un-used resource watchpoint..
    unsigned int watchpointIndex = NUM_RESOURCE_WATCHPOINTS;
    unsigned int rWatchCtrl = ((0xFF) << 16) | 0x1;

    for (unsigned int resWatchNum = 0; resWatchNum < NUM_RESOURCE_WATCHPOINTS; ++resWatchNum) {
      if (dbg_hw_res_watchpoint_at_address(0, 0, resWatchNum) == DBG_SUCCESS) {
	    watchpointIndex = resWatchNum;
	    break;
      }
    }

    if (watchpointIndex == NUM_RESOURCE_WATCHPOINTS)
	return DBG_FAILURE;

    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_rwatch_crtl[watchpointIndex], rWatchCtrl);
    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_rwatch_addr1[watchpointIndex], 0xffffffff);
    dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_rwatch_addr2[watchpointIndex], resourceId);

    return DBG_SUCCESS;
}

void dbg_remove_resource_watchpoint(unsigned int resourceId)
{
  // Checks to see if this resource watchpoint exists
  for (unsigned int resWatchNum = 0; resWatchNum < NUM_RESOURCE_WATCHPOINTS; ++resWatchNum) {
    if (dbg_hw_res_watchpoint_at_address(resourceId, 0xffffffff, resWatchNum) == DBG_SUCCESS) {
      dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_rwatch_crtl[resWatchNum], 0);
      dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_rwatch_addr1[resWatchNum], 0);
      dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_rwatch_addr2[resWatchNum], 0);
      break;
    }
  }
}

void dbg_clear_all_breakpoints()
{
    for (unsigned int breakNum = 0; breakNum < NUM_BREAKPOINTS; ++breakNum) {
      dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_ibreak_crtl[breakNum], 0);
      dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_ibreak_addr[breakNum], 0);
    }

    for (unsigned int watchNum = 0; watchNum < NUM_WATCHPOINTS; ++watchNum) {
      dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_dwatch_crtl[watchNum], 0);
      dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_dwatch_addr1[watchNum], 0);
      dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_dwatch_addr2[watchNum], 0);
    }

    for (unsigned int watchNum = 0; watchNum < NUM_RESOURCE_WATCHPOINTS; ++watchNum) {
      dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_rwatch_crtl[watchNum], 0);
      dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_rwatch_addr1[watchNum], 0);
      dbg_write_proc_state(XS1_RES_TYPE_PS, 0, dbg_rwatch_addr2[watchNum], 0);
    }
}


#if 0
bool displayMemoryBreakpoints()
{

    printf("===> Memory Breakpoints Currently Set:\n");

    for (unsigned int breakNum = 0; breakNum < NUM_BREAKPOINTS; ++breakNum)
    {

	if (s_breakpointInUse[current_chip][current_xcore_id][breakNum] ==
	    true)
	{

	    uint iBreakCtrlValue = 0;

	    if (!readProcessorState
		(XS1_RES_TYPE_PS, 0, GetDbgIBreakCtrl(breakNum),
		 &iBreakCtrlValue))
	    {

		//DEBUG_OUTPUT(printf("displayMemoryBreakpoints: ERROR!\n"); fflush(stdout);)
		return false;

	    }

	    uint address = 0;

	    if (!readProcessorState
		(XS1_RES_TYPE_PS, 0, GetDbgIBreakAddr(breakNum), &address))
	    {

		//DEBUG_OUTPUT(printf("displayMemoryBreakpoints: ERROR!\n"); fflush(stdout);)
		return false;

	    }

	    printf("%d: ctrl:0x%08x, addr:0x%08x\n", breakNum,
		   iBreakCtrlValue, address);

	}

    }

    return true;

}


bool displayMemoryWatchpoints()
{

    printf("===> Memory Watchpoints Currently Set:\n");

    for (unsigned int watchNum = 0; watchNum < NUM_WATCHPOINTS; ++watchNum)
    {

	if (s_watchpointInUse[current_chip][current_xcore_id][watchNum] ==
	    true)
	{

	    uint mWatchCtrlValue = 0;

	    if (!readProcessorState
		(XS1_RES_TYPE_PS, 0, GetDbgDWatchCtrl(watchNum),
		 &mWatchCtrlValue))
	    {

		//DEBUG_OUTPUT(printf("displayMemoryWatchpoints: ERROR!\n"); fflush(stdout);)
		return false;

	    }

	    uint mWatch1Value = 0;

	    if (!readProcessorState
		(XS1_RES_TYPE_PS, 0, GetDbgDWatchAddr1(watchNum),
		 &mWatch1Value))
	    {

		//DEBUG_OUTPUT(printf("displayMemoryWatchpoints: ERROR!\n"); fflush(stdout);)
		return false;

	    }

	    uint mWatch2Value = 0;

	    if (!readProcessorState
		(XS1_RES_TYPE_PS, 0, GetDbgDWatchAddr2(watchNum),
		 &mWatch2Value))
	    {

		//DEBUG_OUTPUT(printf("displayMemoryWatchpoints: ERROR!\n"); fflush(stdout);)
		return false;

	    }

	    printf("%d: ctrl: 0x%08x, addr1: 0x%08x, addr2: 0x%08x\n",
		   watchNum, mWatchCtrlValue, mWatch1Value, mWatch2Value);

	}

    }

    return true;

}


bool displayResourceWatchpoints()
{

    printf("===> Resource Watchpoints Currently Set:\n");

    for (unsigned int watchNum = 0; watchNum < NUM_RESOURCE_WATCHPOINTS;
	 ++watchNum)
    {

	if (s_resWatchpointInUse[current_chip][current_xcore_id][watchNum]
	    == true)
	{

	    uint rWatchCtrlValue = 0;

	    if (!readProcessorState
		(XS1_RES_TYPE_PS, 0, GetDbgRWatchCtrl(watchNum),
		 &rWatchCtrlValue))
	    {

		//DEBUG_OUTPUT(printf("displayResourceWatchpoints: ERROR!\n"); fflush(stdout);)
		return false;

	    }

	    uint rWatch1Value = 0;

	    if (!readProcessorState
		(XS1_RES_TYPE_PS, 0, GetDbgRWatchAddr1(watchNum),
		 &rWatch1Value))
	    {

		//DEBUG_OUTPUT(printf("displayResourceWatchpoints: ERROR!\n"); fflush(stdout);)
		return false;

	    }

	    uint rWatch2Value = 0;

	    if (!readProcessorState
		(XS1_RES_TYPE_PS, 0, GetDbgRWatchAddr2(watchNum),
		 &rWatch2Value))
	    {

		//DEBUG_OUTPUT(printf("displayResourceWatchpoints: ERROR!\n"); fflush(stdout);)
		return false;

	    }

	    printf("%d: ctrl: 0x%08x, addr1: 0x%08x, addr2: 0x%08x\n",
		   watchNum, rWatchCtrlValue, rWatch1Value, rWatch2Value);

	}

    }

    return true;

}


#endif				/* 
				 */

static int interrupt_step_operation = 0;

void dbg_interrupt_single_step()
{

    interrupt_step_operation = 1;

}

void dbg_wait_single_step()
{

    // Wait until the single step is complete...
    // i.e. we are back in debug mode and the pc has changed.
    unsigned int completedSingleStep = 0;


    interrupt_step_operation = 0;

    while (!completedSingleStep) {

	// Need to wait for a while here to make sure that we actually exit
	// debug mode, before checking that we have entered it again.

        dbg_delay(10000);

	completedSingleStep = dbg_in_debug_mode();

	if (interrupt_step_operation) {

	    dbg_enter_debug_mode();

	}

    }

}


{
unsigned int, unsigned int, unsigned int, unsigned int,
	unsigned int} dbg_get_stop_state()
{

    unsigned int dbg_type = 0;

    unsigned int dbg_data = 0;

    unsigned int dbg_thread = 0;

    unsigned int dbg_pc = 0;

    unsigned int dbg_thread_state = 0;

    dbg_type = dbg_read_proc_state(XS1_RES_TYPE_PS, 0, (XS1_PS_DBG_TYPE >> 8) & 0xff);

    dbg_data = dbg_read_proc_state(XS1_RES_TYPE_PS, 0, (XS1_PS_DBG_DATA >> 8) & 0xff);

    dbg_thread = XS1_DBG_TYPE_T_NUM(dbg_type);

    dbg_pc = dbg_read_core_reg(dbg_thread, XS1_DBG_T_REG_PC_NUM);

    for (int i = 0; i < dbg_get_num_threads_per_core(0); i++) {
      if (XS1_THREAD_CTRL0_INUSE (dbg_read_proc_state (XS1_RES_TYPE_THREAD, XS1_RES_PS_CTRL0, i)))
       dbg_thread_state |= 1 << i;
    }

    if (dbg_get_step_thread() == dbg_thread) {
      dbg_remove_single_step_break();
      dbg_enable_mem_breakpoints();
    }

    return {dbg_type, dbg_data, dbg_thread, dbg_pc, dbg_thread_state};

}

void dbg_init()
{

    jtag_init();

}

void dbg_deinit()
{

    jtag_deinit();

}
