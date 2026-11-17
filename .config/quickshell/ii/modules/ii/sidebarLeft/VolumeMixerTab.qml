import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.volumeMixer

// Mezclador de volumen para el sidebar izquierdo.
// Reutiliza VolumeDialogContent (el mismo que usa el overlay y el sidebar derecho),
// así que no hay lógica de audio duplicada.
Item {
    id: root

    // Pestaña activa (Output / Input). Local, no depende del estado del overlay.
    property int tabIndex: 0

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        SecondaryTabBar {
            id: tabBar
            Layout.fillWidth: true

            currentIndex: root.tabIndex
            onCurrentIndexChanged: root.tabIndex = tabBar.currentIndex

            SecondaryTabButton {
                buttonIcon: "media_output"
                buttonText: Translation.tr("Output")
            }
            SecondaryTabButton {
                buttonIcon: "mic"
                buttonText: Translation.tr("Input")
            }
        }

        SwipeView {
            id: swipeView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            currentIndex: root.tabIndex
            onCurrentIndexChanged: root.tabIndex = swipeView.currentIndex

            PaddedVolumeDialogContent {
                isSink: true
            }
            PaddedVolumeDialogContent {
                isSink: false
            }
        }
    }

    component PaddedVolumeDialogContent: Item {
        id: paddedVolumeDialogContent
        property alias isSink: volDialogContent.isSink
        property real padding: 12
        implicitWidth: volDialogContent.implicitWidth + padding * 2
        implicitHeight: volDialogContent.implicitHeight + padding * 2

        VolumeDialogContent {
            id: volDialogContent
            anchors {
                fill: parent
                margins: paddedVolumeDialogContent.padding
            }
        }
    }
}
