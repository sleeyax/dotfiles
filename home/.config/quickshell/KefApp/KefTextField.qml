import QtQuick
import QtQuick.Controls
import qs.CustomTheme

TextField {
    id: field

    implicitHeight: 34
    leftPadding: 14
    rightPadding: 14
    color: Theme.on_surface
    placeholderTextColor: Theme.on_surface_variant
    selectionColor: Theme.primary
    selectedTextColor: Theme.on_primary
    font.family: Theme.fontFamily
    font.pixelSize: 13

    background: Rectangle {
        radius: 17
        color: Theme.surface_container_high
        border.width: field.activeFocus ? 1 : 0
        border.color: Theme.primary
    }
}
