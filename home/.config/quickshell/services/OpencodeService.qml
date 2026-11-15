pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

import "../theme"

// The OpenCode Go plan's usage windows (five hours, week, month), asked of
// the account with `opencode_usage.py`. Polled only while subscribed, the way
// `CodexService` is.
Singleton {
    id: root

    readonly property int pollInterval: 300000

    property int watchers: 0
    property bool available: false
    // `{ name, minutes, used, resets, limited }`, the shorter window first.
    property var limits: []

    // The module is offered only once `available` is true.
    Component.onCompleted: root.refresh()

    // The five hours and the week, as the bar's glyph shows them.
    readonly property var session: root.limits.find(limit => limit.minutes === 300) ?? null
    readonly property var week: root.limits.find(limit => limit.minutes === 10080) ?? null

    readonly property real gauge: root.limits.reduce((worst, limit) => Math.max(worst, limit.used), 0)
    readonly property bool measured: root.limits.length > 0

    readonly property color tint: {
        if (!root.measured)
            return Theme.indicator
        if (root.gauge >= 0.85 || root.limits.some(limit => limit.limited))
            return Theme.indicatorBad
        if (root.gauge >= 0.6)
            return Theme.indicatorWarn
        return Theme.indicator
    }

    function tintOf(used: real): color {
        return used >= 0.85 ? Theme.indicatorBad : used >= 0.6 ? Theme.indicatorWarn : Theme.indicator
    }

    function subscribe(): void {
        root.watchers += 1
        root.refresh()
    }

    function release(): void {
        root.watchers = Math.max(0, root.watchers - 1)
    }

    function refresh(): void {
        root.query.running = true
    }

    readonly property Timer poller: Timer {
        interval: root.pollInterval
        repeat: true
        running: root.watchers > 0
        onTriggered: root.refresh()
    }

    readonly property Process query: Process {
        command: [Quickshell.shellPath("scripts/opencode_usage.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                let report = null
                try {
                    report = JSON.parse(text)
                } catch (error) {
                    console.warn("Cannot parse the OpenCode Go usage report:", error)
                    return
                }
                // A failed request keeps the last figures rather than
                // hiding the module between polls.
                if (report.available !== true)
                    return
                root.limits = report.limits ?? []
                root.available = true
            }
        }
    }
}
