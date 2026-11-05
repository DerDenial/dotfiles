import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Theme" as ThemeApi

SCard {
    id: card
    objectName: "cursorSettings"
    property var preferences: null
    readonly property var info: preferences && preferences.info ? preferences.info : ({ themes: [], current: { theme: "", size: 24 }, saved: false })
    readonly property var themes: Array.isArray(info.themes) ? info.themes : []
    readonly property bool busy: preferences ? preferences.busy : false
    readonly property bool loading: preferences ? preferences.loading : false
    property string candidateTheme: ""
    property int candidateSize: 24
    property bool candidateReady: false
    property string reportedTheme: ""
    property int reportedSize: 24
    readonly property var candidate: themes.find(theme => theme.id === candidateTheme) || null
    readonly property var sizes: candidate && Array.isArray(candidate.sizes) && candidate.sizes.length ? candidate.sizes : [16, 24, 32, 40, 48, 64]
    readonly property bool changed: candidateTheme !== String(info.current ? info.current.theme : "") || candidateSize !== Number(info.current ? info.current.size : 24)
    readonly property bool canApply: candidate !== null && !busy && !loading && (changed || !info.saved)

    title: "Cursor"
    subtitle: "Choose a pointer style for your desktop and apps."
    iconName: "mouse"

    function nearestSize(value) {
        let closest = Number(sizes[0]);
        for (const size of sizes)
            if (Math.abs(Number(size) - value) < Math.abs(closest - value)) closest = Number(size);
        return closest;
    }
    function synchronize() {
        if (!themes.length) return;
        const current = info.current || ({ theme: "", size: 24 });
        const theme = themes.find(entry => entry.id === current.theme) || themes[0];
        const size = Number(current.size) || 24;
        const externalChange = reportedTheme !== String(current.theme) || reportedSize !== size;
        const missing = !themes.some(entry => entry.id === candidateTheme);
        if (!candidateReady || externalChange || missing) {
            candidateTheme = theme.id;
            candidateSize = nearestSize(size);
        }
        reportedTheme = String(current.theme);
        reportedSize = size;
        candidateReady = true;
    }
    function selectTheme(index) {
        if (busy || loading || index < 0 || index >= themes.length) return;
        candidateTheme = themes[index].id;
        candidateSize = nearestSize(candidateSize);
    }
    function applyCandidate() {
        if (canApply && preferences) preferences.apply(candidateTheme, candidateSize);
    }
    onInfoChanged: synchronize()
    onThemesChanged: synchronize()
    Component.onCompleted: { synchronize(); if (preferences) preferences.refresh(); }

    SNotice {
        objectName: "cursorError"
        text: card.preferences ? card.preferences.error : ""
        warning: true
    }

    SNotice {
        objectName: "cursorWarnings"
        text: Array.isArray(card.info.warnings) ? card.info.warnings.filter(message => typeof message === "string" && message.trim()).join("\n") : ""
        warning: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 14
        Rectangle {
            Layout.preferredWidth: 72
            Layout.preferredHeight: 72
            radius: 18
            color: ThemeApi.Theme.surfaceAlt
            border.width: 1
            border.color: Qt.alpha(ThemeApi.Theme.border, 0.55)
            Image {
                id: largePreview
                objectName: "cursorPreview"
                anchors.centerIn: parent
                width: Math.min(56, Math.max(24, card.candidateSize))
                height: width
                source: card.candidate ? card.candidate.preview : ""
                asynchronous: true
                cache: false
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 112
                sourceSize.height: 112
                visible: status === Image.Ready
                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 0.4 } }
            }
            Text {
                anchors.centerIn: parent
                visible: largePreview.status !== Image.Ready
                text: "arrow_selector_tool"
                font.family: "Material Symbols Rounded"
                font.pixelSize: 32
                color: ThemeApi.Theme.accent
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5
            SLabel {
                Layout.fillWidth: true
                text: card.loading ? "Finding installed cursors…" : card.candidate ? card.candidate.name : "No cursor themes found"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: ThemeApi.Theme.textBright
                elide: Text.ElideMiddle
            }
            SLabel {
                Layout.fillWidth: true
                text: card.candidate ? card.candidateSize + " px · " + (card.changed || !card.info.saved ? "Ready to apply" : "Applied") : "Install a cursor theme to get started."
                font.pixelSize: 11
                color: ThemeApi.Theme.muted
                wrapMode: Text.WordWrap
            }
        }
        SButton {
            objectName: "cursorRefresh"
            iconName: "refresh"
            Accessible.name: "Refresh installed cursor themes"
            enabled: !card.busy && !card.loading
            onClicked: if (card.preferences) card.preferences.refresh()
            ToolTip.visible: hovered
            ToolTip.text: "Refresh installed themes"
        }
    }

    ComboBox {
        id: themePicker
        objectName: "cursorThemePicker"
        Layout.fillWidth: true
        implicitHeight: 44
        model: card.themes
        textRole: "name"
        valueRole: "id"
        currentIndex: card.themes.findIndex(theme => theme.id === card.candidateTheme)
        enabled: !card.busy && !card.loading && card.themes.length > 0
        Accessible.name: "Cursor theme"
        leftPadding: 14
        rightPadding: 40
        onActivated: index => card.selectTheme(index)
        contentItem: SLabel {
            text: themePicker.displayText
            font.pixelSize: 12
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideMiddle
        }
        indicator: Text {
            x: themePicker.width - width - 12
            anchors.verticalCenter: parent.verticalCenter
            text: themePicker.popup.visible ? "expand_less" : "expand_more"
            color: ThemeApi.Theme.muted
            font.family: "Material Symbols Rounded"
            font.pixelSize: 20
        }
        background: Rectangle {
            radius: 12
            color: themePicker.hovered ? ThemeApi.Theme.surfaceRaised : ThemeApi.Theme.surfaceAlt
            border.width: themePicker.activeFocus ? 2 : 1
            border.color: themePicker.activeFocus ? ThemeApi.Theme.accent : ThemeApi.Theme.border
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        delegate: ItemDelegate {
            id: themeOption
            required property int index
            required property var modelData
            width: themePicker.width - 10
            implicitHeight: 48
            highlighted: themePicker.highlightedIndex === index
            leftPadding: 12
            rightPadding: 12
            Accessible.name: modelData.name
            contentItem: RowLayout {
                spacing: 12
                Item {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    Image {
                        id: smallPreview
                        anchors.centerIn: parent
                        width: 30; height: 30
                        source: themeOption.modelData.preview
                        asynchronous: true
                        cache: false
                        sourceSize.width: 60
                        sourceSize.height: 60
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: smallPreview.status !== Image.Ready
                        text: "arrow_selector_tool"
                        color: ThemeApi.Theme.accent
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 22
                    }
                }
                SLabel {
                    Layout.fillWidth: true
                    text: themeOption.modelData.name
                    elide: Text.ElideMiddle
                    font.pixelSize: 12
                    color: ThemeApi.Theme.textBright
                }
                Text {
                    visible: themeOption.modelData.id === card.candidateTheme
                    text: "check"
                    color: ThemeApi.Theme.accent
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 18
                }
            }
            background: Rectangle {
                radius: 9
                color: themeOption.highlighted ? ThemeApi.Theme.accentSoft : "transparent"
            }
        }
        popup: Popup {
            y: themePicker.height + 6
            width: themePicker.width
            implicitHeight: Math.min(300, themeList.contentHeight + 12)
            padding: 5
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            contentItem: ListView {
                id: themeList
                clip: true
                implicitHeight: contentHeight
                model: themePicker.popup.visible ? themePicker.delegateModel : null
                currentIndex: themePicker.highlightedIndex
                boundsBehavior: Flickable.StopAtBounds
                ScrollIndicator.vertical: ScrollIndicator { }
            }
            background: Rectangle {
                radius: 14
                color: ThemeApi.Theme.surfaceRaised
                border.width: 1
                border.color: ThemeApi.Theme.border
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        SLabel { text: "Cursor size"; font.pixelSize: 12; Layout.fillWidth: true }
        SLabel { text: card.candidateSize + " px"; font.pixelSize: 11; color: ThemeApi.Theme.accent }
    }
    GridLayout {
        Layout.fillWidth: true
        columns: width >= 300 ? 6 : 3
        columnSpacing: 6
        rowSpacing: 6
        Repeater {
            model: card.sizes
            delegate: SButton {
                required property int modelData
                objectName: "cursorSize" + modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 36
                implicitWidth: 36
                text: String(modelData)
                accent: card.candidateSize === modelData
                Accessible.name: "Cursor size " + modelData + " pixels"
                enabled: card.candidate !== null && !card.busy && !card.loading
                onClicked: card.candidateSize = modelData
            }
        }
    }
    SLabel {
        Layout.fillWidth: true
        text: "Some running apps need to be reopened to use the new cursor."
        font.pixelSize: 10
        color: ThemeApi.Theme.muted
        wrapMode: Text.WordWrap
    }
    SButton {
        objectName: "cursorApply"
        text: card.busy ? "Applying…" : "Apply everywhere"
        iconName: "check"
        accent: true
        Layout.alignment: Qt.AlignRight
        enabled: card.canApply
        onClicked: card.applyCandidate()
    }
}
