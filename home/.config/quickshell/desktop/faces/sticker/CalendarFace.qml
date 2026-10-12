// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   C   A   L   E   N   D   A   R       F   A   C   E                      │
// │   today as a sticker, the month on a sheet · sticker                     │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell

import "../../../theme"
import "../../../services"

// Today on a red sticker, or the current month on a sheet of vinyl.
Item {
    id: root

    property string family: "2x2"
    property var ink: DesktopService.inkFor(null)
    property string seed: ""

    readonly property date today: clock.date
    readonly property real side: Math.min(root.width, root.height)

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Tone { id: tone; hue: root.ink.red }

    component Day: Cut {
        id: day

        shape: "soft"
        seed: root.seed
        fill: tone.fill

        Column {
            anchors.centerIn: parent
            spacing: -day.side * 0.04

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(root.today, "dddd").toUpperCase()
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(Theme.fontSizeLabel - 1, Math.round(day.side * 0.08))
                font.weight: Font.Bold
                font.letterSpacing: 2
                color: tone.deep
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: `${root.today.getDate()}`
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(day.side * 0.5)
                font.weight: Font.Bold
                color: tone.deep
            }
        }

    }

    Loader {
        anchors.fill: parent
        sourceComponent: root.family === "4x4" ? month : room

    }

    Component {
        id: room

        Spread {
            family: root.family
            ink: root.ink
            seed: root.seed
            hue: root.ink.red
            reading: Qt.formatDateTime(root.today, "MMMM")
            note: Qt.formatDateTime(root.today, "yyyy")

            Day {
                anchors.centerIn: parent
                width: parent.width * 0.92
                height: parent.height
            }

        }
    }

    Component {
        id: month

        Cut {
            id: sheet

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

            anchors.fill: parent
            anchors.margins: root.side * 0.03
            shape: "soft"
            lean: Theme.stickerLean * 0.3
            seed: root.seed
            fill: root.ink.paper

            Text {
                id: title

                x: sheet.side * 0.08
                y: sheet.side * 0.06
                text: Qt.formatDateTime(root.today, "MMMM")
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(sheet.side * 0.09)
                font.weight: Font.Bold
                color: tone.deep
            }

            Grid {
                id: grid

                readonly property real cellWidth: width / 7
                readonly property real cellHeight: height / (1 + sheet.cells.length / 7)

                x: sheet.side * 0.06
                y: title.y + title.height + sheet.side * 0.02
                width: sheet.width - 2 * x
                height: sheet.height - y - sheet.side * 0.06
                columns: 7

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
                            font.weight: Font.Bold
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

                        Cut {
                            anchors.centerIn: parent
                            visible: cell.today
                            width: Math.min(parent.width, parent.height) * 1.1
                            height: width
                            shape: "cookie"
                            lobes: 10
                            depth: 0.08
                            seed: root.seed + "today"
                            fill: tone.hue
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: cell.modelData > 0
                            text: `${cell.modelData}`
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: cell.today ? Font.Bold : Font.Medium
                            color: cell.today ? root.ink.paper : Theme.paperInk
                        }

                    }
                }
            }
        }
    }

}
