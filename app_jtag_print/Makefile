# The TARGET variable determines what target system the application is 
# compiled for. It either refers to an XN file in the source directories
# or a valid argument for the --target option when compiling.


# The APP_NAME variable determines the name of the final .xe file. It should
# not include the .xe postfix. If left blank the name will default to 
# the project name
APP_NAME = app_jtag

SOURCE_DIRS = src/*
INCLUDE_DIRS = src/*

# The flags passed to xcc when building the application
# You can also set the following to override flags for a particular language:
#
#    XCC_XC_FLAGS, XCC_C_FLAGS, XCC_ASM_FLAGS, XCC_CPP_FLAGS
#
# If the variable XCC_MAP_FLAGS is set it overrides the flags passed to 
# xcc for the final link (mapping) stage.

BUILD_FLAGS = -D G1 -O1 -g -Wall -fsubword-select -Wno-timing -Xmapper --show-report 


#U8
XCC_FLAGS_u8 = $(BUILD_FLAGS) -D XTAG_U_SERIES -D XTAG_USE_COMBINED_MSEL_SRST -D XTAG_SUPPORTS_ADC_SCOPE -D XUD_ON_U_SERIES
INCLUDE_ONLY_IN_u8 = 

#L series 
XCC_FLAGS_l = $(BUILD_FLAGS) -DXUD_SERIES_SUPPORT=2 
INCLUDE_ONLY_IN_l = 

# The USED_MODULES variable lists other module used by the application. 
USED_MODULES = module_jtag_master module_xcore_debug module_jtag_otp_access module_xs1_su_debug

#ifeq ($(CONFIG), u8) 
	TARGET = XS1-U16A-128-FB217-C10
	MODULE_LIBRARIES = xud_u 
#endif

ifeq ($(CONFIG), l) 
	TARGET = xtag2_with_xscope.xn
	MODULE_LIBRARIES = xud_l 
endif

#=============================================================================
#=============================================================================
# The following part of the Makefile includes the common build infrastructure
# for compiling XMOS applications. You should not need to edit below here.

XMOS_MAKE_PATH ?= ../..
ifneq ($(wildcard $(XMOS_MAKE_PATH)/xcommon/module_xcommon/build/Makefile.common),)
include $(XMOS_MAKE_PATH)/xcommon/module_xcommon/build/Makefile.common
else
include ../module_xcommon/build/Makefile.common
endif

=======
# Use the main Makefile from module_xmos_common
XMOS_MAKE_PATH ?= ../..
include $(XMOS_MAKE_PATH)/xcommon/module_xcommon/build/Makefile.common
