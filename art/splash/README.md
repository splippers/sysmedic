# SysMedic boot splash art
Meta AI, 2026-11-24, no text. Palette matches docs/art/app-icon.jpg (dark teal #021E26, green binary, cyan ECG).
- `sysmedic-splash-centred-source.jpg`: chosen source (2048x1152). `...-left-pulse-alt.jpg`: alternative.
- `background-1920x1080.png`: quantised, used by Plymouth and grub-theme/background.png.
- `grub-1280x720.png`: smaller copy for GRUB `background_image`.
Status: Plymouth script now scales the background to the screen (not yet booted). The GRUB theme.txt change
(desktop-image, plain title, size-16 fonts) did NOT make gfxmenu load the theme in a QEMU Secure Boot test
(plain GRUB menu shown), so the theme needs debugging; `background_image` works under Secure Boot (see Haar test).
