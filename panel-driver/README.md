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
- The selected generated extclk mode is 120 Hz, 8 bpc, DSC slice height 32,
  and sends a standard PPS/compression-mode command.
- The current hand-written driver models a combined 1440-pixel mode and uses
  Razer-specific assumptions for 10 bpc, DSC slice height 8, and DDIC-internal
  DSC setup without standard PPS.
- Factory DTBO contains several command/video, 30/48/120 Hz and extclk
  variants. The exact boot-selected `*_extclk_cmd_10bit` variant must be
  isolated before replacing any production values.

Therefore the generated output is evidence and a clean-code starting point,
not yet an upstream-ready replacement.
