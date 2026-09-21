import QtQuick
import QtQuick.Controls
import qs.CustomTheme

Slider {
    id: slider

    // The speaker's value, followed only while the user is not dragging; binding `value` directly would be broken by the first drag.
    property real externalValue: 0

    signal committed(real value)

    Binding on value {
        when: !slider.pressed && !commitDelay.running
        value: slider.externalValue
    }

    onMoved: commitDelay.restart()
    onPressedChanged: {
        if (!pressed) {
            commitDelay.stop();
            committed(value);
        }
    }

    Timer {
        id: commitDelay
        interval: 250
        onTriggered: slider.committed(slider.value)
    }

    background: Rectangle {
        x: slider.leftPadding
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        implicitWidth: 200
        implicitHeight: 4
        width: slider.availableWidth
        height: implicitHeight
        radius: 2
        color: Theme.surface_container_highest

        Rectangle {
            width: slider.visualPosition * parent.width
            height: parent.height
            radius: 2
            color: Theme.primary
        }
    }

    handle: Rectangle {
        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        implicitWidth: 14
        implicitHeight: 14
        radius: 7
        color: slider.pressed ? Theme.primary_fixed : Theme.primary
    }
}
