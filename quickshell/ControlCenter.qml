// ControlCenter.qml — Centro de control estilo "isla dinámica" para Quickshell.
// Reimplementación limpia del antiguo control center embebido en shell.qml.
//
// Depende de `shellRoot` (el PanelWindow de shell.qml) para:
//   - Estado: volumeOut/volumeMuted, volumeMic/micMuted, brightnessLevel/hasBacklight,
//     wifiText/wifiIcon, bluetoothStatus, temperature, updates,
//     mediaStatus/mediaText/mediaPlaying
//   - Acciones (property alias ccXxx que apuntan a los Process de shell.qml):
//     ccVolMute/ccVolSet, ccMicMute/ccMicSet, ccBrightSet,
//     ccWifiToggle, ccBtToggle, ccMediaPrev/ccMediaPlay/ccMediaNext
//   - Popups (property alias ccXxx que apuntan a los popups de shell.qml):
//     ccWifiMenu, ccBluetoothMenu, ccAppLauncher, ccClipboard, ccTheme, ccPower
//
// NOTA: los alias existen porque los `id` de objetos hijos de otro documento QML
// NO son accesibles vía una referencia `var` a la instancia del otro documento.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: cc

    property bool show: false
    property var shellRoot
    property real animHeight: animRect.height
    property bool audioOutExpanded: false

    WlrLayershell.keyboardFocus: show ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // Se mantiene mapeado hasta que la animación de cierre termina (opacity 0)
    visible: show || animRect.opacity > 0

    onShowChanged: { if (show) focusTimer.start() }

    Timer {
        id: focusTimer
        interval: 50
        onTriggered: ccContent.forceActiveFocus()
    }

    // ------------------------------------------------------------------
    // Sub-componentes reutilizables
    // ------------------------------------------------------------------

    component CCSlider: Slider {
        id: sld
        Layout.fillWidth: true
        Layout.preferredHeight: 24
        Layout.alignment: Qt.AlignVCenter
        from: 0
        to: 1.0

        background: Rectangle {
            x: sld.leftPadding
            y: sld.topPadding + sld.availableHeight / 2 - height / 2
            implicitWidth: 200
            implicitHeight: 6
            width: sld.availableWidth
            height: implicitHeight
            radius: 3
            color: Qt.rgba(1, 1, 1, 0.12)

            Rectangle {
                width: sld.visualPosition * parent.width
                height: parent.height
                radius: 3
                color: "#ffffff"
            }
        }

        handle: Rectangle {
            x: sld.leftPadding + sld.visualPosition * (sld.availableWidth - width)
            y: sld.topPadding + sld.availableHeight / 2 - height / 2
            width: 14
            height: 14
            radius: 7
            color: sld.pressed ? Qt.rgba(0.9, 0.9, 0.9, 1) : "#ffffff"
            scale: sld.pressed ? 1.15 : 1.0
            Behavior on scale { NumberAnimation { duration: 100 } }
        }
    }

    component SliderRow: Item {
        id: srow
        property string icon
        property string iconMuted
        property bool muted: false
        property real value: 0
        signal iconClicked()
        signal valueMoved(real v)

        Layout.fillWidth: true
        Layout.preferredHeight: 28

        RowLayout {
            anchors.fill: parent
            spacing: 12

            Item {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignVCenter

                Text {
                    anchors.centerIn: parent
                    text: srow.muted ? srow.iconMuted : srow.icon
                    color: srow.muted ? Qt.rgba(1, 1, 1, 0.4) : "#ffffff"
                    font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                    font.pixelSize: 17
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: srow.iconClicked()
                }
            }

            CCSlider {
                value: srow.value
                onMoved: srow.valueMoved(value)
            }
        }
    }

    // Baldosa para Wi-Fi / Bluetooth / Ethernet: clic principal alterna, chevron abre el menú.
    // `pulse` late el círculo mientras se alterna; `radar` dibuja un anillo de búsqueda.
    component ToggleTile: Item {
        id: tile
        property string icon
        property string label
        property string status
        property string busyText: "…"
        property bool active: false
        property bool busy: false
        property bool pulse: false
        property bool radar: false
        property bool menuVisible: true
        property color accent: "#007AFF"
        signal clicked()
        signal menuClicked()

        Layout.fillWidth: true
        Layout.preferredHeight: 44

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: mainArea.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
            border.color: tile.busy || tile.active ? Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.45) : "transparent"
            border.width: 1
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 8

            Item {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    id: circleRect
                    anchors.fill: parent
                    radius: width / 2
                    color: tile.busy ? Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.85)
                                     : tile.active ? tile.accent
                                     : Qt.rgba(1, 1, 1, 0.12)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    // Latido del círculo mientras se ejecuta el toggle.
                    SequentialAnimation on scale {
                        running: tile.pulse
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 1.3; duration: 300; easing.type: Easing.OutCubic }
                        NumberAnimation { from: 1.3; to: 1.0; duration: 300; easing.type: Easing.InCubic }
                    }

                    BusyIndicator {
                        anchors.centerIn: parent
                        width: 14
                        height: 14
                        visible: tile.busy
                    }

                    Text {
                        anchors.centerIn: parent
                        text: tile.icon
                        color: "#ffffff"
                        font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                        font.pixelSize: 13
                        visible: !tile.busy
                    }
                }

                // Radar: anillo que se expande y se desvanece (búsqueda de redes).
                Rectangle {
                    id: radarRing
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.color: Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.7)
                    border.width: 1.5
                    visible: tile.radar
                    SequentialAnimation on scale {
                        running: tile.radar
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 2.4; duration: 1100; easing.type: Easing.OutCubic }
                    }
                    SequentialAnimation on opacity {
                        running: tile.radar
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.8; to: 0.0; duration: 1100; easing.type: Easing.OutCubic }
                    }
                }
            }

            ColumnLayout {
                spacing: 2
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                Text {
                    text: tile.label
                    color: "#ffffff"
                    font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    text: tile.busy ? tile.busyText : tile.status
                    color: tile.busy ? Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.9) : Qt.rgba(1, 1, 1, 0.4)
                    font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            Text {
                text: ""
                visible: tile.menuVisible
                color: chevron.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.3)
                font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                font.pixelSize: 13
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        MouseArea {
            id: mainArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: tile.clicked()
        }

        MouseArea {
            id: chevron
            visible: tile.menuVisible
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 28
            hoverEnabled: true
            onClicked: tile.menuClicked()
        }
    }

    component QuickButton: Item {
        id: qbtn
        property string icon
        property string label
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredHeight: 44

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: qbtnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2
            Text {
                text: qbtn.icon
                color: qbtnMouse.containsMouse ? "#ffffff" : Qt.rgba(1, 1, 1, 0.8)
                font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                font.pixelSize: 16
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: qbtn.label
                color: Qt.rgba(1, 1, 1, 0.5)
                font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                font.pixelSize: 9
                Layout.alignment: Qt.AlignHCenter
            }
        }

        MouseArea {
            id: qbtnMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: qbtn.clicked()
        }

        scale: qbtnMouse.containsPress ? 0.95 : 1.0
        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }
    }

    // ------------------------------------------------------------------
    // Isla dinámica
    // ------------------------------------------------------------------

    Item {
        id: ccContent
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: cc.show = false

        MouseArea {
            anchors.fill: parent
            enabled: cc.show
            onClicked: cc.show = false
        }

        Rectangle {
            id: animRect
            anchors.top: parent.top
            anchors.topMargin: cc.show ? 16 : (shellRoot && shellRoot.isBarMode ? 0 : 4)
            anchors.horizontalCenter: parent.horizontalCenter

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
            }

            width: cc.show ? 380 : (shellRoot ? shellRoot.notchWidth + 32 : 120)
            height: cc.show ? (contentColumn.implicitHeight + 32) : 32

            color: Qt.rgba(0.02, 0.02, 0.02, 0.95)
            radius: cc.show ? 24 : (shellRoot && shellRoot.isBarMode ? 0 : 16)
            border.color: Qt.rgba(1, 1, 1, 0.1)
            border.width: cc.show ? 1 : 0

            opacity: (!cc.show && height <= 36) ? 0.0 : 1.0

            Behavior on radius { NumberAnimation { duration: cc.show ? 450 : 300; easing.type: cc.show ? Easing.OutBack : Easing.OutExpo; easing.overshoot: cc.show ? 1.2 : 0 } }
            Behavior on width  { NumberAnimation { duration: cc.show ? 450 : 300; easing.type: cc.show ? Easing.OutBack : Easing.OutExpo; easing.overshoot: cc.show ? 1.2 : 0 } }
            Behavior on height { NumberAnimation { duration: cc.show ? 450 : 300; easing.type: cc.show ? Easing.OutBack : Easing.OutExpo; easing.overshoot: cc.show ? 1.2 : 0 } }
            Behavior on anchors.topMargin { NumberAnimation { duration: cc.show ? 450 : 300; easing.type: cc.show ? Easing.OutBack : Easing.OutExpo; easing.overshoot: cc.show ? 1.2 : 0 } }

            Item {
                anchors.fill: parent
                anchors.margins: 16
                opacity: cc.show ? 1.0 : 0.0
                clip: true
                Behavior on opacity { NumberAnimation { duration: cc.show ? 300 : 100; easing.type: Easing.InOutQuad } }

                ColumnLayout {
                    id: contentColumn
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 10

                    // ---- Cabecera: reloj, fecha y estado del sistema ----
                    RowLayout {
                        Layout.fillWidth: true

                        ColumnLayout {
                            spacing: 2
                            Layout.alignment: Qt.AlignVCenter

                            Text {
                                id: clockText
                                text: Qt.formatDateTime(new Date(), "h:mm AP")
                                color: "#ffffff"
                                font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                                font.pixelSize: 26
                                font.bold: true

                                Timer {
                                    interval: 1000; running: true; repeat: true
                                    onTriggered: clockText.text = Qt.formatDateTime(new Date(), "h:mm AP")
                                }
                            }

                            Text {
                                text: Qt.formatDateTime(new Date(), "dddd, MMMM d")
                                color: Qt.rgba(1, 1, 1, 0.4)
                                font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                                font.pixelSize: 12
                            }
                        }

                        Item { Layout.fillWidth: true }

                        RowLayout {
                            spacing: 8
                            Layout.alignment: Qt.AlignVCenter

                            Text {
                                text: " " + (shellRoot ? shellRoot.temperature : "0") + "°"
                                color: shellRoot && parseInt(shellRoot.temperature) >= 80 ? "#FF3B30" : Qt.rgba(1, 1, 1, 0.4)
                                font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                                font.pixelSize: 11
                            }

                            Text {
                                text: "󰮯 " + (shellRoot ? shellRoot.updates : "0")
                                color: Qt.rgba(1, 1, 1, 0.4)
                                font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                                font.pixelSize: 11
                                visible: shellRoot && parseInt(shellRoot.updates) > 0
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.rgba(1, 1, 1, 0.1) }

                    // ---- Reproductor (MPRIS genérico, no solo Spotify) ----
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: shellRoot && shellRoot.mediaStatus !== "offline"

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: ""
                                color: shellRoot && shellRoot.mediaPlaying ? "#1DB954" : "#ffffff"
                                font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                                font.pixelSize: 18
                            }

                            ColumnLayout {
                                spacing: 2
                                Layout.fillWidth: true
                                Text {
                                    text: shellRoot ? shellRoot.mediaText : ""
                                    color: "#ffffff"
                                    font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                                    font.pixelSize: 13
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: shellRoot && shellRoot.mediaPlaying ? "Reproduciendo" : "Pausado"
                                    color: shellRoot && shellRoot.mediaPlaying ? "#1DB954" : Qt.rgba(1, 1, 1, 0.4)
                                    font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                                    font.pixelSize: 10
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Item { Layout.fillWidth: true }

                            QuickButton {
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 36
                                icon: "󰒮"
                                label: ""
                                onClicked: shellRoot.ccMediaPrev.running = true
                            }

                            QuickButton {
                                Layout.preferredWidth: 60
                                Layout.preferredHeight: 36
                                icon: shellRoot && shellRoot.mediaPlaying ? "󰏤" : "󰐊"
                                label: ""
                                onClicked: shellRoot.ccMediaPlay.running = true
                            }

                            QuickButton {
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 36
                                icon: "󰒭"
                                label: ""
                                onClicked: shellRoot.ccMediaNext.running = true
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.rgba(1, 1, 1, 0.1); visible: shellRoot && shellRoot.mediaStatus !== "offline" }

                    // ---- Salida de audio ----
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: shellRoot && shellRoot.audioOuts.length > 0

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            radius: 12
                            color: audHead.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)

                            MouseArea {
                                id: audHead
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: cc.audioOutExpanded = !cc.audioOutExpanded
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 10
                                spacing: 8

                                Text {
                                    text: "󰕾"
                                    color: "#ffffff"
                                    font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                                    font.pixelSize: 16
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                ColumnLayout {
                                    spacing: 0
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    Text {
                                        text: "Salida"
                                        color: "#ffffff"
                                        font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                    Text {
                                        text: shellRoot ? shellRoot.defaultSink : "…"
                                        color: Qt.rgba(1, 1, 1, 0.4)
                                        font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    text: ""
                                    color: Qt.rgba(1, 1, 1, 0.4)
                                    font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                                    font.pixelSize: 13
                                    rotation: cc.audioOutExpanded ? 90 : 0
                                    Behavior on rotation { NumberAnimation { duration: 150 } }
                                }
                            }
                        }

                        Repeater {
                            model: shellRoot ? shellRoot.audioOuts : []

                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                radius: 8
                                visible: cc.audioOutExpanded
                                color: outHov.containsMouse ? Qt.rgba(1, 1, 1, 0.15)
                                     : (shellRoot && modelData.id === shellRoot.defaultSinkId) ? Qt.rgba(0.2, 0.6, 1.0, 0.22)
                                     : "transparent"

                                MouseArea {
                                    id: outHov
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (!shellRoot) return
                                        // Aplicar ya (el poll de 3s lo confirma después).
                                        shellRoot.defaultSink = modelData.name;
                                        shellRoot.defaultSinkId = modelData.id;
                                        shellRoot.ccAudioSet.command = ["wpctl", "set-default", String(modelData.id)];
                                        shellRoot.ccAudioSet.running = true;
                                        cc.audioOutExpanded = false;
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    Text {
                                        text: shellRoot && modelData.id === shellRoot.defaultSinkId ? "✓" : ""
                                        color: "#40C4FF"
                                        font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                                        font.pixelSize: 11
                                        Layout.preferredWidth: 14
                                    }
                                    Text {
                                        text: modelData.name
                                        color: "#ffffff"
                                        font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }

                    // ---- Sliders: volumen, micrófono, brillo ----
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        SliderRow {
                            icon: shellRoot && shellRoot.volumeMuted ? "󰝟" : "󰕾"
                            iconMuted: "󰝟"
                            muted: shellRoot && shellRoot.volumeMuted
                            value: shellRoot ? parseInt(shellRoot.volumeOut) / 100.0 : 0
                            onIconClicked: shellRoot.ccVolMute.running = true
                            onValueMoved: v => {
                                shellRoot.ccVolSet.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", v.toFixed(2)]
                                shellRoot.ccVolSet.running = true
                            }
                        }

                        SliderRow {
                            icon: shellRoot && shellRoot.micMuted ? "" : ""
                            iconMuted: ""
                            muted: shellRoot && shellRoot.micMuted
                            value: shellRoot ? parseInt(shellRoot.volumeMic) / 100.0 : 0
                            onIconClicked: shellRoot.ccMicMute.running = true
                            onValueMoved: v => {
                                shellRoot.ccMicSet.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", v.toFixed(2)]
                                shellRoot.ccMicSet.running = true
                            }
                        }

                        SliderRow {
                            icon: "󰃠"
                            iconMuted: "󰃠"
                            value: shellRoot ? parseInt(shellRoot.brightnessLevel) / 100.0 : 0
                            visible: shellRoot && shellRoot.hasBacklight
                            onValueMoved: v => {
                                shellRoot.ccBrightSet.command = ["brightnessctl", "s", Math.round(v * 100) + "%"]
                                shellRoot.ccBrightSet.running = true
                            }
                        }
                    }

                    // ---- Conexiones: Ethernet, Wi-Fi y Bluetooth ----
                    // Filas a ancho completo (separadas por tipo de red).
                    GridLayout {
                        columns: 1
                        rowSpacing: 6
                        Layout.fillWidth: true

                        ToggleTile {
                            icon: "󰈀"
                            label: "Ethernet"
                            status: shellRoot && shellRoot.ethConnected ? "Conectado" : "No conectado"
                            active: shellRoot && shellRoot.ethConnected
                            busy: shellRoot && shellRoot.ethToggling
                            pulse: shellRoot && shellRoot.ethToggling
                            busyText: shellRoot && shellRoot.ethConnected ? "Desconectando…" : "Conectando…"
                            menuVisible: false
                            accent: "#007AFF"
                            onClicked: shellRoot.ccEthToggle.running = true
                        }

                        ToggleTile {
                            icon: shellRoot ? shellRoot.wifiIcon : "󰤮"
                            label: "Wi-Fi"
                            status: {
                                if (shellRoot && shellRoot.wifiText === "Disconnected") return "Apagado"
                                if (shellRoot && shellRoot.wifiText === "Scanning") return "Buscando redes…"
                                return (shellRoot ? shellRoot.wifiText : "0%") + " · Conectado"
                            }
                            active: shellRoot && shellRoot.wifiRadio === "on"
                            busy: shellRoot && shellRoot.wifiToggling
                            pulse: shellRoot && shellRoot.wifiToggling
                            busyText: shellRoot && shellRoot.wifiRadio === "on" ? "Apagando…" : "Encendiendo…"
                            radar: shellRoot && shellRoot.wifiText === "Scanning"
                            accent: "#007AFF"
                            // El clic siempre alterna el radio Wi-Fi (como Bluetooth).
                            onClicked: shellRoot.ccWifiToggle.running = true
                            onMenuClicked: { shellRoot.ccWifiMenu.show = true; cc.show = false }
                        }

                        ToggleTile {
                            icon: shellRoot && shellRoot.bluetoothStatus === "on" ? "" : "󰂲"
                            label: "Bluetooth"
                            status: shellRoot && shellRoot.bluetoothStatus === "on" ? "Activo" : "Apagado"
                            active: shellRoot && shellRoot.bluetoothStatus === "on"
                            busy: shellRoot && shellRoot.btToggling
                            pulse: shellRoot && shellRoot.btToggling
                            busyText: shellRoot && shellRoot.bluetoothStatus === "on" ? "Apagando…" : "Activando…"
                            accent: "#007AFF"
                            onClicked: shellRoot.ccBtToggle.running = true
                            onMenuClicked: { shellRoot.ccBluetoothMenu.show = true; cc.show = false }
                        }
                    }

                    // ---- Accesos rápidos ----
                    GridLayout {
                        columns: 4
                        columnSpacing: 8
                        rowSpacing: 8
                        Layout.fillWidth: true

                        QuickButton { icon: "󰀻"; label: "Apps"; onClicked: { shellRoot.ccAppLauncher.show = true; cc.show = false } }
                        QuickButton { icon: ""; label: "Portapapeles"; onClicked: { shellRoot.ccClipboard.show = true; cc.show = false } }
                        QuickButton { icon: "󰁧"; label: "Tema"; onClicked: { shellRoot.ccTheme.show = true; cc.show = false } }
                        QuickButton { icon: "⏻"; label: "Encendido"; onClicked: { shellRoot.ccPower.show = true; cc.show = false } }
                    }
                }
            }
        }
    }
}
