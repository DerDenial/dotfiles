import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import QtQuick.Effects

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: appearance.backgroundColor

    readonly property color accentColor: appearance.accent
    readonly property color surfaceColor: appearance.surface
    readonly property color backgroundColor: appearance.backgroundColor
    readonly property color foregroundColor: appearance.text
    readonly property color mutedColor: appearance.muted
    readonly property color borderColor: appearance.border
    readonly property color errorColor: appearance.error
    readonly property string textFont: "Inter"
    readonly property string iconFont: "Material Symbols Rounded"
    readonly property real compactScale: Math.min(1, height / 820)
    property bool entered: false
    property bool authenticated: false
    property bool busy: false
    property bool passwordVisible: false
    property string errorMessage: ""
    property string pendingPower: ""
    property date now: new Date()

    Settings {
        id: appearance
        location: "file://" + (config.StateFile || "/var/lib/quickshell-sddm/theme.ini")
        category: "Theme"
        property string background: ""
        property string backgroundColor: "#15171b"
        property string surface: "#22252c"
        property string border: "#626774"
        property string text: "#e5e7ef"
        property string muted: "#bdc2ce"
        property string accent: "#b8c7ee"
        property string error: "#ffb4ab"
    }

    function tinted(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    function login() {
        if (busy || pendingPower || !username.text.trim()) return;
        errorMessage = "";
        passwordVisible = false;
        busy = true;
        sddm.login(username.text.trim(), password.text, Math.max(0, session.currentIndex));
    }

    function powerAvailable(action) {
        if (action === "reboot") return sddm.canReboot;
        if (action === "powerOff") return sddm.canPowerOff;
        if (action === "suspend") return sddm.canSuspend;
        return false;
    }

    function requestPower(action) {
        if (busy || pendingPower || !powerAvailable(action)) return;
        powerConfirm.action = action;
        pendingPower = action;
        Qt.callLater(function() {
            if (root.pendingPower) cancelPowerButton.forceActiveFocus();
        });
    }

    function cancelPower() {
        pendingPower = "";
        Qt.callLater(function() {
            if (!root.busy && !root.pendingPower) password.forceActiveFocus();
        });
    }

    function performPower() {
        const action = pendingPower;
        if (busy || !powerAvailable(action)) return;
        pendingPower = "";
        if (action === "reboot") sddm.reboot();
        else if (action === "powerOff") sddm.powerOff();
        else if (action === "suspend") sddm.suspend();
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false;
            root.errorMessage = "Anmeldung fehlgeschlagen. Bitte erneut versuchen.";
            password.clear();
            password.forceActiveFocus();
        }
        function onLoginSucceeded() {
            root.authenticated = true;
            password.clear();
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }
    Component.onCompleted: {
        entered = true;
        if (username.text.trim()) password.forceActiveFocus();
        else username.forceActiveFocus();
    }

    // Identical bounds and aspect crop to the desktop transition. Keep the blur
    // until the greeter is replaced; SDDM can tear its scene down immediately.
    Image {
        id: wallpaper
        anchors.fill: parent
        visible: false
        source: appearance.background ? "file://" + appearance.background : "assets/background.svg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        blurEnabled: true
        blurMax: 64
        blur: 0.8
        autoPaddingEnabled: false
    }
    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor
        opacity: 0.22
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#12000000" }
            GradientStop { position: 0.55; color: "#1f000000" }
            GradientStop { position: 1; color: "#80000000" }
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: 236
        height: 34
        color: root.tinted(root.backgroundColor, 0.88)
        bottomLeftRadius: 17
        bottomRightRadius: 17
        border.width: 1
        border.color: root.tinted(root.borderColor, 0.46)
        Rectangle {
            x: 1
            y: 0
            width: parent.width - 2
            height: 1
            color: parent.color
        }
        Row {
            anchors.centerIn: parent
            spacing: 7
            Text {
                text: "lock"
                color: root.accentColor
                font.family: root.iconFont
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.busy ? "Anmeldung läuft" : "Willkommen zurück"
                color: root.foregroundColor
                font.family: root.textFont
                font.pixelSize: 11
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Column {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(54, root.height * 0.15)
        spacing: 5
        opacity: !root.entered || root.busy ? 0 : 1
        scale: root.busy ? 0.98 : root.entered ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: root.busy ? 340 : 620; easing.type: Easing.InOutCubic } }
        Behavior on scale { NumberAnimation { duration: 640; easing.type: Easing.OutCubic } }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "HH:mm")
            color: root.foregroundColor
            font.family: root.textFont
            font.pixelSize: Math.min(108, root.height * 0.125)
            font.weight: Font.DemiBold
            font.letterSpacing: -4
            style: Text.Raised
            styleColor: "#18000000"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.locale("de_DE").toString(root.now, "dddd, d. MMMM")
            color: root.foregroundColor
            opacity: 0.88
            font.family: root.textFont
            font.pixelSize: 16 * root.compactScale
            font.weight: Font.Medium
        }
    }

    ColumnLayout {
        id: form
        width: Math.min(380, root.width - 64)
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(24, Math.min(Math.max(clock.y + clock.height + 38 * root.compactScale, root.height * 0.47), root.height - form.implicitHeight - 70))
        spacing: 10 * root.compactScale
        enabled: !root.busy && !root.pendingPower
        opacity: !root.entered || root.busy ? 0 : 1
        scale: root.busy ? 0.96 : root.entered ? 1 : 0.94
        transform: Translate {
            y: root.busy ? -12 : root.entered ? 0 : 16
            Behavior on y { NumberAnimation { duration: 460; easing.type: Easing.InOutCubic } }
        }
        Behavior on scale { NumberAnimation { duration: 660; easing.type: Easing.OutBack; easing.overshoot: 0.55 } }
        Behavior on opacity { NumberAnimation { duration: root.busy ? 300 : 460; easing.type: Easing.InOutCubic } }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 68 * root.compactScale
            Layout.preferredHeight: 68 * root.compactScale
            Layout.bottomMargin: 3
            radius: width * 0.37
            color: root.tinted(root.accentColor, 0.16)
            border.width: 1
            border.color: root.tinted(root.accentColor, 0.28)
            Text {
                anchors.centerIn: parent
                text: username.text.trim() ? username.text.trim().charAt(0).toUpperCase() : "person"
                color: root.accentColor
                font.family: username.text.trim() ? root.textFont : root.iconFont
                font.pixelSize: 29 * root.compactScale
                font.weight: Font.DemiBold
            }
        }

        TextField {
            id: username
            Layout.fillWidth: true
            Layout.preferredHeight: 38 * root.compactScale
            Layout.bottomMargin: 7 * root.compactScale
            text: userModel.lastUser || config.DefaultUsername || ""
            placeholderText: "Benutzername"
            color: root.foregroundColor
            placeholderTextColor: appearance.muted
            selectionColor: root.accentColor
            selectedTextColor: root.backgroundColor
            horizontalAlignment: TextInput.AlignHCenter
            font.family: root.textFont
            font.pixelSize: 23 * root.compactScale
            font.weight: Font.DemiBold
            selectByMouse: true
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            background: Rectangle {
                radius: 12
                color: username.activeFocus ? root.tinted(root.surfaceColor, 0.38) : "transparent"
                border.width: username.activeFocus ? 1 : 0
                border.color: root.tinted(root.accentColor, 0.55)
                Behavior on color { ColorAnimation { duration: 180 } }
            }
            Accessible.name: "Benutzername"
            onAccepted: password.forceActiveFocus()
            KeyNavigation.tab: password
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 62
            radius: 23
            color: root.tinted(root.surfaceColor, 0.69)
            border.width: 1
            border.color: root.errorMessage ? root.tinted(root.errorColor, 0.8)
                          : password.activeFocus ? root.tinted(root.accentColor, 0.72)
                          : root.tinted(root.foregroundColor, 0.15)
            Behavior on border.color { ColorAnimation { duration: 180 } }

            Text {
                x: 17
                anchors.verticalCenter: parent.verticalCenter
                text: "lock"
                color: password.activeFocus ? root.accentColor : root.mutedColor
                font.family: root.iconFont
                font.pixelSize: 20
            }
            TextField {
                id: password
                anchors.left: parent.left
                anchors.right: visibilityButton.left
                anchors.leftMargin: 42
                anchors.verticalCenter: parent.verticalCenter
                height: 54
                leftPadding: 4
                rightPadding: 3
                placeholderText: "Passwort eingeben"
                echoMode: root.passwordVisible ? TextInput.Normal : TextInput.Password
                color: root.foregroundColor
                placeholderTextColor: appearance.muted
                selectionColor: root.accentColor
                selectedTextColor: root.backgroundColor
                font.family: root.textFont
                font.pixelSize: 14
                passwordCharacter: "●"
                passwordMaskDelay: 0
                selectByMouse: true
                inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                background: Item {}
                Accessible.name: "Passwort"
                onAccepted: root.login()
                onTextEdited: root.errorMessage = ""
                Keys.onEscapePressed: {
                    clear();
                    root.errorMessage = "";
                    root.passwordVisible = false;
                }
                KeyNavigation.tab: loginButton
            }
            ToolButton {
                id: visibilityButton
                anchors.right: loginButton.left
                anchors.rightMargin: 3
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 44
                text: root.passwordVisible ? "visibility_off" : "visibility"
                font.family: root.iconFont
                font.pixelSize: 19
                Accessible.name: root.passwordVisible ? "Passwort verbergen" : "Passwort anzeigen"
                contentItem: Text {
                    text: visibilityButton.text
                    font: visibilityButton.font
                    color: visibilityButton.hovered || visibilityButton.activeFocus ? root.foregroundColor : root.mutedColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 12
                    color: visibilityButton.hovered || visibilityButton.activeFocus ? root.tinted(root.foregroundColor, 0.07) : "transparent"
                }
                onClicked: {
                    root.passwordVisible = !root.passwordVisible;
                    password.forceActiveFocus();
                }
            }
            Button {
                id: loginButton
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 50
                height: 50
                text: "arrow_forward"
                font.family: root.iconFont
                font.pixelSize: 25
                Accessible.name: "Anmelden"
                contentItem: Text {
                    text: loginButton.text
                    font: loginButton.font
                    color: root.backgroundColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 18
                    color: root.accentColor
                    opacity: loginButton.down ? 0.75 : loginButton.hovered || loginButton.activeFocus ? 1 : 0.9
                    scale: loginButton.down ? 0.94 : 1
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack; easing.overshoot: 0.6 } }
                    border.width: loginButton.activeFocus ? 2 : 0
                    border.color: root.foregroundColor
                }
                onClicked: root.login()
                KeyNavigation.tab: session
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            text: root.errorMessage
            color: appearance.error
            font.family: root.textFont
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            Accessible.role: Accessible.StaticText
            Accessible.name: root.errorMessage
        }

        ComboBox {
            id: session
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 224
            Layout.preferredHeight: 38
            model: sessionModel
            textRole: "name"
            currentIndex: Math.max(0, sessionModel.lastIndex)
            font.family: root.textFont
            font.pixelSize: 12
            leftPadding: 31
            rightPadding: 29
            Accessible.name: "Desktop-Sitzung"
            contentItem: Text {
                text: session.displayText
                font: session.font
                color: root.mutedColor
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            background: Rectangle {
                radius: 15
                color: session.hovered || session.activeFocus ? root.tinted(root.surfaceColor, 0.62) : root.tinted(root.surfaceColor, 0.25)
                border.width: 1
                border.color: session.activeFocus ? root.tinted(root.accentColor, 0.7) : root.tinted(root.foregroundColor, 0.08)
                Behavior on color { ColorAnimation { duration: 180 } }
                Text {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "desktop_windows"
                    color: root.mutedColor
                    font.family: root.iconFont
                    font.pixelSize: 16
                }
            }
            indicator: Text {
                x: session.width - width - 10
                anchors.verticalCenter: parent.verticalCenter
                text: session.popup.visible ? "expand_less" : "expand_more"
                color: root.mutedColor
                font.family: root.iconFont
                font.pixelSize: 18
            }
            delegate: ItemDelegate {
                id: sessionEntry
                required property string name
                required property int index
                width: session.width - 12
                height: 40
                highlighted: session.highlightedIndex === index
                text: name
                font: session.font
                contentItem: Text {
                    text: sessionEntry.text
                    font: sessionEntry.font
                    color: sessionEntry.highlighted ? root.accentColor : root.foregroundColor
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                background: Rectangle {
                    radius: 10
                    color: sessionEntry.highlighted ? root.tinted(root.accentColor, 0.13) : "transparent"
                }
            }
            popup: Popup {
                topMargin: 16
                bottomMargin: 16
                y: session.height + 8
                width: session.width
                padding: 6
                implicitHeight: Math.min(contentItem.implicitHeight + 12, 208)
                background: Rectangle {
                    radius: 17
                    color: root.tinted(root.surfaceColor, 0.98)
                    border.width: 1
                    border.color: root.tinted(root.borderColor, 0.7)
                }
                contentItem: ListView {
                    implicitHeight: contentHeight
                    clip: true
                    model: session.popup.visible ? session.delegateModel : null
                    currentIndex: session.highlightedIndex
                    ScrollIndicator.vertical: ScrollIndicator {}
                }
            }
            KeyNavigation.tab: username
        }
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.height * 0.06
        spacing: 18
        opacity: root.busy ? 1 : 0
        visible: opacity > 0.001
        Behavior on opacity { NumberAnimation { duration: 340; easing.type: Easing.InOutCubic } }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 7
            Repeater {
                model: 3
                Rectangle {
                    id: progressDot
                    required property int index
                    width: 5
                    height: 5
                    radius: 3
                    color: root.accentColor
                    opacity: 0.3
                    SequentialAnimation on opacity {
                        running: root.busy
                        loops: Animation.Infinite
                        PauseAnimation { duration: progressDot.index * 100 }
                        NumberAnimation { to: 1; duration: 260; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.3; duration: 380; easing.type: Easing.InOutSine }
                        PauseAnimation { duration: (2 - progressDot.index) * 100 }
                    }
                }
            }
        }
        Text {
            text: "Einen Moment …"
            color: root.foregroundColor
            font.family: root.textFont
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }

    Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 30
        visible: root.width >= 600
        spacing: 8
        opacity: root.busy ? 0 : 0.78
        Behavior on opacity { NumberAnimation { duration: 260 } }
        Text {
            text: "keyboard_return"
            color: root.accentColor
            font.family: root.iconFont
            font.pixelSize: 17
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: "Enter zum Anmelden"
            color: root.foregroundColor
            font.family: root.textFont
            font.pixelSize: 11
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 26
        spacing: 9
        opacity: root.busy ? 0 : 1
        enabled: !root.busy && !root.pendingPower
        Behavior on opacity { NumberAnimation { duration: 260 } }
        Repeater {
            model: [
                { icon: "bedtime", action: "suspend", label: "Standby", available: sddm.canSuspend },
                { icon: "restart_alt", action: "reboot", label: "Neu starten", available: sddm.canReboot },
                { icon: "power_settings_new", action: "powerOff", label: "Ausschalten", available: sddm.canPowerOff }
            ]
            delegate: FocusScope {
                id: powerAction
                required property var modelData
                width: 44
                height: 44
                visible: modelData.available
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
                Accessible.onPressAction: root.requestPower(modelData.action)
                Keys.onReturnPressed: event => { root.requestPower(modelData.action); event.accepted = true; }
                Keys.onEnterPressed: event => { root.requestPower(modelData.action); event.accepted = true; }
                Keys.onSpacePressed: event => { root.requestPower(modelData.action); event.accepted = true; }
                Rectangle {
                    anchors.fill: parent
                    radius: 16
                    color: root.tinted(root.surfaceColor, powerMouse.containsMouse || powerAction.activeFocus ? 0.82 : 0.43)
                    border.width: 1
                    border.color: root.tinted(root.foregroundColor, powerAction.activeFocus ? 0.42 : 0.1)
                    scale: powerMouse.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.6 } }
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
                Text {
                    anchors.centerIn: parent
                    text: powerAction.modelData.icon
                    font.family: root.iconFont
                    font.pixelSize: 21
                    color: powerMouse.containsMouse || powerAction.activeFocus ? root.accentColor : root.foregroundColor
                }
                MouseArea {
                    id: powerMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        powerAction.forceActiveFocus();
                        root.requestPower(powerAction.modelData.action);
                    }
                }
                ToolTip.visible: powerMouse.containsMouse
                ToolTip.delay: 700
                ToolTip.text: modelData.label
            }
        }
    }

    component ConfirmationButton: Button {
        id: confirmationControl
        property bool primary: false
        implicitHeight: 44
        leftPadding: 19
        rightPadding: 19
        font.family: root.textFont
        font.pixelSize: 13
        font.weight: Font.Medium
        contentItem: Text {
            text: confirmationControl.text
            font: confirmationControl.font
            color: confirmationControl.primary ? root.backgroundColor : root.foregroundColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 14
            color: confirmationControl.primary ? root.accentColor : root.tinted(root.foregroundColor, 0.08)
            opacity: confirmationControl.down ? 0.7 : confirmationControl.hovered || confirmationControl.activeFocus ? 1 : 0.9
            border.width: confirmationControl.activeFocus ? 1 : 0
            border.color: root.foregroundColor
        }
    }

    FocusScope {
        id: powerConfirm
        property string action: ""
        anchors.fill: parent
        z: 1000
        opacity: root.pendingPower ? 1 : 0
        visible: opacity > 0.001
        enabled: !!root.pendingPower
        focus: !!root.pendingPower
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Keys.onEscapePressed: event => { root.cancelPower(); event.accepted = true; }
        Rectangle {
            anchors.fill: parent
            color: root.tinted(root.backgroundColor, 0.52)
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root.cancelPower()
        }
        Rectangle {
            id: powerConfirmCard
            anchors.centerIn: parent
            width: Math.min(374, root.width - 48)
            height: powerConfirmContent.implicitHeight + 52
            radius: 27
            color: root.tinted(root.surfaceColor, 0.97)
            border.width: 1
            border.color: root.tinted(root.borderColor, 0.75)
            scale: root.pendingPower ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
            MouseArea {
                anchors.fill: parent
                onClicked: mouse => { mouse.accepted = true; }
            }
            ColumnLayout {
                id: powerConfirmContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 26
                spacing: 16
                Rectangle {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    radius: 17
                    color: root.tinted(root.accentColor, 0.12)
                    Text {
                        anchors.centerIn: parent
                        text: powerConfirm.action === "reboot" ? "restart_alt" : powerConfirm.action === "powerOff" ? "power_settings_new" : "bedtime"
                        color: root.accentColor
                        font.family: root.iconFont
                        font.pixelSize: 25
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: powerConfirm.action === "reboot" ? "Neu starten?" : powerConfirm.action === "powerOff" ? "Ausschalten?" : "In Standby wechseln?"
                    color: root.foregroundColor
                    font.family: root.textFont
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    text: powerConfirm.action === "reboot" ? "Der Computer wird neu gestartet."
                        : powerConfirm.action === "powerOff" ? "Der Computer wird vollständig ausgeschaltet."
                        : "Der Computer bleibt im Energiesparmodus bereit."
                    color: root.mutedColor
                    font.family: root.textFont
                    font.pixelSize: 13
                    lineHeight: 1.25
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 9
                    ConfirmationButton {
                        id: cancelPowerButton
                        Layout.fillWidth: true
                        text: "Abbrechen"
                        onClicked: root.cancelPower()
                    }
                    ConfirmationButton {
                        Layout.fillWidth: true
                        primary: true
                        text: powerConfirm.action === "reboot" ? "Neu starten" : powerConfirm.action === "powerOff" ? "Ausschalten" : "Standby"
                        onClicked: root.performPower()
                    }
                }
            }
        }
    }
}
