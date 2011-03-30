// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <xs1.h>
#include <print.h>
#include "jtag.h"
#include "dbg_access.h"
#include "revbAutoDefines.h"
#include <safestring.h>

#define DBG_SSWITCH 1
#define DBG_XCORE0 2
#define DBG_XCORE1 3
#define DBG_XCORE2 4
#define DBG_XCORE3 5

#define DBG_SUCCESS 1
#define DBG_FAILURE 0

unsigned short current_xcore_id;
unsigned short current_module = DBG_XCORE0;
unsigned short current_chip = 0;

void dbg_select_chip (int chip_id) {
	jtag_select_chip(chip_id);
	current_chip = chip_id;
}

int dbg_get_num_chips() {
	return jtag_get_num_chips();
}

int dbg_get_chip_type(int chip_id) {
	return jtag_get_chip_type(chip_id);
}

int dbg_get_num_cores_per_chip(int chip_id) {
	return jtag_get_num_cores_per_chip(chip_id);
}

int dbg_get_num_threads_per_core(int chip_id) {
	return jtag_get_num_threads_per_core(chip_id);
}

int dbg_get_num_regs_per_thread(int chip_id) {
	return jtag_get_num_regs_per_thread(chip_id);
}

void dbg_select_xcore (int xcore) {
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

void dbg_speed(int divider) {
	jtag_speed(divider);
}

void dbg_chain(unsigned int jtag_devs_pre, unsigned int jtag_bits_pre,
               unsigned int jtag_devs_post, unsigned int jtag_bits_post,
               unsigned int jtag_max_speed) {

	jtag_chain(jtag_devs_pre, jtag_bits_pre, 
                   jtag_devs_post, jtag_bits_post,
                   jtag_max_speed);
}

void dbg_reset(int reset_type) {
  jtag_reset(reset_type);
}

// Core debug mode access
void dbg_enter_debug_mode() {
   jtag_write_reg(current_module, REVB_DBG_INT_REGNUM, 1);	
}

void dbg_exit_debug_mode() {
   jtag_write_reg(current_module, REVB_DBG_INT_REGNUM, 0);
   jtag_write_reg(current_module, REVB_DBG_COMMAND_REGNUM, REVB_DBG_CMD_RFDBG);
}

int dbg_in_debug_mode() {
   unsigned int dbg_int_reg = 0x0;
   dbg_int_reg = jtag_read_reg(current_module, REVB_DBG_INT_REGNUM);
   if (REVB_DBG_INT_IN_DBG(dbg_int_reg) == 1)
	   return DBG_SUCCESS;
   return DBG_FAILURE;
}

// Processor state access
static unsigned int dbg_read_proc_state(unsigned int res_type, unsigned int res_reg_id, unsigned int res_num) {
	unsigned int resourceId =
	    ((res_type << REVB_RES_ID_TYPE_SHIFT) & REVB_RES_ID_TYPE_MASK) |
	    ((res_reg_id << REVB_RES_ID_REGID_SHIFT) & REVB_RES_ID_REGID_MASK) |
	    ((res_num << REVB_RES_ID_RESNUM_SHIFT) & REVB_RES_ID_RESNUM_MASK);

	jtag_write_reg(current_module, REVB_DBG_ARG0_REG_REGNUM, resourceId);
	jtag_write_reg(current_module, REVB_DBG_COMMAND_REGNUM, (unsigned int)REVB_DBG_CMD_GETPS);

	return jtag_read_reg(current_module, REVB_DBG_ARG2_REG_REGNUM);
}

static void dbg_write_proc_state(unsigned int res_type, unsigned int res_reg_id, unsigned int res_num, unsigned int data) {
	unsigned int resourceId =
	   ((res_type << REVB_RES_ID_TYPE_SHIFT) & REVB_RES_ID_TYPE_MASK) |
	   ((res_reg_id << REVB_RES_ID_REGID_SHIFT) & REVB_RES_ID_REGID_MASK) |
	   ((res_num << REVB_RES_ID_RESNUM_SHIFT) & REVB_RES_ID_RESNUM_MASK);
	
	jtag_write_reg(current_module, REVB_DBG_ARG0_REG_REGNUM, resourceId);
	jtag_write_reg(current_module, REVB_DBG_ARG2_REG_REGNUM, data);
    jtag_write_reg(current_module, REVB_DBG_COMMAND_REGNUM, (unsigned int)REVB_DBG_CMD_SETPS);
}

// Thread state access
static unsigned int dbg_read_thread_state(unsigned int thread_num, unsigned int state_num) {
	jtag_write_reg(current_module, REVB_DBG_ARG0_REG_REGNUM, thread_num);
	jtag_write_reg(current_module, REVB_DBG_ARG1_REG_REGNUM, state_num);
	jtag_write_reg(current_module, REVB_DBG_COMMAND_REGNUM, (unsigned int)REVB_DBG_CMD_GETSTATE);
	return jtag_read_reg(current_module, REVB_DBG_ARG2_REG_REGNUM);
}

static void dbg_write_thread_state(unsigned int thread_num, unsigned int state_num, unsigned int data) {
	jtag_write_reg(current_module, REVB_DBG_ARG0_REG_REGNUM, thread_num);
    jtag_write_reg(current_module, REVB_DBG_ARG1_REG_REGNUM, state_num);
    jtag_write_reg(current_module, REVB_DBG_ARG2_REG_REGNUM, data);
	jtag_write_reg(current_module, REVB_DBG_COMMAND_REGNUM, (unsigned int)REVB_DBG_CMD_SETSTATE);
}

int dbg_set_thread_mask(int thread_mask) {
	int previous_mask = dbg_read_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_RUN_CTRL_NUM);
	dbg_write_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_RUN_CTRL_NUM, thread_mask);
	return previous_mask;
}

