// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 FIXME
// Generated with linux-mdss-dsi-panel-driver-generator from vendor device tree:
//   Copyright (c) 2014, The Linux Foundation. All rights reserved. (FIXME)

#ifndef _PANEL_NT36830_WQHD_DUALDSI_EXTCLK_CMD_H_
#define _PANEL_NT36830_WQHD_DUALDSI_EXTCLK_CMD_H_

#include <mipi_dsi.h>
#include <panel_display.h>
#include <panel.h>
#include <string.h>

static struct panel_config nt36830_wqhd_dualdsi_extclk_cmd_panel_data = {
	.panel_node_id = "qcom,mdss_dsi_nt36830_wqhd_dualdsi_extclk_cmd",
	.panel_controller = "dsi:0:",
	.panel_compatible = "qcom,mdss-dsi-panel",
	.panel_type = 1,
	.panel_destination = "DISPLAY_1",
	/* .panel_orientation not supported yet */
	.panel_framerate = 120,
	.panel_lp11_init = 0,
	.panel_init_delay = 0,
};

static struct panel_resolution nt36830_wqhd_dualdsi_extclk_cmd_panel_res = {
	.panel_width = 720,
	.panel_height = 2560,
	.hfront_porch = 20,
	.hback_porch = 12,
	.hpulse_width = 8,
	.hsync_skew = 0,
	.vfront_porch = 16,
	.vback_porch = 14,
	.vpulse_width = 2,
	/* Borders not supported yet */
};

static struct color_info nt36830_wqhd_dualdsi_extclk_cmd_color = {
	.color_format = 24,
	.color_order = DSI_RGB_SWAP_RGB,
	.underflow_color = 0xff,
	/* Borders and pixel packing not supported yet */
};

