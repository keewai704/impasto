// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   C   A   L   E   N   D   A   R       F   A   C   E                      │
// │   wall calendar · day, week and month views                              │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell

import "../../../theme"
import "../../../services"

// The calendar as paper: a day leaf, a week of leaves or a month sheet.
Item {
    id: root

    property string family: "2x2"
    property var ink: DesktopService.inkFor(null)

    readonly property date today: clock.date

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Loader {
        anchors.fill: parent

        sourceComponent: {
            if (root.family === "2x2")
                return square
            if (root.family === "4x4")
                return month
            return week
        }
    }

    Component {
        id: square

        Instrument {
            family: root.family
            ink: root.ink

            Leaf {
                anchors.centerIn: parent
                ink: root.ink
                width: Math.min(parent.width, parent.height * 0.74)
                height: parent.height
                month: Qt.formatDateTime(root.today, "MMMM").toUpperCase()
                day: `${root.today.getDate()}`
                weekday: Qt.formatDateTime(root.today, "dddd")

            }
        }
    }

    Component {
        id: week

        Item {
            id: strip

            Leaf {
                x: 22
                y: 22
                width: 100
                height: parent.height - 44
                ink: root.ink
                month: Qt.formatDateTime(root.today, "MMMM").toUpperCase()
                day: `${root.today.getDate()}`
                weekday: Qt.formatDateTime(root.today, "dddd")
            }

            Row {
                id: days

                x: 146
                y: 40
                width: strip.width - 146 - 22
                height: 66
                spacing: 6

                Repeater {
                    model: 7

                    Item {
                        id: day

                        required property int index

                        // Monday first, the way the month is laid out.
                        readonly property date date: {
                            const base = new Date(root.today)
                            const shift = (base.getDay() + 6) % 7
                            base.setDate(base.getDate() - shift + day.index)
                            return base
                        }

                        readonly property bool today:
                            day.date.getDate() === root.today.getDate()
                            && day.date.getMonth() === root.today.getMonth()

                        width: (days.width - 36) / 7
                        height: days.height

                        Leaf {
                            anchors.fill: parent
                            ink: root.ink
                            rings: false
                            band: 16
                            today: day.today
                            month: Qt.formatDateTime(day.date, "ddd").charAt(0)
                            day: `${day.date.getDate()}`
                        }

                    }
                }
            }

            Text {
                x: 146
                y: 122
                width: strip.width - 146 - 22
                text: Qt.formatDateTime(root.today, "dddd")
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeRegular
                color: root.ink.muted
            }
        }
    }

    Component {
        id: month

        Leaf {
            id: sheet

            anchors.fill: parent
            anchors.margins: 22
            ink: root.ink
            band: 34
            month: Qt.formatDateTime(root.today, "MMMM yyyy").toUpperCase()

            readonly property var cells: {
                const year = root.today.getFullYear()
                const index = root.today.getMonth()
                const shift = (new Date(year, index, 1).getDay() + 6) % 7
                const total = new Date(year, index + 1, 0).getDate()
                const list = []
                for (let blank = 0; blank < shift; blank++)
                    list.push(0)
                for (let date = 1; date <= total; date++)
                    list.push(date)
                while (list.length % 7 !== 0)
                    list.push(0)
                return list
            }

            Column {
                anchors.fill: parent
                anchors.margins: 14
                anchors.topMargin: sheet.band + 10
                spacing: 8

                Grid {
                    id: grid

                    width: parent.width
                    height: parent.height
                    columns: 7

                    readonly property real cellWidth: width / 7
                    readonly property real cellHeight: height / (1 + sheet.cells.length / 7)

                    Repeater {
                        model: ["M", "T", "W", "T", "F", "S", "S"]

                        Item {
                            required property var modelData

                            width: grid.cellWidth
                            height: grid.cellHeight

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeLabel
                                font.weight: Font.DemiBold
                                color: Theme.paperInkMuted
                            }
                        }
                    }

                    Repeater {
                        model: sheet.cells

                        Item {
                            id: cell

                            required property int modelData

                            readonly property bool today: cell.modelData === root.today.getDate()

                            width: grid.cellWidth
                            height: grid.cellHeight

                            Rectangle {
                                anchors.centerIn: parent
                                width: Math.min(parent.width, parent.height) - 6
                                height: width
                                radius: width / 2
                                visible: cell.today
                                color: root.ink.accent
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: cell.modelData > 0
                                text: `${cell.modelData}`
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: cell.today ? Font.DemiBold : Font.Normal
                                color: cell.today ? root.ink.accentText : Theme.paperInk
                            }

                        }
                    }
                }

            }

        }
    }

}
