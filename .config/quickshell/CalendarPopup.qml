import QtQuick
import "Theme" as ThemePalette
import QtQuick.Layouts
import Quickshell

Item {
    id: popup
    property var settingsController: null

    property date displayedMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property date selectedDate: new Date()
    property int firstWeekdayOffset: (new Date(displayedMonth.getFullYear(), displayedMonth.getMonth(), 1).getDay() + 6) % 7
    property string monthLabel: Qt.formatDate(displayedMonth, "MMMM yyyy")

    function changeMonth(amount) {
        displayedMonth = new Date(displayedMonth.getFullYear(), displayedMonth.getMonth() + amount, 1);
    }
    function selectDay(dayOffset) {
        const date = new Date(displayedMonth.getFullYear(), displayedMonth.getMonth(), dayOffset);
        selectedDate = date;
        if (date.getMonth() !== displayedMonth.getMonth())
            displayedMonth = new Date(date.getFullYear(), date.getMonth(), 1);
    }
    function open() {
        visible = true;
        openAnimation.restart();
    }
    function close() {
        if (settingsController) settingsController.close();
        else closeAnimation.restart();
    }
    function toggle() {
        if (visible) close();
        else open();
    }


    Rectangle {
        id: surface
        anchors.fill: parent
        radius: 0
        color: "transparent"
        border.width: 0
        border.color: "transparent"
        scale: 0.92
        opacity: 0

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 0
            spacing: 18

                SettingsPageHeader {
        title: "Calendar"
        subtitle: "Your month at a glance"
        iconName: "calendar_month"
        accentColor: ThemePalette.Theme.accent

        Rectangle {
            Layout.preferredWidth: 92
            Layout.preferredHeight: 36
            radius: 13
            color: ThemePalette.Theme.surfaceAlt
            Text {
                anchors.centerIn: parent
                text: Qt.formatDate(new Date(), "ddd, d MMM")
                color: ThemePalette.Theme.text
                font.family: "Inter"
                font.pixelSize: 10
                font.weight: Font.Medium
            }
        }
    }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                spacing: 8
                MonthButton {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    icon: "chevron_left"
                    onClicked: popup.changeMonth(-1)
                }
                Text {
                    text: popup.monthLabel
                    color: ThemePalette.Theme.text
                    font.family: "Inter"
                    font.pixelSize: 19
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }
                MonthButton {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    icon: "chevron_right"
                    onClicked: popup.changeMonth(1)
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 7
                columnSpacing: 4
                rowSpacing: 4
                Repeater {
                    model: 7
                    delegate: Text {
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: Qt.locale().dayName(index + 1, Locale.ShortFormat)
                        color: ThemePalette.Theme.muted
                        font.family: "Inter"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                columnSpacing: 4
                rowSpacing: 4
                Repeater {
                    model: 42
                    delegate: Rectangle {
                        required property int index
                        property int dayOffset: index - popup.firstWeekdayOffset + 1
                        property date cellDate: new Date(popup.displayedMonth.getFullYear(), popup.displayedMonth.getMonth(), dayOffset)
                        property bool inDisplayedMonth: cellDate.getMonth() === popup.displayedMonth.getMonth()
                        property bool isSelected: cellDate.getFullYear() === popup.selectedDate.getFullYear()
                            && cellDate.getMonth() === popup.selectedDate.getMonth()
                            && cellDate.getDate() === popup.selectedDate.getDate()
                        property bool isToday: cellDate.getFullYear() === new Date().getFullYear()
                            && cellDate.getMonth() === new Date().getMonth()
                            && cellDate.getDate() === new Date().getDate()

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 38
                        radius: 20
                        color: isSelected ? ThemePalette.Theme.accent : "transparent"
                        border.width: isToday && !isSelected ? 1 : 0
                        border.color: ThemePalette.Theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: parent.cellDate.getDate()
                            color: parent.isSelected ? ThemePalette.Theme.onAccent : (parent.inDisplayedMonth ? ThemePalette.Theme.text : ThemePalette.Theme.mutedStrong)
                            font.family: "Inter"
                            font.pixelSize: 14
                            font.weight: parent.isSelected || parent.isToday ? Font.Medium : Font.Normal
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.selectDay(parent.dayOffset)
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 62
                radius: 20
                color: ThemePalette.Theme.surfaceAlt
                border.width: 1
                border.color: ThemePalette.Theme.border
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12
                    Text {
                        text: "event"
                        color: ThemePalette.Theme.accent
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 23
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: Qt.formatDate(popup.selectedDate, "dddd, d MMMM yyyy")
                            color: ThemePalette.Theme.text
                            font.family: "Inter"
                            font.pixelSize: 13
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Text {
                            text: popup.selectedDate.getDate() === new Date().getDate()
                                && popup.selectedDate.getMonth() === new Date().getMonth()
                                && popup.selectedDate.getFullYear() === new Date().getFullYear()
                                ? "Today" : "Selected date"
                            color: ThemePalette.Theme.muted
                            font.family: "Inter"
                            font.pixelSize: 11
                        }
                    }
                    Rectangle {
                        Layout.preferredWidth: 58
                        Layout.preferredHeight: 34
                        radius: 17
                        color: ThemePalette.Theme.surfaceDark
                        Text {
                            anchors.centerIn: parent
                            text: "today"
                            color: ThemePalette.Theme.accent
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 20
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                popup.selectedDate = new Date();
                                popup.displayedMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
                            }
                        }
                    }
                }
            }
        }
    }

    component MonthButton: Rectangle {
        property string icon: ""
        signal clicked()
        radius: width / 2
        color: ThemePalette.Theme.surfaceAlt
        border.width: 1
        border.color: ThemePalette.Theme.border
        Text {
            anchors.centerIn: parent
            text: parent.icon
            color: ThemePalette.Theme.text
            font.family: "Material Symbols Rounded"
            font.pixelSize: 22
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    ParallelAnimation {
        id: openAnimation
        NumberAnimation { target: surface; property: "scale"; from: 0.92; to: 1; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: surface; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: closeAnimation
        onFinished: popup.visible = false
        NumberAnimation { target: surface; property: "scale"; from: 1; to: 0.94; duration: 180; easing.type: Easing.InCubic }
        NumberAnimation { target: surface; property: "opacity"; from: 1; to: 0; duration: 130 }
    }
}
