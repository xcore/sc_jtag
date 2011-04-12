#include "jtag_otp_access.h"
#include "jtag.h"
#include <xclib.h>

/* Test port commands. */
enum {
  TP_IDLE = 0x0,
  TP_DIRECT = 0x1,
  TP_SHIFT = 0x2,
  TP_UPDATE_MODE = 0x3,
  TP_CAPTURE = 0x4,
  TP_ROTATE = 0x5,
  TP_UPDATE_CMD = 0x6,
  TP_INC_ADDR = 0x7
};

/* Test port commands. */
static inline void update_command(int chipmodule)
{
  jtag_module_otp_write_test_port_cmd(chipmodule, TP_UPDATE_CMD);
}

static inline void update_mode(int chipmodule)
{
  jtag_module_otp_write_test_port_cmd(chipmodule, TP_UPDATE_MODE);
}

static unsigned direct_access(int chipmodule, unsigned data)
{
  jtag_module_otp_write_test_port_cmd(chipmodule, TP_DIRECT);
  return jtag_module_otp_shift_data(chipmodule, data);
}

static inline void idle(int chipmodule)
{
  jtag_module_otp_write_test_port_cmd(chipmodule, TP_IDLE);
}

static unsigned shift(int chipmodule, unsigned data)
{
  jtag_module_otp_write_test_port_cmd(chipmodule, TP_SHIFT);
  data = jtag_module_otp_shift_data(chipmodule, bitrev(data));
  return bitrev(data);
}
