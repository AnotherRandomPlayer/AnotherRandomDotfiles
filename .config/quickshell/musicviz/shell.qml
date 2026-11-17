import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris

// Ola de audio al estilo Illogical Impulse, dibujada sobre la tarjeta de musica de eww.
ShellRoot {
    id: root

    // ---------- Ajustes (deben coincidir con la ventana "music" de eww) ----------
    readonly property int cardWidth: 660
    readonly property int cardHeight: 320
    readonly property int marginLeft: 24
    readonly property int marginBottom: 24
    readonly property int cardRadius: 36

    readonly property string home: Quickshell.env("HOME")
    readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string cavaConfig: home + "/.config/quickshell/ii/scripts/cava/raw_output_config.txt"
    readonly property string desktopScript: home + "/.config/eww/music/desktop-empty.sh"

    // ---------- Estado ----------
    property bool desktopEmpty: true
    property var points: []
    property real maxValue: 1000
    property color waveColor: "#cba6f7"

    readonly property bool playing: {
        const players = Mpris.players.values;
        for (let i = 0; i < players.length; i++) {
            if (players[i].isPlaying)
                return true;
        }
        return false;
    }
    readonly property bool active: desktopEmpty && playing

    // cava sigue corriendo un momento tras pausar, para que la ola se desvanezca
    property bool cavaWanted: false
    Timer {
        id: stopTimer
        interval: 1500
        repeat: false
        onTriggered: root.cavaWanted = false
    }
    onActiveChanged: {
        if (active) {
            stopTimer.stop();
            cavaWanted = true;
        } else {
            stopTimer.restart();
        }
    }
    Component.onCompleted: {
        if (active)
            cavaWanted = true;
    }

    // ---------- Escritorio libre (reutiliza el script de eww) ----------
    Process {
        command: [root.desktopScript]
        running: true
        stdout: SplitParser {
            onRead: data => root.desktopEmpty = (data.trim() !== "false")
        }
    }

    // ---------- Color dominante de la portada (lo escribe music-follow.sh) ----------
    FileView {
        id: colorFile
        path: root.runtime + "/eww-viz/color"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const t = text().trim();
            if (/^#[0-9A-Fa-f]{6}$/.test(t))
                root.waveColor = t;
        }
    }
    // Por si el archivo aparece despues de arrancar (o el aviso de inotify se pierde)
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: colorFile.reload()
    }

    // ---------- Escala de cava: la misma que usa Illogical Impulse ----------
    FileView {
        path: root.cavaConfig
        onLoaded: {
            const m = text().match(/ascii_max_range\s*=\s*(\d+)/);
            if (m)
                root.maxValue = parseInt(m[1]);
        }
    }

    // ---------- cava, con el mismo archivo de configuracion que Illogical Impulse ----------
    Process {
        running: root.cavaWanted
        command: ["cava", "-p", root.cavaConfig]
        onRunningChanged: {
            if (!running)
                root.points = [];
        }
        stdout: SplitParser {
            onRead: data => {
                root.points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
            }
        }
    }

    // ---------- Ventana transparente sobre la tarjeta ----------
    PanelWindow {
        visible: root.desktopEmpty && (root.playing || root.cavaWanted)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:musicviz"

        anchors {
            left: true
            bottom: true
        }
        margins {
            left: root.marginLeft
            bottom: root.marginBottom
        }
        implicitWidth: root.cardWidth
        implicitHeight: root.cardHeight

        // Los clics atraviesan la ventana (los botones de eww siguen funcionando)
        mask: Region {}

        Item {
            anchors.fill: parent
            opacity: root.active ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.InOutQuad
                }
            }

            // Recorta la ola con las esquinas redondeadas de la tarjeta
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: roundMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            WaveVisualizer {
                points: root.points
                maxVisualizerValue: root.maxValue
                live: root.playing
                color: root.waveColor
            }
        }

        Rectangle {
            id: roundMask
            anchors.fill: parent
            radius: root.cardRadius
            layer.enabled: true
            visible: false
        }
    }
}
