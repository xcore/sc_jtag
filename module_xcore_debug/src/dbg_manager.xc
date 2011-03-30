#include <xs1.h>
#include "dbg_cmd.h"
#include "dbg_access.h"
#include <print.h>
#include <safestring.h>

#define XTAG2_FIRMWARE_TYPE 10
#define XTAG2_FIRMWARE_MAJOR_VER 2
#define XTAG2_FIRMWARE_MINOR_VER 0

static dbg_cmd_packet dbg_cmd;
static dbg_cmd_packet dbg_cmd_ret;

static int dbg_total_cores = 0;
static int dbg_current_xcore = 0;
static int dbg_current_thread = 0;

static void dbg_select_core_and_thread(int xcore, int thread) {	
  if (xcore != dbg_current_xcore || xcore != -1) {
    // TODO Will not currently support mixed G1 / G4 systems
    int selected_chip = xcore >> (dbg_get_num_cores_per_chip(0) >> 1);
    int mapped_xcore = xcore % dbg_get_num_cores_per_chip(0);
    dbg_select_chip(selected_chip);
    dbg_select_xcore(mapped_xcore);
    dbg_current_xcore = xcore;
  }
	
  if (thread != dbg_current_thread || xcore != -1) {
    dbg_current_thread = thread;
  }
}

int dbg_cmd_connect(dbg_cmd_type_connect &connect) {
	int data_index = 0;
	int ret_packet_len = 0;
	int num_chips = 0;
	
	// Needs to return
        // NUM_CHIPS
	// NUM_CHIPS * CHIP_TYPES
	// NUM_CHIPS * NUM_CORES_PER_CHIP
	// NUM_CHIPS * NUM_THREADS_PER_CORE
	// NUM_CHIPS * NUM_REGS_PER_THREAD
 
        // printintln(connect.jtag_speed);

        if (connect.jtag_speed != -1) {
          dbg_speed(connect.jtag_speed);
        }
 
        dbg_chain(connect.jtag_devs_pre, connect.jtag_bits_pre,
                  connect.jtag_devs_post, connect.jtag_bits_post,
                  connect.jtag_max_speed);

	dbg_init();
	
	dbg_total_cores = 0;
	
	num_chips = dbg_get_num_chips();

	dbg_cmd_ret.data[data_index] = num_chips;
	data_index++;
	
	for (int i = 0; i < num_chips; i++) {
          dbg_cmd_ret.data[data_index] = dbg_get_chip_type(i);
	  data_index++;
	}
	
	for (int i = 0; i < num_chips; i++) {
	  dbg_cmd_ret.data[data_index] = dbg_get_num_cores_per_chip(i);
	  dbg_total_cores += dbg_cmd_ret.data[data_index];
	  data_index++;
        } 
	
	for (int i = 0; i < num_chips; i++) {
	  dbg_cmd_ret.data[data_index] = dbg_get_num_threads_per_core(i);
	  data_index++;
	}
	
	for (int i = 0; i < num_chips; i++) {
	  dbg_cmd_ret.data[data_index] = dbg_get_num_regs_per_thread(i);
	  data_index++;
	}
	
	dbg_remove_all_mem_breaks();
	
	dbg_cmd_ret.type = DBG_CMD_CONNECT_ACK;
	
	// Just send the whole lot
	ret_packet_len = sizeof(dbg_cmd_ret);

	return ret_packet_len;
}

int dbg_cmd_disconnect(dbg_cmd_type_disconnect &disconnect) {
	int ret_packet_len = 0;
	
	// TODO needs to clean up multi-chip / multi-core
	
	dbg_remove_all_mem_breaks();
	
	dbg_total_cores = 0;
	
	dbg_deinit();
	
	dbg_cmd_ret.type = DBG_CMD_DISCONNECT_ACK;
	ret_packet_len += 4;
	
	return ret_packet_len;
}

