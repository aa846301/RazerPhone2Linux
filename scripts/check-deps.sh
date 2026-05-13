#!/bin/bash
cd ~/razorphone2linux/kernel/linux
for f in \
    include/dt-bindings/arm/qcom,ids.h \
    include/dt-bindings/leds/common.h \
    include/dt-bindings/pinctrl/qcom,pmic-gpio.h \
    include/dt-bindings/regulator/qcom,rpmh-regulator.h \
    include/dt-bindings/sound/qcom,q6afe.h \
    include/dt-bindings/sound/qcom,q6asm.h \
    arch/arm64/boot/dts/qcom/sdm845-wcd9340.dtsi \
    arch/arm64/boot/dts/qcom/pm8998.dtsi \
    arch/arm64/boot/dts/qcom/pmi8998.dtsi
do
    if [ -f "$f" ]; then
        echo "OK: $f"
    else
        echo "MISSING: $f"
    fi
done
