/*
 * Cursor Meter — KDE Plasma 6 applet
 * Three capsule bars: monthly Models/Other pools plus Grok Bot weekly usage.
 */

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property var  data5:    ({ pct: 0, reset_in: null, fresh: false })
    property var  data7:    ({ pct: 0, reset_in: null, fresh: false })
    property var  dataGrok: null
    readonly property bool haveGrok: haveData && dataGrok !== null
    // 0 = Models + Other, 1 = Models + Other + Grok, 2 = Models + Grok
    readonly property bool panelShowOther: Plasmoid.configuration.panelBars !== 2
    readonly property bool panelShowGrok: haveGrok && Plasmoid.configuration.panelBars !== 0
    property bool haveData: false
    property int  ageSec:   0
    property string source:  ""
    property string plan:    ""
    property int totalPct: 0
    property int cycleSec: 2592000
    readonly property int  staleSec: 600
    readonly property bool stale:  haveData && ageSec > staleSec
    readonly property bool noData: !haveData
    readonly property bool degraded: haveData && source !== "" && source !== "live"
    readonly property color accent: "#EDECEC"

    readonly property string meterScript:
        "bash '" + String(Qt.resolvedUrl("../scripts/cursor-meter.sh")).replace("file://", "") + "'"

    preferredRepresentation: compactRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    toolTipMainText: "Cursor usage"
    toolTipSubText: root.haveData ? root.tipText() : "Sign in to Cursor, then wait for the first read…"

    function barColor(v) {
        var t = Math.max(0, Math.min(100, v)) / 100.0
        var hue = (1.0 - t) * 140.0 / 360.0
        var sat = 0.66 + t * 0.16
        return Qt.hsla(hue, sat, 0.55, 1.0)
    }

    function paceColor(pct, timePct) {
        if (timePct === null || timePct === undefined) return barColor(pct)
        var m = pct - timePct
        var hue
        if (m <= -8)      hue = 140
        else if (m < 0)   hue = 55 + (-m / 8) * 85
        else if (m < 8)   hue = 55 * (1 - m / 8)
        else              hue = 0
        return Qt.hsla(hue / 360.0, 0.72, 0.55, 1.0)
    }

    function fmtDur(s) {
        if (s === null || s === undefined) return "—"
        if (s <= 0) return "now"
        var d = Math.floor(s / 86400); s -= d * 86400
        var h = Math.floor(s / 3600);  s -= h * 3600
        var m = Math.floor(s / 60)
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    function fmtAge(s) {
        if (s === null || s === undefined) return "—"
        if (s < 60)    return s + "s"
        if (s < 3600)  return Math.floor(s / 60) + "m"
        if (s < 86400) return Math.floor(s / 3600) + "h"
        return Math.floor(s / 86400) + "d"
    }

    function timePctOf(resetIn, durSec) {
        if (resetIn === null || resetIn === undefined || resetIn <= 0) return null
        var e = (durSec - Math.min(resetIn, durSec)) / durSec * 100.0
        return Math.max(0, Math.min(100, e))
    }

    function paceArrow(pct, timePct) {
        if (timePct === null || timePct === undefined) return ""
        var m = pct - timePct
        if (m > 8)  return "↑"
        if (m < -8) return "↓"
        return "→"
    }

    function paceWord(pct, timePct) {
        if (timePct === null || timePct === undefined) return ""
        var m = pct - timePct
        if (m > 8)  return "burning fast"
        if (m < -8) return "comfortable"
        return "on pace"
    }

    function detailLine(d, active, durSec) {
        if (!active) return "no reading yet"
        if (d.fresh) return "cycle not started yet"
        var parts = []
        if (d.reset_in === null || d.reset_in === undefined) parts.push("no reset info")
        else if (d.reset_in <= 0) parts.push("cycle just reset")
        else parts.push("resets in " + fmtDur(d.reset_in))
        var tp = timePctOf(d.reset_in, durSec)
        if (tp !== null) {
            parts.push(Math.round(tp) + "% through cycle")
            var w = paceWord(Math.max(0, Math.min(100, d.pct)), tp)
            if (w !== "") parts.push(w)
        }
        return parts.join("   ·   ")
    }

    function lineFor(pfx, d, durSec) {
        if (d.fresh) return pfx + "  unused"
        var pct = Math.round(Math.max(0, Math.min(100, d.pct)))
        var s = pfx + "  " + pct + "%"
        if (d.reset_in !== null && d.reset_in > 0) s += "  ·  resets " + fmtDur(d.reset_in)
        else if (d.reset_in !== null && d.reset_in <= 0) s += "  ·  just reset"
        var tp = timePctOf(d.reset_in, durSec)
        if (tp !== null) s += "  ·  " + Math.round(tp) + "% thru " + paceArrow(pct, tp)
        return s
    }

    function sourceText() {
        if (source === "live") return "live · account-wide Cursor"
        var s = "from last live read · " + fmtAge(ageSec) + " ago"
        if (ageSec > staleSec) s += " · stale"
        s += "\nopen Cursor or run cursor-agent once to refresh the token"
        return s
    }

    function tipText() {
        var s = "included  " + totalPct + "% of monthly allowance\n"
            + lineFor("Models", data5, cycleSec) + "\n"
            + lineFor("Other", data7, cycleSec)
        if (haveGrok)
            s += "\n" + lineFor("Grok", dataGrok, dataGrok.week_sec || 604800)
        return s + "\n" + sourceText()
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            exec.disconnectSource(source)
            var out = (data && data.stdout ? String(data.stdout) : "").trim()
            if (out.length === 0) return
            try {
                var j = JSON.parse(out)
                if (j && j.ok) {
                    root.data5     = j.five
                    root.data7     = j.seven
                    root.dataGrok  = j.grok || null
                    root.ageSec    = j.age || 0
                    root.source    = j.source || ""
                    root.plan      = j.plan || ""
                    root.totalPct  = j.total_pct || 0
                    root.cycleSec  = j.cycle_sec || 2592000
                    root.haveData  = true
                } else {
                    root.haveData = false
                }
            } catch (e) {
                // keep the previous values
            }
        }

        function poll() { exec.connectSource(root.meterScript) }
    }

    Timer {
        interval: 90000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.poll()
    }

    Component.onCompleted: exec.poll()

    component MeterBar : Item {
        id: mb
        property string label: ""
        property real   value: 0
        property var    timePct: null
        property bool   active: true
        property bool   stale: false
        property bool   justReset: false
        property bool   showValue: true
        property real   labelWidth: -1
        readonly property real labelImplicitWidth: labelItem.visible ? labelItem.implicitWidth : 0

        implicitHeight: Kirigami.Units.gridUnit
        implicitWidth:  Kirigami.Units.gridUnit * 6
        Layout.minimumHeight: 4

        readonly property real  v: Math.max(0, Math.min(100, value))
        readonly property color fillColor: mb.stale
            ? Qt.rgba(0.56, 0.58, 0.63, 1.0)
            : root.paceColor(v, mb.timePct)

        RowLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                id: labelItem
                text: mb.label
                visible: mb.label.length > 0
                font.pixelSize: Math.max(8, mb.height * 0.62)
                font.bold: true
                opacity: 0.6
                Layout.minimumHeight: 0
                Layout.fillHeight: true
                Layout.preferredWidth: mb.label.length === 0 ? 0
                    : mb.labelWidth >= 0 ? mb.labelWidth : Kirigami.Units.gridUnit * 0.95
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
            }

            Rectangle {
                id: track
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Layout.maximumHeight: Kirigami.Units.gridUnit * 0.9
                Layout.alignment: Qt.AlignVCenter
                radius: height / 2
                color: Qt.rgba(0.5, 0.5, 0.56, 0.28)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.06)

                Rectangle {
                    id: fill
                    height: parent.height
                    width: (!mb.active || mb.v <= 0) ? 0 : parent.width * mb.v / 100.0
                    topLeftRadius: height / 2
                    bottomLeftRadius: height / 2
                    topRightRadius: Math.max(0, Math.min(height / 2, width - (parent.width - height / 2)))
                    bottomRightRadius: topRightRadius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.lighter(mb.fillColor, 1.35) }
                        GradientStop { position: 1.0; color: mb.fillColor }
                    }
                    Behavior on width { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }
                }

                Rectangle {
                    id: tick
                    visible: mb.active && mb.timePct !== null && mb.timePct !== undefined
                    width: 2
                    height: parent.height + 4
                    y: -2
                    x: Math.max(0, Math.min(parent.width - width,
                                parent.width * Math.min(100, (mb.timePct || 0)) / 100.0 - width / 2))
                    radius: 1
                    color: mb.stale ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.92)
                    Behavior on x { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }
                }

                PlasmaComponents.Label {
                    visible: mb.justReset && mb.active
                    text: "↺"
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Math.max(7, parent.height * 0.72)
                    font.bold: true
                    color: Qt.rgba(1, 1, 1, 0.75)
                }
            }

            PlasmaComponents.Label {
                visible: mb.showValue
                text: mb.active ? Math.round(mb.v) + "%" : "—"
                font.pixelSize: Math.max(8, mb.height * 0.58)
                font.bold: true
                color: mb.active ? mb.fillColor : Qt.rgba(0.6, 0.6, 0.6, 1)
                Layout.minimumHeight: 0
                Layout.fillHeight: true
                Layout.preferredWidth: mb.showValue ? Kirigami.Units.gridUnit * 1.7 : 0
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    compactRepresentation: MouseArea {
        id: compactRoot
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        Layout.minimumWidth: contentRow.implicitWidth
        Layout.preferredWidth: contentRow.implicitWidth
        Layout.minimumHeight: Kirigami.Units.gridUnit * 1.6

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            height: Math.min(parent.height - Kirigami.Units.smallSpacing,
                             Kirigami.Units.gridUnit * (barsCol.barCount === 3 ? 3.3 : 2.3))
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                id: brandIcon
                visible: Plasmoid.configuration.showIcon
                source: Qt.resolvedUrl("../icons/cursor.svg")
                isMask: Plasmoid.configuration.monochromeIcon
                color: Kirigami.Theme.textColor
                Layout.preferredWidth: visible ? Math.round(contentRow.height * 0.72) : 0
                Layout.preferredHeight: Layout.preferredWidth
                Layout.alignment: Qt.AlignVCenter
                opacity: root.stale ? 0.5 : 1.0
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }

            ColumnLayout {
                id: barsCol
                Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                Layout.fillHeight: true
                spacing: barCount === 3 ? 2 : Kirigami.Units.smallSpacing
                opacity: root.stale ? 0.5 : 1.0
                Behavior on opacity { NumberAnimation { duration: 400 } }
                readonly property int barCount: 1 + (root.panelShowOther ? 1 : 0) + (root.panelShowGrok ? 1 : 0)
                readonly property real labelW: Math.max(barModels.labelImplicitWidth, barOther.labelImplicitWidth,
                                                        barGrok.labelImplicitWidth, Kirigami.Units.gridUnit * 0.95)

                MeterBar {
                    id: barModels
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    labelWidth: barsCol.labelW
                    label: Plasmoid.configuration.showWindowLabels ? "Models" : ""
                    active: root.haveData
                    stale: root.stale
                    value: root.data5.pct
                    timePct: root.timePctOf(root.data5.reset_in, root.cycleSec)
                    justReset: root.haveData && !root.data5.fresh
                               && root.data5.reset_in !== null && root.data5.reset_in <= 0
                }
                MeterBar {
                    id: barOther
                    visible: root.panelShowOther
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    labelWidth: barsCol.labelW
                    label: Plasmoid.configuration.showWindowLabels ? "Other" : ""
                    active: root.haveData
                    stale: root.stale
                    value: root.data7.pct
                    timePct: root.timePctOf(root.data7.reset_in, root.cycleSec)
                    justReset: root.haveData && !root.data7.fresh
                               && root.data7.reset_in !== null && root.data7.reset_in <= 0
                }
                MeterBar {
                    id: barGrok
                    visible: root.panelShowGrok
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    labelWidth: barsCol.labelW
                    label: Plasmoid.configuration.showWindowLabels ? "Grok" : ""
                    active: root.panelShowGrok
                    stale: root.stale
                    value: root.dataGrok.pct
                    timePct: root.timePctOf(root.dataGrok.reset_in, root.dataGrok.week_sec || 604800)
                    justReset: root.panelShowGrok && !root.dataGrok.fresh
                               && root.dataGrok.reset_in !== null && root.dataGrok.reset_in <= 0
                }
            }

            RowLayout {
                visible: root.stale || root.noData || root.degraded
                Layout.fillHeight: true
                spacing: 2
                Kirigami.Icon {
                    source: root.noData ? "documentinfo" : root.stale ? "clock" : "offline"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    Layout.alignment: Qt.AlignVCenter
                    opacity: 0.75
                }
                PlasmaComponents.Label {
                    text: root.noData ? "no data" : root.stale ? root.fmtAge(root.ageSec) : "offline"
                    font.pixelSize: Math.max(8, contentRow.height * 0.36)
                    opacity: 0.75
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }

    component WindowBlock : ColumnLayout {
        id: wb
        property string title: ""
        property var    d: ({ pct: 0, reset_in: null, fresh: false })
        property bool   active: true
        property real   windowSec: 2592000
        spacing: Kirigami.Units.smallSpacing
        Layout.fillWidth: true

        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents.Label {
                text: wb.title
                opacity: 0.8
                font.pixelSize: Kirigami.Units.gridUnit * 0.82
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: !wb.active ? "—"
                    : wb.d.fresh ? "unused"
                    : Math.round(Math.max(0, Math.min(100, wb.d.pct))) + "%"
                font.bold: true
                font.pixelSize: Kirigami.Units.gridUnit * (wb.active && wb.d.fresh ? 0.78 : 0.9)
                color: !wb.active ? Qt.rgba(0.6, 0.6, 0.6, 1)
                    : root.stale ? Qt.rgba(0.62, 0.64, 0.68, 1)
                    : root.paceColor(wb.d.pct, root.timePctOf(wb.d.reset_in, wb.windowSec))
            }
        }

        MeterBar {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.05
            label: ""
            showValue: false
            active: wb.active
            stale: root.stale
            value: wb.d.pct
            timePct: root.timePctOf(wb.d.reset_in, wb.windowSec)
            justReset: wb.active && !wb.d.fresh && wb.d.reset_in !== null && wb.d.reset_in <= 0
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            opacity: 0.6
            wrapMode: Text.WordWrap
            font.pixelSize: Kirigami.Units.gridUnit * 0.72
            text: root.detailLine(wb.d, wb.active, wb.windowSec)
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth:  Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: root.haveGrok ? Kirigami.Units.gridUnit * 15 : Kirigami.Units.gridUnit * 12
        Layout.preferredWidth:  Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: root.haveGrok ? Kirigami.Units.gridUnit * 16 : Kirigami.Units.gridUnit * 13

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: Qt.resolvedUrl("../icons/cursor.svg")
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }
                ColumnLayout {
                    spacing: 0
                    PlasmaComponents.Label {
                        text: "Cursor"
                        font.bold: true
                        font.pixelSize: Kirigami.Units.gridUnit * 1.0
                        color: root.accent
                    }
                    PlasmaComponents.Label {
                        text: root.plan !== ""
                            ? "included usage · " + root.plan + " · allowance " + root.totalPct + "%"
                            : "included usage"
                        opacity: 0.6
                        font.pixelSize: Kirigami.Units.gridUnit * 0.72
                    }
                }
                Item { Layout.fillWidth: true }
            }

            WindowBlock {
                title: "Cursor, Grok and Composer"
                d: root.data5
                active: root.haveData
                windowSec: root.cycleSec
            }

            WindowBlock {
                title: "Other models"
                d: root.data7
                active: root.haveData
                windowSec: root.cycleSec
            }

            WindowBlock {
                visible: root.haveGrok
                title: "Grok Bot (weekly)"
                d: root.dataGrok
                active: root.haveGrok
                windowSec: root.dataGrok.week_sec || 604800
            }

            Item { Layout.fillHeight: true }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                opacity: 0.5
                font.pixelSize: Kirigami.Units.gridUnit * 0.72
                text: root.haveData
                    ? (root.source === "live"
                        ? "live · account-wide Cursor"
                        : ("from last live read · " + root.fmtAge(root.ageSec) + " ago"
                           + (root.ageSec > root.staleSec ? "  ·  stale" : "")
                           + "  ·  open Cursor or run cursor-agent once to refresh the token"))
                    : "no data yet — sign in to Cursor"
            }
        }
    }
}