// Resource types
#define DBG_XCORE_CHANEND_RES 0

int dbg_read_object(unsigned int objectType, unsigned int address) {
	if (objectType == DBG_XCORE_CHANEND_RES) {
	    // Must divide the passed addr by 4 to get the actual resource id.
	    unsigned int resourceId = address >> 2;
	    return dbg_read_proc_state(REVB_RES_TYPE_CHANEND, REVB_RES_PS_DATA, REVB_RES_ID_RESNUM(resourceId));
	}
	
	return 0;
}

// Register access

#define NUM_GENERAL_REGS 12
#define REVB_DBG_SPC_STACK_OFFSET 1
#define REVB_DBG_SSR_STACK_OFFSET 2
#define REVB_DBG_SED_STACK_OFFSET 3
#define REVB_DBG_ET_STACK_OFFSET  4
#define REVB_DBG_REG_STACK_OFFSET 5

static unsigned int dbg_register_stack_loc(unsigned int regnum) {
    unsigned int address = REVB_RAM_BASE + REVB_RAM_SIZE - (REVB_DBG_BUFFER_WORDS * 4);

    if ((regnum >= 0) && (regnum < NUM_GENERAL_REGS)) {
       address += (REVB_DBG_REG_STACK_OFFSET * 4) + (regnum * 4);
    }  else if (regnum == REVB_DBG_T_REG_LR_NUM) {
      address += (REVB_DBG_REG_STACK_OFFSET * 4) + (NUM_GENERAL_REGS * 4);
    }  else if (regnum == REVB_DBG_T_REG_SPC_NUM) {
      address += (REVB_DBG_SPC_STACK_OFFSET * 4);
    }  else if (regnum == REVB_DBG_T_REG_SSR_NUM) {
      address += (REVB_DBG_SSR_STACK_OFFSET * 4);
    }  else if (regnum == REVB_DBG_T_REG_SED_NUM) {
      address += (REVB_DBG_SED_STACK_OFFSET * 4);
    }  else if (regnum == REVB_DBG_T_REG_ET_NUM) {
      address += (REVB_DBG_REG_STACK_OFFSET * 4) - 0x4;
    } else {
      address = 0;
    }
  
    return address;
}

int dbg_read_sys_reg(unsigned int reg_addr) {
	return jtag_read_reg(current_module, reg_addr);
}

void dbg_write_sys_reg(unsigned int reg_addr, unsigned int data) {
	jtag_write_reg(current_module, reg_addr, data);
}