static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_0[] = {
	0xff, 0xd0, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_1[] = {
	0x75, 0x40, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_2[] = {
	0xf1, 0x40, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_3[] = {
	0xff, 0x10, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_4[] = {
	0x06, 0x00, 0x39, 0xc0, 0x2c, 0x01, 0x02, 0x04,
	0x08, 0x10, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_5[] = {
	0xff, 0xd0, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_6[] = {
	0x75, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_7[] = {
	0xf1, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_8[] = {
	0xff, 0x10, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_9[] = {
	0xfb, 0x01, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_10[] = {
	0xba, 0x03, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_11[] = {
	0xbc, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_12[] = {
	0xc0, 0x83, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_13[] = {
	0x11, 0x00, 0x39, 0xc0, 0xc1, 0xab, 0x28, 0x00,
	0x08, 0x02, 0x00, 0x02, 0x68, 0x00, 0xd5, 0x00,
	0x0a, 0x0d, 0xb7, 0x09, 0x89, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_14[] = {
	0x03, 0x00, 0x39, 0xc0, 0xc2, 0x10, 0xf0, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_15[] = {
	0xd5, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_16[] = {
	0xd6, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_17[] = {
	0xde, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_18[] = {
	0xe1, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_19[] = {
	0xe5, 0x01, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_20[] = {
	0xbb, 0x10, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_21[] = {
	0xf6, 0x71, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_22[] = {
	0xf7, 0x80, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_23[] = {
	0x05, 0x00, 0x39, 0xc0, 0xbe, 0x00, 0x10, 0x00,
	0x10, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_24[] = {
	0x35, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_25[] = {
	0xff, 0x20, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_26[] = {
	0xfb, 0x01, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_27[] = {
	0x5d, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_28[] = {
	0x5e, 0x14, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_29[] = {
	0x5f, 0xeb, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_30[] = {
	0x87, 0x02, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_31[] = {
	0x96, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_32[] = {
	0x97, 0x6d, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_33[] = {
	0x98, 0x6d, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_34[] = {
	0xae, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_35[] = {
	0xff, 0x21, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_36[] = {
	0xfb, 0x01, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_37[] = {
	0xe0, 0x24, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_38[] = {
	0x0d, 0x00, 0x39, 0xc0, 0xe1, 0x42, 0x0a, 0x86,
	0x53, 0x1b, 0x97, 0x0a, 0x86, 0x42, 0x1b, 0x97,
	0x53, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_39[] = {
	0x0d, 0x00, 0x39, 0xc0, 0xe2, 0x86, 0x42, 0x0a,
	0x97, 0x53, 0x1b, 0x0a, 0x86, 0x42, 0x1b, 0x97,
	0x53, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_40[] = {
	0xff, 0x20, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_41[] = {
	0xfb, 0x01, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_42[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb0, 0x00, 0x01, 0x00,
	0x21, 0x00, 0x43, 0x00, 0x5b, 0x00, 0x72, 0x00,
	0x83, 0x00, 0x96, 0x00, 0xa5, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_43[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb1, 0x00, 0xb2, 0x00,
	0xe1, 0x01, 0x09, 0x01, 0x4b, 0x01, 0x80, 0x01,
	0xd3, 0x02, 0x16, 0x02, 0x19, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_44[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb2, 0x02, 0x58, 0x02,
	0x9b, 0x02, 0xc4, 0x02, 0xfb, 0x03, 0x1f, 0x03,
	0x4b, 0x03, 0x5b, 0x03, 0x69, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_45[] = {
	0x0f, 0x00, 0x39, 0xc0, 0xb3, 0x03, 0x7c, 0x03,
	0x93, 0x03, 0xb7, 0x03, 0xcf, 0x03, 0xe1, 0x03,
	0xe6, 0x00, 0x00, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_46[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb4, 0x00, 0xc0, 0x00,
	0xca, 0x00, 0xd5, 0x00, 0xe0, 0x00, 0xea, 0x00,
	0xf4, 0x00, 0xfd, 0x01, 0x06, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_47[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb5, 0x01, 0x0f, 0x01,
	0x2f, 0x01, 0x4b, 0x01, 0x7b, 0x01, 0xa6, 0x01,
	0xec, 0x02, 0x28, 0x02, 0x2a, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_48[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb6, 0x02, 0x65, 0x02,
	0xa6, 0x02, 0xce, 0x03, 0x04, 0x03, 0x27, 0x03,
	0x51, 0x03, 0x62, 0x03, 0x71, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_49[] = {
	0x0f, 0x00, 0x39, 0xc0, 0xb7, 0x03, 0x86, 0x03,
	0x9e, 0x03, 0xb6, 0x03, 0xcd, 0x03, 0xdf, 0x03,
	0xe6, 0x00, 0xbf, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_50[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb8, 0x01, 0x12, 0x01,
	0x18, 0x01, 0x20, 0x01, 0x27, 0x01, 0x2e, 0x01,
	0x35, 0x01, 0x3b, 0x01, 0x42, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_51[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb9, 0x01, 0x48, 0x01,
	0x61, 0x01, 0x77, 0x01, 0x9e, 0x01, 0xc2, 0x02,
	0x00, 0x02, 0x37, 0x02, 0x39, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_52[] = {
	0x11, 0x00, 0x39, 0xc0, 0xba, 0x02, 0x71, 0x02,
	0xb0, 0x02, 0xd9, 0x03, 0x11, 0x03, 0x37, 0x03,
	0x5c, 0x03, 0x6e, 0x03, 0x81, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_53[] = {
	0x0f, 0x00, 0x39, 0xc0, 0xbb, 0x03, 0x9d, 0x03,
	0xb6, 0x03, 0xca, 0x03, 0xda, 0x03, 0xe4, 0x03,
	0xe6, 0x01, 0x11, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_54[] = {
	0xff, 0x21, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_55[] = {
	0xfb, 0x01, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_56[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb0, 0x00, 0x01, 0x00,
	0x21, 0x00, 0x43, 0x00, 0x5b, 0x00, 0x72, 0x00,
	0x83, 0x00, 0x96, 0x00, 0xa5, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_57[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb1, 0x00, 0xb2, 0x00,
	0xe1, 0x01, 0x09, 0x01, 0x4b, 0x01, 0x80, 0x01,
	0xd3, 0x02, 0x16, 0x02, 0x19, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_58[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb2, 0x02, 0x58, 0x02,
	0x9b, 0x02, 0xc4, 0x02, 0xfb, 0x03, 0x1f, 0x03,
	0x4b, 0x03, 0x5b, 0x03, 0x69, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_59[] = {
	0x0f, 0x00, 0x39, 0xc0, 0xb3, 0x03, 0x7c, 0x03,
	0x93, 0x03, 0xb7, 0x03, 0xcf, 0x03, 0xe1, 0x03,
	0xe6, 0x00, 0x00, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_60[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb4, 0x00, 0xc0, 0x00,
	0xca, 0x00, 0xd5, 0x00, 0xe0, 0x00, 0xea, 0x00,
	0xf4, 0x00, 0xfd, 0x01, 0x06, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_61[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb5, 0x01, 0x0f, 0x01,
	0x2f, 0x01, 0x4b, 0x01, 0x7b, 0x01, 0xa6, 0x01,
	0xec, 0x02, 0x28, 0x02, 0x2a, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_62[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb6, 0x02, 0x65, 0x02,
	0xa6, 0x02, 0xce, 0x03, 0x04, 0x03, 0x27, 0x03,
	0x51, 0x03, 0x62, 0x03, 0x71, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_63[] = {
	0x0f, 0x00, 0x39, 0xc0, 0xb7, 0x03, 0x86, 0x03,
	0x9e, 0x03, 0xb6, 0x03, 0xcd, 0x03, 0xdf, 0x03,
	0xe6, 0x00, 0xbf, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_64[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb8, 0x01, 0x12, 0x01,
	0x18, 0x01, 0x20, 0x01, 0x27, 0x01, 0x2e, 0x01,
	0x35, 0x01, 0x3b, 0x01, 0x42, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_65[] = {
	0x11, 0x00, 0x39, 0xc0, 0xb9, 0x01, 0x48, 0x01,
	0x61, 0x01, 0x77, 0x01, 0x9e, 0x01, 0xc2, 0x02,
	0x00, 0x02, 0x37, 0x02, 0x39, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_66[] = {
	0x11, 0x00, 0x39, 0xc0, 0xba, 0x02, 0x71, 0x02,
	0xb0, 0x02, 0xd9, 0x03, 0x11, 0x03, 0x37, 0x03,
	0x5c, 0x03, 0x6e, 0x03, 0x81, 0xff, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_67[] = {
	0x0f, 0x00, 0x39, 0xc0, 0xbb, 0x03, 0x9d, 0x03,
	0xb6, 0x03, 0xca, 0x03, 0xda, 0x03, 0xe4, 0x03,
	0xe6, 0x01, 0x11, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_68[] = {
	0xff, 0x24, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_69[] = {
	0xfb, 0x01, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_70[] = {
	0x14, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_71[] = {
	0x15, 0x10, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_72[] = {
	0x16, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_73[] = {
	0x17, 0x10, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_74[] = {
	0xb4, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_75[] = {
	0xb6, 0x30, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_76[] = {
	0x18, 0x02, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_77[] = {
	0x1b, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_78[] = {
	0x1c, 0x0e, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_79[] = {
	0x1d, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_80[] = {
	0x1e, 0x10, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_81[] = {
	0x1f, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_82[] = {
	0x22, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_83[] = {
	0x23, 0x0e, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_84[] = {
	0x24, 0x0f, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_85[] = {
	0x25, 0xa8, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_86[] = {
	0xff, 0x26, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_87[] = {
	0xfb, 0x01, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_88[] = {
	0x60, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_89[] = {
	0x62, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_90[] = {
	0x40, 0x00, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_91[] = {
	0xff, 0x28, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_92[] = {
	0xfb, 0x01, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_93[] = {
	0x91, 0x02, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_94[] = {
	0xff, 0xe0, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_95[] = {
	0xfb, 0x01, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_96[] = {
	0x48, 0x81, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_97[] = {
	0x8e, 0x09, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_98[] = {
	0xff, 0xf0, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_99[] = {
	0xfb, 0x01, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_100[] = {
	0x33, 0x20, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_101[] = {
	0x34, 0x35, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_102[] = {
	0xff, 0x23, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_103[] = {
	0xfb, 0x01, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_104[] = {
	0x06, 0x22, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_105[] = {
	0xff, 0x10, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_106[] = {
	0xfb, 0x01, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_107[] = {
	0x03, 0x00, 0x39, 0xc0, 0x51, 0x0f, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_108[] = {
	0x55, 0x03, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_109[] = {
	0x53, 0x2c, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_110[] = {
	0xb1, 0x04, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_111[] = {
	0x11, 0x00, 0x05, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_112[] = {
	0x29, 0x00, 0x05, 0x80
};

static struct mipi_dsi_cmd nt36830_wqhd_dualdsi_extclk_cmd_on_command[] = {
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_0), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_0, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_1), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_1, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_2), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_2, 10 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_3), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_3, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_4), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_4, 10 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_5), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_5, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_6), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_6, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_7), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_7, 10 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_8), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_8, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_9), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_9, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_10), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_10, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_11), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_11, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_12), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_12, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_13), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_13, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_14), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_14, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_15), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_15, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_16), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_16, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_17), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_17, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_18), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_18, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_19), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_19, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_20), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_20, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_21), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_21, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_22), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_22, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_23), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_23, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_24), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_24, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_25), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_25, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_26), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_26, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_27), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_27, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_28), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_28, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_29), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_29, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_30), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_30, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_31), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_31, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_32), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_32, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_33), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_33, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_34), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_34, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_35), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_35, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_36), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_36, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_37), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_37, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_38), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_38, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_39), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_39, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_40), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_40, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_41), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_41, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_42), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_42, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_43), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_43, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_44), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_44, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_45), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_45, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_46), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_46, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_47), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_47, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_48), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_48, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_49), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_49, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_50), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_50, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_51), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_51, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_52), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_52, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_53), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_53, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_54), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_54, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_55), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_55, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_56), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_56, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_57), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_57, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_58), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_58, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_59), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_59, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_60), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_60, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_61), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_61, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_62), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_62, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_63), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_63, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_64), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_64, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_65), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_65, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_66), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_66, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_67), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_67, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_68), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_68, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_69), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_69, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_70), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_70, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_71), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_71, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_72), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_72, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_73), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_73, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_74), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_74, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_75), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_75, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_76), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_76, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_77), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_77, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_78), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_78, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_79), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_79, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_80), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_80, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_81), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_81, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_82), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_82, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_83), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_83, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_84), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_84, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_85), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_85, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_86), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_86, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_87), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_87, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_88), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_88, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_89), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_89, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_90), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_90, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_91), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_91, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_92), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_92, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_93), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_93, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_94), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_94, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_95), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_95, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_96), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_96, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_97), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_97, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_98), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_98, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_99), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_99, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_100), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_100, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_101), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_101, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_102), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_102, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_103), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_103, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_104), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_104, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_105), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_105, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_106), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_106, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_107), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_107, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_108), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_108, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_109), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_109, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_110), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_110, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_111), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_111, 120 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_112), nt36830_wqhd_dualdsi_extclk_cmd_on_cmd_112, 0 },
};

