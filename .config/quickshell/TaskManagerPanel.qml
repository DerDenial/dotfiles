pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Theme" as ThemeApi

FocusScope {
    id: panel
    required property var manager
    signal closeRequested()
    signal moveRequested()
    readonly property int selectedIndex: manager.rows.findIndex(row => row.key === manager.selectedKey)
    readonly property real memoryFraction: manager.summary.memoryTotal > 0
        ? manager.summary.memoryUsed / manager.summary.memoryTotal : 0
    property alias processView: processes
    property alias searchInput: search

    function bytes(value, perSecond) {
        if (value === null || value === undefined || !Number.isFinite(Number(value))) return "—";
        let amount = Number(value);
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        let unit = 0;
        while (amount >= 1024 && unit < units.length - 1) { amount /= 1024; ++unit; }
        return amount.toFixed(unit > 1 ? 1 : 0) + " " + units[unit] + (perSecond ? "/s" : "");
    }
    function percent(value) {
        return value === null || value === undefined || !Number.isFinite(Number(value)) ? "—" : Number(value).toFixed(1) + "%";
    }
    function diskRate(row) {
        if (row.diskReadRate === null || row.diskReadRate === undefined
            || row.diskWriteRate === null || row.diskWriteRate === undefined) return null;
        return row.diskReadRate + row.diskWriteRate;
    }
    function refreshRows() {
        if (!manager) return;
        const next = manager.rows;
        // Change role values instead of replacing the ListView model. Live
        // samples can reorder rows without throwing away the scroll position.
        for (let i = 0; i < next.length; ++i) {
            if (i < tableRows.count) tableRows.setProperty(i, "process", next[i]);
            else tableRows.append({process: next[i]});
        }
        if (tableRows.count > next.length) tableRows.remove(next.length, tableRows.count - next.length);
    }
    Component.onCompleted: refreshRows()
    ListModel { id: tableRows }
    function focusSearch() { search.forceActiveFocus(); search.selectAll(); }
    function focusProcesses() { keyboardTarget.forceActiveFocus(); }
    function selectRelative(step) {
        if (!manager.rows.length || manager.pendingEnd) return;
        const current = selectedIndex >= 0 ? selectedIndex : step > 0 ? -1 : manager.rows.length;
        const next = Math.max(0, Math.min(manager.rows.length - 1, current + step));
        manager.select(manager.rows[next].key);
        processes.positionViewAtIndex(next, ListView.Contain);
    }
    function handleEscape() {
        if (manager.pendingEnd) manager.cancelEnd();
        else if (search.text) { search.clear(); panel.focusProcesses(); }
        else closeRequested();
    }
    Keys.onPressed: event => {
        if (manager.pendingEnd) {
            if (event.key === Qt.Key_Escape) { manager.cancelEnd(); event.accepted = true; }
            return;
        }
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            selectRelative(event.key === Qt.Key_Down ? 1 : -1); event.accepted = true;
        } else if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
            const next = event.key === Qt.Key_Home ? 0 : manager.rows.length - 1;
            if (next >= 0 && manager.rows.length) { manager.select(manager.rows[next].key); processes.positionViewAtIndex(next, ListView.Contain); }
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) { handleEscape(); event.accepted = true; }
        else if (event.key === Qt.Key_F && event.modifiers & Qt.ControlModifier) { focusSearch(); event.accepted = true; }
    }
    Connections {
        target: panel.manager
        function onRowsChanged() { panel.refreshRows(); }
        function onPendingEndChanged() {
            if (panel.manager.pendingEnd) Qt.callLater(function() { if (panel.manager.pendingEnd) cancelButton.forceActiveFocus(); });
            else panel.focusProcesses();
        }
    }

    component Label: Text {
        color: ThemeApi.Theme.text
        font.family: "Inter"
        font.pixelSize: 12
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }
    component ActionButton: Button {
        id: action
        property string glyph: ""
        property bool prominent: false
        property bool destructive: false
        implicitHeight: 36
        implicitWidth: contentItem.implicitWidth + 26
        focusPolicy: Qt.TabFocus
        opacity: enabled ? 1 : 0.38
        padding: 11
        background: Rectangle {
            radius: 11
            color: action.prominent ? (action.destructive ? ThemeApi.Theme.red : ThemeApi.Theme.accent)
                : action.down ? ThemeApi.Theme.surfaceRaised : action.hovered ? ThemeApi.Theme.surfaceAlt : ThemeApi.Theme.surface
            border.width: action.activeFocus ? 2 : 0
            border.color: ThemeApi.Theme.accent
        }
        contentItem: Row {
            spacing: 7
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: action.glyph
                font.family: "Material Symbols Rounded"
                font.pixelSize: 17
                color: action.prominent ? (action.destructive ? ThemeApi.Theme.onError : ThemeApi.Theme.onAccent) : ThemeApi.Theme.muted
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: action.text
                font.pixelSize: 11
                font.weight: Font.Medium
                color: action.prominent ? (action.destructive ? ThemeApi.Theme.onError : ThemeApi.Theme.onAccent) : ThemeApi.Theme.text
            }
        }
    }
    component Graph: Canvas {
        id: graph
        property var samples: []
        property color ink: ThemeApi.Theme.accent
        onSamplesChanged: requestPaint()
        onInkChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (samples.length < 2 || width <= 0 || height <= 0) return;
            const start = Math.max(0, samples.length - 60);
            const dx = width / 59;
            const x0 = width - (samples.length - start - 1) * dx;
            ctx.beginPath();
            for (let i = start; i < samples.length; ++i) {
                const x = x0 + (i - start) * dx;
                const y = height - 2 - Math.max(0, Math.min(100, Number(samples[i]))) / 100 * (height - 4);
                if (i === start) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            ctx.lineWidth = 1.5; ctx.strokeStyle = ink; ctx.stroke();
            ctx.lineTo(width, height); ctx.lineTo(x0, height); ctx.closePath();
            ctx.fillStyle = Qt.alpha(ink, 0.08); ctx.fill();
        }
    }
    component Stat: Rectangle {
        id: stat
        property string label: ""
        property string value: ""
        property string detail: ""
        property string glyph: ""
        property color ink: ThemeApi.Theme.accent
        property var samples: []
        radius: 15
        color: ThemeApi.Theme.surface
        implicitHeight: 104
        Column {
            anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 15
            spacing: 7
            Row {
                spacing: 6
                Text { text: stat.glyph; font.family: "Material Symbols Rounded"; font.pixelSize: 15; color: stat.ink }
                Label { text: stat.label; color: ThemeApi.Theme.muted; font.pixelSize: 11 }
            }
            Label { text: stat.value; color: ThemeApi.Theme.textBright; font.pixelSize: 23; font.weight: Font.DemiBold }
            Label { text: stat.detail; color: ThemeApi.Theme.muted; font.pixelSize: 10 }
        }
        Graph {
            anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.rightMargin: 12; anchors.bottomMargin: 31
            width: Math.min(105, parent.width * 0.43); height: 30
            samples: stat.samples; ink: stat.ink
            opacity: 0.72
        }
    }

    Item { id: keyboardTarget; focus: true }
    Rectangle { anchors.fill: parent; color: ThemeApi.Theme.bg0 }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 16
        enabled: !panel.manager.pendingEnd
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 43
            MouseArea { anchors.fill: parent; onPressed: panel.moveRequested() }
            RowLayout {
                anchors.fill: parent
                spacing: 11
            Rectangle {
                width: 38; height: 38; radius: 12; color: ThemeApi.Theme.accentSoft
                Text { anchors.centerIn: parent; text: "monitoring"; color: ThemeApi.Theme.accent; font.family: "Material Symbols Rounded"; font.pixelSize: 23 }
            }
            ColumnLayout {
                spacing: 3
                Label { text: "Task Manager"; font.pixelSize: 21; font.weight: Font.DemiBold; color: ThemeApi.Theme.textBright }
                Label { text: "A clear view of what your computer is doing"; color: ThemeApi.Theme.muted; font.pixelSize: 11 }
            }
            Item { Layout.fillWidth: true }
            Label { text: panel.manager.paused ? "Updates paused" : "Live · 1.5 s"; color: ThemeApi.Theme.muted; font.pixelSize: 10 }
            ToolButton {
                id: closeButton
                objectName: "taskManagerClose"
                width: 32; height: 32
                Accessible.name: "Close Task Manager"
                contentItem: Text { text: "close"; font.family: "Material Symbols Rounded"; font.pixelSize: 20; color: ThemeApi.Theme.muted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 10; color: closeButton.hovered ? ThemeApi.Theme.surfaceRaised : "transparent" }
                onClicked: panel.closeRequested()
            }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Stat {
                Layout.fillWidth: true; Layout.preferredWidth: 1
                label: "CPU"; glyph: "memory"; value: panel.percent(panel.manager.summary.cpuPercent)
                detail: (panel.manager.summary.cpuCount || 0) + " logical processors"
                samples: panel.manager.cpuHistory
            }
            Stat {
                Layout.fillWidth: true; Layout.preferredWidth: 1
                label: "Memory"; glyph: "memory_alt"; value: panel.manager.summary.memoryTotal > 0 ? (panel.memoryFraction * 100).toFixed(0) + "%" : "—"
                detail: panel.bytes(panel.manager.summary.memoryUsed) + " / " + panel.bytes(panel.manager.summary.memoryTotal)
                ink: ThemeApi.Theme.purple; samples: panel.manager.memoryHistory
            }
            Stat {
                Layout.fillWidth: true; Layout.preferredWidth: 1
                label: "Disk"; glyph: "storage"
                value: panel.bytes(panel.manager.summary.diskReadRate === null || panel.manager.summary.diskWriteRate === null ? null
                    : panel.manager.summary.diskReadRate + panel.manager.summary.diskWriteRate, true)
                detail: "Read + write"; ink: ThemeApi.Theme.orange
            }
            Stat {
                Layout.fillWidth: true; Layout.preferredWidth: 1
                label: "Network"; glyph: "swap_vert"
                value: panel.bytes(panel.manager.summary.netRxRate === null || panel.manager.summary.netTxRate === null ? null
                    : panel.manager.summary.netRxRate + panel.manager.summary.netTxRate, true)
                detail: "Download + upload"; ink: ThemeApi.Theme.green
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 9
            TextField {
                id: search
                objectName: "taskManagerSearch"
                Layout.fillWidth: true
                Layout.maximumWidth: 460
                implicitHeight: 38
                leftPadding: 36; rightPadding: 12
                placeholderText: "Search processes or PID"
                placeholderTextColor: ThemeApi.Theme.muted
                color: ThemeApi.Theme.textBright
                font.family: "Inter"; font.pixelSize: 12
                selectByMouse: true
                text: panel.manager.search
                onTextEdited: panel.manager.search = text
                onTextChanged: if (text !== panel.manager.search) panel.manager.search = text
                background: Rectangle { radius: 11; color: ThemeApi.Theme.surface; border.width: search.activeFocus ? 1 : 0; border.color: ThemeApi.Theme.accent }
                Text { x: 11; anchors.verticalCenter: parent.verticalCenter; text: "search"; color: ThemeApi.Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 19 }
                Keys.onEscapePressed: panel.handleEscape()
                Keys.onDownPressed: { panel.selectRelative(1); panel.focusProcesses(); }
                Keys.onUpPressed: { panel.selectRelative(-1); panel.focusProcesses(); }
            }
            Item { Layout.fillWidth: true }
            ActionButton {
                objectName: "taskManagerPause"
                text: panel.manager.paused ? "Resume" : "Pause"
                glyph: panel.manager.paused ? "play_arrow" : "pause"
                onClicked: panel.manager.paused = !panel.manager.paused
            }
            ActionButton {
                objectName: "taskManagerEnd"
                text: "End task"; glyph: "stop_circle"
                enabled: !!panel.manager.selectedProcess && panel.manager.selectedProcess.canEnd && !panel.manager.actionBusy
                onClicked: panel.manager.requestEnd()
                ToolTip.visible: hovered && !!panel.manager.selectedProcess && !panel.manager.selectedProcess.canEnd
                ToolTip.text: panel.manager.selectedProcess ? panel.manager.selectedProcess.protectedReason || "This process cannot be ended here." : ""
            }
        }
        Rectangle {
            visible: panel.manager.errorText !== ""
            Layout.fillWidth: true
            implicitHeight: errorLabel.implicitHeight + 20
            radius: 10; color: Qt.alpha(ThemeApi.Theme.red, 0.10)
            Label { id: errorLabel; anchors.fill: parent; anchors.margins: 10; text: panel.manager.errorText; color: ThemeApi.Theme.red; wrapMode: Text.Wrap; elide: Text.ElideNone }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: 0
            Row {
                id: headings
                objectName: "taskManagerHeadings"
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                leftPadding: 12
                readonly property real pidWidth: 64
                readonly property real cpuWidth: 90
                readonly property real memoryWidth: 114
                readonly property real diskWidth: 120
                readonly property real nameWidth: Math.max(120, width - pidWidth - cpuWidth - memoryWidth - diskWidth - 24)
                Repeater {
                    model: [
                        {key:"name", label:"Name", size:headings.nameWidth, align:Text.AlignLeft},
                        {key:"pid", label:"PID", size:headings.pidWidth, align:Text.AlignRight},
                        {key:"cpu", label:"CPU", size:headings.cpuWidth, align:Text.AlignRight},
                        {key:"memory", label:"Memory", size:headings.memoryWidth, align:Text.AlignRight},
                        {key:"disk", label:"Disk", size:headings.diskWidth, align:Text.AlignRight}
                    ]
                    delegate: Item {
                        id: heading
                        required property var modelData
                        objectName: "taskManagerHeading-" + modelData.key
                        width: modelData.size; height: 34
                        Label {
                            anchors.fill: parent; anchors.rightMargin: 10
                            verticalAlignment: Text.AlignVCenter; horizontalAlignment: heading.modelData.align
                            text: heading.modelData.label + (panel.manager.sortKey === heading.modelData.key ? panel.manager.sortDescending ? "  ↓" : "  ↑" : "")
                            color: panel.manager.sortKey === heading.modelData.key ? ThemeApi.Theme.accent : ThemeApi.Theme.muted
                            font.pixelSize: 11; font.weight: Font.Medium
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: panel.manager.sortBy(heading.modelData.key) }
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(ThemeApi.Theme.border, 0.5) }
            ListView {
                id: processes
                objectName: "taskManagerProcesses"
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true; reuseItems: true
                model: tableRows
                spacing: 3
                topMargin: 5; bottomMargin: 5
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 5 }
                delegate: Rectangle {
                    id: processRow
                    required property var process
                    readonly property var modelData: process
                    required property int index
                    width: processes.width; height: 43; radius: 10
                    color: panel.manager.selectedKey === modelData.key ? ThemeApi.Theme.accentSoft
                        : processHover.containsMouse ? ThemeApi.Theme.surface : "transparent"
                    MouseArea {
                        id: processHover
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: { panel.manager.select(processRow.modelData.key); panel.focusProcesses(); }
                    }
                    Row {
                        x: 12
                        height: parent.height
                        Item {
                            width: headings.nameWidth; height: parent.height
                            Rectangle {
                                x: 0; anchors.verticalCenter: parent.verticalCenter
                                width: 27; height: 27; radius: 8
                                color: panel.manager.selectedKey === processRow.modelData.key ? Qt.alpha(ThemeApi.Theme.accent, 0.12) : ThemeApi.Theme.surface
                                Text { anchors.centerIn: parent; text: processRow.modelData.canEnd ? "deployed_code" : "settings"; color: processRow.modelData.canEnd ? ThemeApi.Theme.accent : ThemeApi.Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 17 }
                            }
                            Label { x: 38; width: parent.width - 46; anchors.verticalCenter: parent.verticalCenter; text: processRow.modelData.name; color: ThemeApi.Theme.textBright; font.pixelSize: 12; font.weight: panel.manager.selectedKey === processRow.modelData.key ? Font.Medium : Font.Normal }
                        }
                        Label { width: headings.pidWidth; height: parent.height; rightPadding: 10; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: processRow.modelData.pid; color: ThemeApi.Theme.muted; font.pixelSize: 11 }
                        Rectangle {
                            width: headings.cpuWidth; height: parent.height - 6; y: 3; radius: 6
                            color: Qt.alpha(ThemeApi.Theme.accent, Math.min(0.22, Math.max(0, Number(processRow.modelData.cpuPercent) || 0) / 100 * 0.5))
                            Label { anchors.fill: parent; rightPadding: 10; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: panel.percent(processRow.modelData.cpuPercent); font.pixelSize: 11 }
                        }
                        Rectangle {
                            width: headings.memoryWidth; height: parent.height - 6; y: 3; radius: 6
                            color: Qt.alpha(ThemeApi.Theme.purple, Math.min(0.22, panel.manager.summary.memoryTotal > 0 ? processRow.modelData.memoryBytes / panel.manager.summary.memoryTotal * 1.2 : 0))
                            Label { anchors.fill: parent; rightPadding: 10; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: panel.bytes(processRow.modelData.memoryBytes); font.pixelSize: 11 }
                        }
                        Label { width: headings.diskWidth; height: parent.height; rightPadding: 10; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; text: panel.bytes(panel.diskRate(processRow.modelData), true); color: ThemeApi.Theme.muted; font.pixelSize: 11 }
                    }
                }
                Label {
                    anchors.centerIn: parent
                    text: panel.manager.loading ? "Reading processes…" : "No matching processes"
                    color: ThemeApi.Theme.muted
                    visible: processes.count === 0
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(ThemeApi.Theme.border, 0.5) }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Label { text: panel.manager.rows.length + (panel.manager.rows.length === 1 ? " process" : " processes"); color: ThemeApi.Theme.muted; font.pixelSize: 10 }
            Label {
                Layout.fillWidth: true
                text: panel.manager.selectedProcess ? panel.manager.selectedProcess.user + "  ·  " + panel.manager.selectedProcess.state + "  ·  " + panel.manager.selectedProcess.threads + " threads" : "Select a process to inspect it"
                color: ThemeApi.Theme.muted; font.pixelSize: 10
            }
            Label {
                text: "Resident memory ⓘ"; color: ThemeApi.Theme.muted; font.pixelSize: 10
                ToolTip.visible: memoryHelp.containsMouse
                ToolTip.text: "Memory is resident RAM (RSS). Shared pages can appear in several processes.\nCPU is a share of the whole machine. — means a reading is not available."
                MouseArea { id: memoryHelp; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: !!panel.manager.pendingEnd
        color: Qt.alpha(ThemeApi.Theme.bgDim, 0.82)
        MouseArea { anchors.fill: parent; onClicked: panel.manager.cancelEnd() }
        Rectangle {
            width: Math.min(420, parent.width - 60)
            height: confirmationLayout.implicitHeight + 40
            anchors.centerIn: parent
            radius: 20; color: ThemeApi.Theme.surface
            border.width: 1; border.color: ThemeApi.Theme.border
            MouseArea { anchors.fill: parent }
            ColumnLayout {
                id: confirmationLayout
                anchors.fill: parent; anchors.margins: 20
                spacing: 15
                Label { text: "End this task?"; font.pixelSize: 20; font.weight: Font.DemiBold; color: ThemeApi.Theme.textBright }
                Label {
                    Layout.fillWidth: true
                    text: panel.manager.pendingEnd ? panel.manager.pendingEnd.name + " · PID " + panel.manager.pendingEnd.pid : ""
                    font.weight: Font.Medium
                }
                Label { Layout.fillWidth: true; text: "The process will be asked to quit. Unsaved changes may be lost."; wrapMode: Text.Wrap; elide: Text.ElideNone; color: ThemeApi.Theme.muted; font.pixelSize: 11 }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    ActionButton { id: cancelButton; objectName: "taskManagerCancelEnd"; text: "Cancel"; onClicked: panel.manager.cancelEnd(); Keys.onReturnPressed: panel.manager.cancelEnd(); Keys.onEnterPressed: panel.manager.cancelEnd(); Keys.onEscapePressed: panel.manager.cancelEnd() }
                    ActionButton { objectName: "taskManagerConfirmEnd"; text: panel.manager.actionBusy ? "Ending…" : "End task"; glyph: "stop_circle"; prominent: true; destructive: true; enabled: !panel.manager.actionBusy; onClicked: panel.manager.confirmEnd(); Keys.onEscapePressed: panel.manager.cancelEnd() }
                }
            }
        }
    }
}