int dbg_read_core_reg(unsigned short thread, unsigned short regnum) {
    if (thread == 0) {
        // Some register values are saved in hardware..
        if (regnum == REVB_DBG_T_REG_PC_NUM) {
	        return dbg_read_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_SPC_NUM);
        } else if (regnum  == REVB_DBG_T_REG_SR_NUM) {
	        return dbg_read_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_SSR_NUM);
	    } else if (regnum == REVB_DBG_T_REG_SP_NUM) {
	        return dbg_read_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_SSP_NUM);
	    } else if (regnum == REVB_DBG_T_REG_ED_NUM) {
	        return dbg_read_thread_state(thread, regnum);
	    } else if (regnum == REVB_DBG_T_REG_KEP_NUM) {   
		    return dbg_read_thread_state(thread, regnum);
	    } else if (regnum == REVB_DBG_T_REG_KSP_NUM) {
	        return dbg_read_thread_state(thread, regnum);
	    } else if (regnum == REVB_DBG_T_REG_CP_NUM) {
	        return dbg_read_thread_state(thread, regnum);
	    } else if (regnum == REVB_DBG_T_REG_DP_NUM) {
	        return dbg_read_thread_state(thread, regnum);
    	} else {
    	// The rest are saved by software and must be read from the debug stack.
	        unsigned int reg_stack_loc = dbg_register_stack_loc(regnum);
	  
	        if(!reg_stack_loc)
	   	        return DBG_FAILURE;
	  
	        jtag_write_reg(current_module, REVB_DBG_ARG0_REG_REGNUM, reg_stack_loc);
	        jtag_write_reg(current_module, REVB_DBG_COMMAND_REGNUM, REVB_DBG_CMD_READ);
	        return jtag_read_reg(current_module, REVB_DBG_ARG2_REG_REGNUM);
	    }
	} else {
	    return dbg_read_thread_state(thread, regnum);
	}
}

void dbg_write_core_reg(unsigned short thread, unsigned short regnum, unsigned int data) {
	// Special case for writing to thread 0 registers..
	if (thread == 0) {
	    // Some register values are saved in hardware..
	    if (regnum == REVB_DBG_T_REG_PC_NUM) {
	        dbg_write_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_SPC_NUM, data);
	    } else if (regnum == REVB_DBG_T_REG_SR_NUM) {
	        dbg_write_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_SSR_NUM, data);
	    } else if (regnum == REVB_DBG_T_REG_SP_NUM) {
	        dbg_write_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_SSP_NUM, data);
	    } else {
	    // The rest are saved by software and must be written to the debug stack.
	     	unsigned int reg_stack_loc = dbg_register_stack_loc(regnum);
	  	  	  
	    	if(!reg_stack_loc)
	    	    return;
	    	  	  
	        jtag_write_reg(current_module, REVB_DBG_ARG0_REG_REGNUM, reg_stack_loc);
	        jtag_write_reg(current_module, REVB_DBG_ARG2_REG_REGNUM, data);
	        jtag_write_reg(current_module, REVB_DBG_COMMAND_REGNUM, REVB_DBG_CMD_WRITE);
	    }
	} else {
	    dbg_write_thread_state(thread, regnum, data);
	}
}

// Memory access
unsigned int dbg_read_mem_word(unsigned int address) {
	jtag_write_reg(current_module, REVB_DBG_ARG0_REG_REGNUM, address);
	jtag_write_reg(current_module, REVB_DBG_COMMAND_REGNUM, REVB_DBG_CMD_READ);
	return jtag_read_reg(current_module, REVB_DBG_ARG2_REG_REGNUM);
}

void dbg_write_mem_word(unsigned int address, unsigned int data) {
	jtag_write_reg(current_module, REVB_DBG_ARG0_REG_REGNUM, address);
	jtag_write_reg(current_module, REVB_DBG_ARG2_REG_REGNUM, data);
	jtag_write_reg(current_module, REVB_DBG_COMMAND_REGNUM, REVB_DBG_CMD_WRITE);
}

{unsigned int, unsigned int, unsigned int, unsigned int} dbg_read_mem_quad(unsigned int address) {
	unsigned int val0, val1, val2, val3;
	jtag_write_reg(current_module, REVB_DBG_ARG0_REG_REGNUM, address);
    jtag_write_reg(current_module, REVB_DBG_COMMAND_REGNUM, REVB_DBG_CMD_READ4PI);
    val0 = jtag_read_reg(current_module, REVB_DBG_ARG2_REG_REGNUM);
    val1 = jtag_read_reg(current_module, REVB_DBG_ARG3_REG_REGNUM);
    val2 = jtag_read_reg(current_module, REVB_DBG_ARG4_REG_REGNUM);
    val3 = jtag_read_reg(current_module, REVB_DBG_ARG5_REG_REGNUM);
    return {val0, val1, val2, val3};
}

