
#define XS1_SU_BASE_TAP_LEN 4
#define XS1_SU_DBG_TAP_LEN 22

void jtag_xs1_su_enable_mux(void);
void jtag_xs1_su_disable_mux(void);
unsigned int jtag_xs1_su_read_reg(unsigned int address);
unsigned int jtag_xs1_su_write_reg(unsigned int address, unsigned int value);
void jtag_xs1_su_bypass(void);
