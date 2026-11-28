import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    property string yogaMode: "dual"
    property bool dual: true
    property string popover: ""
    property var popoverScreen: null

    readonly property bool tablet: yogaMode !== "dual"

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/yb-mode/mode"
        watchChanges: true
        onFileChanged: reload()
        onTextChanged: {
            const mode = text().trim()
            root.yogaMode = mode === "" ? "dual" : mode
            root.dual = root.yogaMode === "dual"
        }
    }

    FileView {
        id: barsState
        path: Quickshell.env("HOME") + "/.local/state/quickshell-bars.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: bars
            property bool top: true
            property bool bottom: true
            property bool external: true
        }
    }

    function open(page, screen) {
        if (root.popover === page && root.popoverScreen === screen) {
            root.popover = ""
            return
        }
        root.popoverScreen = screen
        root.popover = page
    }

    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData
            screen: modelData
            dual: root.dual
            enabled: modelData.name === "eDP-1" ? bars.top
                : modelData.name === "eDP-2" ? bars.bottom
                : bars.external
            onOpenControlCenter: root.open("control", modelData)
            onOpenQuickMenu: root.open("quick", modelData)
            onOpenTouchMenu: root.open("touch", modelData)
            onOpenKanata: {
                if (root.popover === "control" && controlCenter.detail === "kanata") {
                    root.popover = ""
                    return
                }
                root.popoverScreen = modelData
                root.popover = "control"
                controlCenter.detail = "kanata"
            }
        }
    }

    IpcHandler {
        target: "shell"

        function control(): string {
            root.popoverScreen = Quickshell.screens[0]
            root.popover = "control"
            return "ok"
        }

        function quick(): string {
            root.popoverScreen = Quickshell.screens[0]
            root.popover = "quick"
            return "ok"
        }

        function touch(): string {
            root.popoverScreen = Quickshell.screens[0]
            root.popover = "touch"
            return "ok"
        }

        function close(): string {
            root.popover = ""
            return "ok"
        }

        function workspace(id: string): string {
            Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({workspace = \u0027" + id + "\u0027})"])
            return "ok"
        }

        function bars(mode: string): string {
            if (mode === "all-on") {
                bars.top = true
                bars.bottom = true
                bars.external = true
            } else if (mode === "all-off") {
                bars.top = false
                bars.bottom = false
                bars.external = false
            } else if (mode === "top") {
                bars.top = !bars.top
            } else if (mode === "bottom") {
                bars.bottom = !bars.bottom
            } else if (mode === "external") {
                bars.external = !bars.external
            } else if (mode === "all") {
                const show = !(bars.top || bars.bottom || bars.external)
                bars.top = show
                bars.bottom = show
                bars.external = show
            } else if (mode === "both") {
                const show = !(bars.top && bars.bottom)
                bars.top = show
                bars.bottom = show
            }
            return "ok"
        }
    }

    ControlCenter {
        id: controlCenter
        page: root.popover
        targetScreen: root.popoverScreen
        tablet: root.tablet
        onCloseRequested: root.popover = ""
    }
}
