// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 FIXME
// Generated with linux-mdss-dsi-panel-driver-generator from vendor device tree:
//   Copyright (c) 2013, The Linux Foundation. All rights reserved. (FIXME)

#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>

#include <video/mipi_display.h>

#include <drm/display/drm_dsc.h>
#include <drm/display/drm_dsc_helper.h>
#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>
#include <drm/drm_probe_helper.h>

struct nt36830_wqhd_dualdsi_30hz {
	struct drm_panel panel;
	struct mipi_dsi_device *dsi;
	struct drm_dsc_config dsc;
	struct gpio_desc *reset_gpio;
};

static inline
struct nt36830_wqhd_dualdsi_30hz *to_nt36830_wqhd_dualdsi_30hz(struct drm_panel *panel)
{
	return container_of_const(panel, struct nt36830_wqhd_dualdsi_30hz, panel);
}

static void nt36830_wqhd_dualdsi_30hz_reset(struct nt36830_wqhd_dualdsi_30hz *ctx)
{
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	usleep_range(10000, 11000);
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	usleep_range(10000, 11000);
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	usleep_range(10000, 11000);
}

static int nt36830_wqhd_dualdsi_30hz_on(struct nt36830_wqhd_dualdsi_30hz *ctx)
{
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = ctx->dsi };

	ctx->dsi->mode_flags &= ~MIPI_DSI_MODE_LPM;

	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0xd0);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x75, 0x40);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xf1, 0x40);
	mipi_dsi_usleep_range(&dsi_ctx, 10000, 11000);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x10);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_WRITE_MEMORY_START,
				     0x01, 0x02, 0x04, 0x08, 0x10);
	mipi_dsi_usleep_range(&dsi_ctx, 10000, 11000);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0xd0);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x75, 0x00);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xf1, 0x00);
	mipi_dsi_usleep_range(&dsi_ctx, 10000, 11000);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x10);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xfb, 0x01);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xba, 0x03);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xbc, 0x08);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xc0, 0x83);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xc1,
				     0x89, 0x28, 0x00, 0x20, 0x02, 0x00, 0x02,
				     0x68, 0x03, 0x87, 0x00, 0x0a, 0x03, 0x19,
				     0x02, 0x63);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xc2, 0x10, 0xf0);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xd5, 0x00);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xd6, 0x00);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xde, 0x00);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xe1, 0x00);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xe5, 0x01);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xbb, 0x13);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xf6, 0x70);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xf7, 0x80);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xbe, 0x00, 0x10, 0x00, 0x10);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x20);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xfb, 0x01);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x87, 0x02);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x5d, 0x00);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_SET_CABC_MIN_BRIGHTNESS,
				     0x14);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x5f, 0xeb);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x26);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xfb, 0x01);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x60, 0x00);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x62, 0x03);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_SET_VSYNC_TIMING, 0x00);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x28);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xfb, 0x01);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x91, 0x02);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0xe0);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xfb, 0x01);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x48, 0x81);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x8e, 0x09);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0xf0);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xfb, 0x01);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x33, 0x20);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x34, 0x35);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x23);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xfb, 0x01);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x06, 0x22);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x24);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xfb, 0x01);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xb4, 0x00);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xb6, 0x30);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x10);
	mipi_dsi_dcs_set_display_brightness_multi(&dsi_ctx, 0xffff);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_WRITE_POWER_SAVE, 0x01);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_WRITE_CONTROL_DISPLAY,
				     0x2c);
	mipi_dsi_dcs_exit_sleep_mode_multi(&dsi_ctx);
	mipi_dsi_msleep(&dsi_ctx, 120);
	mipi_dsi_dcs_set_display_on_multi(&dsi_ctx);

	return dsi_ctx.accum_err;
}

static int nt36830_wqhd_dualdsi_30hz_off(struct nt36830_wqhd_dualdsi_30hz *ctx)
{
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = ctx->dsi };

	ctx->dsi->mode_flags |= MIPI_DSI_MODE_LPM;

	mipi_dsi_generic_write_seq_multi(&dsi_ctx, 0xff, 0x10);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, 0xbc, 0x00);
	mipi_dsi_dcs_set_display_off_multi(&dsi_ctx);
	mipi_dsi_msleep(&dsi_ctx, 34);
	mipi_dsi_dcs_enter_sleep_mode_multi(&dsi_ctx);
	mipi_dsi_msleep(&dsi_ctx, 180);

	return dsi_ctx.accum_err;
}

static int nt36830_wqhd_dualdsi_30hz_prepare(struct drm_panel *panel)
{
	struct nt36830_wqhd_dualdsi_30hz *ctx = to_nt36830_wqhd_dualdsi_30hz(panel);
	struct device *dev = &ctx->dsi->dev;
	struct drm_dsc_picture_parameter_set pps;
	int ret;

	nt36830_wqhd_dualdsi_30hz_reset(ctx);

	ret = nt36830_wqhd_dualdsi_30hz_on(ctx);
	if (ret < 0) {
		dev_err(dev, "Failed to initialize panel: %d\n", ret);
		gpiod_set_value_cansleep(ctx->reset_gpio, 1);
		return ret;
	}

	drm_dsc_pps_payload_pack(&pps, &ctx->dsc);

	ret = mipi_dsi_picture_parameter_set(ctx->dsi, &pps);
	if (ret < 0) {
		dev_err(panel->dev, "failed to transmit PPS: %d\n", ret);
		return ret;
	}

	ret = mipi_dsi_compression_mode(ctx->dsi, true);
	if (ret < 0) {
		dev_err(dev, "failed to enable compression mode: %d\n", ret);
		return ret;
	}

	msleep(28); /* TODO: Is this panel-dependent? */

	return 0;
}

