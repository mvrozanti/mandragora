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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    implicitWidth: Screen.width
    implicitHeight: Screen.height

    readonly property real pickerScale: {
        let r = Screen.width / 1920.0
        return r <= 1.0 ? Math.max(0.35, Math.pow(r, 0.85)) : Math.pow(r, 0.5)
    }
    readonly property int pickerHeight: Math.round(650 * pickerScale)
    readonly property int pickerY: Math.floor((Screen.height - pickerHeight) / 2)

    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: Qt.quit()
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Q && (event.modifiers & Qt.ControlModifier)) {
                Qt.quit()
                event.accepted = true
            }
        }

        MouseArea {
            x: 0; y: 0
            width: Screen.width
            height: root.pickerY
            onClicked: Qt.quit()
        }

        MouseArea {
            x: 0
            y: root.pickerY + root.pickerHeight
            width: Screen.width
            height: Screen.height - (root.pickerY + root.pickerHeight)
            onClicked: Qt.quit()
        }

        Item {
            x: 0
            y: root.pickerY
            width: Screen.width
            height: root.pickerHeight

            WallpaperPicker {
                anchors.fill: parent
            }
        }
    }

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
