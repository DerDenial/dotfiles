pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Theme" as ThemePalette

Flickable {
    id: body
    objectName: "networkPanelBody"
    property var telemetry: null
    property var diagnostics: null
    property bool checkMode: false
    property string hotkeyText: "Super + Shift + N"
    property string connectionName: ""
    property real signalPercent: -1
    readonly property var sample: telemetry ? telemetry.snapshot : ({ interface: { connected: false }, warnings: [] })
    readonly property var connection: sample.interface || ({ connected: false })
    readonly property bool connected: connection.connected === true
    readonly property var history: telemetry ? telemetry.history : []
    readonly property string error: telemetry ? telemetry.error : ""
    signal closeRequested()
    signal checkRequested()
    signal trafficRequested()
    contentWidth: width
    contentHeight: checkMode ? checkView.implicitHeight : stack.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    flickableDirection: Flickable.VerticalFlick
    clip: true
    function resetScroll() { contentY = 0; }
    onCheckModeChanged: resetScroll()
    function isValue(value) { return typeof value === "number" && Number.isFinite(value) && value >= 0; }
    function amount(value, rate) {
        if (!isValue(value)) return { number: "—", unit: "" }
        const suffix = rate ? "/s" : "";
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        let index = 0;
        while (value >= 1024 && index < units.length - 1) { value /= 1024; index++; }
        return { number: value.toFixed(index === 0 ? 0 : value >= 100 ? 0 : 1), unit: units[index] + suffix }
    }
    function compact(value, rate) { const metric = amount(value, rate); return metric.unit ? metric.number + " " + metric.unit : metric.number; }
    function connectionDetails() {
        const lines = [connectionName || (connection.kind === "wifi" ? "Wi-Fi" : "Ethernet")];
        if (connection.name) lines.push("Interface: " + connection.name);
        if (Array.isArray(connection.ipv4) && connection.ipv4.length) lines.push("IPv4: " + connection.ipv4.join(", "));
        if (Array.isArray(connection.ipv6) && connection.ipv6.length) lines.push("IPv6: " + connection.ipv6.join(", "));
        return lines.join("\n");
    }
    function axisLimit(value) {
        if (!isValue(value) || value < 1024) return 1024;
        const scale = Math.pow(1024, Math.floor(Math.log(value) / Math.log(1024)));
        const factors = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1024];
        for (const factor of factors) if (factor * scale >= value) return factor * scale;
        return value;
    }
    ScrollBar.vertical: ScrollBar { policy: body.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff; width: 3 }

    component Card: Rectangle {
        radius: 18
        color: ThemePalette.Theme.surface
        border.width: 1
        border.color: Qt.rgba(ThemePalette.Theme.border.r, ThemePalette.Theme.border.g, ThemePalette.Theme.border.b, 0.42)
    }
    component SpeedCard: Card {
        id: speed
        property string label: ""
        property string iconName: ""
        property var metricValue: null
        property color flowColor: ThemePalette.Theme.accent
        readonly property var metric: body.amount(body.connected ? metricValue : null, true)
        height: 100
        Row {
            x: 14; y: 13; spacing: 7
            Text { text: speed.iconName; color: speed.flowColor; font.family: "Material Symbols Rounded"; font.pixelSize: 17 }
            Text { text: speed.label; color: ThemePalette.Theme.muted; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 0.8; anchors.verticalCenter: parent.verticalCenter }
        }
        Text {
            objectName: speed.objectName + "Value"
            x: 14; y: 37; width: parent.width - 28
            text: speed.metric.number
            font.family: "Inter"; font.pixelSize: speed.width < 210 ? 25 : 30; font.weight: Font.DemiBold
            color: ThemePalette.Theme.textBright
        }
        Text {
            objectName: speed.objectName + "Unit"
            x: 14; y: 76; width: parent.width - 28
            text: speed.metric.unit || (!body.connected ? "No connection" : "Measuring…")
            font.family: "Inter"; font.pixelSize: 10; color: speed.flowColor
        }
    }

    ConnectionCheckBody {
        id: checkView
        width: body.width
        height: implicitHeight
        visible: body.checkMode
        controller: body.diagnostics
        onBackRequested: body.trafficRequested()
        onCloseRequested: body.closeRequested()
    }
    Column {
        id: stack
        visible: !body.checkMode
        width: body.width
        spacing: 10
        Item {
            width: parent.width; height: 44
            Text { text: "NETWORK"; color: ThemePalette.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
            Text { y: 15; text: "Live traffic"; color: ThemePalette.Theme.textBright; font.family: "Inter"; font.pixelSize: 21; font.weight: Font.DemiBold }
            Button {
                id: checkButton
                objectName: "openConnectionCheck"
                anchors.right: statusRow.left; anchors.rightMargin: 10
                y: 3; width: 72; height: 32
                Accessible.name: "Check connection"
                contentItem: Row {
                    spacing: 5
                    Text { text: "network_check"; color: ThemePalette.Theme.accent; font.family: "Material Symbols Rounded"; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Check"; color: ThemePalette.Theme.text; font.family: "Inter"; font.pixelSize: 10; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                }
                leftPadding: 9; rightPadding: 6
                background: Rectangle { radius: 11; color: checkButton.hovered ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface }
                onClicked: body.checkRequested()
            }
            Row {
                id: statusRow
                anchors.right: closeButton.left; anchors.rightMargin: 13
                anchors.verticalCenter: closeButton.verticalCenter; spacing: 6
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 5; height: 5; radius: 3; color: body.telemetry && body.telemetry.ready && !body.error ? ThemePalette.Theme.accent : ThemePalette.Theme.mutedStrong }
                Text { text: body.error ? "UNAVAILABLE" : body.telemetry && body.telemetry.ready ? "LIVE · 1 s" : "READING…"; color: ThemePalette.Theme.muted; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.Medium }
            }
            ToolButton {
                id: closeButton
                objectName: "closeNetworkPanel"
                anchors.right: parent.right; y: 2; width: 34; height: 34
                Accessible.name: "Close network panel"
                contentItem: Text { text: "close"; font.family: "Material Symbols Rounded"; font.pixelSize: 20; color: ThemePalette.Theme.muted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 12; color: closeButton.hovered ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface }
                ToolTip.visible: hovered
                ToolTip.text: body.hotkeyText + " · Esc to close"
                onClicked: body.closeRequested()
            }
        }
        Card {
            objectName: "networkError"
            visible: body.error.length > 0
            width: parent.width; height: errorLabel.implicitHeight + 22
            color: ThemePalette.Theme.redDark
            Text { id: errorLabel; x: 12; y: 11; width: parent.width - 24; text: body.error; font.family: "Inter"; font.pixelSize: 11; color: ThemePalette.Theme.onErrorContainer; wrapMode: Text.WordWrap }
        }
        Card {
            objectName: "networkConnection"
            width: parent.width; height: 58
            Rectangle {
                x: 13; y: 12; width: 34; height: 34; radius: 11
                color: ThemePalette.Theme.accentSoft
                Text { anchors.centerIn: parent; text: !body.connected ? "wifi_off" : body.connection.kind === "wifi" ? "wifi" : "lan"; font.family: "Material Symbols Rounded"; font.pixelSize: 21; color: ThemePalette.Theme.accent }
            }
            Text {
                id: connectionLabel
                objectName: "networkConnectionName"
                x: 59; y: 12; width: parent.width - 130
                text: body.connected ? body.connectionName || (body.connection.kind === "wifi" ? "Wi-Fi" : "Ethernet") : "No active connection"
                textFormat: Text.PlainText
                font.family: "Inter"; font.pixelSize: 12; font.weight: Font.Medium; color: ThemePalette.Theme.textBright
                elide: Text.ElideRight
                ToolTip.visible: labelHover.hovered
                ToolTip.text: body.connectionDetails()
                HoverHandler { id: labelHover }
            }
            Text {
                objectName: "networkInterface"
                x: 59; y: 32; width: parent.width - 75
                text: body.connected ? body.connection.name + (body.connection.kind === "wifi" && body.signalPercent >= 0 ? " · " + body.signalPercent + "% signal" : "") : "Connect through Wi-Fi or Ethernet to see live traffic."
                textFormat: Text.PlainText
                font.family: "Inter"; font.pixelSize: 10; color: ThemePalette.Theme.muted; elide: Text.ElideRight
            }
            Text { anchors.right: parent.right; anchors.rightMargin: 14; y: 14; text: body.connected ? "Link up" : "Offline"; color: ThemePalette.Theme.muted; font.family: "Inter"; font.pixelSize: 9 }
        }
        Row {
            objectName: "networkRates"
            width: parent.width; height: 100; spacing: 10
            SpeedCard { objectName: "downloadRate"; width: (parent.width - 10) / 2; label: "DOWNLOAD"; iconName: "south_west"; metricValue: body.sample.rxBytesPerSecond; flowColor: ThemePalette.Theme.accent }
            SpeedCard { objectName: "uploadRate"; width: (parent.width - 10) / 2; label: "UPLOAD"; iconName: "north_east"; metricValue: body.sample.txBytesPerSecond; flowColor: ThemePalette.Theme.green }
        }
        Card {
            id: graphCard
            objectName: "networkGraphCard"
            width: parent.width; height: 174
            Text { x: 14; y: 13; text: "TRANSFER RATE"; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 0.9; color: ThemePalette.Theme.muted }
            Text { anchors.right: parent.right; anchors.rightMargin: 14; y: 13; text: body.history.length > 1 ? "last " + Math.min(120, Math.round(body.history[body.history.length - 1].t - body.history[0].t)) + " s" : "since opened"; font.family: "Inter"; font.pixelSize: 9; color: ThemePalette.Theme.mutedStrong }
            Item {
                id: graph
                objectName: "networkTrafficGraph"
                x: 14; y: 35; width: parent.width - 28; height: 104
                readonly property real ceiling: body.axisLimit(Math.max.apply(null, body.history.map(point => Math.max(body.isValue(point.rx) ? point.rx : 0, body.isValue(point.tx) ? point.tx : 0)).concat([0])))
                Canvas {
                    id: chart
                    anchors.fill: parent; anchors.rightMargin: 62
                    renderStrategy: Canvas.Immediate
                    onPaint: {
                        const ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                        const top = 4; const bottom = height - 4;
                        ctx.lineWidth = 1;
                        ctx.strokeStyle = Qt.rgba(ThemePalette.Theme.border.r, ThemePalette.Theme.border.g, ThemePalette.Theme.border.b, 0.3);
                        for (let i = 0; i < 3; i++) { const y = top + (bottom - top) * i / 2; ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke(); }
                        const points = body.history;
                        if (!points.length) return;
                        const lastTime = points[points.length - 1].t;
                        const start = Math.max(points[0].t, lastTime - 120);
                        const span = Math.max(1, lastTime - start);
                        function segments(key) {
                            let result = [], line = [], previous = null;
                            for (const point of points) {
                                if (!body.isValue(point[key]) || previous && (point.t - previous.t > 3 || point.id !== previous.id)) { if (line.length) result.push(line); line = []; }
                                if (body.isValue(point[key])) line.push({x: Math.max(0, Math.min(width, (point.t - start) / span * width)), y: bottom - Math.max(0, Math.min(graph.ceiling, point[key])) / graph.ceiling * (bottom - top)});
                                previous = point;
                            }
                            if (line.length) result.push(line);
                            return result;
                        }
                        function draw(lines, color, dashed) {
                            for (const line of lines) {
                                if (!dashed && line.length > 1) {
                                    ctx.beginPath(); ctx.moveTo(line[0].x, bottom);
                                    for (const p of line) ctx.lineTo(p.x, p.y);
                                    ctx.lineTo(line[line.length - 1].x, bottom); ctx.closePath();
                                    const fill = ctx.createLinearGradient(0, top, 0, bottom);
                                    fill.addColorStop(0, Qt.rgba(color.r, color.g, color.b, 0.18)); fill.addColorStop(1, Qt.rgba(color.r, color.g, color.b, 0.01));
                                    ctx.fillStyle = fill; ctx.fill();
                                }
                                ctx.beginPath(); ctx.strokeStyle = color; ctx.lineWidth = 2; ctx.lineJoin = "round"; ctx.lineCap = "round";
                                if (!dashed) { ctx.moveTo(line[0].x, line[0].y); for (let i = 1; i < line.length; i++) ctx.lineTo(line[i].x, line[i].y); }
                                else {
                                    let phase = 0;
                                    for (let i = 1; i < line.length; i++) {
                                        const a = line[i - 1], b = line[i], dx = b.x - a.x, dy = b.y - a.y, length = Math.sqrt(dx * dx + dy * dy);
                                        let distance = 0;
                                        while (distance < length) {
                                            const on = phase < 5, step = Math.min(length - distance, (on ? 5 : 9) - phase);
                                            if (on) { ctx.moveTo(a.x + dx * distance / length, a.y + dy * distance / length); ctx.lineTo(a.x + dx * (distance + step) / length, a.y + dy * (distance + step) / length); }
                                            distance += step; phase = (phase + step) % 9;
                                        }
                                    }
                                }
                                ctx.stroke();
                                const last = line[line.length - 1];ctx.beginPath();ctx.arc(last.x,last.y,dashed?2:2.5,0,Math.PI*2);ctx.fillStyle=color;ctx.fill();
                            }
                        }
                        draw(segments("rx"), ThemePalette.Theme.accent, false);
                        draw(segments("tx"), ThemePalette.Theme.green, true);
                    }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    Connections { target: body; function onHistoryChanged() { chart.requestPaint(); } }
                    Connections { target: ThemePalette.Theme; function onAccentChanged() { chart.requestPaint(); } function onGreenChanged() { chart.requestPaint(); } function onBorderChanged() { chart.requestPaint(); } }
                }
                Text { anchors.right: parent.right; y: 0; text: body.compact(graph.ceiling, true); font.family: "Inter"; font.pixelSize: 8; color: ThemePalette.Theme.mutedStrong }
                Text { anchors.right: parent.right; anchors.bottom: parent.bottom; text: "0 B/s"; font.family: "Inter"; font.pixelSize: 8; color: ThemePalette.Theme.mutedStrong }
                Text { anchors.centerIn: chart; visible: !body.connected || body.history.filter(point => body.isValue(point.rx) || body.isValue(point.tx)).length === 0; text: !body.connected ? "Waiting for a connection…" : "Waiting for rate samples…"; font.family: "Inter"; font.pixelSize: 10; color: ThemePalette.Theme.muted }
            }
            Row {
                x: 14; y: 150; spacing: 17
                Row { spacing: 6; Rectangle { width: 19; height: 2; anchors.verticalCenter: parent.verticalCenter; radius: 1; color: ThemePalette.Theme.accent } Text { text: "Download"; font.family: "Inter"; font.pixelSize: 9; color: ThemePalette.Theme.muted } }
                Row { spacing: 6; Row { anchors.verticalCenter: parent.verticalCenter; spacing: 3; Repeater { model: 3; Rectangle { width: 4; height: 2; color: ThemePalette.Theme.green } } } Text { text: "Upload"; font.family: "Inter"; font.pixelSize: 9; color: ThemePalette.Theme.muted } }
            }
        }
        Card {
            objectName: "networkSession"
            width: parent.width; height: 64
            Row {
                x: 14; y: 12; width: parent.width - 28; spacing: 18
                Column { width: (parent.width - 18) / 2; spacing: 5; Text { width: parent.width; elide: Text.ElideRight; text: "Received · this connection"; font.family: "Inter"; font.pixelSize: 10; color: ThemePalette.Theme.muted } Text { objectName: "receivedSession"; text: body.compact(body.sample.receivedBytes, false); font.family: "Inter"; font.pixelSize: 17; font.weight: Font.DemiBold; color: ThemePalette.Theme.textBright } }
                Column { width: (parent.width - 18) / 2; spacing: 5; Text { width: parent.width; elide: Text.ElideRight; text: "Sent · this connection"; font.family: "Inter"; font.pixelSize: 10; color: ThemePalette.Theme.muted } Text { objectName: "sentSession"; text: body.compact(body.sample.sentBytes, false); font.family: "Inter"; font.pixelSize: 17; font.weight: Font.DemiBold; color: ThemePalette.Theme.textBright } }
            }
        }
        Text {
            width: parent.width; height: 24
            text: "Wi-Fi/Ethernet traffic, including local/VPN data · resets on opening."
            font.family: "Inter"; font.pixelSize: 10; color: ThemePalette.Theme.mutedStrong
            wrapMode: Text.WordWrap
        }
    }
}
