pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Theme" as ThemePalette

Flickable {
    id: body
    objectName: "hardwarePanelBody"
    property var telemetry: null
    property string hotkeyText: "Super + H"
    readonly property var sample: telemetry ? telemetry.snapshot : ({ cpu: {}, gpus: [], battery: { present: false }, warnings: [] })
    readonly property var battery: sample.battery || ({ present: false })
    readonly property var gpus: Array.isArray(sample.gpus) && sample.gpus.length ? sample.gpus : [{ name: "Graphics processor unavailable", usagePercent: null, temperatureC: null }]
    readonly property var history: telemetry ? telemetry.history : []
    readonly property string error: telemetry ? telemetry.error : ""
    signal closeRequested()
    contentWidth: width
    contentHeight: stack.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    flickableDirection: Flickable.VerticalFlick
    clip: true
    function resetScroll() { contentY = 0; }
    function isValue(value) { return typeof value === "number" && Number.isFinite(value); }
    function metric(value, suffix, precision, approximate) { return isValue(value) ? (approximate ? "≈ " : "") + value.toFixed(precision) + suffix : "Unavailable"; }
    function duration(seconds) {
        if (!isValue(seconds) || seconds <= 0) return "Unavailable";
        const minutes = Math.max(1, Math.round(seconds / 60));
        const hours = Math.floor(minutes / 60);
        return hours ? hours + "h " + (minutes % 60) + "m" : minutes + " min";
    }
    ScrollBar.vertical: ScrollBar { policy: body.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff; width: 3 }

    component Card: Rectangle {
        radius: 18
        color: ThemePalette.Theme.surface
        border.width: 1
        border.color: Qt.rgba(ThemePalette.Theme.border.r, ThemePalette.Theme.border.g, ThemePalette.Theme.border.b, 0.42)
    }
    component HardwareCard: Card {
        id: hardware
        property string title: "CPU"
        property string iconName: "memory"
        property var device: ({})
        implicitHeight: 98
        readonly property bool validUsage: body.isValue(device.usagePercent)
        Rectangle {
            x: 14; y: 14; width: 32; height: 32
            radius: 11
            color: ThemePalette.Theme.accentSoft
            Text { anchors.centerIn: parent; text: hardware.iconName; font.family: "Material Symbols Rounded"; font.pixelSize: 20; color: ThemePalette.Theme.accent }
        }
        Text {
            x: 57; y: 13
            text: hardware.title
            color: ThemePalette.Theme.mutedStrong
            font.family: "Inter"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1
        }
        Text {
            objectName: hardware.title.toLowerCase().replace(/\s+/g, "") + "Name"
            x: 57; y: 29
            width: Math.max(0, hardware.width - 151)
            text: hardware.device.name || "Reading processor…"
            color: ThemePalette.Theme.textBright
            font.family: "Inter"; font.pixelSize: 12; font.weight: Font.Medium
            elide: Text.ElideRight
            ToolTip.visible: modelHover.hovered
            ToolTip.text: text
            HoverHandler { id: modelHover }
        }
        Text {
            objectName: hardware.title.toLowerCase().replace(/\s+/g, "") + "Usage"
            anchors.right: parent.right; anchors.rightMargin: 14
            y: 10
            text: hardware.validUsage ? Math.round(hardware.device.usagePercent) + "%" : "—"
            color: ThemePalette.Theme.textBright
            font.family: "Inter"; font.pixelSize: 26; font.weight: Font.DemiBold
        }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 14
            y: 41
            text: hardware.validUsage ? "utilization" : body.telemetry && body.telemetry.ready ? "unavailable" : "sampling"
            color: ThemePalette.Theme.muted
            font.family: "Inter"; font.pixelSize: 9
        }
        Rectangle {
            x: 14; y: 72
            width: Math.max(0, parent.width - 116); height: 5
            radius: 3
            color: ThemePalette.Theme.surfaceRaised
            Rectangle {
                height: parent.height; radius: 3
                width: parent.width * (hardware.validUsage ? Math.max(0, Math.min(100, hardware.device.usagePercent)) / 100 : 0)
                color: ThemePalette.Theme.accent
                Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 14
            y: 64; spacing: 4
            Text { text: "device_thermostat"; font.family: "Material Symbols Rounded"; font.pixelSize: 18; color: ThemePalette.Theme.muted }
            Text {
                objectName: hardware.title.toLowerCase().replace(/\s+/g, "") + "Temperature"
                text: body.isValue(hardware.device.temperatureC) ? Math.round(hardware.device.temperatureC) + " °C" : "— °C"
                color: ThemePalette.Theme.text
                font.family: "Inter"; font.pixelSize: 12; font.weight: Font.Medium
            }
        }
    }
    component BatteryMetric: Item {
        id: metric
        property string label: ""
        property string value: ""
        implicitHeight: 39
        Text { width: parent.width; text: metric.label; color: ThemePalette.Theme.muted; font.family: "Inter"; font.pixelSize: 10; elide: Text.ElideRight }
        Text { objectName: metric.objectName + "Value"; y: 17; width: parent.width; text: metric.value; color: ThemePalette.Theme.textBright; font.family: "Inter"; font.pixelSize: 18; font.weight: Font.DemiBold; elide: Text.ElideRight }
    }

    Column {
        id: stack
        width: body.width
        spacing: 10
        Item {
            width: parent.width; height: 44
            Text { text: "HARDWARE"; color: ThemePalette.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
            Text { y: 15; text: "Live overview"; color: ThemePalette.Theme.textBright; font.family: "Inter"; font.pixelSize: 21; font.weight: Font.DemiBold }
            Row {
                anchors.right: closeButton.left; anchors.rightMargin: 13
                anchors.verticalCenter: closeButton.verticalCenter
                spacing: 6
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 5; height: 5; radius: 3; color: body.telemetry && body.telemetry.ready && !body.error ? ThemePalette.Theme.accent : ThemePalette.Theme.mutedStrong }
                Text { text: body.error ? "UNAVAILABLE" : body.telemetry && body.telemetry.ready ? "LIVE · 1 s" : "READING…"; color: ThemePalette.Theme.muted; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.Medium }
            }
            ToolButton {
                id: closeButton
                objectName: "closeHardwarePanel"
                anchors.right: parent.right; y: 2
                width: 34; height: 34
                Accessible.name: "Close hardware panel"
                contentItem: Text { text: "close"; font.family: "Material Symbols Rounded"; font.pixelSize: 20; color: ThemePalette.Theme.muted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 12; color: closeButton.hovered ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface }
                ToolTip.visible: hovered
                ToolTip.text: body.hotkeyText + " · Esc to close"
                onClicked: body.closeRequested()
            }
        }
        Card {
            objectName: "hardwareError"
            visible: body.error.length > 0
            width: parent.width
            height: errorLabel.implicitHeight + 22
            color: ThemePalette.Theme.redDark
            Text { id: errorLabel; x: 12; y: 11; width: parent.width - 24; text: body.error; font.family: "Inter"; font.pixelSize: 11; color: ThemePalette.Theme.onErrorContainer; wrapMode: Text.WordWrap }
        }
        HardwareCard { objectName: "cpuCard"; width: parent.width; title: "CPU"; iconName: "memory"; device: body.sample.cpu || ({}) }
        Repeater {
            model: body.gpus
            delegate: HardwareCard {
                required property var modelData
                required property int index
                objectName: "gpuCard" + index
                width: stack.width
                title: body.gpus.length > 1 ? "GPU " + (index + 1) : "GPU"
                iconName: "developer_board"
                device: modelData
            }
        }
        Card {
            id: batteryCard
            objectName: "batteryCard"
            width: parent.width
            height: body.battery.present ? 288 : 82
            Rectangle {
                x: 14; y: 14; width: 32; height: 32; radius: 11
                color: ThemePalette.Theme.accentSoft
                Text { anchors.centerIn: parent; text: body.battery.charging ? "battery_charging_full" : "battery_full"; color: ThemePalette.Theme.accent; font.family: "Material Symbols Rounded"; font.pixelSize: 21 }
            }
            Text { x: 57; y: 13; text: "BATTERY"; color: ThemePalette.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1 }
            Text {
                objectName: "batteryStatus"
                x: 57; y: 29; width: parent.width - 150
                text: !body.battery.present ? "No system battery detected" : body.battery.charging ? "Charging" : body.battery.draining ? "On battery" : body.battery.externalPower ? "Plugged in" : body.battery.status || "Unknown status"
                color: ThemePalette.Theme.text
                font.family: "Inter"; font.pixelSize: 12; font.weight: Font.Medium; elide: Text.ElideRight
            }
            Text {
                objectName: "batteryPercent"
                anchors.right: parent.right; anchors.rightMargin: 14; y: 11
                text: body.battery.present && body.isValue(body.battery.percent) ? Math.round(body.battery.percent) + "%" : "—"
                color: ThemePalette.Theme.textBright
                font.family: "Inter"; font.pixelSize: 26; font.weight: Font.DemiBold
            }
            Rectangle {
                x: 14; y: 61; width: parent.width - 28; height: 5
                radius: 3; color: ThemePalette.Theme.surfaceRaised
                visible: body.battery.present
                Rectangle {
                    height: parent.height; radius: 3
                    width: parent.width * (body.isValue(body.battery.percent) ? Math.max(0, Math.min(100, body.battery.percent)) / 100 : 0)
                    color: ThemePalette.Theme.accent
                    Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                }
            }
            GridLayout {
                id: metrics
                objectName: "batteryMetrics"
                visible: body.battery.present
                x: 14; y: 81; width: parent.width - 28
                columns: 2; rowSpacing: 10; columnSpacing: 18
                BatteryMetric { objectName: "batteryFullCapacity"; Layout.fillWidth: true; label: "Full capacity"; value: body.metric(body.battery.fullWh, " Wh", 1, body.battery.energyApproximate === true) }
                BatteryMetric { objectName: "batteryStoredEnergy"; Layout.fillWidth: true; label: "Stored energy"; value: body.metric(body.battery.storedWh, " Wh", 1, body.battery.energyApproximate === true) }
                BatteryMetric { objectName: "batteryPower"; Layout.fillWidth: true; label: body.battery.charging ? "Charging power" : body.battery.draining ? "Power draw" : "Battery power"; value: body.metric(body.battery.powerW, " W", 1) }
                BatteryMetric {
                    objectName: "batteryRemaining"
                    Layout.fillWidth: true
                    label: body.battery.charging ? "Until full (est.)" : body.battery.draining ? "Remaining (est.)" : "Runtime"
                    value: body.battery.charging ? body.duration(body.battery.chargingSeconds) : body.battery.draining ? body.duration(body.battery.remainingSeconds) : body.battery.externalPower ? "On AC power" : "Unavailable"
                }
            }
            Text {
                visible: body.battery.present
                x: 14; y: 183
                text: "Battery power"
                color: ThemePalette.Theme.muted
                font.family: "Inter"; font.pixelSize: 10
            }
            Text {
                visible: body.battery.present
                anchors.right: parent.right; anchors.rightMargin: 14; y: 183
                text: body.history.length > 1 ? "last " + Math.min(120, Math.round(body.history[body.history.length - 1].t - body.history[0].t)) + " s" : "since opened"
                color: ThemePalette.Theme.mutedStrong
                font.family: "Inter"; font.pixelSize: 9
            }
            Item {
                id: graph
                objectName: "batteryPowerGraph"
                visible: body.battery.present
                x: 14; y: 202; width: parent.width - 28; height: 70
                readonly property real ceiling: Math.max(5, Math.ceil(Math.max.apply(null, body.history.map(point => body.isValue(point.watts) ? point.watts : 0).concat([0])) / 5) * 5)
                Canvas {
                    id: chart
                    anchors.fill: parent
                    anchors.rightMargin: 34
                    renderStrategy: Canvas.Immediate
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        const top = 4;
                        const bottom = height - 4;
                        ctx.lineWidth = 1;
                        ctx.strokeStyle = Qt.rgba(ThemePalette.Theme.border.r, ThemePalette.Theme.border.g, ThemePalette.Theme.border.b, 0.3);
                        for (let index = 0; index < 3; index++) {
                            const y = top + (bottom - top) * index / 2;
                            ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
                        }
                        const points = body.history;
                        if (!points.length) return;
                        const lastTime = points[points.length - 1].t;
                        const start = Math.max(points[0].t, lastTime - 120);
                        const span = Math.max(1, lastTime - start);
                        let segments = [];
                        let segment = [];
                        let previous = null;
                        for (const point of points) {
                            const gap = previous && (point.t - previous.t > 3 || point.charging !== previous.charging || point.draining !== previous.draining);
                            if (gap || !body.isValue(point.watts)) {
                                if (segment.length) segments.push(segment);
                                segment = [];
                            }
                            if (body.isValue(point.watts)) segment.push({ x: Math.max(0, Math.min(width, (point.t - start) / span * width)), y: bottom - Math.min(graph.ceiling, Math.max(0, point.watts)) / graph.ceiling * (bottom - top), charging: point.charging });
                            previous = point;
                        }
                        if (segment.length) segments.push(segment);
                        for (const line of segments) {
                            const color = line[0].charging ? ThemePalette.Theme.green : ThemePalette.Theme.accent;
                            ctx.beginPath(); ctx.moveTo(line[0].x, bottom);
                            for (const point of line) ctx.lineTo(point.x, point.y);
                            ctx.lineTo(line[line.length - 1].x, bottom); ctx.closePath();
                            const gradient = ctx.createLinearGradient(0, top, 0, bottom);
                            gradient.addColorStop(0, Qt.rgba(color.r, color.g, color.b, 0.23));
                            gradient.addColorStop(1, Qt.rgba(color.r, color.g, color.b, 0.015));
                            ctx.fillStyle = gradient; ctx.fill();
                            ctx.beginPath(); ctx.moveTo(line[0].x, line[0].y);
                            for (let i = 1; i < line.length; i++) ctx.lineTo(line[i].x, line[i].y);
                            ctx.strokeStyle = color; ctx.lineWidth = 2; ctx.lineJoin = "round"; ctx.lineCap = "round"; ctx.stroke();
                            const last = line[line.length - 1];
                            ctx.beginPath(); ctx.arc(last.x, last.y, 2.5, 0, Math.PI * 2); ctx.fillStyle = color; ctx.fill();
                        }
                    }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    Connections { target: body; function onHistoryChanged() { chart.requestPaint(); } }
                    Connections { target: ThemePalette.Theme; function onAccentChanged() { chart.requestPaint(); } function onGreenChanged() { chart.requestPaint(); } function onBorderChanged() { chart.requestPaint(); } }
                }
                Text { anchors.right: parent.right; y: 0; text: graph.ceiling + " W"; color: ThemePalette.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 8 }
                Text { anchors.right: parent.right; anchors.bottom: parent.bottom; text: "0 W"; color: ThemePalette.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 8 }
                Text { anchors.centerIn: chart; visible: body.history.filter(point => body.isValue(point.watts)).length === 0; text: body.telemetry && body.telemetry.ready ? "Power reading unavailable" : "Waiting for battery readings…"; color: ThemePalette.Theme.muted; font.family: "Inter"; font.pixelSize: 10 }
            }
        }
    }
}