void dbg_write_mem_quad(unsigned int address, unsigned int data[4]) {
	jtag_write_reg(current_module, REVB_DBG_ARG0_REG_REGNUM, address);
    jtag_write_reg(current_module, REVB_DBG_ARG2_REG_REGNUM, data[0]);
    jtag_write_reg(current_module, REVB_DBG_ARG3_REG_REGNUM, data[1]);
    jtag_write_reg(current_module, REVB_DBG_ARG4_REG_REGNUM, data[2]);
    jtag_write_reg(current_module, REVB_DBG_ARG5_REG_REGNUM, data[3]);
    jtag_write_reg(current_module, REVB_DBG_COMMAND_REGNUM, REVB_DBG_CMD_WRITE4PI);
}

// Breakpoints
 
static unsigned int dbg_ibreak_crtl[4] = {
   REVB_PS_DBG_IBREAK_CTRL_0_NUM,
   REVB_PS_DBG_IBREAK_CTRL_1_NUM,
   REVB_PS_DBG_IBREAK_CTRL_2_NUM,
   REVB_PS_DBG_IBREAK_CTRL_3_NUM
};

static unsigned int dbg_ibreak_addr[4] = {
	REVB_PS_DBG_IBREAK_ADDR_0_NUM,
	REVB_PS_DBG_IBREAK_ADDR_1_NUM,
	REVB_PS_DBG_IBREAK_ADDR_2_NUM,
	REVB_PS_DBG_IBREAK_ADDR_3_NUM
};

static unsigned int dbg_dwatch_crtl[4] = {
	REVB_PS_DBG_DWATCH_CTRL_0_NUM,
	REVB_PS_DBG_DWATCH_CTRL_1_NUM,
	REVB_PS_DBG_DWATCH_CTRL_2_NUM,
	REVB_PS_DBG_DWATCH_CTRL_3_NUM
};

static unsigned int dbg_dwatch_addr1[4] = {
	REVB_PS_DBG_DWATCH_ADDR1_0_NUM,
	REVB_PS_DBG_DWATCH_ADDR1_1_NUM,
	REVB_PS_DBG_DWATCH_ADDR1_2_NUM,
	REVB_PS_DBG_DWATCH_ADDR1_3_NUM
};

static unsigned int dbg_dwatch_addr2[4] = {
	REVB_PS_DBG_DWATCH_ADDR2_0_NUM,
	REVB_PS_DBG_DWATCH_ADDR2_1_NUM,
	REVB_PS_DBG_DWATCH_ADDR2_2_NUM,
	REVB_PS_DBG_DWATCH_ADDR2_3_NUM
};

static unsigned int dbg_rwatch_crtl[4] = {
	REVB_PS_DBG_RWATCH_CTRL_0_NUM,
	REVB_PS_DBG_RWATCH_CTRL_1_NUM,
	REVB_PS_DBG_RWATCH_CTRL_2_NUM,
	REVB_PS_DBG_RWATCH_CTRL_3_NUM
};

static unsigned int dbg_rwatch_addr1[4] = {
	REVB_PS_DBG_RWATCH_ADDR1_0_NUM,
	REVB_PS_DBG_RWATCH_ADDR1_1_NUM,
	REVB_PS_DBG_RWATCH_ADDR1_2_NUM,
	REVB_PS_DBG_RWATCH_ADDR1_3_NUM
};

static unsigned int dbg_rwatch_addr2[4] = {
	REVB_PS_DBG_RWATCH_ADDR2_0_NUM,
	REVB_PS_DBG_RWATCH_ADDR2_1_NUM,
	REVB_PS_DBG_RWATCH_ADDR2_2_NUM,
	REVB_PS_DBG_RWATCH_ADDR2_3_NUM
};

// For the moment
#define MAX_CHIPS 16
#define MAX_CORES_PER_CHIP 4
#define NUM_BREAKPOINTS 4
#define NUM_WATCHPOINTS 4
#define NUM_RESOURCE_WATCHPOINTS 4

static unsigned int breakpointInUse[MAX_CHIPS][MAX_CORES_PER_CHIP][NUM_BREAKPOINTS];
static unsigned int savedBreakpointCtrl[MAX_CHIPS][MAX_CORES_PER_CHIP][NUM_BREAKPOINTS];
static unsigned int savedBreakpointAddr[MAX_CHIPS][MAX_CORES_PER_CHIP][NUM_BREAKPOINTS];
static unsigned int watchpointInUse[MAX_CHIPS][MAX_CORES_PER_CHIP][NUM_WATCHPOINTS];
static unsigned int resWatchpointInUse[MAX_CHIPS][MAX_CORES_PER_CHIP][NUM_RESOURCE_WATCHPOINTS];

