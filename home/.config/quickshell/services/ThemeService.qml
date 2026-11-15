// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   T H E M E   S E R V I C E                                              │
// │   active palette · persistence and adaptive colours                      │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

import "../theme"

// Owns which palette is active and keeps that choice across restarts.
QtObject {
    id: root

    readonly property string script: Quickshell.shellPath("scripts/theme_manager.py")

    property string activeId: "adaptive"
    property var adaptiveColors: ({})
    readonly property var dynamicColors: root.adaptiveColors[root.isAdaptive(root.activeId) ? root.activeId : "adaptive"] ?? null

    // The adaptive entry has no static colours: they come from the wallpaper.
    readonly property var adaptiveTheme: ({
        id: "adaptive",
        name: "Adaptive (Wallpaper)",
        badge: "From Wallpaper",
        adaptive: true,
        colors: null
    })

    // Built from Palettes so a palette is described exactly once.
    readonly property var adaptiveThemes: [
        root.adaptiveTheme,
        { id: "adaptive-dominant", name: "Adaptive · Dominant", badge: "Most Area", adaptive: true, colors: null },
        { id: "adaptive-muted", name: "Adaptive · Muted", badge: "Soft Tone", adaptive: true, colors: null },
        { id: "adaptive-complement", name: "Adaptive · Complement", badge: "Opposite Hue", adaptive: true, colors: null }
    ]

    readonly property var availableThemes: root.adaptiveThemes.concat(Palettes.list)

    function isAdaptive(themeId: string): bool {
        return root.adaptiveThemes.some(entry => entry.id === themeId)
    }

    function adaptiveEntry(themeId: string): var {
        return root.adaptiveThemes.find(entry => entry.id === themeId) ?? root.adaptiveTheme
    }

    function adaptiveColorsOf(themeId: string): var {
        return root.adaptiveColors[themeId] ?? null
    }

    // The wallpaper colours once extracted, the current theme until then.
    readonly property var adaptiveSwatches: root.dynamicColors
        ? [root.dynamicColors.background, root.dynamicColors.surface,
           root.dynamicColors.accent, root.dynamicColors.text]
        : [Theme.background, Theme.surface, Theme.accent, Theme.text]

    // Restores the persisted choice on startup.
    readonly property Process stateProcess: Process {
        command: [root.script, "get-state"]
        running: true
        stdout: StdioCollector {
            // streamFinished, not textChanged: the collector fires per chunk
            // and JSON.parse on half a document throws.
            onStreamFinished: {
                const state = root.parseJson(text, "shell state")
                if (state && state.activeTheme)
                    root.setTheme(state.activeTheme, false)
            }
        }
    }

    readonly property Process extractProcess: Process {
        command: [root.script, "extract-variants"]
        stdout: StdioCollector {
            onStreamFinished: {
                const variants = root.parseJson(text, "wallpaper colours")
                if (!variants)
                    return
                root.adaptiveColors = variants
                const colors = root.dynamicColors
                if (colors && root.isAdaptive(root.activeId)) {
                    Theme.apply(root.look(colors), root.adaptiveEntry(root.activeId).name)
                    root.pushTerminal(colors)
                }
            }
        }
    }

    readonly property Process persistProcess: Process {}

    // The applications to write, as the shell holds them, ahead of the
    // settings file's next write.
    readonly property Process terminalProcess: Process {
        environment: ({ IMPASTO_THEME_TARGETS: root.themeTargets })
        onExited: {
            const colors = root.pendingColors
            root.pendingColors = null
            if (colors)
                root.pushTerminal(colors)
        }
    }

    // ── FONT ────────────────────────────────────────────────────────────────
    //
    // The monospace family is pushed to kitty so the terminal follows the
    // setting.
    readonly property string terminalFont: SettingsService.fontMono

    onTerminalFontChanged: root.pushTerminalFont()

    function pushTerminalFont(): void {
        if (!SettingsService.arrived)
            return
        root.fontProcess.command = [root.script, "push-terminal-font",
                                    SettingsService.fontMono]
        if (root.fontProcess.running)
            root.fontAgain = true
        else
            root.fontProcess.running = true
    }

    // A push asked for while one runs goes again when it exits; a running
    // Process ignores being started.
    property bool fontAgain: false
    readonly property Process fontProcess: Process {
        onExited: if (root.fontAgain) {
            root.fontAgain = false
            root.pushTerminalFont()
        }
    }

    // ── GROUND ──────────────────────────────────────────────────────────────
    //
    // The terminal's ground, chosen beside the shell's.
    readonly property string terminalGround: SettingsService.terminalGround

    readonly property bool pureBlack: SettingsService.pureBlack

    onPureBlackChanged: if (SettingsService.arrived) root.setTheme(root.activeId, false)

    function darken(value: string, amount: real): string {
        const c = Qt.color(value)
        return Qt.rgba(c.r * (1 - amount), c.g * (1 - amount), c.b * (1 - amount), 1).toString()
    }

    function look(colors: var): var {
        if (!colors || !root.pureBlack)
            return colors
        const ground = Qt.color(colors.background)
        if (0.2126 * ground.r + 0.7152 * ground.g + 0.0722 * ground.b > 0.5)
            return colors
        return Object.assign({}, colors, {
            background: "#000000",
            surface: root.darken(colors.surface, 0.6),
            surfaceHover: root.darken(colors.surfaceHover, 0.4),
            border: root.darken(colors.border, 0.25)
        })
    }

    onTerminalGroundChanged: root.pushTerminalGround()

    function pushTerminalGround(): void {
        if (!SettingsService.arrived)
            return
        root.groundProcess.command = [root.script, "push-terminal-ground",
                                      SettingsService.terminalGround]
        if (root.groundProcess.running)
            root.groundAgain = true
        else
            root.groundProcess.running = true
    }

    property bool groundAgain: false
    readonly property Process groundProcess: Process {
        onExited: if (root.groundAgain) {
            root.groundAgain = false
            root.pushTerminalGround()
        }
    }

    // Also pushed at startup, once the settings are read: before that they
    // hold the defaults, and a setting that never changes would leave the
    // fragment kitty.conf includes unwritten.
    function pushTerminalSettings(): void {
        root.pushTerminalFont()
        root.pushTerminalGround()
        root.pushGreeting()
    }

    Component.onCompleted: root.pushTerminalSettings()

    readonly property Connections settingsArrival: Connections {
        target: SettingsService
        function onArrivedChanged(): void {
            root.pushedTargets = root.themeTargets
            root.pushTerminalSettings()
            if (root.pureBlack)
                root.setTheme(root.activeId, false)
        }
    }

    // ── GREETING ────────────────────────────────────────────────────────────
    //
    // Which scene `fa` shows. The palette push redraws all of them
    // (`greeting.py`); this only records the choice. `random` is resolved
    // by `fa`.
    readonly property var greetings: [
        { id: "lava", label: "Lava lamp" },
        { id: "critters", label: "Critters" },
        { id: "koi", label: "Koi" },
        { id: "invaders", label: "Invaders" },
        { id: "random", label: "Random" }
    ]

    readonly property string greetingScript: Quickshell.shellPath("scripts/greeting.py")
    readonly property string greeting: SettingsService.greeting

    onGreetingChanged: root.pushGreeting()

    // A running Process ignores being started again, so queue the latest
    // pick.
    property bool greetingPending: false

    function pushGreeting(): void {
        if (root.greetingProcess.running) {
            root.greetingPending = true
            return
        }
        root.greetingProcess.command = [root.greetingScript, "choose", SettingsService.greeting]
        root.greetingProcess.running = true
    }

    readonly property Process greetingProcess: Process {
        onExited: {
            if (root.greetingPending) {
                root.greetingPending = false
                root.pushGreeting()
            }
        }
    }

    // Written by `greeting.py` once every scene is redrawn. The settings
    // tiles reload on this rather than on the palette change, when the new
    // scenes are still being drawn.
    property string greetingStamp: ""

    readonly property FileView greetingStampView: FileView {
        path: `${SettingsService.stateDirectory}/greeting.stamp`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.greetingStamp = text().trim()
    }

    // The backend writes the colour fragment kitty.conf includes and repaints
    // open kitty windows.
    function pushTerminal(colors: var): void {
        if (!colors)
            return
        if (root.terminalProcess.running) {
            root.pendingColors = colors
            return
        }
        root.terminalProcess.command = [root.script, "push-terminal-palette",
                                        JSON.stringify(root.look(colors))]
        root.terminalProcess.running = true
    }

    // A push asked for while one runs, sent when it ends.
    property var pendingColors: null

    // The colours on screen, for a push that is not a change of palette.
    function currentColors(): var {
        if (root.isAdaptive(root.activeId))
            return root.dynamicColors
        return Palettes.byId(root.activeId)?.colors ?? null
    }

    // A program switched back on in Settings is painted at once rather than
    // on the next change of palette. Compared as text, since a reload of the
    // settings file announces the list again unchanged.
    property string pushedTargets: ""
    readonly property string themeTargets: JSON.stringify(SettingsService.themeTargets ?? null)
    onThemeTargetsChanged: {
        const before = root.pushedTargets
        root.pushedTargets = root.themeTargets
        if (SettingsService.arrived && before !== root.themeTargets)
            root.pushTerminal(root.currentColors())
    }

    function parseJson(text: string, what: string): var {
        if (!text || text.trim() === "")
            return null
        try {
            return JSON.parse(text)
        } catch (error) {
            console.warn(`Cannot parse ${what}:`, error)
            return null
        }
    }

    function reloadAdaptiveColors(): void {
        root.extractProcess.running = true
    }

    function setTheme(themeId: string, persist = true): void {
        root.activeId = themeId
        Theme.activeId = themeId

        if (root.isAdaptive(themeId)) {
            if (root.dynamicColors) {
                Theme.apply(root.look(root.dynamicColors), root.adaptiveEntry(themeId).name)
                root.pushTerminal(root.dynamicColors)
            } else {
                root.reloadAdaptiveColors()
            }
        } else {
            const palette = Palettes.byId(themeId)
            if (palette) {
                Theme.apply(root.look(palette.colors), palette.name)
                root.pushTerminal(palette.colors)
            } else {
                console.warn("Unknown palette:", themeId)
            }
        }

        if (persist) {
            root.persistProcess.command = [root.script, "set-theme", themeId]
            root.persistProcess.running = true
        }
    }
}
