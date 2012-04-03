#ifndef DBG_ACCESS_H_
#define DBG_ACCESS_H_

void dbg_init();

void dbg_deinit();

void dbg_select_chip(int chip_id, int chip_type);

int dbg_get_num_chips();

int dbg_get_num_jtag_taps(void);

int dbg_get_jtag_tap_id(int index);

int dbg_get_chip_type(int chip_id);

int dbg_get_num_cores_per_chip(int chip_id);

int dbg_get_num_threads_per_core(int chip_id);

int dbg_get_num_regs_per_thread(int chip_id);

void dbg_select_xcore(int xcore);

void dbg_speed(int divider);

void dbg_reset(int reset_type);

{
unsigned int, unsigned int, unsigned int, unsigned int,
	unsigned int} dbg_get_stop_state();

// Core debug mode access
void dbg_enter_debug_mode();

void dbg_exit_debug_mode();

int dbg_in_debug_mode();

// Memory access
unsigned int dbg_read_mem_word(unsigned int address);

void dbg_write_mem_word(unsigned int address, unsigned int data);

{
unsigned int, unsigned int, unsigned int,
	unsigned int} dbg_read_mem_quad(unsigned int address);

void dbg_write_mem_quad(unsigned int address, unsigned int data[4]);

// Register access
int dbg_read_sys_reg(unsigned int reg_addr);

void dbg_write_sys_reg(unsigned int reg_addr, unsigned int data);

int dbg_read_core_reg(unsigned short thread, unsigned short regnum);

void dbg_write_core_reg(unsigned short thread, unsigned short regnum,
			unsigned int data);

// Resource access
int dbg_read_object(unsigned int objectType, unsigned int address);
int dbg_write_object(unsigned int objectType, unsigned int address, unsigned int data);

int dbg_read_jtag_reg(unsigned int address, unsigned int index, unsigned int chipmodule);
int dbg_write_jtag_reg(unsigned int address, unsigned int index, unsigned int chipmodule, unsigned int data);

// Core stepping
void dbg_add_single_step_break(int thread, unsigned int pc);

void dbg_remove_single_step_break();

void dbg_wait_single_step();

void dbg_interrupt_single_step();

// Breakpoints
enum WatchpointType {
    WATCHPOINT_READ,
    WATCHPOINT_WRITE,
    WATCHPOINT_ACCESS
};

int dbg_set_thread_mask(int thread_mask);

unsigned int dbg_add_mem_break(unsigned int address);

void dbg_remove_mem_break(unsigned int address);

void dbg_remove_all_mem_breaks();

void dbg_disable_mem_breakpoints();

void dbg_enable_mem_breakpoints();

int dbg_is_mem_breakpoint(unsigned int address);

unsigned int dbg_add_memory_watchpoint(unsigned int address1,
				       unsigned int address2,
				       enum WatchpointType watchpointType);

void dbg_remove_memory_watchpoint(unsigned int address1,
				  unsigned int address2,
				  enum WatchpointType watchpointType);

unsigned int dbg_add_resource_watchpoint(unsigned int resourceId);

void dbg_remove_resource_watchpoint(unsigned int resourceId);

void dbg_clear_all_breakpoints();

#endif				/*DBG_ACCESS_H_ */
