# Android Emulator Linux Helper

This is a little script I have made to make pretending my touchscreen Linux laptop is an Android tablet a bit nicer.
It glues together a bunch of shell commands (`xdotool`, `wmctrl`, `adb`, and `xrandr`) together with some Julia code.

It basically tried to always match the rotation of the emulated Android to tthe rotation of the laptop screen.
It also tries to keep things as close to fullscreen as possible.

It's not really general purpose software, but the script shouldn't be too hard to get working on someone elses system.
Some constants and literals may need changing, and on different systems the shell commands might have different outputs.

It's a bit over engineered, it basically is using multiple dispatch to very similar to pattern matching, with a ton of singletons.
Which is not very performant, but it is interesting as a style, performance doesn't matter here.