static int coreStepped[MAX_CHIPS][MAX_CORES_PER_CHIP];
static int coreSteppedThread[MAX_CHIPS][MAX_CORES_PER_CHIP];
static unsigned int coreSteppedThreadMask[MAX_CHIPS][MAX_CORES_PER_CHIP];

void dbg_add_single_step_break(int thread, unsigned int pc) {
    unsigned int ibreakCtrl = ((1 << thread) << 16) | 0x3;
    dbg_write_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_IBREAK_CTRL_3_NUM, ibreakCtrl);
    dbg_write_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_IBREAK_ADDR_3_NUM, pc);

    // Save stepping state
    coreStepped[current_chip][current_xcore_id] = 1;
    coreSteppedThread[current_chip][current_xcore_id] = thread;
    coreSteppedThreadMask[current_chip][current_xcore_id] = dbg_read_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_RUN_CTRL_NUM);
}

void dbg_remove_single_step_break() {
    dbg_write_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_IBREAK_CTRL_3_NUM, 0);
    dbg_write_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_IBREAK_ADDR_3_NUM, 0);

    // Restore pre-step state
    coreStepped[current_chip][current_xcore_id] = 0;
    coreSteppedThread[current_chip][current_xcore_id] = -1;
    dbg_write_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_RUN_CTRL_NUM, coreSteppedThreadMask[current_chip][current_xcore_id]);
    coreSteppedThreadMask[current_chip][current_xcore_id] = 0;
}

unsigned int dbg_add_mem_break(unsigned int address) {
    // Finds the first un-used breakpoint..
    unsigned int ibreakCtrl = ((0xFF) << 16) | 0x1;
    unsigned int breakpointIndex = NUM_BREAKPOINTS;

    for (unsigned int breakNum = 0; breakNum < NUM_BREAKPOINTS; ++breakNum) {
      if (breakpointInUse[current_chip][current_xcore_id][breakNum] == 0) {
        breakpointIndex = breakNum;
        breakpointInUse[current_chip][current_xcore_id][breakNum] = 1;
        break;
      }
    }

    if (breakpointIndex == NUM_BREAKPOINTS)
      return DBG_FAILURE;

  dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_ibreak_crtl[breakpointIndex], ibreakCtrl);
  dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_ibreak_addr[breakpointIndex], address);

  return DBG_SUCCESS;
}

void dbg_remove_all_mem_breaks() {

    safememset((breakpointInUse, unsigned char[MAX_CHIPS*MAX_CORES_PER_CHIP*NUM_BREAKPOINTS*4]), 0, MAX_CHIPS*MAX_CORES_PER_CHIP*NUM_BREAKPOINTS*4);

#if 0
    for (unsigned int xcoreChip = 0; xcoreChip < MAX_CHIPS; xcoreChip++) {
      for (unsigned int xcoreNum = 0; xcoreNum < MAX_CORES_PER_CHIP; xcoreNum++) {
        for (unsigned int breakNum = 0; breakNum < NUM_BREAKPOINTS; ++breakNum) {
            dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_ibreak_crtl[breakNum], 0);
            dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_ibreak_addr[breakNum], 0);
            breakpointInUse[xcoreChip][xcoreNum][breakNum] = 0;
        }
      }
    }
#endif
}

void dbg_remove_mem_break(unsigned int address) {
    // Checks to see if this breakpoint exists
    for (unsigned int breakNum = 0; breakNum < NUM_BREAKPOINTS; ++breakNum) {
        if (breakpointInUse[current_chip][current_xcore_id][breakNum] == 1) {
            unsigned int regValue = dbg_read_proc_state(REVB_RES_TYPE_PS, 0, dbg_ibreak_addr[breakNum]);
   
            if (regValue == address) {
                dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_ibreak_crtl[breakNum], 0);
                breakpointInUse[current_chip][current_xcore_id][breakNum] = 0;
                break;
            }
        }
    }
}