static char nt36830_wqhd_dualdsi_extclk_cmd_off_cmd_0[] = {
	0x02, 0x00, 0x29, 0xc0, 0xff, 0x10, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_off_cmd_1[] = {
	0xfb, 0x01, 0x15, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_off_cmd_2[] = {
	0x02, 0x00, 0x29, 0xc0, 0xbc, 0x00, 0xff, 0xff
};
static char nt36830_wqhd_dualdsi_extclk_cmd_off_cmd_3[] = {
	0x28, 0x00, 0x05, 0x80
};
static char nt36830_wqhd_dualdsi_extclk_cmd_off_cmd_4[] = {
	0x10, 0x00, 0x05, 0x80
};

static struct mipi_dsi_cmd nt36830_wqhd_dualdsi_extclk_cmd_off_command[] = {
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_off_cmd_0), nt36830_wqhd_dualdsi_extclk_cmd_off_cmd_0, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_off_cmd_1), nt36830_wqhd_dualdsi_extclk_cmd_off_cmd_1, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_off_cmd_2), nt36830_wqhd_dualdsi_extclk_cmd_off_cmd_2, 0 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_off_cmd_3), nt36830_wqhd_dualdsi_extclk_cmd_off_cmd_3, 34 },
	{ sizeof(nt36830_wqhd_dualdsi_extclk_cmd_off_cmd_4), nt36830_wqhd_dualdsi_extclk_cmd_off_cmd_4, 180 },
};

