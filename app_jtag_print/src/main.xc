#include <xs1.h>
#include <platform.h>
#include <print.h>
#include <stdio.h>
#include "jtag.h"
#include "dbg_access.h"
#include <stdlib.h>


void run(void)
{
    while (1) {
        dbg_init();
        
        printf("num JTAG taps = %d\n", jtag_get_num_taps());
        for (int i = 0; i < jtag_get_num_taps(); i++) {
            printf("JTAG TAP ID [%d] = 0x%x\n", i, jtag_get_tap_id(i));
        }
        jtag_select_xmos_tap(0, 0);
        for (int i = 0; i < 8; i++) {
            printf("SSWITCH XLINK %d = 0x%x\n", i, jtag_read_reg(MUX_SSWITCH, 0x80 + i));
        }
        for (int i = 0; i < 8; i++) {
            printf("THREAD %d PC = 0x%x\n", i, jtag_read_reg(MUX_XCORE0, 64 + i));
        }

        dbg_deinit();
    }

}

int main()
{
    run();
    return 0;
}