void dbg_disable_mem_breakpoints() {
    for (unsigned int breakNum = 0; breakNum < NUM_BREAKPOINTS; ++breakNum) {
        if (breakpointInUse[current_chip][current_xcore_id][breakNum] == 1) {
        	savedBreakpointCtrl[current_chip][current_xcore_id][breakNum] = dbg_read_proc_state(REVB_RES_TYPE_PS, 0, dbg_ibreak_crtl[breakNum]);
        	savedBreakpointAddr[current_chip][current_xcore_id][breakNum] = dbg_read_proc_state(REVB_RES_TYPE_PS, 0, dbg_ibreak_addr[breakNum]);
        	dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_ibreak_crtl[breakNum], 0);
        	dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_ibreak_addr[breakNum], 0);   
        }
    }
}

void dbg_enable_mem_breakpoints() {
    for (unsigned int breakNum = 0; breakNum < NUM_BREAKPOINTS; ++breakNum) {
        if (breakpointInUse[current_chip][current_xcore_id][breakNum] == 1) {
            dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_ibreak_crtl[breakNum], savedBreakpointCtrl[current_chip][current_xcore_id][breakNum]);
            dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_ibreak_addr[breakNum], savedBreakpointAddr[current_chip][current_xcore_id][breakNum]); 
        }
    }
}

int dbg_is_mem_breakpoint(unsigned int address) {
    // Checks to see if this breakpoint exists
    for (unsigned int breakNum = 0; breakNum < NUM_BREAKPOINTS; ++breakNum) {
        if (breakpointInUse[current_chip][current_xcore_id][breakNum] == 1) {
            unsigned int regValue = dbg_read_proc_state(REVB_RES_TYPE_PS, 0, dbg_ibreak_addr[breakNum]);
            if (regValue == address)
              return DBG_SUCCESS;       
        }
    }
    return DBG_FAILURE;
}

unsigned int dbg_add_memory_watchpoint(unsigned int address1, unsigned int address2, enum WatchpointType watchpointType) {
    // Finds the first un-used watchpoint..
    unsigned int watchpointIndex = NUM_WATCHPOINTS;
    unsigned int dbgWatchCtrl = ((0xFF) << 16) | 0x1;
    
    for (unsigned int watchNum = 0; watchNum < NUM_WATCHPOINTS; ++watchNum) {
        if (watchpointInUse[current_chip][current_xcore_id][watchNum] == 0) {
             watchpointIndex = watchNum;
            watchpointInUse[current_chip][current_xcore_id][watchNum] = 1;
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

    dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_dwatch_crtl[watchpointIndex], dbgWatchCtrl);
    dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_dwatch_addr1[watchpointIndex], address1);
    dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_dwatch_addr2[watchpointIndex], address2);
    return DBG_SUCCESS;
}


void dbg_remove_memory_watchpoint(unsigned int address1, unsigned int address2, enum WatchpointType watchpointType) {
    // Checks to see if this watchpoint exists
    for (unsigned int watchNum = 0; watchNum < NUM_WATCHPOINTS; ++watchNum) {
        if (watchpointInUse[current_chip][current_xcore_id][watchNum] == 1) {
            unsigned int regValue1 = dbg_read_proc_state(REVB_RES_TYPE_PS, 0, dbg_dwatch_addr1[watchNum]);
            unsigned int regValue2 = dbg_read_proc_state(REVB_RES_TYPE_PS, 0, dbg_dwatch_addr2[watchNum]);

            if ((regValue1 == address1) && (regValue2 == address2)) {
                dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_dwatch_crtl[watchNum], 0);
                watchpointInUse[current_chip][current_xcore_id][watchNum] = 0;
                break;
            }
        }
    }
}

unsigned int dbg_add_resource_watchpoint(unsigned int resourceId) {
    // Finds the first un-used resource watchpoint..
    unsigned int watchpointIndex = NUM_RESOURCE_WATCHPOINTS;
    unsigned int rWatchCtrl = ((0xFF) << 16) | 0x1;
  
    for (unsigned int resWatchNum = 0; resWatchNum < NUM_RESOURCE_WATCHPOINTS; ++resWatchNum) {
        if (resWatchpointInUse[current_chip][current_xcore_id][resWatchNum] == 0) {
            watchpointIndex = resWatchNum;
            resWatchpointInUse[current_chip][current_xcore_id][resWatchNum] = 1;
            break;
        }
    }

    if (watchpointIndex == NUM_RESOURCE_WATCHPOINTS)
        return DBG_FAILURE;

    dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_rwatch_crtl[watchpointIndex], rWatchCtrl);
    dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_rwatch_addr1[watchpointIndex], 0xffffffff);
    dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_rwatch_addr2[watchpointIndex], resourceId);
  
    return DBG_SUCCESS;
}

