# Quickshell Overview

Third-party code, vendored here via ML4W. Not ours.

- Upstream: https://github.com/Shanu-Kumawat/quickshell-overview (GPL)
- Originally extracted from the overview feature in [illogical-impulse](https://github.com/end-4/dots-hyprland) by [end-4](https://github.com/end-4).

Launched by `ml4w-autostart` as `qs -p ~/.config/quickshell/overview`, and toggled by SUPER + Tab.

Our only change is `config.json`: `colorSource` is `matugen` rather than `default`, and the three fonts are Fira Sans Semibold.
Everything else is upstream's.
Matugen renders `common/Appearance.colors.qml` into this directory from `matugen/templates/quickshell-overview.qml`.

Upstream's full documentation and screenshots live at the URL above; they were dropped here rather than kept in sync by hand.
