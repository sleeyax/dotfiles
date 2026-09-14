import QtQuick
import qs.CustomTheme

Rectangle {
    id: pill

    property string icon: ""
    property string text: ""
    property bool selected: false

    signal clicked()

    implicitHeight: 30
    implicitWidth: row.implicitWidth + (text !== "" ? 24 : 14)
    radius: 15
    opacity: enabled ? 1 : 0.4
    color: selected ? Theme.primary : mouse.containsMouse ? Theme.surface_container_highest : Theme.surface_container_high

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: pill.icon !== ""
            name: pill.icon
            size: 16
            color: pill.selected ? Theme.on_primary : Theme.on_surface
        }
        KefLabel {
            anchors.verticalCenter: parent.verticalCenter
            visible: pill.text !== ""
            text: pill.text
            color: pill.selected ? Theme.on_primary : Theme.on_surface
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.clicked()
    }
}
