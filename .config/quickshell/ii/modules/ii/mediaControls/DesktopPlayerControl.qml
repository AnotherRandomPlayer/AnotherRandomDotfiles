pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item { // Player instance
    id: root
    required property MprisPlayer player
    // Spotify entrega por MPRIS la portada de 300px (ab67616d00001e02); se pide la de 640px (ab67616d0000b273)
    property string artUrl: String(player?.trackArtUrl ?? "").replace("ab67616d00001e02", "ab67616d0000b273")
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property color artDominantColor: ColorUtils.mix((colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary), Appearance.colors.colPrimaryContainer, 0.8) || Appearance.m3colors.m3secondaryContainer
    property bool downloaded: false
    property list<real> visualizerPoints: []
    property real maxVisualizerValue: 1000 // Max value in the data points
    property int visualizerSmoothing: 2 // Number of points to average for smoothing
    property real radius
    property bool active: true // false cuando el widget está oculto: se paran timers y animaciones
    property real uiScale: 1 // tamaño real del widget (no es un escalado de imagen, así no se ve borroso)

    property string displayedArtFilePath: root.downloaded ? Qt.resolvedUrl(artFilePath) : ""

    component TrackChangeButton: RippleButton {
        implicitWidth: 32 * root.uiScale
        implicitHeight: 32 * root.uiScale

        property var iconName
        colBackground: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 1)
        colBackgroundHover: blendedColors.colSecondaryContainerHover
        colRipple: blendedColors.colSecondaryContainerActive

        contentItem: MaterialSymbol {
            iconSize: Appearance.font.pixelSize.huge * root.uiScale
            fill: 1
            horizontalAlignment: Text.AlignHCenter
            color: blendedColors.colOnSecondaryContainer
            text: iconName

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    Timer { // Force update for revision (solo para resincronizar)
        running: root.active && root.player?.playbackState == MprisPlaybackState.Playing
        interval: 1000
        repeat: true
        onTriggered: {
            root.player.positionChanged()
        }
    }

    // --- Posición suavizada ---
    // MPRIS solo da la posición cuando se le pregunta, no de forma continua. Entre consultas
    // se avanza con el reloj (anchorPosition + tiempo transcurrido) y solo se corrige si la
    // posición real se desvía, o al pausar, saltar o cambiar de canción.
    property real anchorPosition: 0
    property double anchorTime: Date.now()
    property real smoothPosition: 0
    readonly property int smoothSeconds: Math.floor(root.smoothPosition) // cambia 1 vez/s, evita reevaluar textos 30 veces/s
    readonly property real smoothValue: (root.player?.length ?? 0) > 0
        ? Math.max(0, Math.min(1, root.smoothPosition / root.player.length)) : 0

    function elapsedPosition() {
        return root.anchorPosition + (Date.now() - root.anchorTime) / 1000
    }

    function anchorAt(pos) {
        root.anchorPosition = pos
        root.anchorTime = Date.now()
        root.smoothPosition = pos
    }

    property double seekHoldUntil: 0 // tras un salto, ignora la posición vieja que aún reporte el reproductor

    function seekTo(pos) {
        root.player.position = pos
        root.anchorAt(pos)
        root.seekHoldUntil = Date.now() + 1500
    }

    function resync(force) {
        if (!force && Date.now() < root.seekHoldUntil)
            return
        const actual = root.player?.position ?? 0
        const playing = root.player?.isPlaying ?? false
        if (force || !playing || Math.abs(actual - root.elapsedPosition()) > 2)
            root.anchorAt(actual)
    }

    Timer { // Actualiza la barra unas 30 veces por segundo
        interval: 33
        repeat: true
        running: root.active && (root.player?.isPlaying ?? false)
        onTriggered: root.smoothPosition = Math.min(root.elapsedPosition(), root.player?.length ?? Infinity)
    }

    Connections {
        target: root.player
        function onPositionChanged() { root.resync(false) }
        function onIsPlayingChanged() { root.resync(true) }
        function onTrackTitleChanged() { root.resync(true) }
    }
    Component.onCompleted: resync(true)
    onActiveChanged: if (active) resync(true) // al reaparecer, recoloca la barra

    onArtFilePathChanged: {
        if (root.artUrl.length == 0) {
            root.artDominantColor = Appearance.m3colors.m3secondaryContainer
            return;
        }

        // Binding does not work in Process
        coverArtDownloader.targetFile = root.artUrl 
        coverArtDownloader.artFilePath = root.artFilePath
        // Download
        root.downloaded = false
        coverArtDownloader.running = true
    }

    Process { // Cover art downloader
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        command: [ "bash", "-c", `[ -f ${artFilePath} ] || curl -4 -sSL '${targetFile}' -o '${artFilePath}'` ]
        onExited: (exitCode, exitStatus) => {
            root.downloaded = true
        }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0 // 2^0 = 1 color
        rescaleSize: 1 // Rescale to 1x1 pixel for faster processing
    }

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: artDominantColor
    }

    StyledRectangularShadow {
        target: background
    }
    Rectangle { // Background
        id: background
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        color: ColorUtils.applyAlpha(blendedColors.colLayer0, 1)
        radius: root.radius

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: background.width
                height: background.height
                radius: background.radius
            }
        }

        StyledImage {
            id: blurredArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            fillMode: Image.PreserveAspectCrop
            cache: false
            antialiasing: true
            asynchronous: true

            layer.enabled: true
            layer.effect: StyledBlurEffect {
                source: blurredArt
            }

            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(blendedColors.colLayer0, 0.3)
                radius: root.radius
            }
        }

        WaveVisualizer {
            id: visualizerCanvas
            anchors.fill: parent
            live: root.active && (root.player?.isPlaying ?? false)
            points: root.visualizerPoints
            maxVisualizerValue: root.maxVisualizerValue
            smoothing: root.visualizerSmoothing
            color: blendedColors.colPrimary
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 13 * root.uiScale
            spacing: 10 * root.uiScale

            RowLayout { // Cover (left) + info & controls (right)
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 15 * root.uiScale

                Rectangle { // Art background
                    id: artBackground
                    Layout.fillHeight: true
                    implicitWidth: height
                    radius: Appearance.rounding.verysmall * root.uiScale
                    color: ColorUtils.transparentize(blendedColors.colLayer1, 0.5)

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: artBackground.width
                            height: artBackground.height
                            radius: artBackground.radius
                        }
                    }

                    StyledImage { // Art image
                        id: mediaArt
                        anchors.fill: parent
                        source: root.displayedArtFilePath
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        antialiasing: true
                        smooth: true
                        mipmap: true
                        // Cargar la imagen al doble de resolución para que no se vea borrosa
                        sourceSize.width: Math.max(1, width) * 2
                        sourceSize.height: Math.max(1, height) * 2
                    }
                }

                ColumnLayout { // Title, artist, buttons (centered)
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 2 * root.uiScale

                    Item { Layout.fillHeight: true }

                    StyledText {
                        id: trackTitle
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.larger * root.uiScale
                        color: blendedColors.colOnLayer0
                        elide: Text.ElideRight
                        text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || "Untitled"
                        animateChange: true
                        animationDistanceX: 6
                        animationDistanceY: 0
                    }
                    StyledText {
                        id: trackArtist
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smaller * root.uiScale
                        color: blendedColors.colSubtext
                        elide: Text.ElideRight
                        text: root.player?.trackArtist
                        animateChange: true
                        animationDistanceX: 6
                        animationDistanceY: 0
                    }

                    Item { Layout.preferredHeight: 8 * root.uiScale }

                    RowLayout { // previous | play/pause | next
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8 * root.uiScale

                        TrackChangeButton {
                            iconName: "skip_previous"
                            downAction: () => root.player?.previous()
                        }

                        RippleButton {
                            id: playPauseButton
                            property real size: 44 * root.uiScale
                            implicitWidth: size
                            implicitHeight: size
                            downAction: () => root.player.togglePlaying()

                            buttonRadius: root.player?.isPlaying ? Appearance?.rounding.normal * root.uiScale : size / 2
                            colBackground: root.player?.isPlaying ? blendedColors.colPrimary : blendedColors.colSecondaryContainer
                            colBackgroundHover: root.player?.isPlaying ? blendedColors.colPrimaryHover : blendedColors.colSecondaryContainerHover
                            colRipple: root.player?.isPlaying ? blendedColors.colPrimaryActive : blendedColors.colSecondaryContainerActive

                            contentItem: MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.huge * root.uiScale
                                fill: 1
                                horizontalAlignment: Text.AlignHCenter
                                color: root.player?.isPlaying ? blendedColors.colOnPrimary : blendedColors.colOnSecondaryContainer
                                text: root.player?.isPlaying ? "pause" : "play_arrow"

                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }
                        }

                        TrackChangeButton {
                            iconName: "skip_next"
                            downAction: () => root.player?.next()
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            RowLayout { // Bottom row: elapsed time | progress bar | total time
                Layout.fillWidth: true
                spacing: 8 * root.uiScale

                TextMetrics { // Ancho fijo para los tiempos: el de la cadena más ancha posible
                    id: timeMetrics
                    font: elapsedTime.font
                    text: (root.player?.length ?? 0) >= 3600 ? "00:00:00" : "00:00"
                }

                StyledText {
                    id: elapsedTime
                    Layout.preferredWidth: Math.ceil(timeMetrics.advanceWidth) + 2
                    Layout.minimumWidth: Layout.preferredWidth
                    horizontalAlignment: Text.AlignLeft
                    font.pixelSize: Appearance.font.pixelSize.small * root.uiScale
                    color: blendedColors.colSubtext
                    text: StringUtils.friendlyTimeForSeconds(root.smoothSeconds)
                }

                Item { // Progress bar: full-width bottom row
                    id: progressBarContainer
                    Layout.fillWidth: true
                    implicitHeight: Math.max(sliderLoader.implicitHeight, progressBarLoader.implicitHeight)

                    Loader {
                        id: sliderLoader
                        anchors.fill: parent
                        active: root.player?.canSeek ?? false
                        sourceComponent: StyledSlider {
                            id: seekSlider
                            configuration: StyledSlider.Configuration.Wavy
                            highlightColor: blendedColors.colPrimary
                            trackColor: blendedColors.colSecondaryContainer
                            handleColor: blendedColors.colPrimary
                            trackDotSize: 0 // quita el puntito blanco del final de la barra

                            // Mientras se arrastra, el slider obedece al ratón; el resto del tiempo sigue a la canción
                            Binding on value {
                                when: !seekSlider.pressed
                                value: root.smoothValue
                                restoreMode: Binding.RestoreNone
                            }
                            // El salto se hace una sola vez, al soltar
                            onPressedChanged: {
                                if (!pressed && root.player)
                                    root.seekTo(value * root.player.length)
                            }
                        }
                    }

                    Loader {
                        id: progressBarLoader
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            right: parent.right
                        }
                        active: !(root.player?.canSeek ?? false)
                        sourceComponent: StyledProgressBar {
                            wavy: root.player?.isPlaying
                            highlightColor: blendedColors.colPrimary
                            trackColor: blendedColors.colSecondaryContainer
                            value: root.smoothValue
                        }
                    }
                }

                StyledText {
                    id: totalTime
                    Layout.preferredWidth: Math.ceil(timeMetrics.advanceWidth) + 2
                    Layout.minimumWidth: Layout.preferredWidth
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: Appearance.font.pixelSize.small * root.uiScale
                    color: blendedColors.colSubtext
                    text: StringUtils.friendlyTimeForSeconds(root.player?.length)
                }
            }
        }
    }
}
