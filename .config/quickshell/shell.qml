import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "wallpaper"

PanelWindow {
    id: root
    color: "transparent"

    WlrLayershell.namespace: "qs-wallpaper-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    focusable: true

    width: Screen.width
    height: Screen.height

    // Scale matches WindowRegistry.js wallpaper layout: h: s(650, scale)
    readonly property real pickerScale: {
        let r = Screen.width / 1920.0
        return r <= 1.0 ? Math.max(0.35, Math.pow(r, 0.85)) : Math.pow(r, 0.5)
    }
    readonly property int pickerHeight: Math.round(650 * pickerScale)

    Keys.onEscapePressed: Qt.quit()

    MouseArea {
        anchors.fill: parent
        onClicked: Qt.quit()
    }

    Item {
        x: 0
        y: Math.floor((Screen.height - root.pickerHeight) / 2)
        width: Screen.width
        height: root.pickerHeight

        WallpaperPicker {
            width: parent.width
            height: parent.height
        }
    }

    // Watch for "close" written by picker after wallpaper apply
    Process {
        id: ipcWatcher
        command: ["bash", "-c",
            "echo '' > /tmp/qs_widget_state; " +
            "touch /tmp/qs_widget_state; " +
            "inotifywait -qq -e close_write /tmp/qs_widget_state 2>/dev/null; " +
            "cat /tmp/qs_widget_state"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "close") Qt.quit()
            }
        }
    }
}
