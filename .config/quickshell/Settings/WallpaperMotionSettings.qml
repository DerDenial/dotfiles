import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Theme" as ThemeApi

SCard {
    id: card
    objectName: "wallpaperMotionSettings"
    readonly property var choices: ThemeApi.Theme.wallpaperTransitions
    readonly property var selected: choices.find(option => option.id === ThemeApi.Theme.wallpaperTransitionId) || choices[0]
    title: "Wallpaper animation"
    subtitle: "Choose the transition for wallpaper and theme changes."
    iconName: "animation"

    ComboBox {
        id: picker
        objectName: "wallpaperMotionPicker"
        Layout.fillWidth: true
        implicitHeight: 44
        model: card.choices
        textRole: "name"
        valueRole: "id"
        currentIndex: card.choices.findIndex(option => option.id === ThemeApi.Theme.wallpaperTransitionId)
        Accessible.name: "Wallpaper transition"
        leftPadding: 14
        rightPadding: 40
        onActivated: index => {
            if (index >= 0 && index < card.choices.length)
                ThemeApi.Theme.setWallpaperTransition(card.choices[index].id);
        }
        background: Rectangle {
            radius: 12
            color: ThemeApi.Theme.surfaceAlt
            border.width: 1
            border.color: picker.activeFocus ? ThemeApi.Theme.accent : ThemeApi.Theme.border
        }
        contentItem: SLabel {
            text: picker.displayText
            font.pixelSize: 12
            color: ThemeApi.Theme.textBright
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
        indicator: Text {
            x: picker.width - width - 14
            anchors.verticalCenter: parent.verticalCenter
            text: "expand_more"
            font.family: "Material Symbols Rounded"
            font.pixelSize: 20
            color: ThemeApi.Theme.muted
        }
        delegate: ItemDelegate {
            id: option
            required property var modelData
            required property int index
            width: picker.width - 10
            height: 40
            highlighted: picker.highlightedIndex === index
            leftPadding: 12
            rightPadding: 12
            contentItem: RowLayout {
                SLabel {
                    Layout.fillWidth: true
                    text: option.modelData.name
                    font.pixelSize: 12
                    color: ThemeApi.Theme.textBright
                }
                Text {
                    visible: option.modelData.id === ThemeApi.Theme.wallpaperTransitionId
                    text: "check"
                    color: ThemeApi.Theme.accent
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 18
                }
            }
            background: Rectangle {
                radius: 9
                color: option.highlighted ? ThemeApi.Theme.accentSoft : "transparent"
            }
        }
        popup: Popup {
            y: picker.height + 6
            width: picker.width
            implicitHeight: Math.min(340, options.contentHeight + 12)
            padding: 5
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            contentItem: ListView {
                id: options
                clip: true
                implicitHeight: contentHeight
                model: picker.popup.visible ? picker.delegateModel : null
                currentIndex: picker.highlightedIndex
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
    SLabel {
        Layout.fillWidth: true
        text: card.selected ? card.selected.description : ""
        font.pixelSize: 11
        color: ThemeApi.Theme.muted
        wrapMode: Text.WordWrap
    }
}