void dbg_remove_resource_watchpoint(unsigned int resourceId) {
    // Checks to see if this resource watchpoint exists
    for (unsigned int resWatchNum = 0; resWatchNum < NUM_RESOURCE_WATCHPOINTS; ++resWatchNum) {
        if (resWatchpointInUse[current_chip][current_xcore_id][resWatchNum] == 1) {
            unsigned int regValue = dbg_read_proc_state(REVB_RES_TYPE_PS, 0, dbg_rwatch_addr2[resWatchNum]);

            if (regValue == resourceId) {
                dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_rwatch_crtl[resWatchNum], 0);
                resWatchpointInUse[current_chip][current_xcore_id][resWatchNum] = 0;
                break;
            }
        }
    }
}

void dbg_clear_all_breakpoints() {
    for (unsigned int breakNum = 0; breakNum < NUM_BREAKPOINTS; ++breakNum) {
        if (breakpointInUse[current_chip][current_xcore_id][breakNum] == 1) {
            dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_ibreak_crtl[breakNum], 0);
            breakpointInUse[current_chip][current_xcore_id][breakNum] = 0;
        }
    }
    for (unsigned int watchNum = 0; watchNum < NUM_WATCHPOINTS; ++watchNum) {
        if (watchpointInUse[current_chip][current_xcore_id][watchNum] == 1) {
            dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_dwatch_crtl[watchNum], 0);
            watchpointInUse[current_chip][current_xcore_id][watchNum] = 0;
        }
    }
    for (unsigned int watchNum = 0; watchNum < NUM_RESOURCE_WATCHPOINTS; ++watchNum) {
        if (resWatchpointInUse[current_chip][current_xcore_id][watchNum] == 1) {
            dbg_write_proc_state(REVB_RES_TYPE_PS, 0, dbg_rwatch_crtl[watchNum], 0);
            resWatchpointInUse[current_chip][current_xcore_id][watchNum] = 0;
        }
    }
}

#if 0
bool displayMemoryBreakpoints()
{
  printf("===> Memory Breakpoints Currently Set:\n");
  for (unsigned int breakNum = 0; breakNum < NUM_BREAKPOINTS; ++breakNum)
  {
    if (s_breakpointInUse[current_chip][current_xcore_id][breakNum] == true)
    {
      uint iBreakCtrlValue = 0;
      if (!readProcessorState(REVB_RES_TYPE_PS, 0, GetDbgIBreakCtrl(breakNum), &iBreakCtrlValue))
      {
        //DEBUG_OUTPUT(printf("displayMemoryBreakpoints: ERROR!\n"); fflush(stdout);)
        return false;
      }
      uint address = 0;
      if (!readProcessorState(REVB_RES_TYPE_PS, 0, GetDbgIBreakAddr(breakNum), &address))
      {
        //DEBUG_OUTPUT(printf("displayMemoryBreakpoints: ERROR!\n"); fflush(stdout);)
        return false;
      }
      printf("%d: ctrl:0x%08x, addr:0x%08x\n", breakNum, iBreakCtrlValue, address);
    }
  }
  return true;
}

bool displayMemoryWatchpoints()
{
  printf("===> Memory Watchpoints Currently Set:\n");
  for (unsigned int watchNum = 0; watchNum < NUM_WATCHPOINTS; ++watchNum)
  {
    if (s_watchpointInUse[current_chip][current_xcore_id][watchNum] == true)
    {
      uint mWatchCtrlValue = 0;
      if (!readProcessorState(REVB_RES_TYPE_PS, 0, GetDbgDWatchCtrl(watchNum), &mWatchCtrlValue))
      {
        //DEBUG_OUTPUT(printf("displayMemoryWatchpoints: ERROR!\n"); fflush(stdout);)
        return false;
      }
      uint mWatch1Value = 0;
      if (!readProcessorState(REVB_RES_TYPE_PS, 0, GetDbgDWatchAddr1(watchNum), &mWatch1Value))
      {
        //DEBUG_OUTPUT(printf("displayMemoryWatchpoints: ERROR!\n"); fflush(stdout);)
        return false;
      }
      uint mWatch2Value = 0;
      if (!readProcessorState(REVB_RES_TYPE_PS, 0, GetDbgDWatchAddr2(watchNum), &mWatch2Value))
      {
        //DEBUG_OUTPUT(printf("displayMemoryWatchpoints: ERROR!\n"); fflush(stdout);)
        return false;
      }
      printf("%d: ctrl: 0x%08x, addr1: 0x%08x, addr2: 0x%08x\n", watchNum, mWatchCtrlValue, mWatch1Value, mWatch2Value);
    }
  }
  return true;
}

