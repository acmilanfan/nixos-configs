import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Networking
import Quickshell.Bluetooth

PanelWindow {
    id: cc

    property string page: ""
    property var targetScreen: null
    property string detail: ""
    signal closeRequested()

    readonly property color bg: "#1a1b26"
    readonly property color card: "#1f2130"
    readonly property color cardHover: "#272a3d"
    readonly property color border: "#2b3b51"
    readonly property color fg: "#c6d0f5"
    readonly property color dim: "#7f849c"
    readonly property color accent: "#7b5cff"

    readonly property var wifiDevice: {
        const devices = Networking.devices ? Networking.devices.values : []
        for (let i = 0; i < devices.length; i++)
            if (devices[i].type === DeviceType.Wifi)
                return devices[i]
        return null
    }
    readonly property var wifiNetworks: {
        if (!wifiDevice || !wifiDevice.networks)
            return []
        const values = wifiDevice.networks.values.filter(n => String(n.name || "").length > 0)
        values.sort((a, b) => (b.connected - a.connected) || (b.known - a.known)
            || (b.signalStrength - a.signalStrength))
        return values
    }
    readonly property var activeWifi: {
        const values = wifiNetworks
        for (let i = 0; i < values.length; i++)
            if (values[i].connected)
                return values[i]
        return null
    }
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var btDevices: {
        if (!Bluetooth.devices)
            return []
        const values = Bluetooth.devices.values.slice()
        values.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired)
            || String(a.name || "").localeCompare(String(b.name || "")))
        return values
    }

    onDetailChanged: if (wifiDevice) wifiDevice.scannerEnabled = detail === "wifi"
    onVisibleChanged: {
        if (!visible)
            detail = ""
        else
            focusScope.forceActiveFocus()
    }

    visible: page !== ""
    screen: targetScreen
    anchors {
        top: true
        left: page === "quick"
        right: page === "control"
    }
    margins {
        top: 29
        left: 3
        right: 3
    }
    implicitWidth: 380
    implicitHeight: content.implicitHeight + 28
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "quickshell-control-center"
    WlrLayershell.keyboardFocus: cc.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    Timer {
        interval: 8000
        running: cc.detail === "bt" && cc.adapter && cc.adapter.discovering
        onTriggered: if (cc.adapter) cc.adapter.discovering = false
    }

    component Tile: Rectangle {
        id: tile
        property string glyph: ""
        property string label: ""
        property string sublabel: ""
        property string command: ""
        property string openDetail: ""
        property bool active: false

        Layout.fillWidth: true
        implicitHeight: 58
        radius: 8
        activeFocusOnTab: true
        color: tile.active ? "#2a2350" : (hover.hovered ? cc.cardHover : cc.card)
        border.width: 1
        border.color: tile.active || tile.activeFocus ? cc.accent : cc.border
        Keys.onReturnPressed: run()
        Keys.onEnterPressed: run()
        Keys.onSpacePressed: run()

        function run() {
            if (tile.openDetail) {
                cc.detail = tile.openDetail
                return
            }
            if (tile.command)
                Quickshell.execDetached(["sh", "-c", tile.command])
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            spacing: 8

            Rectangle {
                implicitWidth: 26
                implicitHeight: 26
                radius: 7
                color: Qt.rgba(1, 1, 1, 0.04)

                Text {
                    anchors.centerIn: parent
                    text: tile.glyph
                    color: tile.active ? cc.accent : cc.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 14
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: tile.label
                    color: tile.active ? cc.accent : cc.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.bold: true
                }

                Text {
                    text: tile.sublabel
                    visible: text.length > 0
                    color: cc.dim
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 8
                }
            }
        }

        HoverHandler { id: hover }

        MouseArea {
            anchors.fill: parent
            onClicked: tile.run()
        }
    }

    component Mini: Rectangle {
        id: mini
        property string label: ""
        property string command: ""

        implicitWidth: Math.max(26, labelText.implicitWidth + 12)
        implicitHeight: 22
        radius: 6
        activeFocusOnTab: true
        color: hover.hovered ? cc.cardHover : cc.card
        border.width: 1
        border.color: mini.activeFocus ? cc.accent : cc.border
        Keys.onReturnPressed: run()
        Keys.onEnterPressed: run()
        Keys.onSpacePressed: run()

        function run() {
            if (mini.command)
                Quickshell.execDetached(["sh", "-c", mini.command])
        }

        Text {
            id: labelText
            anchors.centerIn: parent
            text: mini.label
            color: cc.fg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9
        }

        HoverHandler { id: hover }

        MouseArea {
            anchors.fill: parent
            onClicked: mini.run()
        }
    }

    component NetRow: Rectangle {
        id: row
        property string label: ""
        property string sublabel: ""
        property bool connected: false
        property string action: ""

        Layout.fillWidth: true
        implicitHeight: 34
        radius: 7
        activeFocusOnTab: true
        color: row.activeFocus || area.hovered ? cc.cardHover : cc.card
        border.width: 1
        border.color: row.activeFocus ? cc.accent : cc.border
        Keys.onReturnPressed: run()
        Keys.onEnterPressed: run()
        Keys.onSpacePressed: run()

        function run() {
            if (row.action)
                Quickshell.execDetached(["sh", "-c", row.action])
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: row.label
                color: row.connected ? cc.accent : cc.fg
                elide: Text.ElideRight
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                font.bold: row.connected
            }

            Text {
                text: row.sublabel
                color: cc.dim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 8
            }
        }

        HoverHandler { id: area }

        MouseArea {
            anchors.fill: parent
            onClicked: row.run()
        }
    }

    component VolumeRow: Rectangle {
        id: volume
        readonly property var sink: Pipewire.defaultAudioSink

        Layout.fillWidth: true
        implicitHeight: 44
        radius: 8
        color: cc.card
        border.width: 1
        border.color: cc.border

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            spacing: 8

            Text {
                text: {
                    const s = volume.sink
                    if (!s || !s.audio)
                        return "󰕾"
                    return s.audio.muted || s.audio.volume < 0.01 ? "󰝟" : "󰕾"
                }
                color: cc.fg
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: Quickshell.execDetached(["pamixer", "-t"])
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: 14

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: cc.cardHover
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * Math.max(0, Math.min(1,
                        volume.sink && volume.sink.audio ? volume.sink.audio.volume : 0))
                    height: 4
                    radius: 2
                    color: cc.accent
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.width * Math.max(0, Math.min(1,
                        volume.sink && volume.sink.audio ? volume.sink.audio.volume : 0)) - 5
                    width: 10
                    height: 10
                    radius: 5
                    color: cc.fg
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: (mouse) => apply(mouse.x)
                    onPositionChanged: (mouse) => {
                        if (pressed)
                            apply(mouse.x)
                    }
                    function apply(x) {
                        if (volume.sink && volume.sink.audio)
                            volume.sink.audio.volume = Math.max(0, Math.min(1, x / width))
                    }
                }
            }

            Text {
                width: 34
                horizontalAlignment: Text.AlignRight
                text: volume.sink && volume.sink.audio
                    ? Math.round(volume.sink.audio.volume * 100) + "%"
                    : "--"
                color: cc.dim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
            }
        }
    }

    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: {
            if (cc.detail.length > 0)
                cc.detail = ""
            else
                cc.closeRequested()
        }

        Rectangle {
            anchors.fill: parent
            radius: 11
            color: cc.bg
            border.width: 1
            border.color: cc.border

            ColumnLayout {
                id: content
                anchors.fill: parent
                anchors.margins: 14
                spacing: 9

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        visible: cc.detail.length > 0
                        text: "‹"
                        color: cc.dim
                        font.pixelSize: 15

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            onClicked: cc.detail = ""
                        }
                    }

                    Text {
                        text: cc.detail === "wifi" ? "Wi-Fi"
                            : cc.detail === "bt" ? "Bluetooth"
                            : cc.page === "quick" ? "Quick Menu" : "Control Center"
                        color: cc.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "✕"
                        color: cc.dim
                        font.pixelSize: 12

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            onClicked: cc.closeRequested()
                        }
                    }
                }

                // --- Wi-Fi detail ---
                ColumnLayout {
                    visible: cc.detail === "wifi"
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: Networking.wifiEnabled
                                ? (cc.activeWifi ? cc.activeWifi.name : "Not connected")
                                : "Off"
                            color: cc.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                        Mini {
                            label: Networking.wifiEnabled ? "off" : "on"
                            command: "nmcli radio wifi " + (Networking.wifiEnabled ? "off" : "on")
                        }
                        Mini { label: "scan"; command: "nmcli dev wifi rescan" }
                    }

                    Repeater {
                        model: cc.wifiNetworks.slice(0, 7)
                        delegate: NetRow {
                            required property var modelData
                            label: modelData.name
                            sublabel: modelData.connected ? "connected"
                                : (modelData.known ? "saved" : Math.round(modelData.signalStrength * 100) + "%")
                            connected: modelData.connected
                            action: modelData.connected
                                ? "nmcli connection down id " + JSON.stringify(modelData.name)
                                : "nmcli connection up id " + JSON.stringify(modelData.name)
                        }
                    }
                }

                // --- Bluetooth detail ---
                ColumnLayout {
                    visible: cc.detail === "bt"
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: cc.adapter && cc.adapter.enabled ? "On" : "Off"
                            color: cc.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                        Mini {
                            label: cc.adapter && cc.adapter.enabled ? "off" : "on"
                            command: "bluetoothctl power " + (cc.adapter && cc.adapter.enabled ? "off" : "on")
                        }
                        Mini { label: "scan"; command: "bluetoothctl --timeout 8 scan on" }
                    }

                    Repeater {
                        model: cc.btDevices.slice(0, 7)
                        delegate: NetRow {
                            required property var modelData
                            label: modelData.name && modelData.name.length > 0
                                ? modelData.name : modelData.address
                            sublabel: modelData.connected ? "connected"
                                : (modelData.paired ? "saved" : "")
                            connected: modelData.connected
                            action: "bluetoothctl " + (modelData.connected ? "disconnect " : "connect ")
                                + modelData.address
                        }
                    }
                }

                // --- Home tiles ---
                GridLayout {
                    visible: cc.page === "control" && cc.detail === ""
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8

                    Tile {
                        glyph: "󰤢"
                        label: "Wi-Fi"
                        sublabel: Networking.wifiEnabled
                            ? (cc.activeWifi ? cc.activeWifi.name : "Not connected") : "Off"
                        active: Networking.wifiEnabled
                        openDetail: "wifi"
                    }
                    Tile {
                        glyph: "󰂯"
                        label: "Bluetooth"
                        sublabel: cc.adapter && cc.adapter.enabled
                            ? (cc.btDevices.filter(d => d.connected).length + " connected") : "Off"
                        active: cc.adapter && cc.adapter.enabled
                        openDetail: "bt"
                    }
                }

                VolumeRow {
                    visible: cc.page === "control" && cc.detail === ""
                    Layout.fillWidth: true
                }

                Rectangle {
                    visible: cc.page === "control" && cc.detail === ""
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 8
                    color: cc.card
                    border.width: 1
                    border.color: cc.border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        spacing: 6

                        Text {
                            text: "Kanata"
                            color: cc.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            font.bold: true
                        }
                        ScriptLabel {
                            Layout.fillWidth: true
                            command: "hypr-kanata-status | jq -r '.text // \"absent\"'"
                            interval: 5
                            textColor: cc.dim
                        }
                        Mini { label: "HR"; command: "$HOME/.config/kanata/switch-kanata.sh homerow" }
                        Mini { label: "off"; command: "$HOME/.config/kanata/switch-kanata.sh disabled" }
                        Mini { label: "↻"; command: "$HOME/.config/kanata/reload-kanata.sh restart" }
                    }
                }

                GridLayout {
                    visible: cc.page === "control" && cc.detail === ""
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8

                    Tile { glyph: "󰌾"; label: "Lock"; command: "hyprlock-session start" }
                    Tile { glyph: "󰐥"; label: "Power"; command: "wlogout" }
                }

                // --- Quick Menu ---
                GridLayout {
                    visible: cc.page === "quick"
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8

                    Tile { glyph: "󰀻"; label: "Apps"; command: "nwg-drawer" }
                    Tile { glyph: "󰒓"; label: "Profiles"; command: "hypr-profile" }
                    Tile { glyph: "󰌌"; label: "Keyboard"; command: "hypr-toggle-kb" }
                    Tile { glyph: "󰑓"; label: "Rotate"; command: "hypr-iio-toggle" }
                }

                Rectangle {
                    visible: cc.page === "quick"
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 8
                    color: cc.card
                    border.width: 1
                    border.color: cc.border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: "Brightness"
                            color: cc.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                        Mini { label: "−"; command: "brightness-ctl down 5" }
                        Mini { label: "+"; command: "brightness-ctl up 5" }
                    }
                }

                Rectangle {
                    visible: cc.page === "quick"
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 8
                    color: cc.card
                    border.width: 1
                    border.color: cc.border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: "Volume"
                            color: cc.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                        Mini { label: "−"; command: "change-volume -5" }
                        Mini { label: "+"; command: "change-volume +5" }
                    }
                }

                GridLayout {
                    visible: cc.page === "quick"
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8

                    Tile { glyph: "󰌾"; label: "Lock"; command: "hyprlock-session start" }
                    Tile { glyph: "󰐥"; label: "Power"; command: "wlogout" }
                }
            }
        }
    }
}