int dbg_cmd_get_core_state(dbg_cmd_type_get_core_state &get_state) {
	int ret_packet_len = 0;
	
	dbg_select_core_and_thread(get_state.xcore, dbg_current_thread);
	
	// Returns
	// DBG_TYPE 
	// DBG_DATA
	// DBG_THREAD
	// DBG_PC
	// ENABLED_THREAD_MASK
	
	{dbg_cmd_ret.data[0], dbg_cmd_ret.data[1], dbg_cmd_ret.data[2], dbg_cmd_ret.data[3], dbg_cmd_ret.data[4]} = dbg_get_stop_state();
	ret_packet_len += 20;
	
	dbg_cmd_ret.type = DBG_CMD_GET_CORE_STATE_ACK;
	ret_packet_len += 4;

	return ret_packet_len;
}

int dbg_cmd_enable_thread(dbg_cmd_type_enable_thread &enable_thread) {
	int ret_packet_len = 0;
		
	dbg_cmd_ret.type = DBG_CMD_ENABLE_THREAD_ACK;
	ret_packet_len += 4;
		
	return ret_packet_len;	
}

int dbg_cmd_disable_thread(dbg_cmd_type_disable_thread &disable_thread) {
	int ret_packet_len = 0;
		
	dbg_cmd_ret.type = DBG_CMD_DISABLE_THREAD_ACK;
	ret_packet_len += 4;
		
	return ret_packet_len;	
}

int dbg_cmd_read_regs(dbg_cmd_type_read_regs &read_regs) {
	int ret_packet_len = 0;
    int thread = 0;
    int reg = 0;
    int num_threads = dbg_get_num_threads_per_core(0);
    int num_regs = dbg_get_num_regs_per_thread(0);
    
    dbg_select_core_and_thread(read_regs.xcore, dbg_current_thread);
    
    // 512 Byte max USB transfer size
    if (read_regs.upper_block) {
    	thread = 4;
    }

    //printintln(thread);
    //printintln(read_regs.thread_mask);

    for (int i = 0; i < (num_threads / 2); i++) {
        if (read_regs.thread_mask & (1 << (i + thread))) {
            for (reg = 0; reg < num_regs; reg++) {
              dbg_cmd_ret.data[((i*num_regs)+reg)] = dbg_read_core_reg(i + thread, reg);
            }
        }  
    }
    
    ret_packet_len += (num_threads/2)*num_regs*4; // Total size of all registers

	dbg_cmd_ret.type = DBG_CMD_READ_REGS_ACK;
	ret_packet_len += 4;

    // should be 352 + 4
		
	return ret_packet_len;	
}

int dbg_cmd_write_regs(dbg_cmd_type_write_regs &write_regs) {
	int ret_packet_len = 0;
	int reg = 0;
	int num_threads = dbg_get_num_threads_per_core(0);
	int num_regs = dbg_get_num_regs_per_thread(0);
	
	dbg_select_core_and_thread(write_regs.xcore, dbg_current_thread);
	
	// Currently only doing 1 thread at a time register writes
#if 0
	// 512 Byte max USB transfer size
	if (write_regs.upper_block) {
	    thread = 4;
	}
#endif

	for (int i = 0; i < num_threads; i++) {
		if (write_regs.thread_mask & (1 << i)) {
	        for (reg = 0; reg < num_regs; reg++) {
	            dbg_write_core_reg(i, reg, write_regs.data[reg]);
	        }  
		}
	}	
		
	dbg_cmd_ret.type = DBG_CMD_WRITE_REGS_ACK;
	ret_packet_len += 4;
		
	return ret_packet_len;	
}

