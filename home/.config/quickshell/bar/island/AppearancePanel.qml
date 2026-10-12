// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   A P P E A R A N C E   P A N E L                                        │
// │   animated wallpaper, wallpaper and palette picker                       │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Widgets

import "../../theme"
import "../../services"
import "../../components"

// Animated wallpapers, wallpapers, palettes and effects, each as a strip
// (`Carousel`): the tile in the middle large, its neighbours stepping away.
// Left and Right slide, Enter applies. Four pages top to bottom: Up and Down
// move between them, the second shortcut opens on the palettes, and the
// chevrons in the footer do it with the pointer.
//
// The wallpaper directories are rescanned whenever the panel opens, so there
// is no refresh button.
FocusScope {
    id: root

    signal closed()
    signal panelRequested(string panel)

    // The shortcut's page slides a panel that is already open. `shown` is
    // screen, which can also be `animated`, a page with no name of its own.
    property string page: "wallpaper"
    property string shown: root.page
    onPageChanged: root.shown = root.page

    readonly property var pages: ["animated", "wallpaper", "palette", "effects"]
    readonly property int shownIndex: root.pages.indexOf(root.shown)
    readonly property bool onPalette: root.shown === "palette"
    readonly property bool onAnimated: root.shown === "animated"
    readonly property bool onEffects: root.shown === "effects"

    readonly property int gap: 12
    readonly property int tileWidth: 160
    readonly property int tileHeight: 100
    readonly property real centreScale: 1.25
    readonly property int daub: 12
    readonly property int loadReach: 8

    readonly property Carousel strip:
        root.onEffects ? effects : root.onPalette ? palettes : root.onAnimated ? animations : wallpapers

    readonly property var centredWallpaper: WallpaperService.wallpapers[wallpapers.current] ?? null
    readonly property var centredAnimation: WallpaperService.animated[animations.current] ?? null
    readonly property var centredPalette: ThemeService.availableThemes[palettes.current] ?? null
    readonly property var centredEffect: WallpaperService.effects[effects.current] ?? null

    Component.onCompleted: {
        WallpaperService.scan()
        root.forceActiveFocus()
    }

    // Initial values for the strips' `current`, so they open on what is
    // applied instead of sliding there from the first tile. `settle` follows
    // the list when the scan returns a moment after opening.
    readonly property int appliedWallpaper: Math.max(0, WallpaperService.wallpapers.findIndex(
        entry => entry.path === WallpaperService.chosen))
    readonly property int appliedAnimation: Math.max(0, WallpaperService.animated.findIndex(
        entry => entry.path === WallpaperService.chosen))
    readonly property int activePalette: Math.max(0, ThemeService.availableThemes.findIndex(
        entry => entry.id === ThemeService.activeId))
    readonly property int appliedEffect: Math.max(0, WallpaperService.effects.findIndex(
        entry => entry.id === WallpaperService.currentEffect))
    onAppliedEffectChanged: effects.goTo(root.appliedEffect)

    function settle(): void {
        wallpapers.goTo(root.appliedWallpaper)
        animations.goTo(root.appliedAnimation)
        palettes.goTo(root.activePalette)
        effects.goTo(root.appliedEffect)
    }

    Connections {
        target: WallpaperService
        function onWallpapersChanged(): void { root.settle() }
        function onAnimatedChanged(): void { root.settle() }
        function onChosenChanged(): void { root.settle() }
        function onEffectsChanged(): void { root.settle() }
    }

    function apply(): void {
        if (root.onEffects) {
            if (root.centredEffect)
                WallpaperService.applyEffect(root.centredEffect.id)
        } else if (root.onPalette) {
            if (root.centredPalette)
                ThemeService.setTheme(root.centredPalette.id)
        } else if (root.onAnimated) {
            if (root.centredAnimation)
                WallpaperService.apply(root.centredAnimation.path)
        } else if (root.centredWallpaper) {
            WallpaperService.apply(root.centredWallpaper.path)
        }
    }

    // The page `delta` away, up or down. The named pages go through the
    // island, so its name follows; the animated one is this panel's own.
    function turn(delta: int): void {
        const index = root.shownIndex + delta
        if (index < 0 || index >= root.pages.length)
            return
        root.shown = root.pages[index]
        if (root.shown !== "animated")
            root.panelRequested(root.shown === "wallpaper" ? "appearance" : root.shown)
    }

    // Five daubs, in the board's order: the accent and the four status hues.
    // The adaptive entry shows the current theme until the wallpaper has been
    // read.
    function daubsOf(theme: var): var {
        const colors = theme.adaptive ? ThemeService.dynamicColors : theme.colors
        return colors
            ? [colors.accent, colors.green, colors.yellow, colors.red, colors.blue]
            : [Theme.accent, Theme.green, Theme.yellow, Theme.red, Theme.blue]
    }

    Keys.onLeftPressed: root.strip.step(-1)
    Keys.onRightPressed: root.strip.step(1)
    Keys.onDownPressed: root.turn(1)
    Keys.onUpPressed: root.turn(-1)
    Keys.onReturnPressed: root.apply()
    Keys.onEnterPressed: root.apply()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home)
            root.strip.goTo(0)
        else if (event.key === Qt.Key_End)
            root.strip.goTo(root.strip.count - 1)
        else if (event.key === Qt.Key_PageUp)
            root.strip.step(-5)
        else if (event.key === Qt.Key_PageDown)
            root.strip.step(5)
        else
            return
        event.accepted = true
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.gap

        // ── STRIPS ──────────────────────────────────────────────────────────

        // Each strip is parked a strip's height per page away
        // from the one shown, so turning the page slides them past each other.
        Item {
            id: pages

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Carousel {
                id: wallpapers

                width: pages.width
                height: pages.height
                y: (1 - root.shownIndex) * pages.height
                opacity: root.shownIndex === 1 ? 1 : 0
                current: root.appliedWallpaper
                model: WallpaperService.wallpapers
                tileWidth: root.tileWidth
                tileHeight: root.tileHeight
                centreScale: root.centreScale
                gap: root.gap
                onActivated: root.apply()

                Behavior on y { NumberAnimation { duration: Theme.durationMorph; easing.type: Theme.easing } }
                Behavior on opacity { NumberAnimation { duration: Theme.durationMorph; easing.type: Theme.easing } }

                delegate: CarouselTile {
                    id: tile

                    readonly property bool applied:
                        tile.modelData.path === WallpaperService.chosen

                    ClippingRectangle {
                        anchors.fill: parent
                        contentUnderBorder: true
                        radius: Theme.radiusMedium
                        color: Theme.surfaceIn(QsWindow.window)
                        border.color: tile.centred ? Theme.accent : Theme.borderIn(QsWindow.window)
                        border.width: tile.centred ? 2 : 1

                        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                        // Only tiles near the middle load a picture: decoding
                        // every wallpaper on open leaves the visible ones
                        // black for over a second. Qt caches decoded images,
                        // so stepping back does not read them again.
                        Image {
                            anchors.fill: parent
                            source: Math.abs(tile.distance) <= root.loadReach
                                ? `file://${tile.modelData.path}` : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 320
                            sourceSize.height: 200
                        }

                        AppliedMark { visible: tile.applied }
                    }
                }
            }

            Carousel {
                id: animations

                width: pages.width
                height: pages.height
                y: (0 - root.shownIndex) * pages.height
                opacity: root.onAnimated ? 1 : 0
                current: root.appliedAnimation
                model: WallpaperService.animated
                tileWidth: root.tileWidth
                tileHeight: root.tileHeight
                centreScale: root.centreScale
                gap: root.gap
                onActivated: root.apply()

                Behavior on y { NumberAnimation { duration: Theme.durationMorph; easing.type: Theme.easing } }
                Behavior on opacity { NumberAnimation { duration: Theme.durationMorph; easing.type: Theme.easing } }

                // Each tile is the video's poster, the frame it starts from.
                delegate: CarouselTile {
                    id: clip

                    readonly property bool applied:
                        clip.modelData.path === WallpaperService.chosen

                    ClippingRectangle {
                        anchors.fill: parent
                        contentUnderBorder: true
                        radius: Theme.radiusMedium
                        color: Theme.surfaceIn(QsWindow.window)
                        border.color: clip.centred ? Theme.accent : Theme.borderIn(QsWindow.window)
                        border.width: clip.centred ? 2 : 1

                        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                        Image {
                            anchors.fill: parent
                            source: Math.abs(clip.distance) <= root.loadReach
                                ? `file://${clip.modelData.poster}` : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 320
                            sourceSize.height: 200
                        }

                        AppliedMark { visible: clip.applied }
                    }
                }
            }

            // With no videos yet, where to put them.
            Text {
                x: (pages.width - width) / 2
                y: animations.y + (pages.height - height) / 2
                width: pages.width - 4 * root.gap
                visible: WallpaperService.animated.length === 0
                opacity: animations.opacity
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Tr.t("No animated wallpapers yet. Videos in ~/.local/share/wallpapers/animated show up here.")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }

            Carousel {
                id: palettes

                width: pages.width
                height: pages.height
                y: (2 - root.shownIndex) * pages.height
                opacity: root.onPalette ? 1 : 0
                current: root.activePalette
                model: ThemeService.availableThemes
                tileWidth: root.tileWidth
                tileHeight: root.tileHeight
                centreScale: root.centreScale
                gap: root.gap
                onActivated: root.apply()

                Behavior on y { NumberAnimation { duration: Theme.durationMorph; easing.type: Theme.easing } }
                Behavior on opacity { NumberAnimation { duration: Theme.durationMorph; easing.type: Theme.easing } }

                delegate: CarouselTile {
                    id: card

                    readonly property bool applied: card.modelData.id === ThemeService.activeId

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusMedium
                        color: card.hovered ? Theme.surfaceHoverIn(QsWindow.window) : Theme.surfaceIn(QsWindow.window)
                        border.color: card.centred ? Theme.accent : Theme.borderIn(QsWindow.window)
                        border.width: card.centred ? 2 : 1

                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 10

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 6

                                Repeater {
                                    model: root.daubsOf(card.modelData)

                                    Rectangle {
                                        required property var modelData

                                        width: root.daub
                                        height: root.daub
                                        radius: width / 2
                                        color: modelData
                                        border.color: Theme.hairline
                                        border.width: 1

                                        Behavior on color { ColorAnimation { duration: Theme.paletteTransition } }
                                    }
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: card.modelData.name
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: card.centred ? Font.DemiBold : Font.Normal
                                color: card.centred ? Theme.text : Theme.textMuted
                            }
                        }

                        AppliedMark { visible: card.applied }
                    }
                }
            }

            Carousel {
                id: effects

                width: pages.width
                height: pages.height
                y: (3 - root.shownIndex) * pages.height
                opacity: root.onEffects ? 1 : 0
                current: root.appliedEffect
                model: WallpaperService.effects
                tileWidth: root.tileWidth
                tileHeight: root.tileHeight
                centreScale: root.centreScale
                gap: root.gap
                onActivated: root.apply()

                Behavior on y { NumberAnimation { duration: Theme.durationMorph; easing.type: Theme.easing } }
                Behavior on opacity { NumberAnimation { duration: Theme.durationMorph; easing.type: Theme.easing } }

                delegate: CarouselTile {
                    id: effect

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusMedium
                        color: effect.hovered ? Theme.surfaceHoverIn(QsWindow.window) : Theme.surfaceIn(QsWindow.window)
                        border.color: effect.centred ? Theme.accent : Theme.borderIn(QsWindow.window)
                        border.width: effect.centred ? 2 : 1

                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 16
                            spacing: 10

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: effect.modelData.id === "none" ? "󰸉" : "󰔎"
                                font.family: Theme.fontMono
                                font.pixelSize: 24
                                color: effect.centred ? Theme.accent : Theme.textMuted
                            }

                            Text {
                                width: parent.width
                                text: Tr.t(effect.modelData.name)
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: effect.centred ? Font.DemiBold : Font.Normal
                                color: effect.centred ? Theme.text : Theme.textMuted
                            }
                        }

                        AppliedMark { visible: effect.modelData.id === WallpaperService.currentEffect }
                    }
                }
            }
        }

        // ── FOOTER ──────────────────────────────────────────────────────────

        RowLayout {
            Layout.fillWidth: true
            spacing: root.gap

            Text {
                Layout.fillWidth: true
                text: root.onEffects ? (WallpaperService.processingEffect
                        ? Tr.t("Applying…") : Tr.t(root.centredEffect?.name ?? ""))
                    : root.onPalette ? (root.centredPalette?.badge ?? "")
                    : root.onAnimated ? (root.centredAnimation?.name ?? "")
                    : (root.centredWallpaper?.name ?? "")
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }

            // Position in the strip; the tile's mark already shows what is
            // applied.
            Text {
                text: root.strip.count === 0
                    ? (WallpaperService.scanning ? "Scanning…" : "")
                    : `${root.strip.current + 1}/${root.strip.count}`
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }

            // Switch pages with the pointer: up, and down, where there is one.
            Door {
                glyph: "󰅃"
                visible: root.shownIndex > 0
                onClicked: root.turn(-1)
            }

            Door {
                glyph: "󰅀"
                visible: root.shownIndex < root.pages.length - 1
                onClicked: root.turn(1)
            }
        }
    }

    component Door: Text {
        id: door

        property string glyph: ""
        signal clicked()

        text: door.glyph
        font.family: Theme.fontMono
        font.pixelSize: Theme.fontSizeRegular
        color: doorMouse.containsMouse ? Theme.text : Theme.textMuted

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

        MouseArea {
            id: doorMouse

            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: door.clicked()
        }
    }

    // The check on what is applied, distinct from the accent ring, which
    // marks the position in the strip.
    component AppliedMark: Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 6
        width: 18
        height: 18
        radius: width / 2
        color: Theme.accent

        Text {
            anchors.centerIn: parent
            text: "󰄬"
            font.family: Theme.fontMono
            font.pixelSize: 10
            color: Theme.accentText
        }
    }
}
