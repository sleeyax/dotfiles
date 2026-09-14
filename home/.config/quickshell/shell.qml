//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import "PowerApp"
import "CalendarApp"
import "WallpaperApp"
import "CustomTheme"
import "KefApp"

ShellRoot {
    // Test IPC tools: qs ipc show

    // A singleton is only created once referenced, and its IpcHandler has to answer before the panel is ever opened.
    readonly property var kef: KefService

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