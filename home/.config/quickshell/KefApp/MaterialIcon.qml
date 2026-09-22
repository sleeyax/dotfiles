import QtQuick
import qs.CustomTheme

Text {
    property string name: ""
    property real size: 22

    text: name
    font.family: "Material Icons"
    font.pixelSize: size
    color: Theme.on_surface
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
