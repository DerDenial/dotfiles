import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import QtQuick.Effects

Rectangle {
    id: root

    readonly property color accentColor: appearance.accent
    property bool authenticated: false
    readonly property color backgroundColor: appearance.backgroundColor
    readonly property color borderColor: appearance.border
    property bool busy: false
    readonly property real compactScale: Math.min(1, height / 600)
    property bool entered: false
    readonly property color errorColor: appearance.error
    property string errorMessage: ""
    readonly property color foregroundColor: appearance.text
    readonly property string iconFont: "Material Symbols Rounded"
    readonly property color mutedColor: appearance.muted
    property date now: new Date()
    property bool passwordVisible: false
    property string pendingPower: ""
    readonly property bool profileMatches: !!appearance.avatar && username.text.trim() === (appearance.profileUsername || config.DefaultUsername || "")
    readonly property color surfaceColor: appearance.surface
    readonly property string textFont: "Inter"

    function cancelPower() {
        pendingPower = "";
        Qt.callLater(function () {
            if (!root.busy && !root.pendingPower)
                password.forceActiveFocus();
        });
    }
    function login() {
        if (busy || pendingPower || !username.text.trim())
            return;
        errorMessage = "";
        passwordVisible = false;
        busy = true;
        sddm.login(username.text.trim(), password.text, Math.max(0, session.currentIndex));
    }
    function performPower() {
        const action = pendingPower;
        if (busy || !powerAvailable(action))
            return;
        pendingPower = "";
        if (action === "reboot")
            sddm.reboot();
        else if (action === "powerOff")
            sddm.powerOff();
        else if (action === "suspend")
            sddm.suspend();
    }
    function powerAvailable(action) {
        if (action === "reboot")
            return sddm.canReboot;
        if (action === "powerOff")
            return sddm.canPowerOff;
        if (action === "suspend")
            return sddm.canSuspend;
        return false;
    }
    function requestPower(action) {
        if (busy || pendingPower || !powerAvailable(action))
            return;
        powerConfirm.action = action;
        pendingPower = action;
        Qt.callLater(function () {
            if (root.pendingPower)
                cancelPowerButton.forceActiveFocus();
        });
    }
    function tinted(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    color: appearance.backgroundColor
    height: 1080
    width: 1920

    Component.onCompleted: {
        entered = true;
        if (username.text.trim())
            password.forceActiveFocus();
        else
            username.forceActiveFocus();
    }

    Settings {
        id: appearance

        property string accent: "#b8c7ee"
        property string avatar: ""
        property string background: ""
        property string backgroundColor: "#15171b"
        property string border: "#626774"
        property string error: "#ffb4ab"
        property string muted: "#bdc2ce"
        property string profileUsername: ""
        property string surface: "#22252c"
        property string text: "#e5e7ef"

        category: "Theme"
        location: "file://" + (config.StateFile || "/var/lib/quickshell-sddm/theme.ini")
    }
    Connections {
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

        target: sddm
    }
    Timer {
        interval: 1000
        repeat: true
        running: true

        onTriggered: root.now = new Date()
    }

    // Keep the same blurred wallpaper throughout authentication. The greeter
    // is replaced by SDDM when the session is ready.
    Image {
        id: wallpaper

        anchors.fill: parent
        asynchronous: true
        cache: false
        fillMode: Image.PreserveAspectCrop
        source: appearance.background ? "file://" + appearance.background : "assets/background.svg"
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        autoPaddingEnabled: false
        blur: 0.8
        blurEnabled: true
        blurMax: 64
        source: wallpaper
    }
    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor
        opacity: 0.30
    }
    Rectangle {
        anchors.fill: parent

        gradient: Gradient {
            GradientStop {
                color: "#1a000000"
                position: 0
            }
            GradientStop {
                color: "#24000000"
                position: 0.55
            }
            GradientStop {
                color: "#66000000"
                position: 1
            }
        }
    }
    Item {
        anchors.fill: parent
        opacity: root.entered ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 280
                easing.type: Easing.OutCubic
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.foregroundColor
            font.family: root.textFont
            font.letterSpacing: -2.5 * root.compactScale
            font.pixelSize: 80 * root.compactScale
            font.weight: Font.DemiBold
            style: Text.Raised
            styleColor: "#30000000"
            text: Qt.formatTime(root.now, "HH:mm")
            y: root.height * 0.20 - height / 2
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.mutedColor
            font.family: root.textFont
            font.pixelSize: 14 * root.compactScale
            font.weight: Font.Medium
            text: Qt.locale("de_DE").toString(root.now, "dddd, d. MMMM")
            y: root.height * 0.29 - height / 2
        }
        Item {
            id: authentication

            anchors.horizontalCenter: parent.horizontalCenter
            enabled: !root.busy && !root.pendingPower
            height: 320 * root.compactScale
            width: Math.min(360, root.width - 48)
            y: root.height / 2 - 120 * root.compactScale

            Rectangle {
                id: avatar

                anchors.horizontalCenter: parent.horizontalCenter
                border.color: root.tinted(root.foregroundColor, 0.22)
                border.width: 1
                color: root.tinted(root.surfaceColor, 0.65)
                height: width
                radius: width / 2
                width: 88 * root.compactScale
                y: 16 * root.compactScale

                Text {
                    anchors.centerIn: parent
                    color: root.foregroundColor
                    font.family: username.text.trim() ? root.textFont : root.iconFont
                    font.pixelSize: 30 * root.compactScale
                    font.weight: Font.DemiBold
                    text: username.text.trim() ? username.text.trim().charAt(0).toUpperCase() : "person"
                    visible: portrait.status !== Image.Ready
                }
                Image {
                    id: portrait

                    anchors.fill: parent
                    anchors.margins: 2
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectCrop
                    source: root.profileMatches ? "file://" + appearance.avatar : ""
                    sourceSize.height: Math.ceil(176 * root.compactScale)
                    sourceSize.width: Math.ceil(176 * root.compactScale)
                    visible: false
                }
                // A mask must be a visual child of the scene to have a window
                // and a render-thread texture provider, even while hidden.
                Rectangle {
                    id: portraitMask

                    anchors.fill: portrait
                    antialiasing: true
                    color: "white"
                    layer.enabled: true
                    radius: width / 2
                    visible: false
                }
                MultiEffect {
                    anchors.fill: portrait
                    autoPaddingEnabled: false
                    maskEnabled: true
                    maskSource: portraitMask
                    source: portrait
                    visible: portrait.status === Image.Ready
                }
            }
            TextField {
                id: username

                Accessible.name: "Benutzername"
                KeyNavigation.tab: password
                anchors.horizontalCenter: parent.horizontalCenter
                color: root.foregroundColor
                font.family: root.textFont
                font.pixelSize: 18 * root.compactScale
                font.weight: Font.DemiBold
                height: 36 * root.compactScale
                horizontalAlignment: TextInput.AlignHCenter
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                placeholderText: "Benutzername"
                placeholderTextColor: appearance.muted
                selectByMouse: true
                selectedTextColor: root.backgroundColor
                selectionColor: root.accentColor
                text: userModel.lastUser || config.DefaultUsername || ""
                width: parent.width
                y: (120 + 8 - 18) * root.compactScale

                background: Rectangle {
                    border.color: root.tinted(root.accentColor, 0.55)
                    border.width: username.activeFocus ? 1 : 0
                    color: username.activeFocus ? root.tinted(root.surfaceColor, 0.38) : "transparent"
                    radius: 12

                    Behavior on color {
                        ColorAnimation {
                            duration: 180
                        }
                    }
                }

                onAccepted: password.forceActiveFocus()
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                border.color: root.errorMessage ? root.tinted(root.errorColor, 0.8) : password.activeFocus ? root.tinted(root.accentColor, 0.65) : root.tinted(root.foregroundColor, 0.18)
                border.width: 1
                color: root.tinted(root.surfaceColor, 0.72)
                height: 52 * root.compactScale
                radius: 18 * root.compactScale
                width: Math.min(320, authentication.width)
                y: (120 + 65 - 26) * root.compactScale

                Behavior on border.color {
                    ColorAnimation {
                        duration: 180
                    }
                }

                TextField {
                    id: password

                    Accessible.name: "Passwort"
                    KeyNavigation.tab: loginButton
                    anchors.left: parent.left
                    anchors.leftMargin: 16 * root.compactScale
                    anchors.right: visibilityButton.left
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.foregroundColor
                    echoMode: root.passwordVisible ? TextInput.Normal : TextInput.Password
                    font.family: root.textFont
                    font.pixelSize: 14 * root.compactScale
                    height: parent.height - 4
                    inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    leftPadding: 0
                    passwordCharacter: "●"
                    passwordMaskDelay: 0
                    placeholderText: "Passwort"
                    placeholderTextColor: appearance.muted
                    rightPadding: 3
                    selectByMouse: true
                    selectedTextColor: root.backgroundColor
                    selectionColor: root.accentColor

                    background: Item {
                    }

                    Keys.onEscapePressed: {
                        clear();
                        root.errorMessage = "";
                        root.passwordVisible = false;
                    }
                    onAccepted: root.login()
                    onTextEdited: root.errorMessage = ""
                }
                ToolButton {
                    id: visibilityButton

                    Accessible.name: root.passwordVisible ? "Passwort verbergen" : "Passwort anzeigen"
                    anchors.right: loginButton.left
                    anchors.rightMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: root.iconFont
                    font.pixelSize: 19 * root.compactScale
                    height: 40 * root.compactScale
                    text: root.passwordVisible ? "visibility_off" : "visibility"
                    width: 32 * root.compactScale

                    background: Rectangle {
                        color: visibilityButton.hovered || visibilityButton.activeFocus ? root.tinted(root.foregroundColor, 0.07) : "transparent"
                        radius: 12
                    }
                    contentItem: Text {
                        color: visibilityButton.hovered || visibilityButton.activeFocus ? root.foregroundColor : root.mutedColor
                        font: visibilityButton.font
                        horizontalAlignment: Text.AlignHCenter
                        text: visibilityButton.text
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        root.passwordVisible = !root.passwordVisible;
                        password.forceActiveFocus();
                    }
                }
                Button {
                    id: loginButton

                    Accessible.name: "Anmelden"
                    KeyNavigation.tab: session
                    anchors.right: parent.right
                    anchors.rightMargin: 6 * root.compactScale
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: root.iconFont
                    font.pixelSize: 22 * root.compactScale
                    height: 38 * root.compactScale
                    text: "arrow_forward"
                    width: 38 * root.compactScale

                    background: Rectangle {
                        border.color: root.foregroundColor
                        border.width: loginButton.activeFocus ? 2 : 0
                        color: root.tinted(root.accentColor, 0.12)
                        opacity: loginButton.down ? 0.75 : loginButton.hovered || loginButton.activeFocus ? 1 : 0.9
                        radius: 12 * root.compactScale
                        scale: loginButton.down ? 0.94 : 1

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 140
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 250
                                easing.overshoot: 0.6
                                easing.type: Easing.OutBack
                            }
                        }
                    }
                    contentItem: Text {
                        color: root.accentColor
                        font: loginButton.font
                        horizontalAlignment: Text.AlignHCenter
                        text: loginButton.text
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: root.login()
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.mutedColor
            font.family: root.textFont
            font.pixelSize: 11 * root.compactScale
            text: root.busy ? "Anmeldung läuft …" : "Enter zum Anmelden"
            y: root.height / 2 + 112 * root.compactScale - height / 2
        }
        Text {
            Accessible.name: root.errorMessage
            Accessible.role: Accessible.StaticText
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.errorColor
            font.family: root.textFont
            font.pixelSize: 12 * root.compactScale
            horizontalAlignment: Text.AlignHCenter
            text: root.errorMessage
            width: Math.min(380, root.width - 48)
            wrapMode: Text.WordWrap
            y: root.height / 2 + 134 * root.compactScale
        }
    }
    ComboBox {
        id: session

        Accessible.name: "Desktop-Sitzung"
        KeyNavigation.tab: username
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 24
        currentIndex: Math.max(0, sessionModel.lastIndex)
        enabled: !root.busy && !root.pendingPower && count > 1
        font.family: root.textFont
        font.pixelSize: 11
        height: 40
        leftPadding: 31
        model: sessionModel
        rightPadding: 29
        textRole: "name"
        width: Math.min(220, root.width / 2 - 24)

        background: Rectangle {
            border.color: session.activeFocus ? root.tinted(root.accentColor, 0.7) : root.tinted(root.foregroundColor, 0.08)
            border.width: session.activeFocus ? 1 : 0
            color: session.hovered || session.activeFocus ? root.tinted(root.surfaceColor, 0.62) : "transparent"
            radius: 15

            Behavior on color {
                ColorAnimation {
                    duration: 180
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: root.mutedColor
                font.family: root.iconFont
                font.pixelSize: 16
                text: "desktop_windows"
                x: 12
            }
        }
        contentItem: Text {
            color: root.mutedColor
            elide: Text.ElideRight
            font: session.font
            horizontalAlignment: Text.AlignLeft
            text: session.displayText
            verticalAlignment: Text.AlignVCenter
        }
        delegate: ItemDelegate {
            id: sessionEntry

            required property int index
            required property string name

            font: session.font
            height: 40
            highlighted: session.highlightedIndex === index
            text: name
            width: session.width - 12

            background: Rectangle {
                color: sessionEntry.highlighted ? root.tinted(root.accentColor, 0.13) : "transparent"
                radius: 10
            }
            contentItem: Text {
                color: sessionEntry.highlighted ? root.accentColor : root.foregroundColor
                elide: Text.ElideRight
                font: sessionEntry.font
                text: sessionEntry.text
                verticalAlignment: Text.AlignVCenter
            }
        }
        indicator: Text {
            anchors.verticalCenter: parent.verticalCenter
            color: root.mutedColor
            font.family: root.iconFont
            font.pixelSize: 18
            text: session.popup.visible ? "expand_less" : "expand_more"
            visible: session.count > 1
            x: session.width - width - 10
        }
        popup: Popup {
            bottomMargin: 16
            implicitHeight: Math.min(contentItem.implicitHeight + 12, 208)
            padding: 6
            topMargin: 16
            width: session.width
            y: -height - 6

            background: Rectangle {
                border.color: root.tinted(root.borderColor, 0.7)
                border.width: 1
                color: root.tinted(root.surfaceColor, 0.98)
                radius: 17
            }
            contentItem: ListView {
                clip: true
                currentIndex: session.highlightedIndex
                implicitHeight: contentHeight
                model: session.popup.visible ? session.delegateModel : null

                ScrollIndicator.vertical: ScrollIndicator {
                }
            }
        }
    }
    Row {
        anchors.bottom: parent.bottom
        anchors.margins: 24
        anchors.right: parent.right
        enabled: !root.busy && !root.pendingPower
        spacing: 8

        Repeater {
            model: [
                {
                    icon: "bedtime",
                    action: "suspend",
                    label: "Standby",
                    available: sddm.canSuspend
                },
                {
                    icon: "restart_alt",
                    action: "reboot",
                    label: "Neu starten",
                    available: sddm.canReboot
                },
                {
                    icon: "power_settings_new",
                    action: "powerOff",
                    label: "Ausschalten",
                    available: sddm.canPowerOff
                }
            ]

            delegate: FocusScope {
                id: powerAction

                required property var modelData

                Accessible.name: modelData.label
                Accessible.role: Accessible.Button
                ToolTip.delay: 700
                ToolTip.text: modelData.label
                ToolTip.visible: powerMouse.containsMouse
                activeFocusOnTab: true
                height: 40
                visible: modelData.available
                width: modelData.available ? 40 : 0

                Accessible.onPressAction: root.requestPower(modelData.action)
                Keys.onEnterPressed: event => {
                    root.requestPower(modelData.action);
                    event.accepted = true;
                }
                Keys.onReturnPressed: event => {
                    root.requestPower(modelData.action);
                    event.accepted = true;
                }
                Keys.onSpacePressed: event => {
                    root.requestPower(modelData.action);
                    event.accepted = true;
                }

                Rectangle {
                    anchors.fill: parent
                    border.color: root.tinted(root.foregroundColor, powerAction.activeFocus ? 0.42 : 0.1)
                    border.width: powerAction.activeFocus ? 1 : 0
                    color: root.tinted(root.surfaceColor, powerMouse.containsMouse || powerAction.activeFocus ? 0.75 : 0.14)
                    radius: 13
                    scale: powerMouse.pressed ? 0.92 : 1

                    Behavior on color {
                        ColorAnimation {
                            duration: 180
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: 240
                            easing.overshoot: 0.6
                            easing.type: Easing.OutBack
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    color: powerMouse.containsMouse || powerAction.activeFocus ? root.accentColor : root.mutedColor
                    font.family: root.iconFont
                    font.pixelSize: 19
                    text: powerAction.modelData.icon
                }
                MouseArea {
                    id: powerMouse

                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    onClicked: {
                        powerAction.forceActiveFocus();
                        root.requestPower(powerAction.modelData.action);
                    }
                }
            }
        }
    }
    FocusScope {
        id: powerConfirm

        property string action: ""

        anchors.fill: parent
        enabled: !!root.pendingPower
        focus: !!root.pendingPower
        opacity: root.pendingPower ? 1 : 0
        visible: opacity > 0.001
        z: 1000

        Behavior on opacity {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }

        Keys.onEscapePressed: event => {
            root.cancelPower();
            event.accepted = true;
        }

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
            border.color: root.tinted(root.borderColor, 0.75)
            border.width: 1
            color: root.tinted(root.surfaceColor, 0.97)
            height: powerConfirmContent.implicitHeight + 52
            radius: 27
            scale: root.pendingPower ? 1 : 0.96
            width: Math.min(374, root.width - 48)

            Behavior on scale {
                NumberAnimation {
                    duration: 240
                    easing.overshoot: 0.5
                    easing.type: Easing.OutBack
                }
            }

            MouseArea {
                anchors.fill: parent

                onClicked: mouse => {
                    mouse.accepted = true;
                }
            }
            ColumnLayout {
                id: powerConfirmContent

                anchors.left: parent.left
                anchors.margins: 26
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 16

                Rectangle {
                    Layout.preferredHeight: 48
                    Layout.preferredWidth: 48
                    color: root.tinted(root.accentColor, 0.12)
                    radius: 17

                    Text {
                        anchors.centerIn: parent
                        color: root.accentColor
                        font.family: root.iconFont
                        font.pixelSize: 25
                        text: powerConfirm.action === "reboot" ? "restart_alt" : powerConfirm.action === "powerOff" ? "power_settings_new" : "bedtime"
                    }
                }
                Text {
                    Layout.fillWidth: true
                    color: root.foregroundColor
                    font.family: root.textFont
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    text: powerConfirm.action === "reboot" ? "Neu starten?" : powerConfirm.action === "powerOff" ? "Ausschalten?" : "In Standby wechseln?"
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    color: root.mutedColor
                    font.family: root.textFont
                    font.pixelSize: 13
                    lineHeight: 1.25
                    text: powerConfirm.action === "reboot" ? "Der Computer wird neu gestartet." : powerConfirm.action === "powerOff" ? "Der Computer wird vollständig ausgeschaltet." : "Der Computer bleibt im Energiesparmodus bereit."
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

    component ConfirmationButton: Button {
        id: confirmationControl

        property bool primary: false

        font.family: root.textFont
        font.pixelSize: 13
        font.weight: Font.Medium
        implicitHeight: 44
        leftPadding: 19
        rightPadding: 19

        background: Rectangle {
            border.color: root.foregroundColor
            border.width: confirmationControl.activeFocus ? 1 : 0
            color: confirmationControl.primary ? root.accentColor : root.tinted(root.foregroundColor, 0.08)
            opacity: confirmationControl.down ? 0.7 : confirmationControl.hovered || confirmationControl.activeFocus ? 1 : 0.9
            radius: 14
        }
        contentItem: Text {
            color: confirmationControl.primary ? root.backgroundColor : root.foregroundColor
            font: confirmationControl.font
            horizontalAlignment: Text.AlignHCenter
            text: confirmationControl.text
            verticalAlignment: Text.AlignVCenter
        }
    }
}
