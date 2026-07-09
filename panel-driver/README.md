# NT36830 panel work

The production driver is `panel-novatek-nt36830.c`. It remains experimental
and is not the default display path; current images preserve the bootloader
framebuffer for HelixScreen.

Run:

```bash
bash scripts/generate-panel-driver.sh
```

This extracts the factory `dtbo.img` and runs the pinned
`linux-mdss-dsi-panel-driver-generator`. Generated files are stored below
`generated-reference/` for review.

Important differences found during the first generation run:

- The generator models each DSI half as 720 pixels and only creates one
  `mipi_dsi_device`; the production driver must coordinate both DSI hosts.
- The factory `qcom,mdss_dsi_nt36830_wqhd_dualdsi_extclk_cmd` mode is 120 Hz,
  10 bpc, DSC slice height 8, and 8 bpp. The 8 bpc / slice height 32 values
  belong to the lower-refresh and video variants, not the main extclk command
  mode.
- The current hand-written driver models a combined 1440-pixel dual-DSI mode
  and uses the factory extclk command assumptions: 10 bpc, DSC slice height 8,
  and DDIC-internal DSC setup without standard PPS.
- Factory DTBO contains several command/video, 30/48/120 Hz and extclk
  variants. The Android display selection name may mention `10bit`, but the
  extracted DTBO node name is `qcom,mdss_dsi_nt36830_wqhd_dualdsi_extclk_cmd`;
  this node is the 10 bpc extclk command-mode source used for production
  value comparisons.

Therefore the generated output is evidence and a clean-code starting point,
not yet an upstream-ready replacement.
