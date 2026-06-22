#!/usr/bin/env python3
import sys

kconfig_path = sys.argv[1]
content = open(kconfig_path).read()

old = "depends on BACKLIGHT_CLASS_DEVICE\n\thelp\n\t  Say Y or M here if you want to enable support for the NovaTeK\n\t  NT36830"
new = "depends on BACKLIGHT_CLASS_DEVICE\n\tselect DRM_DISPLAY_HELPER\n\tselect DRM_DISPLAY_DSC_HELPER\n\thelp\n\t  Say Y or M here if you want to enable support for the NovaTeK\n\t  NT36830"

if old in content:
    content = content.replace(old, new)
    open(kconfig_path, 'w').write(content)
    print("Kconfig patched with select statements")
else:
    print("Pattern not found or already patched")