static struct command_state nt36830_wqhd_dualdsi_extclk_cmd_state = {
	.oncommand_state = 1,
	.offcommand_state = 0,
};

static struct commandpanel_info nt36830_wqhd_dualdsi_extclk_cmd_command_panel = {
	/* FIXME: This is a command mode panel */
};

static struct videopanel_info nt36830_wqhd_dualdsi_extclk_cmd_video_panel = {
	.hsync_pulse = 0,
	.hfp_power_mode = 0,
	.hbp_power_mode = 0,
	.hsa_power_mode = 0,
	.bllp_eof_power_mode = 1,
	.bllp_power_mode = 1,
	.traffic_mode = 1,
	/* This is bllp_eof_power_mode and bllp_power_mode combined */
	.bllp_eof_power = 1 << 3 | 1 << 0,
};

static struct lane_configuration nt36830_wqhd_dualdsi_extclk_cmd_lane_config = {
	.dsi_lanes = 4,
	.dsi_lanemap = 0,
	.lane0_state = 1,
	.lane1_state = 1,
	.lane2_state = 1,
	.lane3_state = 1,
	.force_clk_lane_hs = 0,
};

static const uint32_t nt36830_wqhd_dualdsi_extclk_cmd_timings[] = {
	
};

static struct panel_timing nt36830_wqhd_dualdsi_extclk_cmd_timing_info = {
	.tclk_post = 0x0b,
	.tclk_pre = 0x21,
};