int dbg_cmd_read_mem(dbg_cmd_type_read_mem &read_mem) {
	int ret_packet_len = 0;
	unsigned int num_words = (read_mem.len >> 2) + 1;
	unsigned int num_quads = (num_words * 4) >> 4;
	unsigned int byte_offset = read_mem.addr & 3;
	unsigned int aligned_address = read_mem.addr & ~3;
	unsigned int i = 0;
	unsigned int data_index = 0;
	
	dbg_select_core_and_thread(read_mem.xcore, dbg_current_thread);
	
	if (byte_offset) {
	    unsigned int word_1 = dbg_read_mem_word(aligned_address);
	    unsigned int word_2 = 0;
	    unsigned int bit_offset = byte_offset * 8;
	    aligned_address += 4;
	    
	    //printintln(num_words);

	    for (i = 0; i < num_words; i++) {
	      word_2 = dbg_read_mem_word(aligned_address);
	      //printhexln(word_1); printhexln(word_2);
	      dbg_cmd_ret.data[data_index] = word_1 >> bit_offset | word_2 << (32 - bit_offset);
	      aligned_address += 4;
	      word_1 = word_2;
	      data_index++;
	    }
	  } else {
	    // Do quad words
	    for (i = 0; i < num_quads; i++) {
	      {dbg_cmd_ret.data[data_index], dbg_cmd_ret.data[data_index+1], dbg_cmd_ret.data[data_index+2], dbg_cmd_ret.data[data_index+3]} = dbg_read_mem_quad(aligned_address);
	      aligned_address += 16;
	      data_index += 4;
	    }

	    num_words -= num_quads * 4;

	    for (i = 0; i < num_words; i++) {
	      dbg_cmd_ret.data[data_index] = dbg_read_mem_word(aligned_address);
	      aligned_address += 4;
	      data_index++;
	    }
	  }
	
	ret_packet_len = read_mem.len;
#if 0
	if (read_mem.len < 4) {
	    ret_packet_len = 4; // Pad to word
	} else {
		ret_packet_len = read_mem.len;
	}
#endif
			
	dbg_cmd_ret.type = DBG_CMD_READ_MEM_ACK;
	ret_packet_len += 4;
		
	return ret_packet_len;	
}

int dbg_cmd_write_mem(dbg_cmd_type_write_mem &write_mem) {
	int ret_packet_len = 0;	
	unsigned int num_words = 0;
	unsigned int num_quads = 0;
	unsigned int first_address = write_mem.addr & ~3;
	unsigned int first_word = dbg_read_mem_word(first_address);
	unsigned int last_address = (write_mem.addr + write_mem.len) & ~3;
	unsigned int byte_offset = write_mem.addr & 3;
	unsigned char buffer[(MAX_DBG_CMD_DATA_LEN * 4) + 8];
	unsigned int index = 0;
	
	dbg_select_core_and_thread(write_mem.xcore, dbg_current_thread);
	
    //(buffer, unsigned int) = first_word; 
	
	//TODO possible to optimize for aligned writes
	
	buffer[0] = first_word;
	buffer[1] = first_word >> 8;
	buffer[2] = first_word >> 16;
	buffer[3] = first_word >> 24;

	if (first_address != last_address) {
		unsigned int last_offset = last_address - first_address;
		unsigned int last_word = dbg_read_mem_word(last_address);
		buffer[last_offset] = last_word;
		buffer[last_offset + 1] = last_word >> 8;
		buffer[last_offset + 2] = last_word >> 16;
		buffer[last_offset + 3] = last_word >> 24;
	}

	for (int i = 0; i < write_mem.len; i++) {
		buffer[i + byte_offset] = (write_mem.data, unsigned char [])[i];
	}

	num_words = ((last_address - first_address) >> 2) + 1;
	num_quads = num_words >> 2;

	for (int i = 0; i < num_quads; i++) {
		unsigned int quad[4];
		quad[0] = (buffer, unsigned int [])[index];
		quad[1] = (buffer, unsigned int [])[index + 1];
		quad[2] = (buffer, unsigned int [])[index + 2];
		quad[3] = (buffer, unsigned int [])[index + 3];
		dbg_write_mem_quad(first_address, quad);
		index += 4;
		first_address+=16;
	}

	num_words -= num_quads * 4;

	for (int i = 0; i < num_words; i++) {
		dbg_write_mem_word(first_address, (buffer, unsigned int [])[index]);
		first_address+=4;
		index++;
	}

	dbg_cmd_ret.type = DBG_CMD_WRITE_MEM_ACK;
	ret_packet_len += 4;
		
	return ret_packet_len;
	
}

