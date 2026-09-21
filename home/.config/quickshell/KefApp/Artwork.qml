import QtQuick
import QtQuick.Effects
import qs.CustomTheme

Item {
    id: artwork

    property string source: ""
    property real radius: 6
    property string fallbackIcon: "music_note"

    Rectangle {
        anchors.fill: parent
        radius: artwork.radius
        color: Theme.surface_container_high
        visible: image.status !== Image.Ready

        MaterialIcon {
            anchors.centerIn: parent
            name: artwork.fallbackIcon
            size: Math.round(artwork.height * 0.45)
            color: Theme.on_surface_variant
        }
    }

    Image {
        id: image
        anchors.fill: parent
        source: artwork.source
        sourceSize.width: artwork.width * 2
        sourceSize.height: artwork.height * 2
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: artwork.radius
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: image
        visible: image.status === Image.Ready
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
}