static int nt36830_wqhd_dualdsi_30hz_unprepare(struct drm_panel *panel)
{
	struct nt36830_wqhd_dualdsi_30hz *ctx = to_nt36830_wqhd_dualdsi_30hz(panel);
	struct device *dev = &ctx->dsi->dev;
	int ret;

	ret = nt36830_wqhd_dualdsi_30hz_off(ctx);
	if (ret < 0)
		dev_err(dev, "Failed to un-initialize panel: %d\n", ret);

	gpiod_set_value_cansleep(ctx->reset_gpio, 1);

	return 0;
}

static const struct drm_display_mode nt36830_wqhd_dualdsi_30hz_mode = {
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

static int nt36830_wqhd_dualdsi_30hz_get_modes(struct drm_panel *panel,
					       struct drm_connector *connector)
{
	return drm_connector_helper_get_modes_fixed(connector, &nt36830_wqhd_dualdsi_30hz_mode);
}

static const struct drm_panel_funcs nt36830_wqhd_dualdsi_30hz_panel_funcs = {
	.prepare = nt36830_wqhd_dualdsi_30hz_prepare,
	.unprepare = nt36830_wqhd_dualdsi_30hz_unprepare,
	.get_modes = nt36830_wqhd_dualdsi_30hz_get_modes,
};

static int nt36830_wqhd_dualdsi_30hz_probe(struct mipi_dsi_device *dsi)
{
	struct device *dev = &dsi->dev;
	struct nt36830_wqhd_dualdsi_30hz *ctx;
	int ret;

	ctx = devm_drm_panel_alloc(dev, struct nt36830_wqhd_dualdsi_30hz, panel,
				   &nt36830_wqhd_dualdsi_30hz_panel_funcs,
				   DRM_MODE_CONNECTOR_DSI);
	if (IS_ERR(ctx))
		return PTR_ERR(ctx);

	ctx->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(ctx->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->reset_gpio),
				     "Failed to get reset-gpios\n");

	ctx->dsi = dsi;
	mipi_dsi_set_drvdata(dsi, ctx);

	dsi->lanes = 4;
	dsi->format = MIPI_DSI_FMT_RGB888;
	dsi->mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_CLOCK_NON_CONTINUOUS;

	ctx->panel.prepare_prev_first = true;

	ret = drm_panel_of_backlight(&ctx->panel);
	if (ret)
		return dev_err_probe(dev, ret, "Failed to get backlight\n");

	drm_panel_add(&ctx->panel);

	/* This panel only supports DSC; unconditionally enable it */
	dsi->dsc = &ctx->dsc;

	ctx->dsc.dsc_version_major = 1;
	ctx->dsc.dsc_version_minor = 1;

	/* TODO: Pass slice_per_pkt = 1 */
	ctx->dsc.slice_height = 32;
	ctx->dsc.slice_width = 720;
	/*
	 * TODO: hdisplay should be read from the selected mode once
	 * it is passed back to drm_panel (in prepare?)
	 */
	WARN_ON(720 % ctx->dsc.slice_width);
	ctx->dsc.slice_count = 720 / ctx->dsc.slice_width;
	ctx->dsc.bits_per_component = 8;
	ctx->dsc.bits_per_pixel = 8 << 4; /* 4 fractional bits */
	ctx->dsc.block_pred_enable = true;

	ret = mipi_dsi_attach(dsi);
	if (ret < 0) {
		drm_panel_remove(&ctx->panel);
		return dev_err_probe(dev, ret, "Failed to attach to DSI host\n");
	}

	return 0;
}

static void nt36830_wqhd_dualdsi_30hz_remove(struct mipi_dsi_device *dsi)
{
	struct nt36830_wqhd_dualdsi_30hz *ctx = mipi_dsi_get_drvdata(dsi);
	int ret;

	ret = mipi_dsi_detach(dsi);
	if (ret < 0)
		dev_err(&dsi->dev, "Failed to detach from DSI host: %d\n", ret);

	drm_panel_remove(&ctx->panel);
}

static const struct of_device_id nt36830_wqhd_dualdsi_30hz_of_match[] = {
	{ .compatible = "mdss,nt36830-wqhd-dualdsi-30hz" }, // FIXME
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, nt36830_wqhd_dualdsi_30hz_of_match);

static struct mipi_dsi_driver nt36830_wqhd_dualdsi_30hz_driver = {
	.probe = nt36830_wqhd_dualdsi_30hz_probe,
	.remove = nt36830_wqhd_dualdsi_30hz_remove,
	.driver = {
		.name = "panel-nt36830-wqhd-dualdsi-30hz",
		.of_match_table = nt36830_wqhd_dualdsi_30hz_of_match,
	},
};
module_mipi_dsi_driver(nt36830_wqhd_dualdsi_30hz_driver);

MODULE_AUTHOR("linux-mdss-dsi-panel-driver-generator <fix@me>"); // FIXME
MODULE_DESCRIPTION("DRM driver for NT36830 dual dsi video mode 30hz panel with DSC");
MODULE_LICENSE("GPL");