#if 0
int dbg_cmd_write_mem(dbg_cmd_type_write_mem &write_mem) {
	int ret_packet_len = 0;
	unsigned int num_words = write_mem.len >> 2;
	unsigned int remainder = write_mem.len - (num_words * 4);
	unsigned int num_quads = (num_words * 4) >> 4;
	unsigned int byte_offset = write_mem.addr & 3;
	unsigned int aligned_address = write_mem.addr & ~3;
	unsigned int i = 0;
	unsigned int data_index = 0;
		
	if (byte_offset) {
	    unsigned int word_1 = dbg_read_mem_word(aligned_address);
	    unsigned int word_2 = 0;
	    unsigned int bit_offset = byte_offset * 8;
	    unsigned int remaining = write_mem.len;
	    unsigned int num_words_remaining = 0;
	    
	    // Do first word always
	    word_1 = dbg_read_mem_word(aligned_address);
	    word_2 = write_mem.data[data_index];
	    //printstrln("First");
	    //printhexln(word_1); printhexln(word_2);
	    dbg_write_mem_word(aligned_address, (word_1 >> (32 - bit_offset) | word_2 << bit_offset));
	    if (4 - byte_offset > remaining) {
	      remaining = 0;
	    } else {
	      remaining -= (4 - byte_offset);
	    }
	    aligned_address += 4;
	    data_index++;
	    word_1 = word_2;
	   
	    //printintln(remaining);
	    num_words_remaining = remaining >> 2;
	    
	    for (i = 0; i < num_words_remaining; i++) {
	       word_2 = write_mem.data[data_index];
	       //printstrln("Words");
	       //printhexln(word_1); printhexln(word_2);
	       dbg_write_mem_word(aligned_address, (word_1 >> (32 - bit_offset) | word_2 << bit_offset));
	       aligned_address += 4;
	       word_1 = word_2;
	       data_index++;
	       remaining -= 4;
	  	}
	   // printintln(remaining);
	    
	    if (remaining) {
	      //printstrln("remaining");
	      word_2 = dbg_read_mem_word(aligned_address);
	      word_1 = word_1 & (0xffffffff >> (32 - (remaining * 8)));
	      word_2 <<= (remaining * 8);
	      //printhexln(word_1); printhexln(word_2);
	      dbg_write_mem_word(aligned_address, (word_1 | word_2));
	    }
	    
    } else {
		// Do quad words
		for (i = 0; i < num_quads; i++) {
		   unsigned int quad[4];
		   quad[0] = write_mem.data[data_index];
		   quad[1] = write_mem.data[data_index+1]; 
		   quad[2] = write_mem.data[data_index+2]; 
		   quad[3] = write_mem.data[data_index+3]; 
		   dbg_write_mem_quad(aligned_address, quad);
		   aligned_address += 16;
		   data_index += 4;
		}

		num_words -= num_quads * 4;
		
		for (i = 0; i < num_words; i++) {
		    dbg_write_mem_word(aligned_address, write_mem.data[data_index]);
		    aligned_address += 4;
		    data_index++;
		}
		
		if (remainder) {
			unsigned int remainder_word_read = dbg_read_mem_word(aligned_address) & (0xffffffff << (remainder * 8));
			unsigned int remainder_word_write = write_mem.data[data_index] & (0xffffffff >> 32 - (remainder * 8));
			dbg_write_mem_word(aligned_address, remainder_word_write | remainder_word_read);
		}
    }
		
	dbg_cmd_ret.type = DBG_CMD_WRITE_MEM_ACK;
	ret_packet_len += 4;
		
	return ret_packet_len;	
}
#endif

int dbg_cmd_read_obj(dbg_cmd_type_read_obj &read_obj) {
	int ret_packet_len = 0;
	
	dbg_select_core_and_thread(read_obj.xcore, dbg_current_thread);
	
	dbg_cmd_ret.data[0] = dbg_read_object(read_obj.type, read_obj.address);
	ret_packet_len += 4;
		
	dbg_cmd_ret.type = DBG_CMD_READ_OBJ_ACK;
	ret_packet_len += 4;
		
	return ret_packet_len;	
}

