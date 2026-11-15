import QtQuick

import "../theme"

// The OpenCode mark: a tall frame with a dimmer block in the lower half of
// its opening, in proportion to the official artwork (256 × 320, a 64 wall).
Item {
    id: root

    property color color: Theme.indicator

    implicitWidth: 16
    implicitHeight: 16

    readonly property real unit: Math.min(root.width / 256, root.height / 320)

    Rectangle {
        id: frame

        anchors.centerIn: parent
        width: 256 * root.unit
        height: 320 * root.unit
        color: "transparent"
        border.width: 64 * root.unit
        border.color: root.color
        antialiasing: true

        Rectangle {
            x: frame.border.width
            y: 128 * root.unit
            width: 128 * root.unit
            height: 128 * root.unit
            color: root.color
            opacity: 0.4
        }
    }
}
