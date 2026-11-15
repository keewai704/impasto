import QtQuick

import "../../theme"
import "../../services"
import "../../components"

// Each window of the OpenCode Go plan; the ring is the fullest one.
Item {
    id: root

    property bool compact: false

    implicitWidth: holder.implicitWidth
    implicitHeight: holder.implicitHeight

    Component.onCompleted: OpencodeService.subscribe()
    Component.onDestruction: OpencodeService.release()

    Loader {
        id: holder
        anchors.fill: parent
        sourceComponent: root.compact ? chip : detail
    }

    Component {
        id: chip

        Item {
            RingIndicator {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.capsuleHeight
                height: Theme.capsuleHeight
                thickness: 2.5
                progress: OpencodeService.gauge
                trackColor: Theme.indicatorDim
                fillColor: OpencodeService.tint

                OpencodeMark {
                    anchors.centerIn: parent
                    width: Math.round(Theme.capsuleHeight * 0.44)
                    height: Math.round(Theme.capsuleHeight * 0.44)
                }
            }
        }
    }

    Component {
        id: detail

        ModuleCard {
            title: "OpenCode Go"

            mark: RingIndicator {
                anchors.fill: parent
                thickness: 3
                progress: OpencodeService.gauge
                trackColor: Theme.indicatorDim
                fillColor: OpencodeService.tint

                OpencodeMark {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                }
            }

            Repeater {
                model: OpencodeService.limits

                CardLimit {
                    required property var modelData

                    name: Tr.t(modelData.name)
                    fraction: modelData.used
                    resets: modelData.resets
                    tint: modelData.limited ? Theme.indicatorBad : OpencodeService.tintOf(modelData.used)
                }
            }
        }
    }
}
