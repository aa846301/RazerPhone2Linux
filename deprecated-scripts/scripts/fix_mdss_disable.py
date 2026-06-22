#!/usr/bin/env python3
import re

path = '/home/dinochang/razorphone2linux/dts/sdm845-razer-aura.dts'
with open(path, 'rb') as f:
    content = f.read().decode('utf-8')

nodes = ['&mdss', '&mdss_mdp', '&mdss_dsi0', '&mdss_dsi0_phy', '&mdss_dsi1', '&mdss_dsi1_phy']
for node in nodes:
    pattern = re.compile(r'(' + re.escape(node) + r'[^{]*\{[^\n]*\n\t)status = "okay";')
    before = content
    content = pattern.sub(r'\1status = "disabled";', content)
    print(f'{node}: {"OK" if content != before else "NOT FOUND"}')

with open(path, 'wb') as f:
    f.write(content.encode('utf-8'))
print('Done')