int dbg_cmd_step(dbg_cmd_type_step &step) {
	int ret_packet_len = 0;
	
	dbg_select_core_and_thread(step.xcore, step.thread);
	
        if (!step.allcores) {
          dbg_disable_mem_breakpoints();
        }

	dbg_add_single_step_break(step.thread, dbg_read_core_reg(step.thread, 16));

        if (step.allcores) {
          for (int i = 0; i < dbg_total_cores; i++) {
            dbg_select_core_and_thread(i, dbg_current_thread);
            dbg_exit_debug_mode();
          }
        } else {
          // Mask in active thread
	  dbg_set_thread_mask(~(1 << step.thread));
          dbg_exit_debug_mode();
        }  

	dbg_cmd_ret.type = DBG_CMD_STEP_ACK;
	ret_packet_len += 4;
		
	return ret_packet_len;	
}

int dbg_cmd_continue(dbg_cmd_type_continue &cont) {
	int ret_packet_len = 0;

	if (cont.xcore == -1) {
	    for (int i = 0; i < dbg_total_cores; i++) {
		    dbg_select_core_and_thread(i, dbg_current_thread);
		    dbg_exit_debug_mode();
	    }
	} else { 
	  dbg_select_core_and_thread(cont.xcore, dbg_current_thread);
	  dbg_exit_debug_mode();
	}
		
	dbg_cmd_ret.type = DBG_CMD_CONTINUE_ACK;
	ret_packet_len += 4;

	return ret_packet_len;	
}

int dbg_cmd_add_break(dbg_cmd_type_add_break &add_break) {
	int ret_packet_len = 0;
	
	dbg_select_core_and_thread(add_break.xcore, add_break.thread);
	
	switch (add_break.type) {
	    case DBG_MEM_BREAK:
		    dbg_add_mem_break(add_break.address);
	        break;
	    case DBG_W_WATCH_BREAK:
	    	dbg_add_memory_watchpoint(add_break.address, add_break.address+add_break.length, WATCHPOINT_WRITE);   
	        break;
	    case DBG_R_WATCH_BREAK:
		    dbg_add_memory_watchpoint(add_break.address, add_break.address+add_break.length, WATCHPOINT_READ);   
            break; 
	    case DBG_RES_WATCH_BREAK:
	    	dbg_add_resource_watchpoint(add_break.address);
	        break;
	}
	
	dbg_cmd_ret.type = DBG_CMD_ADD_BREAK_ACK;
	ret_packet_len += 4;
		
	return ret_packet_len;	
}

int dbg_cmd_remove_break(dbg_cmd_type_remove_break &remove_break) {
	int ret_packet_len = 0;
	
	dbg_select_core_and_thread(remove_break.xcore, remove_break.thread);
	
	switch (remove_break.type) {
		case DBG_MEM_BREAK:
		    dbg_remove_mem_break(remove_break.address);
		    break;
        case DBG_W_WATCH_BREAK:
		   	dbg_remove_memory_watchpoint(remove_break.address, remove_break.address+remove_break.length, WATCHPOINT_WRITE);   
		    break;
		case DBG_R_WATCH_BREAK:
		    dbg_remove_memory_watchpoint(remove_break.address, remove_break.address+remove_break.length, WATCHPOINT_READ);   
	        break; 
		case DBG_RES_WATCH_BREAK:
		   	dbg_remove_resource_watchpoint(remove_break.address);
		    break;
	}
		
	dbg_cmd_ret.type = DBG_CMD_REMOVE_BREAK_ACK;
	ret_packet_len += 4;
		
	return ret_packet_len;	
}