static struct panel_reset_sequence nt36830_wqhd_dualdsi_extclk_cmd_reset_seq = {
	.pin_state = { 1, 0, 1 },
	.sleep = { 10, 10, 10 },
	.pin_direction = 2,
};

static struct backlight nt36830_wqhd_dualdsi_extclk_cmd_backlight = {
	.bl_interface_type = BL_WLED,
	.bl_min_level = 1,
	.bl_max_level = 4095,
};

static inline void panel_nt36830_wqhd_dualdsi_extclk_cmd_select(struct panel_struct *panel,
								struct msm_panel_info *pinfo,
								struct mdss_dsi_phy_ctrl *phy_db)
{
	panel->paneldata = &nt36830_wqhd_dualdsi_extclk_cmd_panel_data;
	panel->panelres = &nt36830_wqhd_dualdsi_extclk_cmd_panel_res;
	panel->color = &nt36830_wqhd_dualdsi_extclk_cmd_color;
	panel->videopanel = &nt36830_wqhd_dualdsi_extclk_cmd_video_panel;
	panel->commandpanel = &nt36830_wqhd_dualdsi_extclk_cmd_command_panel;
	panel->state = &nt36830_wqhd_dualdsi_extclk_cmd_state;
	panel->laneconfig = &nt36830_wqhd_dualdsi_extclk_cmd_lane_config;
	panel->paneltiminginfo = &nt36830_wqhd_dualdsi_extclk_cmd_timing_info;
	panel->panelresetseq = &nt36830_wqhd_dualdsi_extclk_cmd_reset_seq;
	panel->backlightinfo = &nt36830_wqhd_dualdsi_extclk_cmd_backlight;
	pinfo->mipi.panel_on_cmds = nt36830_wqhd_dualdsi_extclk_cmd_on_command;
	pinfo->mipi.panel_off_cmds = nt36830_wqhd_dualdsi_extclk_cmd_off_command;
	pinfo->mipi.num_of_panel_on_cmds = ARRAY_SIZE(nt36830_wqhd_dualdsi_extclk_cmd_on_command);
	pinfo->mipi.num_of_panel_off_cmds = ARRAY_SIZE(nt36830_wqhd_dualdsi_extclk_cmd_off_command);
	memcpy(phy_db->timing, nt36830_wqhd_dualdsi_extclk_cmd_timings, TIMING_SIZE);
	phy_db->regulator_mode = DSI_PHY_REGULATOR_DCDC_MODE;
}

#endif /* _PANEL_NT36830_WQHD_DUALDSI_EXTCLK_CMD_H_ */
