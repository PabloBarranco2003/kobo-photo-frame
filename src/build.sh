#!/bin/sh
# Rebuilds the helper programs for the Kobo Touch (ARMv7 hard-float, Cortex-A8).
# Needs Python 3 with the ziglang package:  pip install ziglang
set -e
cd "$(dirname "$0")"
OUT=../kobo/.frame
CC="python3 -m ziglang cc -mcpu=cortex_a8 -O2 -static -target arm-linux-musleabihf"
$CC -Wall -o "$OUT/kbinput"          kbinput.c     # reads buttons and touch
$CC -Wall -o "$OUT/rtcalarm-static"  rtcalarm.c    # RTC alarm via ioctl
echo "Done: $OUT/kbinput and $OUT/rtcalarm-static"
# fbink / fbink-static: see ../kobo/.frame/FBInk-README.txt
