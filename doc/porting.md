Porting to a new device
{{hint|If you get stuck or need assistance, you can join our [[Matrix and IRC|Matrix/IRC]] chats (use the ''{{Matrix channel|#porting:postmarketos.org}}''/''{{IRC channel|#postmarketos-porting}}'' channel for porting questions).}}

This page is a step-by-step guide to porting postmarketOS to a new device.

The main steps are:
* Prepare your device for flashing by [[Unlocking Bootloaders|unlocking the bootloader]];
* Set up [[pmbootstrap]], the postmarketOS development tool, on your computer;
* Create the device-specific packages for your device
** If using a vendor (downstream) device-specific kernel, rather than a shared [[(Close to) Mainline|(close to) mainline]] kernel for the SoC, add the package for it
* Compile the kernel package for your device (and add any patches necessary for it to compile);
* Install the system and test your port;
* Create a wiki page for your device;
* Submit the device-specific packages to pmaports so that other people can use them.

{{warning|Please use a spare device! You won't be able to use some features right now, such as making calls, sending text messages, or using Bluetooth. There is no guarantee that you won't break your device.}}

== Introduction ==

In postmarketOS, device support is contained within '''device-specific packages'''. These packages are as follows (replace <code>''vendor''</code> and <code>''codename''</code> with your device's vendor/codename:

* <code>'''device'''-''vendor''-''codename''</code> - referred to as the '''device package'''. This package contains metadata related to the device, and is what allows it to show up in the device list in <code>pmbootstrap init</code>. In particular, it contains:
** The <code>'''deviceinfo'''</code> file, which stores general device settings (model name/codename, screen size, flashing method, etc.);
** Optionally, '''configuration files''' that get installed to the system, which are required to get various features working, e.g. udev config files for various peripherals or ALSA UCM configurations for sound
* <code>'''linux'''-''vendor''-''codename''</code> - referred to as the device-specific '''kernel package'''. This is what builds the Linux kernel and applies any patches necessary to get it to build/work.
** Devices running close-to mainline kernels usually use a '''shared kernel package''' for an SoC (<code>linux-postmarketos-...</code>).
* <code>'''firmware'''-''vendor''-''codename''</code> - firmware blobs necessary for some components to work. This package is not necessary for an initial port, but it's often needed to get e.g. WiFi and Bluetooth working.

Like other pmOS packages, the package build files (in Alpine Linux's <code>APKBUILD</code> format) are stored in the [https://gitlab.postmarketos.org/postmarketOS/pmaports pmaports] repository - in particular, device packages are placed under <code>device/{category}</code>, where <code>{category}</code> is the category (main/community/testing/downstream/archived).

[[pmbootstrap]], the postmarketOS build/development tool, can generate a basic device package and kernel package - however, some manual modifications are still needed to make them complete.

This guide covers the entire porting process, from generating the packages, to getting them to build, all the way to upstreaming your work to pmaports.

<!--
Note to self, when we revamp porting process: mention that the pmbootstrap init settings are saved to deviceinfo, talk about the device/kernel package which was created (drop kernel package for mainline ports once the split happens!), link to porting page. Should have an option for the extra_initfs as well
-->
=== About pmbootstrap ===

pmbootstrap is the postmarketOS build tool. It is used for everything from building individual packages to entire images, and has various utilities which help with the porting and installation process.

It works by creating small self-contained installations (chroots) of Alpine Linux and managing all build dependencies within them. This way, you don't need to install anything manually on your host system to build images and packages; just run a few commands, and pmbootstrap will take care of everything for you.

=== About the <code>APKBUILD</code>/Alpine Linux package format ===

{{note|The "APK" in "APKBUILD" stands for "Alpine Package Keeper", the full name of Alpine's package manager. '''The Alpine apk format/package manager has no relation to Android's .apk format for apps.'''}}

postmarketOS is based on Alpine Linux. As such, it inherits its package manager and build tools.

In Alpine (and pmOS), packages are built according to the information contained in the '''APKBUILD''' file. This file is a shell script containing:

* Metadata of the package, such as its name, description, license, maintainer, etc.
* A list of source files to use when building; these can be tarballs downloaded from an URL (as is done for source code), or stored alongside the APKBUILD file in the package's directory in (pm)aports (as is usually the case with patches).
* The commands for building the program, running its test suite (if applicable) and packaging the program's files/binaries.

The device-specific packages mentioned above use this exact format.

== Prerequisites ==

* You should be familiar with the following:
** The Linux command line; we'll be using pmbootstrap from the command line
** Basic Git workflow, which we'll need when upstreaming our work to postmarketOS; see [[Git workflow]]
* To avoid duplicating effort, make sure your device isn't already supported by postmarketOS - check the [[Devices]] page or use the search bar at the top of the page to look up your device.
* Check if your work drive has at least '''10GB of free space'''. (In case you want to use an external drive, pmbootstrap will let you set the exact location later.)
* To run pmbootstrap, '''you need to be running Linux'''. Other operating systems are not supported - while some people have succeeded at using WSL (see [[Windows FAQ]]), your best option is to set up a Linux install or virtual machine.

=== Getting to know your device ===

Before you begin porting, you should gather some information about the device you want to port:

* The '''codename''' of the device.
** If your device has a LineageOS or TWRP port, you can typically find the codename in the name of the relevant <code>android_device_(vendor)_(codename)</code> repository (usually you can find it on GitHub or linked on XDA forums).
** Android: run <code>adb shell getprop ro.product.device</code>
** As an additional reference, you may look up device identifiers in the [https://storage.googleapis.com/play_public/supported_devices.html Google Play supported devices list] (note: this list is missing some device codenames)
* Which '''SoC (system-on-a-chip)''' it uses.
** For many devices, you can find this by looking up the device name followed by "specifications" or "chipset"; look on sites like GSMArena.
** If you have an Android device, there are various apps you can install to report CPU info (look up "CPU info" in your app store of choice).
** Some SoCs have good support in mainline Linux; see [[Mainlining#Overview|the support matrix table]]. In those cases, it's better to avoid porting the downstream kernel and use the [[(Close to) Mainline]] kernel instead - see [[#Downstream or (close to) mainline kernel?]] section later in the guide.
* Which '''CPU architecture''' the device's SoC has:
** Most phones/tablets use ARM chips. The postmarketOS architectures for ARM chips are:
*** <code>aarch64</code> - 64-bit ('''ARMv8 and above''')
*** <code>armv7</code> - 32-bit ('''ARMv7''' or ARMv8 and above running in 32-bit compatibility mode. <small>Not to be confused with ARM7, which is an ARMv6 core.</small>)
*** <code>armhf</code> - '''ARMv6''' and older '''with a floating point unit''' (FPU). <small>(Not all ARMv6 SoCs have an FPU; notably, the MSM7225 is missing one. Before you port, [https://unix.stackexchange.com/questions/184874/how-do-determine-whether-linux-board-is-using-hardware-fpu-or-not/185070#185070 check if the device has VFP support].)</small>
** postmarketOS also supports <code>x86_64</code> (64-bit)/<code>x86</code> (32-bit) as well as <code>riscv64</code>.
** Run <code>uname -m</code> from the command line (Android: you can run it through <code>adb shell</code>).
** Note that in some cases, the device might be running a 32-bit OS on a 64-bit capable chip. In those cases, you should start with the 32-bit architecture that the stock OS uses; you can try the 64-bit equivalent later.
* '''How to unlock the bootloader'''; in order to flash a custom OS onto the device, '''its bootloader needs to be unlocked''', and there needs to be a known flashing method. See [[Unlocking Bootloaders]] for hints.
* For Android devices, you'll also need the '''boot.img file''', which can either be extracted from an Android ROM or from the <code>boot</code> partition on the device. You can also use a recovery image like TWRP. This file will be used to determine flashing offsets later in the guide.

== Downstream or (close to) mainline kernel ==

postmarketOS, being a Linux distribution, uses Linux as its kernel. However, there's a distinction between the original kernel provided by the manufacturer of a device, and the standard upstream Linux kernel.

=== Downstream (vendor) kernel ===
The '''downstream/vendor kernel''' is the Linux kernel source provided by the manufacturer of the device. It's usually many versions out of date and comes with limited support.

The lifecycle of a vendor kernel is as follows:

* The SoC vendor creates a fork of the Linux kernel (typically based on the Android Common Kernel) with their own SoC drivers added to it.
* The device manufacturer creates their own fork of that kernel with their own device-specific changes.
* Neither of the two upstream the changes to the Linux kernel. Oftentimes, the kernel is only upgraded a few times before device support is dropped.

In the case of Android devices, vendor kernels are made to run Android, and often assume that an Android HAL (hardware abstraction layer) and Android-only vendor blobs will handle many components like audio, modem, camera, GPU acceleration and others. Since the HAL is not present on postmarketOS, vendor kernels provide limited functionality.

Nonetheless, the downstream kernel is a common starting point for new ports; in many cases, where the chip isn't supported in mainline Linux or its support is poor, it's the only option easily available to new porters.

New devices running the downstream kernel go to the '''<code>downstream</code>''' category (see [[Device categorization]]).

=== (Close-to) mainline kernel ===

In contrast, a '''(close-to) mainline kernel''' is based on the upstream Linux kernel and actively maintained by the community. Since it's meant to accommodate a proper Linux userspace, you can expect that more features, like GPU acceleration, will work (and others can be made to work in the future).

However, making a device work with the mainline kernel is a much more involved process. The upstream kernel must have drivers for the SoC in your device and its components (like Wi-Fi/Bluetooth chip, touchscreen controller, display panel, sensors...). Then, a DTS (device tree source/definition) needs to be written to describe your device.

Getting everything to work on mainline is a process that can take anywhere from a few hours (for well-supported devices, where you only need to write a DTS) to even months (in cases where all drivers need to be written from scratch).

New devices running the mainline kernel go to the '''<code>testing</code>''' category.

=== Which one should I choose? ===

Before you make the decision, check the '''[[Mainlining#Supported SoCs]]''' table to see '''if your device's SoC is supported in mainline Linux'''. There, you'll find wiki pages linked to various SoCs, which contain information about working features, known issues and other devices using the SoC.

* '''If your device's SoC has good mainline support, go with mainline.''' Many well-supported SoCs have dedicated mainlining communities and/or guides that can help you get your device working; it takes some effort, but typically gives much better results than running a downstream kernel.

* '''If your device's SoC is not supported in mainline''', continue with the downstream kernel.

{{PrevNext
|next=Porting to a new device/Generating device-specific packages
|next-label=Generating device-specific packages}}
[[Category:Guide]]