bool displayResourceWatchpoints()
{
  printf("===> Resource Watchpoints Currently Set:\n");
  for (unsigned int watchNum = 0; watchNum < NUM_RESOURCE_WATCHPOINTS; ++watchNum)
  {
    if (s_resWatchpointInUse[current_chip][current_xcore_id][watchNum] == true)
    {
      uint rWatchCtrlValue = 0;
      if (!readProcessorState(REVB_RES_TYPE_PS, 0, GetDbgRWatchCtrl(watchNum), &rWatchCtrlValue))
      {
        //DEBUG_OUTPUT(printf("displayResourceWatchpoints: ERROR!\n"); fflush(stdout);)
        return false;
      }
      uint rWatch1Value = 0;
      if (!readProcessorState(REVB_RES_TYPE_PS, 0, GetDbgRWatchAddr1(watchNum), &rWatch1Value))
      {
        //DEBUG_OUTPUT(printf("displayResourceWatchpoints: ERROR!\n"); fflush(stdout);)
        return false;
      }
      uint rWatch2Value = 0;
      if (!readProcessorState(REVB_RES_TYPE_PS, 0, GetDbgRWatchAddr2(watchNum), &rWatch2Value))
      {
        //DEBUG_OUTPUT(printf("displayResourceWatchpoints: ERROR!\n"); fflush(stdout);)
        return false;
      }
      printf("%d: ctrl: 0x%08x, addr1: 0x%08x, addr2: 0x%08x\n", watchNum, rWatchCtrlValue, rWatch1Value, rWatch2Value);
    }
  }
  return true;
}
#endif

static int interrupt_step_operation = 0;
void dbg_interrupt_single_step() {
  interrupt_step_operation = 1;
}

void dbg_wait_single_step() {
    // Wait until the single step is complete...
    // i.e. we are back in debug mode and the pc has changed.
    unsigned int completedSingleStep = 0;
    unsigned s;
    unsigned timeout;
    timer tmr;
    interrupt_step_operation = 0;

    tmr :> timeout;
    
    while (!completedSingleStep) {
        // Need to wait for a while here to make sure that we actually exit
        // debug mode, before checking that we have entered it again.

    	tmr :> s;
    	tmr when timerafter(s+10000) :> s;  // 100 microseconds
        completedSingleStep = dbg_in_debug_mode();

        if (s > timeout + 100000) {
            dbg_enter_debug_mode();
        }
    }
    return;
}

{unsigned int, unsigned int, unsigned int, unsigned int, unsigned int} dbg_get_stop_state() {
	unsigned int dbg_type = 0;
	unsigned int dbg_data = 0;
	unsigned int dbg_thread = 0;
	unsigned int dbg_pc = 0;
	unsigned int dbg_thread_state = 0;
	
	dbg_type = dbg_read_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_TYPE_NUM);
	dbg_data = dbg_read_proc_state(REVB_RES_TYPE_PS, 0, REVB_PS_DBG_DATA_NUM);
	dbg_thread = REVB_DBG_TYPE_T_NUM(dbg_type);
	dbg_pc = dbg_read_core_reg(dbg_thread, REVB_DBG_T_REG_PC_NUM);
	
	for (int i = 0; i < dbg_get_num_threads_per_core(0); i++) {
	//dbg_thread_state = dbg_read_proc_state(REVB_RES_TYPE_PS, 0,
		if (REVB_THREAD_CTRL0_INUSE(dbg_read_proc_state(REVB_RES_TYPE_THREAD, REVB_RES_PS_CTRL0, i)))
			dbg_thread_state |= 1 << i;
	}

        if ((coreStepped[current_chip][current_xcore_id] != 0) && (coreSteppedThread[current_chip][current_xcore_id] == dbg_thread)) {
          dbg_remove_single_step_break();
          dbg_enable_mem_breakpoints();
        }

	return {dbg_type, dbg_data, dbg_thread, dbg_pc, dbg_thread_state};
}

void dbg_init() {
	jtag_init();
}

void dbg_deinit() {
	jtag_deinit();
}
