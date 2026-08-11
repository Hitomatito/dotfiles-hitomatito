import Quickshell
import QtQuick
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Layouts
import Quickshell.Io
import Qt.labs.platform

ShellRoot {
    PanelWindow {
    id: root

    property color colBg: "#000000"
    property color colFg: "#ffffff"
    property color colAccent: "#ffffff"
    property color colMuted: Qt.rgba(1, 1, 1, 0.4)
    property color colHover: Qt.rgba(1, 1, 1, 0.1)
    property color colCrit: "#ff0000"
    property string fontFamily: "JetBrainsMono Nerd Font"
    property int fontSize: 10
    // Home real del usuario (los dotfiles funcionan para cualquier usuario)
    property string userHome: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")
    property string userConfig: String(StandardPaths.writableLocation(StandardPaths.ConfigLocation)).replace(/^file:\/\//, "")
    property int windowCount: 0
    property bool isBarMode: windowCount === 1
    property real notchWidth: notchLayout.implicitWidth

    // Se conserva solo porque los popups externos (PowerMenu, AppLauncher, ...)
    // lo referencian en sus animaciones; siempre es false.
    property bool batteryMode: false

    property bool isAnyPopupOpen: controlCenter.show || appLauncherPopup.show || clipboardManagerPopup.show || themeSwitcherPopup.show || wifiMenuPopup.show || powerMenuPopup.show || bluetoothMenuPopup.show
    property bool isAnyPopupAnimActive: isAnyPopupOpen || controlCenter.animHeight > 36 || appLauncherPopup.animHeight > 36 || clipboardManagerPopup.animHeight > 36 || themeSwitcherPopup.animHeight > 36 || wifiMenuPopup.animHeight > 36 || powerMenuPopup.animHeight > 36 || bluetoothMenuPopup.animHeight > 36

    Process {
        command: [root.userConfig + "/quickshell/count_tiled.sh"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                var c = parseInt(data.trim())
                if (!isNaN(c)) root.windowCount = c
            }
        }
    }

    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: root.isBarMode ? 32 : 36
    color: "transparent"

    // State properties
    property string temperature: "0"
    property string updates: "0"
    property string brightnessLevel: "0%"
    property bool hasBacklight: false
    property string volumeOut: "0%"
    property bool volumeMuted: false
    property string volumeMic: "0%"
    property bool micMuted: false
    property string bluetoothStatus: "off"

    property bool showMicIndicator: false

    onMicMutedChanged: {
        showMicIndicator = true;
        micIndicatorTimer.restart();
    }

    Timer {
        id: micIndicatorTimer
        interval: 1000
        repeat: false
        onTriggered: root.showMicIndicator = false
    }

    // Reproductor multimedia genérico (MPRIS vía playerctl)
    property string mediaStatus: "offline"
    property string mediaText: ""
    property bool mediaPlaying: mediaStatus === "Playing"
    property string wifiIcon: "󰤯"
    property string wifiText: "Disconnected"
    property string wifiRadio: "off"
    property bool wifiToggling: false
    property bool ethConnected: false
    property bool ethToggling: false
    property bool btToggling: false
    property var audioOuts: []
    property string defaultSink: "—"
    property int defaultSinkId: -1
    property var _sinkBuf: []
    property bool _inSinks: false

    property bool showOsd: false
    property string osdText: "0%"
    property string osdIcon: "󰕾"
    property real osdValue: 0
    property bool showPowerMenu: false
    property bool showAppLauncher: false
    property bool showClipboard: false

    // Click Actions
    Process { id: pMicMute; command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"] }
    Process { id: pVolMute; command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"] }
    Process { id: pVolSet } // Dynamic volume setter
    Process { id: pMicSet } // Dynamic mic volume setter
    Process { id: pAudioSet } // Dynamic default sink setter
    Process { id: pBrightSet; command: ["brightnessctl", "s", "50%"] }

    Process {
        id: pWifiToggle
        command: ["sh", "-c", "if [ \"$(nmcli radio wifi)\" = \"enabled\" ]; then nmcli radio wifi off; echo off; else nmcli radio wifi on; echo on; fi"]
        stdout: SplitParser {
            onRead: data => {
                var d = data.trim();
                // Actualización inmediata del estado visual (el poll de 3s lo confirma después).
                if (d === 'on') {
                    root.wifiRadio = "on";
                    root.wifiText = "Scanning";
                    root.wifiIcon = "󰤮";
                } else if (d === 'off') {
                    root.wifiRadio = "off";
                    root.wifiText = "Disconnected";
                    root.wifiIcon = "󰤮";
                }
            }
        }
        onRunningChanged: {
            // Mantén el estado "Encendiendo…/Apagando…" visible un mínimo de ~1s,
            // aunque el comando termine antes, para que se note el cambio.
            if (running) {
                root.wifiToggling = true;
                wifiToggleHold.start();
            }
        }
    }
    Timer {
        id: wifiToggleHold
        interval: 1000
        onTriggered: root.wifiToggling = false
    }
    Process {
        id: pBtToggle
        command: ["sh", "-c", "if bluetoothctl show | grep -q 'Powered: yes'; then rfkill block bluetooth; else rfkill unblock bluetooth; fi"]
        onRunningChanged: {
            if (running) {
                root.btToggling = true;
                btToggleHold.start();
            }
        }
    }
    Timer {
        id: btToggleHold
        interval: 1000
        onTriggered: root.btToggling = false
    }
    Process {
        id: pEthToggle
        command: ["sh", "-c", "dev=$(LC_ALL=C nmcli -t -f DEVICE,TYPE device | grep ':ethernet:' | head -1 | cut -d: -f1); if [ -z \"$dev\" ]; then exit 0; fi; if LC_ALL=C nmcli -t -f DEVICE,STATE device | grep -q \"^$dev:connected\"; then nmcli device disconnect \"$dev\"; echo off; else nmcli device connect \"$dev\"; echo on; fi"]
        stdout: SplitParser {
            onRead: data => {
                var d = data.trim();
                // Actualización inmediata; el poll de 3s luego confirma.
                if (d === 'on') root.ethConnected = true;
                else if (d === 'off') root.ethConnected = false;
            }
        }
        onRunningChanged: {
            if (running) {
                root.ethToggling = true;
                ethToggleHold.start();
            }
        }
    }
    Timer {
        id: ethToggleHold
        interval: 1000
        onTriggered: root.ethToggling = false
    }

    Process {
        command: ["sh", "-c", "while true; do wpctl status; sleep 3; done"]
        running: true; stdout: SplitParser {
            onRead: data => {
                var line = data;
                if (line.indexOf("Sinks:") >= 0) {
                    root._sinkBuf = [];
                    root._inSinks = true;
                    return;
                }
                if (root._inSinks) {
                    if (line.indexOf("Devices:") >= 0 || line.indexOf("Sources:") >= 0 ||
                        line.indexOf("Filters:") >= 0 || line.indexOf("Streams:") >= 0 ||
                        line.indexOf("├─") >= 0 || line.indexOf("└─") >= 0) {
                        root._inSinks = false;
                        if (root._sinkBuf.length > 0) root.audioOuts = root._sinkBuf.slice();
                        return;
                    }
                    var m = line.match(/(\*)?\s+(\d+)\.\s+(.+?)\s+\[vol/);
                    if (m) {
                        var name = m[3].trim();
                        var id = parseInt(m[2]);
                        root._sinkBuf.push({ id: id, name: name, def: m[1] === "*" });
                        if (m[1] === "*") { root.defaultSink = name; root.defaultSinkId = id; }
                    }
                    return;
                }
            }
        }
    }
    Process { id: pMediaPrev; command: ["playerctl", "previous"] }
    Process { id: pMediaPlay; command: ["playerctl", "play-pause"] }
    Process { id: pMediaNext; command: ["playerctl", "next"] }

    Process {
        id: pBright
        command: ["bash", "-c", "if brightnessctl -l 2>/dev/null | grep -q 'Class: backlight'; then brightnessctl -m | awk -F, '{print $4}'; else echo 'none'; fi"]
        running: true
        stdout: SplitParser { onRead: text => { var v = text.trim(); if (v === 'none') { root.hasBacklight = false; } else { root.hasBacklight = true; root.brightnessLevel = v; } } }
    }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: pBright.running = true }

    Timer {
        id: osdTimer
        interval: 2000
        repeat: false
        onTriggered: root.showOsd = false
    }

    // Background Process Loops
    Process {
        command: ["sh", "-c", "while true; do temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0); echo $((temp / 1000)); sleep 3; done"]
        running: true; stdout: SplitParser { onRead: data => root.temperature = data.trim() }
    }
    Process {
        command: ["sh", "-c", "while true; do checkupdates 2>/dev/null | wc -l; sleep 3600; done"]
        running: true; stdout: SplitParser { onRead: data => root.updates = data.trim() }
    }
    Process {
        command: ["sh", "-c", "while true; do wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null; sleep 0.5; done"]
        running: true; stdout: SplitParser {
            onRead: data => {
                var d = data.trim();
                root.volumeMuted = d.includes("[MUTED]");
                var m = d.match(/[0-9.]+/);
                if (m) root.volumeOut = Math.round(parseFloat(m[0]) * 100) + "%";
            }
        }
    }
    Process {
        command: ["sh", "-c", "while true; do wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null; sleep 0.5; done"]
        running: true; stdout: SplitParser {
            onRead: data => {
                var d = data.trim();
                root.micMuted = d.includes("[MUTED]");
                var m = d.match(/[0-9.]+/);
                if (m) root.volumeMic = Math.round(parseFloat(m[0]) * 100) + "%";
            }
        }
    }
    Process {
        command: ["sh", "-c", "while true; do bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo 'on' || echo 'off'; sleep 3; done"]
        running: true; stdout: SplitParser { onRead: data => root.bluetoothStatus = data.trim() }
    }
    Process {
        command: ["sh", "-c", "while true; do if LC_ALL=C nmcli -t -f TYPE,STATE device | grep -q '^ethernet:connected'; then ep=E:up; else ep=E:down; fi; rad=$(nmcli -t -f WIFI radio 2>/dev/null); if [ \"$rad\" = \"enabled\" ]; then rp=R:on; sig=$(LC_ALL=C nmcli -t -f active,signal dev wifi | grep '^yes' | cut -d: -f2); if [ -z \"$sig\" ]; then sig='-'; fi; else rp=R:off; sig='-'; fi; echo \"$ep|$rp|$sig\"; sleep 3; done"]
        running: true; stdout: SplitParser {
            onRead: data => {
                var d = data.trim();
                var p = d.split("|");
                if (p.length < 3) return;
                // Estado Ethernet y radio Wi-Fi por separado (una sola pasada de nmcli).
                root.ethConnected = (p[0] === "E:up");
                root.wifiRadio = (p[1] === "R:on") ? "on" : "off";
                var sig = p[2];
                if (sig === '-') {
                    if (root.wifiRadio === "on") { root.wifiIcon = "󰤮"; root.wifiText = "Scanning"; }
                    else { root.wifiIcon = "󰤮"; root.wifiText = "Disconnected"; }
                } else {
                    var s = parseInt(sig);
                    root.wifiText = s + "%";
                    if (s > 80) root.wifiIcon = "󰤨";
                    else if (s > 60) root.wifiIcon = "󰤥";
                    else if (s > 40) root.wifiIcon = "󰤢";
                    else if (s > 20) root.wifiIcon = "󰤟";
                    else root.wifiIcon = "󰤯";
                }
            }
        }
    }
    Process {
        command: ["sh", "-c", "while true; do st=$(playerctl status 2>/dev/null); if [ \"$st\" = \"Playing\" ] || [ \"$st\" = \"Paused\" ]; then txt=$(playerctl metadata --format '{{title}} - {{artist}}' 2>/dev/null); echo \"$st|$txt\"; else echo 'offline|'; fi; sleep 1; done"]
        running: true; stdout: SplitParser {
            onRead: data => {
                var p = data.split("|");
                root.mediaStatus = p[0].trim();
                root.mediaText = p[1] ? p[1].trim() : "";
            }
        }
    }

    // A helper to make clickable modules easily
    component Mod: MouseArea {
        id: modRoot
        property string text
        property color textColor: root.colFg
        property color bgColor: "transparent"
        property bool blink: false
        property bool show: true
        property real customWidth: 0
        default property alias customContent: contentBox.data

        Layout.fillHeight: true
        Layout.preferredWidth: show ? (customWidth > 0 ? customWidth + 16 : modText.implicitWidth + 16) : 0
        Behavior on Layout.preferredWidth {
            NumberAnimation { duration: 300; easing.type: Easing.OutExpo }
        }

        visible: Layout.preferredWidth > 0
        clip: true
        hoverEnabled: true

        Rectangle {
            anchors.fill: parent
            color: parent.bgColor
            Behavior on color { ColorAnimation { duration: 200 } }

            SequentialAnimation on opacity {
                running: modRoot.blink
                loops: Animation.Infinite
                NumberAnimation { to: 0.1; duration: 500 }
                NumberAnimation { to: 1.0; duration: 500 }
            }
        }

        Item {
            anchors.centerIn: parent
            width: modText.width
            height: modText.height
            scale: parent.containsPress ? 0.85 : (parent.containsMouse ? 1.1 : 1.0)
            Behavior on scale {
                NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
            }

            Text {
                id: modText
                text: parent.parent.text
                color: parent.parent.textColor
                font { family: root.fontFamily; pixelSize: root.fontSize; bold: true }
                anchors.centerIn: parent
                Behavior on color { ColorAnimation { duration: 200 } }
            }
            Item {
                id: contentBox
                anchors.centerIn: parent
            }
        }
    }

    Rectangle {
        id: notchRect
        opacity: (!root.isAnyPopupAnimActive) || root.isBarMode ? 1.0 : 0.0

        anchors.top: parent.top
        anchors.topMargin: root.isBarMode ? 0 : 4
        anchors.horizontalCenter: parent.horizontalCenter
        height: 32
        width: root.isBarMode ? parent.width : notchLayout.implicitWidth + 32
        color: Qt.rgba(0.02, 0.02, 0.02, 0.95)
        radius: root.isBarMode ? 0 : 16

        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
        Behavior on radius { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
        Behavior on anchors.topMargin { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
        border.color: Qt.rgba(1, 1, 1, 0.1)
        border.width: root.isBarMode ? 0 : 1

        RowLayout {
            id: notchLayout
            opacity: root.isAnyPopupOpen ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 150 } }
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            height: parent.height
            spacing: 8

            Repeater {
                model: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
                Mod {
                    property var ws: Hyprland.workspaces.values.find(w => w.id === modelData)
                    property bool isActive: Hyprland.focusedWorkspace != null && Hyprland.focusedWorkspace.id === modelData

                    text: modelData
                    textColor: isActive ? root.colFg : root.colMuted
                    bgColor: "transparent"
                    show: (ws !== undefined || isActive) && !root.showOsd
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + modelData + " })")
                }
            }

            Mod {
                text: ""
                textColor: root.micMuted ? root.colMuted : "#FFA500"
                bgColor: "transparent"
                show: root.showMicIndicator && !controlCenter.show && !root.showOsd
            }

            Mod {
                text: ""
                textColor: root.colFg
                bgColor: "transparent"
                show: root.showOsd
                customWidth: 140

                Item {
                    anchors.centerIn: parent
                    width: 140
                    height: 16
                    RowLayout {
                        anchors.fill: parent
                        spacing: 8
                        Text {
                            text: root.osdIcon
                            color: root.colFg
                            font { family: root.fontFamily; pixelSize: root.fontSize + 2 }
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 4
                                radius: 2
                                color: root.colMuted
                                Rectangle {
                                    height: parent.height
                                    width: parent.width * (root.osdValue / 100)
                                    radius: 2
                                    color: root.colFg
                                }
                            }
                        }
                    }
                }
            }

            Mod {
                text: (root.bluetoothStatus === "on" ? "󰂯 " : "")
                      + (root.ethConnected
                         ? "󰈀 Cable" + (root.wifiRadio === "on" ? " · Wi-Fi" : "")
                         : root.wifiIcon + " "
                           + (root.wifiText === "Disconnected" ? "Apagado"
                              : root.wifiText === "Scanning" ? "Buscando…"
                              : root.wifiText))
                textColor: root.colFg
                bgColor: "transparent"
                show: !controlCenter.show && !root.showOsd
                onClicked: controlCenter.show = !controlCenter.show
            }
        }
    }

    // Centro de control (isla dinámica)
    ControlCenter {
        id: controlCenter
        shellRoot: root
    }

    PowerMenu {
        id: powerMenuPopup
        shellRoot: root
    }

    AppLauncher {
        id: appLauncherPopup
        shellRoot: root
    }

    ClipboardManager {
        id: clipboardManagerPopup
        shellRoot: root
    }

    ThemeSwitcher {
        id: themeSwitcherPopup
        shellRoot: root
    }

    WifiMenu {
        id: wifiMenuPopup
        shellRoot: root
    }

    BluetoothMenu {
        id: bluetoothMenuPopup
        shellRoot: root
    }

    // Referencias para el centro de control. Los `id` no son accesibles
    // desde otro documento QML (ControlCenter.qml) vía `shellRoot`, solo
    // las propiedades declaradas. Por eso exponemos alias de los procesos
    // y popups que el ControlCenter necesita manipular.
    property alias ccVolMute: pVolMute
    property alias ccVolSet: pVolSet
    property alias ccMicMute: pMicMute
    property alias ccMicSet: pMicSet
    property alias ccBrightSet: pBrightSet
    property alias ccWifiToggle: pWifiToggle
    property alias ccBtToggle: pBtToggle
    property alias ccEthToggle: pEthToggle
    property alias ccAudioSet: pAudioSet
    property alias ccMediaPrev: pMediaPrev
    property alias ccMediaPlay: pMediaPlay
    property alias ccMediaNext: pMediaNext
    property alias ccWifiMenu: wifiMenuPopup
    property alias ccBluetoothMenu: bluetoothMenuPopup
    property alias ccAppLauncher: appLauncherPopup
    property alias ccClipboard: clipboardManagerPopup
    property alias ccTheme: themeSwitcherPopup
    property alias ccPower: powerMenuPopup

    IpcHandler {
        id: qsIpc
        target: "qsIpc"
        function showOsd(type: string, val: string) {
            val = parseFloat(val);
            if (type === "V") {
                root.osdIcon = val === 0 ? "󰝟" : (val > 50 ? "󰕾" : "󰖀");
                root.osdText = Math.round(val) + "%";
            } else if (type === "B") {
                root.osdIcon = "󰃠";
                root.osdText = Math.round(val) + "%";
            }
            root.osdValue = val;
            root.showOsd = true;
            osdTimer.restart();
        }
        function toggleAppLauncher() {
            appLauncherPopup.show = !appLauncherPopup.show;
        }
        function togglePowerMenu() {
            powerMenuPopup.show = !powerMenuPopup.show;
        }
        function toggleClipboard() {
            clipboardManagerPopup.show = !clipboardManagerPopup.show;
        }
        function toggleThemeSwitcher() {
            themeSwitcherPopup.show = !themeSwitcherPopup.show;
        }
        function toggleWifiMenu() {
            wifiMenuPopup.show = !wifiMenuPopup.show;
        }
        function toggleBluetoothMenu() {
            bluetoothMenuPopup.show = !bluetoothMenuPopup.show;
        }
        function toggleControlCenter() {
            controlCenter.show = !controlCenter.show;
        }
    }

    }
}
