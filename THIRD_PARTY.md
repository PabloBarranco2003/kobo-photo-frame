# Third-party software

This repository does **not** include the Kobo firmware or KFMon. It does include FBInk binaries.

| Component | Purpose | License | Where |
|---|---|---|---|
| [FBInk](https://github.com/NiLuJe/FBInk) v1.25.0 | Draws text and images on the e-ink screen | GPL-3.0 | `kobo/.frame/fbink`, `fbink-static` (built from unmodified source; see `kobo/.frame/FBInk-README.txt` and `FBInk-LICENSE.txt`) |
| [KFMon](https://github.com/NiLuJe/kfmon) v1.4.6 | Launches the frame when an icon is opened from Nickel | GPL-3.0 | Not included: downloaded separately (see README) |
| Kobo firmware 3.19.5761 | Stock system (Nickel) | Proprietary, Rakuten Kobo | Not included: download from Kobo's official site |

The original code in this repository (`frame.sh`, `kbinput.c`, `rtcalarm.c`, `tools/`) is released under the MIT license (see `LICENSE`).
The FBInk binaries remain GPL-3.0.

This project is not affiliated with Rakuten Kobo.
