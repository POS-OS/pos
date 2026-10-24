# POS: POS OS

The POS project is meant for research and educational purposes.

Goal is to maintain a complete operating system for the Linux kernel, intended for 
any user looking for a general purpose OS to power their PC hardware.

## The scope POS cover

* Boot up process.
* Manage system services.
* Manage the kernel.
* Manage network connections.
* Manage file systems.
* Manage adding installation sources of end users software. 

## Principles

* Provide the essential common libraries, services and features needed by workstation or server workloads.
* Offer a predictable and versatile user and developer experience.
* Focus on reliability and consistency.  

## Kernels

POS boots kernels other projects build, from kernel channels: `fedora`
(Fedora's kernel, the default), `mainline` and `stable` (kernel.org's
trees, built by Fedora's kernel-vanilla project). The `linus` channel
builds kernel.org's mainline release on the machine instead: Fedora's
configuration with the drivers the machine used while it ran Fedora's
kernel built in, and the others left out. It needs POS's sdk
(`pos-stage enable sdk`). Each channel the system
boots has a boot entry for its newest kernel and one for the kernel before
it, to fall back to from the boot menu. Downloading needs the network
stage (`pos-stage enable network`).

    # pos-kernel channels            # the channels, and which are enabled
    # pos-kernel list                # the kernels, with their boot entries
    # pos-kernel update              # get the newest kernel of each channel
    # pos-kernel enable stable       # boot the stable channel's kernels too
    # pos-kernel default stable      # and boot its newest by default
    # pos-kernel disable mainline    # remove its boot entries, keep its kernels
    # pos-kernel remove mainline     # and remove its kernels

The choices are global system preferences (`pos-preferences list`), kept
in `/etc/pos/preferences`.
