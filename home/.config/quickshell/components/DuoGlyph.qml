import QtQuick
import QtQuick.Shapes

import "../theme"

// Two readings in one status glyph, laid out like the iPhone Duo's: an arc
// open at the bottom fills with one, the four dots in its gap light up with
// the other, and the mark sits in the middle. Usage windows warn as they fill;
// a reading where full is good passes its own colours.
Item {
    id: root

    // Fractions used, 0 to 1; a window that is not known stays dim.
    property real arc: 0
    property real dots: 0
    property bool dotsKnown: true
    property real thickness: 2.5
    property color arcColor: root.tintOf(root.clamped)
    property color dotColor: root.tintOf(root.dots)

    default property alias content: centre.data

    implicitWidth: Theme.capsuleHeight
    implicitHeight: Theme.capsuleHeight

    // The gap is centred on the bottom (90°, y down); the dots sit in it, on
    // the arc's centre line.
    readonly property real gap: 110
    readonly property real arcStart: 90 + root.gap / 2
    readonly property real arcSweep: 360 - root.gap
    readonly property var dotAngles: [126, 102, 78, 54]

    readonly property real radius: (Math.min(root.width, root.height) - root.thickness) / 2
    readonly property real clamped: Math.max(0, Math.min(1, root.arc))
    // Any use lights the first dot; each quarter after that lights another.
    readonly property int lit: root.dotsKnown ? Math.ceil(Math.max(0, Math.min(1, root.dots)) * 4) : 0

    function tintOf(used: real): color {
        return used >= 0.85 ? Theme.indicatorBad : used >= 0.6 ? Theme.indicatorWarn : Theme.indicator
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.thickness
            strokeColor: Theme.indicatorDim
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.radius
                radiusY: root.radius
                startAngle: root.arcStart
                sweepAngle: root.arcSweep
            }
        }

        ShapePath {
            strokeWidth: root.thickness
            strokeColor: root.arcColor
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.radius
                radiusY: root.radius
                startAngle: root.arcStart
                sweepAngle: root.clamped <= 0 ? 0 : Math.max(2, root.arcSweep * root.clamped)

                Behavior on sweepAngle {
                    NumberAnimation {
                        duration: Theme.durationMedium
                        easing.type: Theme.easing
                    }
                }
            }
        }
    }

    Repeater {
        model: root.dotAngles

        Rectangle {
            required property real modelData
            required property int index

            readonly property real rad: modelData * Math.PI / 180

            width: root.thickness * 1.25
            height: width
            radius: width / 2
            x: root.width / 2 + root.radius * Math.cos(rad) - width / 2
            y: root.height / 2 + root.radius * Math.sin(rad) - height / 2
            color: index < root.lit ? root.dotColor : Theme.indicatorDim

            Behavior on color { ColorAnimation { duration: Theme.durationMedium } }
        }
    }

    Item {
        id: centre

        anchors.centerIn: parent
        width: Math.round(root.width * 0.42)
        height: width
    }
}