int dbg_cmd_get_status(dbg_cmd_type_get_status &get_status) {
	int ret_packet_len = 0;
	int num_cores_stopped = 0;
	int in_debug_mode = 0;
	
	// Check for any cores in debug mode
	for (int i = 0; i < dbg_total_cores; i++) {
	   dbg_select_core_and_thread(i, dbg_current_thread);
	   in_debug_mode = dbg_in_debug_mode();
	   
	   if (in_debug_mode) {
	     num_cores_stopped++;
	     dbg_cmd_ret.data[num_cores_stopped] = i;
	   }
	   ret_packet_len += 4;
	}
	
	dbg_cmd_ret.data[0] = num_cores_stopped;
        ret_packet_len += 4;
		
	dbg_cmd_ret.type = DBG_CMD_GET_STATUS_ACK;
	ret_packet_len += 4;
		
	return ret_packet_len;	
}

int dbg_cmd_interrupt(dbg_cmd_type_interrupt &interrupt) {
	int ret_packet_len = 0;

	if (interrupt.xcore == -1) {
        for (int i = 0; i < dbg_total_cores; i++) {
        	//printstrln("INTERRUPT");
			dbg_select_core_and_thread(i, dbg_current_thread);
			dbg_enter_debug_mode();
		}
    } else { 
    	dbg_select_core_and_thread(interrupt.xcore, dbg_current_thread);
        dbg_enter_debug_mode();
    }
		
	dbg_cmd_ret.type = DBG_CMD_INTERRUPT_ACK;
	ret_packet_len += 4;
		
	return ret_packet_len;	
}

int dbg_cmd_reset(dbg_cmd_type_reset &reset, chanend ?reset_chan) {
	int ret_packet_len = 0;

        if (reset.type == 64) {
          // Post application load reset - resync xlinks
          outuchar(reset_chan, 2);
          outct(reset_chan, 1);
          chkct(reset_chan, 1);
        } else {
          outuchar(reset_chan, 1);
          outct(reset_chan, 1);
          chkct(reset_chan, 1);
	
  	  dbg_select_core_and_thread(reset.xcore, dbg_current_thread);
	
	  dbg_reset(reset.type);

	  dbg_cmd_ret.type = DBG_CMD_RESET_ACK;
	  ret_packet_len += 4;

          outuchar(reset_chan, 0);
          outct(reset_chan, 1);
          chkct(reset_chan, 1);
        }
		
	return ret_packet_len;	
}

int dbg_cmd_firmware_version(dbg_cmd_type_firmware_version &firmware_version) {
	int ret_packet_len = 0;
		
	dbg_cmd_ret.type = DBG_CMD_FIRMWARE_VERSION_ACK;
	ret_packet_len += 4;
        dbg_cmd_ret.data[0] = XTAG2_FIRMWARE_TYPE;
	ret_packet_len += 4;
        dbg_cmd_ret.data[1] = XTAG2_FIRMWARE_MAJOR_VER;
	ret_packet_len += 4;
        dbg_cmd_ret.data[2] = XTAG2_FIRMWARE_MINOR_VER;
	ret_packet_len += 4;
		
	return ret_packet_len;	
}

int dbg_cmd_firmware_reboot(dbg_cmd_type_firmware_reboot &firmware_reboot) {
	int ret_packet_len = 0;
		
	dbg_cmd_ret.type = DBG_CMD_FIRMWARE_REBOOT_ACK;
	ret_packet_len += 4;

        // End of current firmware!
		
	return ret_packet_len;	
}

