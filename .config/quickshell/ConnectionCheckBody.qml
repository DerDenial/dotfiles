pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "Theme" as ThemePalette

Item {
    id: view
    objectName: "connectionCheckBody"
    property var controller: null
    readonly property var snapshot: controller ? controller.snapshot : ({ phase: "idle", steps: [], summary: {} })
    readonly property var summary: snapshot.summary || ({})
    readonly property bool running: !!controller && controller.running
    readonly property bool cancelling: !!controller && controller.cancelling
    implicitHeight: content.implicitHeight
    signal backRequested()
    signal closeRequested()
    function step(id) {
        const values = snapshot.steps || [];
        return values.find(item => item.id === id) || ({ id: id, status: "pending", title: "", detail: "Not checked yet", durationMs: null });
    }
    function statusColor(status) {
        return status === "ok" ? ThemePalette.Theme.green
            : status === "warning" ? ThemePalette.Theme.yellow
            : status === "failed" || status === "error" ? ThemePalette.Theme.red
            : status === "running" ? ThemePalette.Theme.accent : ThemePalette.Theme.mutedStrong;
    }
    function statusLabel(status) {
        return status === "ok" ? "Passed" : status === "warning" ? "Inconclusive"
            : status === "failed" ? "Failed" : status === "running" ? "Checking…"
            : status === "skipped" ? "Skipped" : "Waiting";
    }
    function symbol(status, fallback) {
        return status === "ok" ? "check" : status === "warning" ? "help_outline"
            : status === "failed" || status === "error" ? "close"
            : status === "skipped" ? "remove" : fallback;
    }
    component StepRow: Item {
        id: row
        required property string stepId
        required property string label
        required property string iconName
        readonly property var result: view.step(stepId)
        readonly property string stateName: result.status || "pending"
        objectName: stepId + "CheckRow"
        width: parent.width
        height: 64
        Rectangle {
            x: 12; anchors.verticalCenter: parent.verticalCenter
            width: 31; height: 31; radius: 10
            color: Qt.alpha(view.statusColor(row.stateName), 0.12)
            Text {
                anchors.centerIn: parent
                text: view.symbol(row.stateName, row.iconName)
                font.family: "Material Symbols Rounded"; font.pixelSize: 19
                color: view.statusColor(row.stateName)
            }
        }
        Text {
            x: 54; y: 12; width: Math.max(0, parent.width - 163)
            text: row.result.title || row.label; textFormat: Text.PlainText
            color: ThemePalette.Theme.textBright
            font.family: "Inter"; font.pixelSize: 11; font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            id: detailLabel
            objectName: row.stepId + "CheckDetail"
            x: 54; y: 29; width: Math.max(0, parent.width - 151)
            text: row.result.detail || (row.stateName === "running" ? "Checking this part of your connection…" : "Not checked yet")
            textFormat: Text.PlainText
            color: ThemePalette.Theme.muted
            font.family: "Inter"; font.pixelSize: 9
            wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
            ToolTip {
                visible: detailHover.hovered && detailLabel.truncated
                delay: 400
                width: Math.min(420, view.width)
                contentItem: Text {
                    text: detailLabel.text
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: ThemePalette.Theme.text
                    font.family: "Inter"; font.pixelSize: 10
                }
                background: Rectangle { radius: 10; color: ThemePalette.Theme.surfaceRaised; border.width: 1; border.color: ThemePalette.Theme.border }
            }
            HoverHandler { id: detailHover }
        }
        Column {
            anchors.right: parent.right; anchors.rightMargin: 13
            y: 14; width: 86; spacing: 5
            Text {
                objectName: row.stepId + "CheckStatus"
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: view.statusLabel(row.stateName)
                color: view.statusColor(row.stateName)
                font.family: "Inter"; font.pixelSize: 9; font.weight: Font.Medium
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: typeof row.result.durationMs === "number" && Number.isFinite(row.result.durationMs) ? Math.round(row.result.durationMs) + " ms" : ""
                color: ThemePalette.Theme.mutedStrong
                font.family: "Inter"; font.pixelSize: 8
            }
        }
        Rectangle {
            x: 54; y: parent.height - 1
            width: parent.width - 68; height: 1
            visible: row.stepId !== "internet"
            color: Qt.alpha(ThemePalette.Theme.border, 0.3)
        }
    }
    Column {
        id: content
        width: parent.width
        spacing: 12
        Item {
            width: parent.width; height: 44
            ToolButton {
                id: backButton
                objectName: "connectionCheckBack"
                x: 0; y: 2; width: 34; height: 34
                Accessible.name: "Back to live traffic"
                contentItem: Text { text: "arrow_back"; font.family: "Material Symbols Rounded"; font.pixelSize: 20; color: ThemePalette.Theme.muted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 12; color: backButton.hovered ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface }
                onClicked: view.backRequested()
                ToolTip.visible: hovered
                ToolTip.text: "Live traffic"
            }
            Text { x: 47; text: "NETWORK"; color: ThemePalette.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
            Text { x: 47; y: 15; width: parent.width - 91; text: "Connection check"; color: ThemePalette.Theme.textBright; font.family: "Inter"; font.pixelSize: 20; font.weight: Font.DemiBold; elide: Text.ElideRight }
            ToolButton {
                id: closeButton
                objectName: "closeConnectionCheck"
                anchors.right: parent.right; y: 2; width: 34; height: 34
                Accessible.name: "Close connection check"
                contentItem: Text { text: "close"; font.family: "Material Symbols Rounded"; font.pixelSize: 20; color: ThemePalette.Theme.muted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 12; color: closeButton.hovered ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface }
                onClicked: view.closeRequested()
            }
        }
        Rectangle {
            width: parent.width; height: 76; radius: 17
            color: view.summary.status === "failed" || view.summary.status === "error" ? ThemePalette.Theme.redDark : ThemePalette.Theme.accentSoft
            border.width: 1; border.color: Qt.alpha(view.statusColor(view.summary.status), 0.2)
            Text {
                x: 14; y: 16; width: 28
                text: view.running ? "network_check" : view.summary.status === "ok" ? "check_circle" : view.summary.status === "warning" ? "help_outline" : view.summary.status === "failed" || view.summary.status === "error" ? "error_outline" : view.summary.status === "cancelled" ? "pause_circle" : "network_check"
                color: view.summary.status === "failed" || view.summary.status === "error" ? ThemePalette.Theme.onErrorContainer : ThemePalette.Theme.accent
                font.family: "Material Symbols Rounded"; font.pixelSize: 24
            }
            Text {
                objectName: "connectionCheckSummaryTitle"
                x: 53; y: 13; width: parent.width - 67
                text: view.summary.title || (view.running ? "Checking your connection…" : "Find where the connection stops")
                textFormat: Text.PlainText
                color: ThemePalette.Theme.textBright
                font.family: "Inter"; font.pixelSize: 12; font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                objectName: "connectionCheckSummaryDetail"
                x: 53; y: 34; width: parent.width - 67
                text: view.summary.detail || "Check your network link, router, DNS and internet access."
                textFormat: Text.PlainText
                color: ThemePalette.Theme.muted
                font.family: "Inter"; font.pixelSize: 10
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
            }
        }
        Rectangle {
            width: parent.width; height: rows.implicitHeight; radius: 17
            color: ThemePalette.Theme.surface
            border.width: 1; border.color: Qt.alpha(ThemePalette.Theme.border, 0.35)
            Column {
                id: rows
                width: parent.width
                StepRow { stepId: "link"; label: "Wi-Fi / Ethernet"; iconName: "wifi" }
                StepRow { stepId: "router"; label: "Router"; iconName: "router" }
                StepRow { stepId: "dns"; label: "DNS"; iconName: "dns" }
                StepRow { stepId: "internet"; label: "Internet"; iconName: "public" }
            }
        }
        Button {
            id: action
            objectName: "connectionCheckAction"
            anchors.horizontalCenter: parent.horizontalCenter
            width: 158; height: 36
            enabled: !!view.controller && !view.cancelling
            Accessible.name: view.cancelling ? "Stopping connection check" : view.running ? "Cancel connection check" : "Check connection"
            contentItem: Text {
                text: view.cancelling ? "Stopping…" : view.running ? "Cancel check" : view.snapshot.phase === "idle" ? "Check connection" : "Check again"
                color: view.running ? ThemePalette.Theme.text : ThemePalette.Theme.onAccent
                font.family: "Inter"; font.pixelSize: 11; font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle { radius: 12; color: view.running ? action.hovered ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface : ThemePalette.Theme.accent; border.width: view.running ? 1 : 0; border.color: ThemePalette.Theme.border }
            onClicked: { if (view.running) view.controller.cancel(); else view.controller.start(); }
        }
        Text {
            width: parent.width; height: 24
            text: view.snapshot.checkedAt ? "Last checked " + Qt.formatTime(new Date(view.snapshot.checkedAt), "HH:mm") + " · Only runs when requested" : "Small connection probes · Only runs when requested"
            color: ThemePalette.Theme.mutedStrong
            font.family: "Inter"; font.pixelSize: 9
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }
}
