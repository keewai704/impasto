// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   B R I G H T N E S S   S E R V I C E                                    │
// │   brightness per screen · through the hypr-brightness daemon             │
// │                                                                          │
// │   Island's replacement for impasto's brightnessctl and ddcutil service   │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import "../theme"

// One entry per screen the daemon can dim: the laptop panel through logind,
// a monitor over DDC/CI. The daemon keeps the devices open and replies at
// once, so a held key or a dragged slider never waits on the hardware. Its
// event stream also carries levels set from elsewhere, such as the CLI. The
// keys and every single reading follow the focused screen, or the first one
// that can be dimmed.
Singleton {
    id: root

    // A level was set here or by another client. A reading taken off the
    // hardware is not a change and does not emit it.
    signal adjusted(var display)

    readonly property var displays: root.variants.instances
    readonly property var dimmable: root.displays.filter(display => display.available)
    readonly property var current: {
        const focused = HyprlandService.focusedMonitor
        return root.dimmable.find(display => display.name === focused)
            ?? root.dimmable[0] ?? null
    }

    readonly property bool available: root.current !== null
    readonly property int percent: root.current?.percent ?? 0
    readonly property string icon: root.iconFor(root.percent)

    // The brightness page, reached only with more than one screen to dim:
    // declared, since the island takes its size before the panel exists — a
    // heading and a level for each screen.
    readonly property bool several: root.dimmable.length > 1
    readonly property int panelWidth: 440
    readonly property int panelHeight: 2 * Theme.panelPadding + Theme.detailHeader
        + Theme.detailSection(root.dimmable.length)

    function iconFor(percent: int): string {
        if (percent < 34)
            return "󰃞"
        return percent < 67 ? "󰃟" : "󰃠"
    }

    function setPercent(value: int): void {
        root.current?.setPercent(value)
    }

    function step(delta: int): void {
        root.current?.step(delta)
    }

    // A monitor's own buttons change it without telling anyone, so whatever
    // shows the levels asks for them again when it opens. A hardware read
    // takes a while, so it goes on its own connection and the answer comes
    // back as an event.
    function refresh(): void {
        if (!root.reader.connected)
            return
        for (const display of root.displays)
            root.reader.write(`refresh ${display.name}\n`)
        root.reader.flush()
    }

    function isPanel(name: string): bool {
        return /^(eDP|LVDS|DSI)-/.test(name)
    }


    // ── DAEMON ──────────────────────────────────────────────────────────────

    readonly property string socketPath: Quickshell.env("HYPR_BRIGHTNESS_SOCKET")
        || `${Quickshell.env("XDG_RUNTIME_DIR")}/hypr-brightness.sock`

    // Every output's last state, by name, and the order they came in.
    property var states: ({})
    property var names: []

    // The commands sent and not yet answered, oldest first: every command
    // has exactly one reply, and events are told apart by `event`.
    property var sent: []

    function send(command: string, output: string): bool {
        if (!root.connection.connected)
            return false
        root.sent.push(output)
        root.connection.write(`${command}\n`)
        root.connection.flush()
        return true
    }

    function displayFor(name: string): var {
        return root.displays.find(display => display.name === name) ?? null
    }

    function setOutputs(outputs: var): void {
        const states = {}
        for (const state of outputs)
            states[state.output] = state
        root.states = states
        root.names = outputs.map(state => state.output)
        for (const display of root.displays)
            display.apply(states[display.name], false)
    }

    function receive(line: string): void {
        let message
        try {
            message = JSON.parse(line)
        } catch (e) {
            return
        }
        if (message.event === "outputs") {
            root.setOutputs(message.outputs)
        } else if (message.event === "brightness" || message.event === "focus") {
            if (!(message.output in root.states)) {
                root.names = root.names.concat([message.output])
                root.states[message.output] = message
            }
            root.displayFor(message.output)?.apply(message,
                message.event === "brightness" && message.source === "user")
        } else if ("ok" in message) {
            const output = root.sent.shift()
            if (message.ok && message.outputs)
                root.setOutputs(message.outputs)
            else if (message.ok && output)
                root.displayFor(output)?.answered(message)
        }
    }

    readonly property Socket connection: Socket {
        path: root.socketPath
        connected: true
        parser: SplitParser {
            onRead: line => root.receive(line)
        }
        onConnectedChanged: {
            root.sent = []
            if (connected) {
                root.send("watch", "")
                root.send("status", "")
            } else {
                root.setOutputs([])
            }
        }
    }

    readonly property Socket reader: Socket {
        path: root.socketPath
        connected: true
        parser: SplitParser {}
    }

    // The daemon starts with the session and restarts on failure; until it
    // listens, try again every second.
    readonly property Timer reconnect: Timer {
        interval: 1000
        repeat: true
        running: !root.connection.connected || !root.reader.connected
        onTriggered: {
            root.connection.connected = true
            root.reader.connected = true
        }
    }


    // ── SCREENS ─────────────────────────────────────────────────────────────

    readonly property Variants variants: Variants {
        model: root.names

        QtObject {
            id: display

            required property string modelData

            readonly property string name: display.modelData
            readonly property ShellScreen screen: Quickshell.screens
                .find(screen => screen.name === display.name) ?? null
            readonly property bool panel: root.isPanel(display.name)
                || display.backend === "backlight"
            readonly property string title: display.panel
                ? "Built-in" : (display.screen?.model || display.name)

            property string backend: ""
            property bool available: false
            property int percent: 0
            readonly property string icon: root.iconFor(display.percent)

            // Levels sent and not yet answered. Until the last one is, the
            // daemon's echo of an older one would pull the level back.
            property int pending: 0

            function apply(state: var, user: bool): void {
                if (!state)
                    return
                display.backend = state.backend
                display.available = state.available
                if (display.pending > 0 || state.percent === display.percent)
                    return
                display.percent = state.percent
                if (user)
                    root.adjusted(display)
            }

            function answered(state: var): void {
                display.pending = Math.max(0, display.pending - 1)
                if (display.pending === 0)
                    display.apply(state, false)
            }

            function setPercent(value: int): void {
                if (!display.available)
                    return
                const clamped = Math.max(1, Math.min(100, value))
                if (clamped === display.percent)
                    return
                if (!root.send(`set ${clamped} ${display.name}`, display.name))
                    return
                display.percent = clamped
                display.pending++
                root.adjusted(display)
            }

            // From the level last asked for, so a held key steps on at once.
            // At either end it writes nothing, and still shows where it
            // stopped.
            function step(delta: int): void {
                const from = display.percent
                if (Math.max(1, Math.min(100, from + delta)) === from)
                    root.adjusted(display)
                else
                    display.setPercent(from + delta)
            }

            Component.onCompleted: display.apply(root.states[display.name], false)
        }
    }
}
