//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import "PowerApp"
import "CalendarApp"
import "WallpaperApp"
import "CustomTheme"

ShellRoot {
    // Test IPC tools: qs ipc show

    IpcHandler {
        target: "theme-manager" 
        function reload(): void {
            Theme.reloadTheme()
        }
    }

    PowerWindow {}
    CalendarWindow {}
    WallpaperWindow {}
}