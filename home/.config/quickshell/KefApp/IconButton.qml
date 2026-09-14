import QtQuick
import qs.CustomTheme

Rectangle {
    id: button

    property string icon: ""
    property real size: 36
    property real iconSize: Math.round(size * 0.6)
    property bool checked: false
    property bool filled: false

    signal clicked()

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    opacity: enabled ? 1 : 0.4
    color: {
        if (filled)
            return mouse.containsMouse ? Theme.primary_fixed_dim : Theme.primary;
        return mouse.containsMouse ? Theme.surface_container_highest : "transparent";
    }

    MaterialIcon {
        anchors.centerIn: parent
        name: button.icon
        size: button.iconSize
        color: button.filled ? Theme.on_primary : button.checked ? Theme.primary : Theme.on_surface
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