void dbg_cmd_manager(chanend input, chanend output, chanend reset) {
	
	while (1) {
		unsigned int dbg_cmd_len = 0;
		
	    // DATA IN FROM HOST
		input :> dbg_cmd_len;
		input :> dbg_cmd.type;
		
		dbg_cmd_len -= 4;
		for (int i = 0; i < dbg_cmd_len >> 2; i++) {
		   input :> dbg_cmd.data[i];
		}

		switch (dbg_cmd.type) {
		case DBG_CMD_CONNECT_REQ:
			dbg_cmd_len = dbg_cmd_connect((dbg_cmd.data, dbg_cmd_type_connect));
			break;
		case DBG_CMD_DISCONNECT_REQ:
			dbg_cmd_len = dbg_cmd_disconnect((dbg_cmd.data, dbg_cmd_type_disconnect));
			break;
		case DBG_CMD_GET_CORE_STATE_REQ:
			dbg_cmd_len = dbg_cmd_get_core_state((dbg_cmd.data, dbg_cmd_type_get_core_state));
			break;
		case DBG_CMD_ENABLE_THREAD_REQ:
			dbg_cmd_len = dbg_cmd_enable_thread((dbg_cmd.data, dbg_cmd_type_enable_thread));
			break;
		case DBG_CMD_DISABLE_THREAD_REQ:
			dbg_cmd_len = dbg_cmd_disable_thread((dbg_cmd.data, dbg_cmd_type_disable_thread));
		    break;
		case DBG_CMD_READ_REGS_REQ:
			dbg_cmd_len = dbg_cmd_read_regs((dbg_cmd.data, dbg_cmd_type_read_regs));
			break;
		case DBG_CMD_WRITE_REGS_REQ:
			dbg_cmd_len = dbg_cmd_write_regs((dbg_cmd.data, dbg_cmd_type_write_regs));
			break;
		case DBG_CMD_READ_MEM_REQ:
			dbg_cmd_len = dbg_cmd_read_mem((dbg_cmd.data, dbg_cmd_type_read_mem));
			break;
		case DBG_CMD_WRITE_MEM_REQ:
			dbg_cmd_len = dbg_cmd_write_mem((dbg_cmd.data, dbg_cmd_type_write_mem));
			break;
		case DBG_CMD_READ_OBJ_REQ:
			dbg_cmd_len = dbg_cmd_read_obj((dbg_cmd.data, dbg_cmd_type_read_obj));
			break;
		case DBG_CMD_STEP_REQ:
			dbg_cmd_len = dbg_cmd_step((dbg_cmd.data, dbg_cmd_type_step));
			break;
		case DBG_CMD_CONTINUE_REQ:
			dbg_cmd_len = dbg_cmd_continue((dbg_cmd.data, dbg_cmd_type_continue));
			break;
		case DBG_CMD_ADD_BREAK_REQ:
			dbg_cmd_len = dbg_cmd_add_break((dbg_cmd.data, dbg_cmd_type_add_break));
			break;
		case DBG_CMD_REMOVE_BREAK_REQ:
			dbg_cmd_len = dbg_cmd_remove_break((dbg_cmd.data, dbg_cmd_type_remove_break));
			break;
		case DBG_CMD_GET_STATUS_REQ:
			dbg_cmd_len = dbg_cmd_get_status((dbg_cmd.data, dbg_cmd_type_get_status));
			break;
		case DBG_CMD_INTERRUPT_REQ:
			dbg_cmd_len = dbg_cmd_interrupt((dbg_cmd.data, dbg_cmd_type_interrupt));
			break;
		case DBG_CMD_RESET_REQ:
			dbg_cmd_len = dbg_cmd_reset((dbg_cmd.data, dbg_cmd_type_reset), reset);
			break;
#if 0
                case DBG_CMD_FIRMWARE_VERSION_REQ:
                        dbg_cmd_len = dbg_cmd_firmware_version((dbg_cmd.data, dbg_cmd_type_firmware_version));
                        break;
                case DBG_CMD_FIRMWARE_REBOOT_REQ:
                        dbg_cmd_len = dbg_cmd_firmware_reboot((dbg_cmd.data, dbg_cmd_type_firmware_reboot));
                        break;
#endif
		default:
			break;
		}
		
		// DATA OUT TO HOST

		output <: dbg_cmd_len;
		output <: dbg_cmd_ret.type;
		dbg_cmd_len -= 4;
		for (int i = 0; i < dbg_cmd_len >> 2; i++) {
		    output <: dbg_cmd_ret.data[i];
		}
	}
}

