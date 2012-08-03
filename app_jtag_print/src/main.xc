#include <xs1.h>
#include <platform.h>
#include <print.h>
#include <stdio.h>
#include "jtag.h"
#include "dbg_access.h"
#include <stdlib.h>


void run(void)
{
        dbg_init();
        
        printf("num JTAG taps = %d\n", jtag_get_num_taps());
        for (int i = 0; i < jtag_get_num_taps(); i++) {
            printf("JTAG TAP ID [%d] = 0x%x\n", i, jtag_get_tap_id(i));
        }
        dbg_deinit();
}

int main()
{
    run();
    return 0;
}
