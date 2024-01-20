# A RISC-V interpreter written in zig

A pure Zig implementation of an RV64IAMFD-ziscr-zfence interpreter with the
intent of being embedded and used for plugin/mod/scripting systems.

Whilst this project has been written from the ground up in Zig, a huge
intellectual debt is owed to https://github.com/fwsGonzo/rvscript for inspiring
me to try this out. I think the main innovation that Zig can bring is a much
better host-side binding system, where C ABI functions have their ABI
implemented and validated at compile time, which should result in faster native
calls. This is already partially implemented.

The other thing that makes this implementation differ (currently) is the
emulated code's ability to write and read directly from the host memory address
space. This is done in a pretty lazy and unsecure way at the moment, but any
exploits that could arise from this are already prohibitively difficult to do as
the loader implementation essentially has ASLR (Address Space Layout
Randomization) in its simplest form.

This project can be thought of as an exploratory leap from my other project that
attempted to achieve this in a way that I _think_ RISC-V does better
https://github.com/zkburke/callisto
