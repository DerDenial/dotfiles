import QtQuick
import "Theme" as ThemePalette
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Rectangle {
    id: root

    required property var panelWindow
    property real anchorBottom: 64

    implicitWidth: trayRow.implicitWidth + 16
    implicitHeight: 33
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: "transparent"
    visible: SystemTray.items.values.length > 0

    RowLayout {
        id: trayRow
        anchors.centerIn: parent
        spacing: 7

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: iconDelegate
                required property var modelData
                width: 22
                height: 22

                IconImage {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    source: iconDelegate.modelData.icon
                    asynchronous: true
                    mipmap: true
                }

                function openTrayMenu() {
                    const item = modelData;
                    if (!item.hasMenu)
                        return;

                    const menuPosition = iconDelegate.mapToItem(
                        root.panelWindow.contentItem,
                        iconDelegate.width / 2,
                        iconDelegate.height
                    );
                    trayMenu.openFor(item.menu, menuPosition.x);
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor

                    onClicked: mouse => {
                        const item = iconDelegate.modelData;

                        if (mouse.button === Qt.RightButton) {
                            iconDelegate.openTrayMenu();
                        } else if (mouse.button === Qt.MiddleButton) {
                            item.secondaryActivate();
                        } else if (item.onlyMenu && item.hasMenu) {
                            iconDelegate.openTrayMenu();
                        } else {
                            item.activate();
                        }
                    }
                }
            }
        }
    }

    PopupWindow {
        id: trayMenu

        property var activeMenu: null
        property var menuStack: []
        property real anchorX: 0
        property real anchorY: 0
        readonly property real screenWidth: root.panelWindow.screen
            ? root.panelWindow.screen.width : root.panelWindow.width
        readonly property real screenHeight: root.panelWindow.screen
            ? root.panelWindow.screen.height : root.panelWindow.height
        readonly property real maximumHeight: Math.max(16, screenHeight - 24)

        function resetScroll() {
            menuScroll.contentY = 0;
            // Menu children and Column geometry can arrive after the handle.
            Qt.callLater(() => menuScroll.contentY = 0);
        }

        function openFor(menuHandle, x) {
            anchorY = root.anchorBottom + 7;
            visible = false;
            Qt.callLater(() => {
                activeMenu = menuHandle;
                menuStack = [];
                anchorX = x;
                resetScroll();
                visible = true;
            });
        }

        function goBack() {
            if (menuStack.length === 0)
                return;
            const stack = menuStack.slice();
            activeMenu = stack.pop();
            menuStack = stack;
            resetScroll();
        }

        implicitWidth: Math.min(228, Math.max(80, screenWidth - 24))
        // Use the menu's natural height; scroll only if it exceeds the display.
        implicitHeight: Math.min(menuColumn.implicitHeight + 12, maximumHeight)
        visible: false
        color: "transparent"
        grabFocus: true

        anchor.window: root.panelWindow
        anchor.rect.x: Math.max(12, Math.min(anchorX - width / 2, screenWidth - width - 12))
        anchor.rect.y: Math.max(12, Math.min(trayMenu.anchorY, screenHeight - height - 12))
        anchor.adjustment: PopupAdjustment.Slide

        QsMenuOpener {
            id: menuOpener
            menu: trayMenu.activeMenu
            onChildrenChanged: trayMenu.resetScroll()
        }

        Rectangle {
            id: menuSurface
            anchors.fill: parent
            radius: 13
            color: ThemePalette.Theme.surface
            border.width: 1
            border.color: ThemePalette.Theme.border

            Flickable {
                id: menuScroll
                anchors.fill: parent
                anchors.margins: 6
                contentWidth: width
                contentHeight: menuColumn.implicitHeight
                clip: true
                interactive: contentHeight > height + 0.5
                boundsBehavior: Flickable.StopAtBounds

                // Wheel and touch scrolling remain available for tall menus.

                Column {
                    id: menuColumn
                    width: menuScroll.width
                    spacing: 1

                    Item {
                        visible: trayMenu.menuStack.length > 0
                        width: menuColumn.width
                        height: visible ? 28 : 0

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 2
                            anchors.rightMargin: 2
                            radius: 8
                            color: backArea.containsMouse ? ThemePalette.Theme.surfaceRaised : "transparent"
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            text: "‹  Back"
                            color: ThemePalette.Theme.red
                            font.family: "Inter"
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: backArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: trayMenu.goBack()
                        }
                    }

                    Repeater {
                        model: menuOpener.children

                        delegate: Item {
                            id: entryRow
                            required property var modelData
                            width: menuColumn.width
                            height: modelData.isSeparator ? 7 : 28

                            Rectangle {
                                visible: entryRow.modelData.isSeparator
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                height: 1
                                color: ThemePalette.Theme.border
                            }

                            Rectangle {
                                visible: !entryRow.modelData.isSeparator
                                anchors.fill: parent
                                anchors.leftMargin: 2
                                anchors.rightMargin: 2
                                radius: 8
                                color: rowArea.containsMouse && entryRow.modelData.enabled
                                    ? ThemePalette.Theme.surfaceRaised
                                    : "transparent"
                            }

                            Image {
                                id: entryIcon
                                visible: !entryRow.modelData.isSeparator && entryRow.modelData.icon !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 9
                                width: 14
                                height: 14
                                source: entryRow.modelData.icon
                                sourceSize.width: width
                                sourceSize.height: height
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }

                            Text {
                                id: entryCheck
                                visible: !entryRow.modelData.isSeparator
                                    && entryRow.modelData.checkState === Qt.Checked
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 9
                                width: 14
                                horizontalAlignment: Text.AlignHCenter
                                text: "✓"
                                color: ThemePalette.Theme.red
                                font.family: "Inter"
                                font.pixelSize: 12
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: entryIcon.visible || entryCheck.visible ? 29 : 10
                                anchors.right: entryArrow.visible ? entryArrow.left : parent.right
                                anchors.rightMargin: entryArrow.visible ? 4 : 10
                                visible: !entryRow.modelData.isSeparator
                                text: entryRow.modelData.text
                                color: entryRow.modelData.enabled ? ThemePalette.Theme.textLight : ThemePalette.Theme.gray1
                                font.family: "Inter"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }

                            Text {
                                id: entryArrow
                                visible: !entryRow.modelData.isSeparator && entryRow.modelData.hasChildren
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                text: "›"
                                color: entryRow.modelData.enabled ? ThemePalette.Theme.red : ThemePalette.Theme.gray1
                                font.family: "Inter"
                                font.pixelSize: 17
                            }

                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !entryRow.modelData.isSeparator && entryRow.modelData.enabled
                                onClicked: {
                                    if (entryRow.modelData.hasChildren) {
                                        trayMenu.menuStack = trayMenu.menuStack.concat([trayMenu.activeMenu]);
                                        trayMenu.activeMenu = entryRow.modelData;
                                        trayMenu.resetScroll();
                                    } else {
                                        entryRow.modelData.triggered();
                                        trayMenu.visible = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
