pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris

// Widget de escritorio (esquina inferior izquierda).
// Usa DesktopPlayerControl (copia visual de PlayerControl) y MprisController: la lógica de reproducción es la misma.
Scope {
    id: root

    // Mismo reproductor que usa el widget de media de la barra
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property real widgetWidth: Appearance.sizes.mediaControlsWidth
    readonly property real widgetHeight: Appearance.sizes.mediaControlsHeight
    readonly property real sizeFactor: 1.5 // tamaño real respecto al popup de la barra (1 = igual, 1.25, 1.5...)
    readonly property real fullWidth: widgetWidth * sizeFactor
    readonly property real fullHeight: (widgetHeight + 24) * sizeFactor // +24: sitio para la barra de progreso inferior
    readonly property real popupRounding: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    // Margen respecto al borde de la pantalla
    readonly property real marginLeft: Appearance.sizes.hyprlandGapsOut
    readonly property real marginBottom: (Config.options.bar.bottom && !Config.options.bar.vertical)
        ? Appearance.sizes.barHeight : Appearance.sizes.hyprlandGapsOut

    property list<real> visualizerPoints: []
    property bool ready: false // se activa con retraso para crear la ventana DESPUÉS del fondo de pantalla
    property int shownCount: 0 // nº de pantallas donde el widget está visible

    // Mismo cava y misma config que MediaControls; solo corre si se ve y suena algo
    Process {
        id: cavaProc
        running: root.shownCount > 0 && (root.activePlayer?.isPlaying ?? false)
        onRunningChanged: {
            if (!cavaProc.running)
                root.visualizerPoints = [];
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                root.visualizerPoints = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
            }
        }
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: root.ready = true
    }

    Variants {
        model: root.ready ? Quickshell.screens : []

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            // ---- Detección de "hay algo por encima" ----
            readonly property var monitor: Hyprland.monitorFor(win.screen)
            readonly property int workspaceId: monitor?.activeWorkspace?.id ?? -1

            // Rectángulo del widget en coordenadas globales de Hyprland
            readonly property real rectX: (monitor?.x ?? 0) + root.marginLeft
            readonly property real rectY: (monitor?.y ?? 0) + win.screen.height - root.marginBottom - root.fullHeight

            function isCovered(): bool {
                const wins = HyprlandData.windowList ?? [];
                for (let i = 0; i < wins.length; ++i) {
                    const w = wins[i];
                    if (!w || !w.at || !w.size || w.mapped === false || w.hidden || w.workspace?.id !== win.workspaceId)
                        continue;
                    const overlaps = w.at[0] < rectX + root.fullWidth && w.at[0] + w.size[0] > rectX
                                  && w.at[1] < rectY + root.fullHeight && w.at[1] + w.size[1] > rectY;
                    if (overlaps)
                        return true;
                }
                return false;
            }

            readonly property bool covered: isCovered()
            readonly property bool shown: !covered

            onShownChanged: root.shownCount += shown ? 1 : -1
            Component.onCompleted: if (shown) root.shownCount += 1
            Component.onDestruction: if (shown) root.shownCount -= 1

            // ---- Ventana en la capa de escritorio ----
            visible: content.opacity > 0
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "quickshell:desktopMedia"

            anchors {
                left: true
                bottom: true
            }
            margins {
                left: root.marginLeft
                bottom: root.marginBottom
            }
            // La ventana mide exactamente lo mismo que el contenido: así toda su superficie es clicable
            // y no hace falta una máscara de entrada que pueda quedarse desactualizada.
            implicitWidth: content.width
            implicitHeight: content.height

            Item {
                id: content
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: root.activePlayer ? root.fullWidth : placeholder.implicitWidth
                height: root.activePlayer ? root.fullHeight : placeholder.implicitHeight

                // Minimizar / restaurar
                opacity: win.shown ? 1 : 0
                scale: win.shown ? 1 : 0.6
                transformOrigin: Item.BottomLeft
                Behavior on opacity {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }

                // Hay multimedia: copia de PlayerControl con el nuevo diseño (tamaño real, sin escalar)
                Loader {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    width: root.fullWidth
                    height: root.fullHeight
                    active: root.activePlayer !== null
                    visible: active
                    sourceComponent: DesktopPlayerControl {
                        player: root.activePlayer
                        visualizerPoints: root.visualizerPoints
                        radius: root.popupRounding * root.sizeFactor
                        uiScale: root.sizeFactor
                        active: win.shown
                    }
                }

                // No hay multimedia: pastilla pequeña
                Item {
                    id: placeholder
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    visible: root.activePlayer === null
                    implicitWidth: placeholderBackground.implicitWidth + Appearance.sizes.elevationMargin
                    implicitHeight: placeholderBackground.implicitHeight + Appearance.sizes.elevationMargin

                    StyledRectangularShadow {
                        target: placeholderBackground
                    }
                    Rectangle {
                        id: placeholderBackground
                        anchors.centerIn: parent
                        color: Appearance.colors.colLayer0
                        radius: Appearance.rounding.full
                        implicitWidth: placeholderRow.implicitWidth + 28
                        implicitHeight: placeholderRow.implicitHeight + 16

                        RowLayout {
                            id: placeholderRow
                            anchors.centerIn: parent
                            spacing: 8

                            MaterialSymbol {
                                text: "music_off"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                text: Translation.tr("No media")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
        }
    }
}
