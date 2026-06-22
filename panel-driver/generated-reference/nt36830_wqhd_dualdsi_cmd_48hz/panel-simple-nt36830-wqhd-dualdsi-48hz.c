// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2013, The Linux Foundation. All rights reserved.

static const struct drm_display_mode nt36830_wqhd_dualdsi_48hz_mode = {
	.clock = (720 + 20 + 8 + 12) * (2560 + 16 + 2 + 14) * 120 / 1000,
	.hdisplay = 720,
	.hsync_start = 720 + 20,
	.hsync_end = 720 + 20 + 8,
	.htotal = 720 + 20 + 8 + 12,
	.vdisplay = 2560,
	.vsync_start = 2560 + 16,
	.vsync_end = 2560 + 16 + 2,
	.vtotal = 2560 + 16 + 2 + 14,
	.width_mm = 71,
	.height_mm = 126,
	.type = DRM_MODE_TYPE_DRIVER,
};

static const struct panel_desc_dsi nt36830_wqhd_dualdsi_48hz = {
	.desc = {
		.modes = &nt36830_wqhd_dualdsi_48hz_mode,
		.num_modes = 1,
		.bpc = 8,
		.size = {
			.width = 71,
			.height = 126,
		},
		.connector_type = DRM_MODE_CONNECTOR_DSI,
	},
	.flags = MIPI_DSI_CLOCK_NON_CONTINUOUS,
	.format = MIPI_DSI_FMT_RGB888,
	.lanes = 4,
};