void dbg_cmd_manager_nochan(int input_size, int input[], int &output_size, int output[], chanend reset) {
                unsigned int dbg_cmd_len = 0;
 
                dbg_cmd.type = input[0];
                for (int i = 1; i < (input_size >> 2); i++) {
                   dbg_cmd.data[i-1] = input[i];
                }

                switch (dbg_cmd.type) {
                case DBG_CMD_CONNECT_REQ:
                        dbg_cmd_len = dbg_cmd_connect((dbg_cmd.data, dbg_cmd_type_connect));
                        break;
                case DBG_CMD_DISCONNECT_REQ:
                        dbg_cmd_len = dbg_cmd_disconnect((dbg_cmd.data, dbg_cmd_type_disconnect));
                        break;
                case DBG_CMD_GET_CORE_STATE_REQ:
                        dbg_cmd_len = dbg_cmd_get_core_state((dbg_cmd.data, dbg_cmd_type_get_core_state));
                        break;
                case DBG_CMD_ENABLE_THREAD_REQ:
                        dbg_cmd_len = dbg_cmd_enable_thread((dbg_cmd.data, dbg_cmd_type_enable_thread));
                        break;
                case DBG_CMD_DISABLE_THREAD_REQ:
                        dbg_cmd_len = dbg_cmd_disable_thread((dbg_cmd.data, dbg_cmd_type_disable_thread));
                    break;
                case DBG_CMD_READ_REGS_REQ: 
                        dbg_cmd_len = dbg_cmd_read_regs((dbg_cmd.data, dbg_cmd_type_read_regs));
                        break;
                case DBG_CMD_WRITE_REGS_REQ:
                        dbg_cmd_len = dbg_cmd_write_regs((dbg_cmd.data, dbg_cmd_type_write_regs));
                        break;
                case DBG_CMD_READ_MEM_REQ:
                        dbg_cmd_len = dbg_cmd_read_mem((dbg_cmd.data, dbg_cmd_type_read_mem));
                        break;
                case DBG_CMD_WRITE_MEM_REQ:
                        dbg_cmd_len = dbg_cmd_write_mem((dbg_cmd.data, dbg_cmd_type_write_mem));
                        break;
                case DBG_CMD_READ_OBJ_REQ:
                        dbg_cmd_len = dbg_cmd_read_obj((dbg_cmd.data, dbg_cmd_type_read_obj));
                        break;
                case DBG_CMD_STEP_REQ:
                        dbg_cmd_len = dbg_cmd_step((dbg_cmd.data, dbg_cmd_type_step));
                        break;
                case DBG_CMD_CONTINUE_REQ:
                        dbg_cmd_len = dbg_cmd_continue((dbg_cmd.data, dbg_cmd_type_continue));
                        break;
                case DBG_CMD_ADD_BREAK_REQ:
                        dbg_cmd_len = dbg_cmd_add_break((dbg_cmd.data, dbg_cmd_type_add_break));
                        break;
                case DBG_CMD_REMOVE_BREAK_REQ:
                        dbg_cmd_len = dbg_cmd_remove_break((dbg_cmd.data, dbg_cmd_type_remove_break));
                        break;
                case DBG_CMD_GET_STATUS_REQ:
                        dbg_cmd_len = dbg_cmd_get_status((dbg_cmd.data, dbg_cmd_type_get_status));
                        break;
                case DBG_CMD_INTERRUPT_REQ:
                        dbg_cmd_len = dbg_cmd_interrupt((dbg_cmd.data, dbg_cmd_type_interrupt));
                        break;
                case DBG_CMD_RESET_REQ:
                        dbg_cmd_len = dbg_cmd_reset((dbg_cmd.data, dbg_cmd_type_reset), reset);
                        break;
#if 0
                case DBG_CMD_FIRMWARE_VERSION_REQ:
                        dbg_cmd_len = dbg_cmd_firmware_version((dbg_cmd.data, dbg_cmd_type_firmware_version));
                        break;
                case DBG_CMD_FIRMWARE_REBOOT_REQ:
                        dbg_cmd_len = dbg_cmd_firmware_reboot((dbg_cmd.data, dbg_cmd_type_firmware_reboot));
                        break;
#endif
                default:
                        break;
                }

                output_size = dbg_cmd_len;
                output[0] = dbg_cmd_ret.type;
                //dbg_cmd_len -= 4;
                for (int i = 1; i < (dbg_cmd_len >> 2); i++) {
                    output[i] = dbg_cmd_ret.data[i-1];
                }
}
