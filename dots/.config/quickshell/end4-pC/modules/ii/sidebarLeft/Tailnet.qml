pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Tailscale (tailnet) panel: connection toggle, exit node picker and device list.
 */
Item {
    id: root
    property real padding: 8

    // ---------- state ----------
    // Device data lives in a map keyed by stable node ID; the list model only
    // holds IDs so delegates update in place instead of being recreated.
    property var deviceMap: ({})
    property var deviceIds: []
    property int deviceCount: 0
    property string lastIdsJson: ""
    property bool statusReady: false
    property bool isConnected: false
    property string backendState: ""
    property int onlineCount: 0
    property string currentExitNode: ""
    property var exitNodeOptions: []
    property string lastExitNodesJson: ""
    property bool needsOperator: false
    property bool actionPending: false
    property var pingResults: ({}) // nodeId -> latency text
    property int keyExpiryDays: -1
    property bool prevRunning: false // previous backend state, for change notifications

    readonly property string operatorCommand: "sudo tailscale set --operator=" + (Quickshell.env("USER") || "$USER")

    // ---------- actions ----------
    function refreshStatus(): void {
        fetchStatusProc.exec(["tailscale", "status", "--json"])
    }

    function connectTailscale(): void {
        root.actionPending = true
        connectProc.running = true
    }

    function disconnectTailscale(): void {
        root.actionPending = true
        disconnectProc.running = true
    }

    function setExitNode(host: string): void {
        exitNodeProc.exec(["tailscale", "set", "--exit-node=" + host])
    }

    function copyIP(ip: string): void {
        Quickshell.clipboardText = ip
    }

    function pingDevice(nodeId: string, target: string): void {
        root.setPingResult(nodeId, Translation.tr("Pinging..."))
        pingProc.nodeId = nodeId
        pingProc.exec(["tailscale", "ping", "-c", "1", target])
    }

    function setPingResult(nodeId: string, result: string): void {
        const upd = {}
        upd[nodeId] = result
        root.pingResults = Object.assign({}, root.pingResults, upd)
    }

    function sendFile(target: string): void {
        filePickProc.target = target
        filePickProc.exec(["kdialog", "--getopenfilename", Quickshell.env("HOME") || "/",
            "--title", Translation.tr("Send file via Taildrop")])
    }

    // Interactive by design: the login name differs per host, so it is asked for
    // in the terminal, with the last answer for that host offered back.
    function sshDevice(host: string): void {
        if (host.length === 0) return
        const stateFile = FileUtils.trimFileProtocol(Directories.state) + "/user/tailnet-ssh-users"
        const script = `
host=$1
state_file=$2
mkdir -p -- "\${state_file%/*}"
touch -- "$state_file"
saved=$(awk -v h="$host" '$1 == h { user=$2 } END { print user }' "$state_file")
read -r -e -i "\${saved:-$USER}" -p "[$host] SSH user: " user
[ -n "$user" ] || exit 0
awk -v h="$host" '$1 != h' "$state_file" > "$state_file.tmp"
printf '%s %s\\n' "$host" "$user" >> "$state_file.tmp"
mv -- "$state_file.tmp" "$state_file"
# Hand the remote a copy of this terminal's terminfo before the session starts:
# a command run over ssh gets no TTY, so sshd sets no TERM there at all.
term=\${TERM:-}
if [ -n "$term" ] && infocmp -x "$term" >/dev/null 2>&1; then
    infocmp -x "$term" 2>/dev/null \\
        | ssh "$user@$host" "infocmp '$term' >/dev/null 2>&1 || tic -x -" >/dev/null 2>&1
fi
ssh "$user@$host"
status=$?
if (( status != 0 )); then
    printf '\\n-- ssh failed, press any key to close --'
    read -rn1 -s
fi`
        const scriptArg = `'${StringUtils.shellSingleQuoteEscape(script)}'`
        const hostArg = `'${StringUtils.shellSingleQuoteEscape(host)}'`
        const stateArg = `'${StringUtils.shellSingleQuoteEscape(stateFile)}'`
        Quickshell.execDetached([
            "bash", "-lc",
            `${Config.options.apps.terminal} bash -lc ${scriptArg} _ ${hostArg} ${stateArg}`
        ])
    }

    function notify(summary: string, body: string): void {
        Quickshell.execDetached(["notify-send", summary, body, "-a", "Shell"])
    }

    // ---------- helpers ----------
    function formatBytes(bytes): string {
        if (bytes === undefined || bytes === null || bytes < 0) return "-"
        if (bytes === 0) return "0 B"
        const units = ["B", "KB", "MB", "GB", "TB"]
        let i = 0
        let val = bytes
        while (val >= 1024 && i < units.length - 1) {
            val /= 1024
            i++
        }
        return val.toFixed(i === 0 ? 0 : 1) + " " + units[i]
    }

    function osIcon(os): string {
        switch (os) {
            case "linux":   return "computer"
            case "windows": return "desktop_windows"
            case "macOS":   return "laptop_mac"
            case "android": return "smartphone"
            case "iOS":
            case "ios":     return "phone_iphone"
            case "tvOS":    return "tv"
            default:        return "device_unknown"
        }
    }

    function osName(os): string {
        switch (os) {
            case "linux":   return "Linux"
            case "windows": return "Windows"
            case "macOS":   return "macOS"
            case "android": return "Android"
            case "iOS":
            case "ios":     return "iOS"
            case "tvOS":    return "tvOS"
            default:        return os || Translation.tr("Unknown")
        }
    }

    function timeAgo(iso): string {
        if (!iso || iso.startsWith("0001")) return ""
        const t = new Date(iso).getTime()
        if (isNaN(t)) return ""
        const mins = Math.floor((Date.now() - t) / 60000)
        if (mins < 1) return Translation.tr("just now")
        if (mins < 60) return Translation.tr("%1 min ago").arg(mins)
        const hrs = Math.floor(mins / 60)
        if (hrs < 24) return Translation.tr("%1 h ago").arg(hrs)
        return Translation.tr("%1 d ago").arg(Math.floor(hrs / 24))
    }

    function cleanDnsName(dnsName): string {
        return (dnsName || "").replace(/\.$/, "")
    }

    function shortName(dnsName, fallback): string {
        const clean = cleanDnsName(dnsName)
        if (clean.length > 0) return clean.split(".")[0]
        return fallback || "unknown"
    }

    function deviceTarget(device): string {
        if (!device) return ""
        if (device.tailscaleIPs?.length > 0) return device.tailscaleIPs[0]
        if (device.dnsName?.length > 0) return cleanDnsName(device.dnsName)
        return device.hostName || ""
    }

    function parseDevice(node, isSelf: bool): var {
        return {
            nodeId: node.ID,
            isSelf: isSelf,
            hostName: node.HostName,
            displayName: shortName(node.DNSName, node.HostName),
            dnsName: cleanDnsName(node.DNSName),
            tailscaleIPs: node.TailscaleIPs || [],
            online: node.Online === true,
            os: node.OS || "",
            isExitNode: node.ExitNode === true,
            relay: isSelf ? "" : (node.Relay || ""),
            curAddr: isSelf ? "" : (node.CurAddr || ""),
            lastSeen: isSelf ? "" : (node.LastSeen || ""),
            rxBytes: node.RxBytes ?? 0,
            txBytes: node.TxBytes ?? 0
        }
    }

    function checkOperatorError(text): void {
        if (text && text.includes("Access denied")) {
            root.needsOperator = true
        }
    }

    // ---------- processes ----------
    Process {
        id: fetchStatusProc
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            id: statusCollector
            onStreamFinished: {
                if (root === null) return // torn down mid-fetch (hot reload)
                try {
                    const raw = statusCollector.text
                    if (!raw || raw.length === 0) {
                        root.statusReady = true
                        root.isConnected = false
                        root.deviceMap = {}
                        root.deviceIds = []
                        root.deviceCount = 0
                        root.lastIdsJson = ""
                        return
                    }
                    const data = JSON.parse(raw)
                    root.backendState = data.BackendState || ""
                    root.isConnected = data.BackendState === "Running"

                    root.keyExpiryDays = -1
                    if (data.Self?.KeyExpiry) {
                        const expiry = new Date(data.Self.KeyExpiry).getTime()
                        if (!isNaN(expiry))
                            root.keyExpiryDays = Math.floor((expiry - Date.now()) / 86400000)
                    }

                    const list = []
                    if (data.Self) list.push(root.parseDevice(data.Self, true))

                    const exitNodes = []
                    root.currentExitNode = ""
                    for (const key in (data.Peer || {})) {
                        const p = data.Peer[key]
                        if (data.Self && p.ID === data.Self.ID) continue
                        list.push(root.parseDevice(p, false))

                        if (p.ExitNode === true) {
                            root.currentExitNode = root.shortName(p.DNSName, p.HostName)
                        }
                        if (p.ExitNodeOption === true) {
                            exitNodes.push({
                                name: root.shortName(p.DNSName, p.HostName),
                                online: p.Online === true
                            })
                        }
                    }

                    exitNodes.sort((a, b) => {
                        if (a.online !== b.online) return a.online ? -1 : 1
                        return a.name.localeCompare(b.name)
                    })
                    const enJson = JSON.stringify(exitNodes)
                    if (enJson !== root.lastExitNodesJson) {
                        root.lastExitNodesJson = enJson
                        root.exitNodeOptions = exitNodes
                    }

                    // Online first, self before peers, then alphabetical
                    list.sort((a, b) => {
                        if (a.online !== b.online) return a.online ? -1 : 1
                        if (a.isSelf !== b.isSelf) return a.isSelf ? -1 : 1
                        return a.displayName.localeCompare(b.displayName)
                    })

                    root.onlineCount = list.filter(d => d.online).length
                    root.deviceCount = list.length

                    // Notify when a peer's reachability changes (skip first load and
                    // reconnects, where every peer would flip at once)
                    if (root.prevRunning && root.isConnected) {
                        for (const d of list) {
                            const prev = root.deviceMap[d.nodeId]
                            if (prev && !d.isSelf && prev.online !== d.online) {
                                root.notify(d.displayName, d.online
                                    ? Translation.tr("came online")
                                    : Translation.tr("went offline"))
                            }
                        }
                    }
                    root.prevRunning = root.isConnected

                    // Refresh data in place; only touch the ID list when membership
                    // or order changes, so existing cards survive refreshes.
                    const map = {}
                    for (const d of list) map[d.nodeId] = d
                    root.deviceMap = map
                    const idsJson = JSON.stringify(list.map(d => d.nodeId))
                    if (idsJson !== root.lastIdsJson) {
                        root.lastIdsJson = idsJson
                        root.deviceIds = list.map(d => d.nodeId)
                    }
                    root.statusReady = true
                } catch (e) {
                    root.statusReady = true
                    root.isConnected = false
                    root.prevRunning = false
                    console.error("[Tailnet] Failed to parse status:", e)
                }
                root.actionPending = false
                connectSwitch.checked = root.isConnected
            }
        }
    }

    Process {
        id: connectProc
        command: ["tailscale", "up"]
        stderr: StdioCollector {
            onStreamFinished: root.checkOperatorError(this.text)
        }
        onExited: root?.refreshStatus()
    }

    Process {
        id: disconnectProc
        command: ["tailscale", "down"]
        stderr: StdioCollector {
            onStreamFinished: root.checkOperatorError(this.text)
        }
        onExited: root?.refreshStatus()
    }

    Process {
        id: exitNodeProc
        stderr: StdioCollector {
            onStreamFinished: root.checkOperatorError(this.text)
        }
        onExited: root?.refreshStatus()
    }

    Process {
        id: pingProc
        property string nodeId: ""
        stdout: StdioCollector {
            id: pingCollector
            onStreamFinished: {
                if (root === null || pingProc.nodeId === "") return
                const m = pingCollector.text.match(/via (\S+) in ([\d.]+)ms/)
                let result = Translation.tr("No response")
                if (m) {
                    const via = m[1].startsWith("DERP(")
                        ? Translation.tr("relay %1").arg(m[1].slice(5, -1))
                        : Translation.tr("direct")
                    result = m[2] + " ms · " + via
                }
                root.setPingResult(pingProc.nodeId, result)
            }
        }
    }

    Process {
        id: filePickProc
        property string target: ""
        stdout: StdioCollector {
            id: filePickCollector
            onStreamFinished: {
                if (root === null) return
                const path = filePickCollector.text.trim()
                if (path.length === 0) return // cancelled
                fileSendProc.fileName = path.split("/").pop()
                fileSendProc.exec(["tailscale", "file", "cp", path, filePickProc.target + ":"])
                root.notify(Translation.tr("Taildrop"), Translation.tr("Sending %1...").arg(fileSendProc.fileName))
            }
        }
    }

    Process {
        id: fileSendProc
        property string fileName: ""
        stderr: StdioCollector {
            onStreamFinished: {
                if (root) root.checkOperatorError(this.text)
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root === null) return
            root.notify(exitCode === 0 ? Translation.tr("File sent") : Translation.tr("File send failed"),
                fileSendProc.fileName)
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root?.refreshStatus()
    }

    // ============= UI =============
    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        // ---- header: status + connect switch ----
        Rectangle {
            Layout.fillWidth: true
            color: Appearance.colors.colLayer2
            radius: Appearance.rounding.normal
            implicitHeight: headerRow.implicitHeight + 20

            RowLayout {
                id: headerRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                    rightMargin: 12
                }
                spacing: 10

                Rectangle {
                    implicitWidth: 38
                    implicitHeight: 38
                    radius: Appearance.rounding.full
                    color: root.isConnected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "hub"
                        fill: root.isConnected ? 1 : 0
                        iconSize: Appearance.font.pixelSize.larger
                        color: root.isConnected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: "Tailscale"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (!root.statusReady) return Translation.tr("Loading...")
                            if (root.actionPending) return Translation.tr("Working...")
                            if (root.isConnected) {
                                let s = Translation.tr("%1 of %2 devices online").arg(root.onlineCount).arg(root.deviceCount)
                                if (root.currentExitNode.length > 0)
                                    s += " • " + Translation.tr("via %1").arg(root.currentExitNode)
                                return s
                            }
                            return root.backendState === "Stopped"
                                ? Translation.tr("Disconnected")
                                : (root.backendState || Translation.tr("Unavailable"))
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                    StyledText {
                        visible: root.keyExpiryDays >= 0 && root.keyExpiryDays <= 14
                        Layout.fillWidth: true
                        text: root.keyExpiryDays === 0
                            ? Translation.tr("Key expires today!")
                            : Translation.tr("Key expires in %1 day(s)").arg(root.keyExpiryDays)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.m3colors.m3error
                        elide: Text.ElideRight
                    }
                }

                StyledSwitch {
                    id: connectSwitch
                    enabled: root.statusReady && !root.actionPending
                    onToggled: {
                        if (checked) root.connectTailscale()
                        else root.disconnectTailscale()
                    }
                }
            }
        }

        // ---- operator permission notice ----
        NoticeBox {
            Layout.fillWidth: true
            visible: root.needsOperator
            materialIcon: "warning"
            text: Translation.tr("Tailscale needs operator permission to be controlled from here. Run this once in a terminal:") + "\n" + root.operatorCommand

            DialogButton {
                buttonText: Translation.tr("Copy command")
                colText: Appearance.colors.colOnPrimaryContainer
                onClicked: Quickshell.clipboardText = root.operatorCommand
            }
            DialogButton {
                buttonText: Translation.tr("Dismiss")
                colText: Appearance.colors.colOnPrimaryContainer
                onClicked: root.needsOperator = false
            }
        }

        // ---- exit node picker ----
        Rectangle {
            Layout.fillWidth: true
            visible: root.isConnected && root.exitNodeOptions.length > 0
            color: Appearance.colors.colLayer2
            radius: Appearance.rounding.normal
            implicitHeight: exitNodeCol.implicitHeight + 20

            ColumnLayout {
                id: exitNodeCol
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                    rightMargin: 12
                }
                spacing: 8

                RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        text: "alt_route"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Exit node")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 5

                    ExitNodePill {
                        label: Translation.tr("None")
                        showDot: false
                        selected: root.currentExitNode === ""
                        onClicked: root.setExitNode("")
                    }
                    Repeater {
                        model: root.exitNodeOptions
                        delegate: ExitNodePill {
                            required property var modelData
                            label: modelData.name
                            online: modelData.online
                            selected: modelData.name === root.currentExitNode
                            onClicked: root.setExitNode(modelData.name)
                        }
                    }
                }
            }
        }

        // ---- device list header ----
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Devices")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            GroupButton {
                baseWidth: 30
                baseHeight: 30
                buttonRadius: Appearance.rounding.full
                onClicked: root.refreshStatus()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colSubtext
                }
                StyledToolTip {
                    text: Translation.tr("Refresh device list")
                }
            }
        }

        // ---- device list ----
        StyledListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 5
            animateAppearance: false

            model: ScriptModel {
                values: root.deviceIds
            }
            delegate: DeviceCard {
                required property var modelData
                device: root.deviceMap[modelData] ?? ({})
                anchors {
                    left: parent?.left
                    right: parent?.right
                }
            }
        }
    }

    // Placeholder when there is nothing to show
    StyledText {
        anchors.centerIn: parent
        visible: root.statusReady && root.deviceCount === 0
        text: Translation.tr("No devices")
        color: Appearance.colors.colSubtext
    }

    // ============= components =============
    // Icon action button styled like the notification action row
    component DeviceActionButton: RippleButton {
        id: actionBtn
        property string symbol
        property string tooltipText
        Layout.fillWidth: true
        implicitHeight: 30
        buttonRadius: Appearance.rounding.small
        colBackground: Appearance.colors.colLayer4
        colBackgroundHover: Appearance.colors.colLayer4Hover
        colRipple: Appearance.colors.colLayer4Active
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: actionBtn.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.m3colors.m3onSurface
        }
        StyledToolTip {
            text: actionBtn.tooltipText
        }
    }

    component ExitNodePill: RippleButton {
        id: pill
        property string label
        property bool selected: false
        property bool online: true
        property bool showDot: true

        // An offline pill is shown for awareness but can't be picked
        // (routing through a dead exit node kills connectivity)
        enabled: online || selected
        opacity: enabled ? 1 : 0.5
        toggled: selected
        pointingHandCursor: enabled
        buttonRadius: Appearance.rounding.full
        horizontalPadding: 12
        verticalPadding: 5
        implicitWidth: pillRow.implicitWidth + horizontalPadding * 2
        implicitHeight: pillRow.implicitHeight + verticalPadding * 2

        colBackground: Appearance.colors.colSurfaceContainerHighest
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
        colRipple: Appearance.colors.colSurfaceContainerHighestActive

        contentItem: Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6

            Rectangle {
                visible: pill.showDot
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 6
                implicitHeight: 6
                radius: Appearance.rounding.full
                color: !pill.online ? "transparent"
                    : pill.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                border.width: pill.online ? 0 : 1
                border.color: pill.selected ? Appearance.colors.colOnPrimary : Appearance.m3colors.m3outline
            }
            StyledText {
                text: pill.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: pill.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }
    }

    component DeviceCard: RippleButton {
        id: card
        required property var device
        property bool expanded: false
        readonly property bool online: card.device.online === true
        readonly property string target: root.deviceTarget(card.device)
        readonly property string connectionText: {
            if (!card.online) {
                const ago = root.timeAgo(card.device.lastSeen)
                return ago ? Translation.tr("Offline · seen %1").arg(ago) : Translation.tr("Offline")
            }
            if (card.device.isSelf) return Translation.tr("This device")
            if (card.device.curAddr) return Translation.tr("Direct")
            if (card.device.relay) return Translation.tr("Relay (%1)").arg(card.device.relay)
            return Translation.tr("Connected")
        }

        onExpandedChanged: {
            // Auto-ping once when a peer card is opened
            if (expanded && card.online && !card.device.isSelf
                && !(root.pingResults[card.device.nodeId] ?? ""))
                root.pingDevice(card.device.nodeId, card.target)
        }

        horizontalPadding: 12
        verticalPadding: 10
        clip: true
        buttonRadius: Appearance.rounding.normal
        colBackground: card.expanded ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2
        colBackgroundHover: card.expanded ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer2Hover
        colRipple: card.expanded ? Appearance.colors.colLayer3Active : Appearance.colors.colLayer2Active
        pointingHandCursor: true

        implicitHeight: cardCol.implicitHeight + verticalPadding * 2
        Behavior on implicitHeight {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        onClicked: card.expanded = !card.expanded
        altAction: () => card.expanded = !card.expanded

        contentItem: ColumnLayout {
            id: cardCol
            anchors {
                fill: parent
                topMargin: card.verticalPadding
                leftMargin: card.horizontalPadding
                rightMargin: card.horizontalPadding
            }
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MouseArea {
                    implicitWidth: osIcon.implicitWidth
                    implicitHeight: osIcon.implicitHeight
                    hoverEnabled: true
                    property bool hovered: containsMouse

                    MaterialSymbol {
                        id: osIcon
                        text: root.osIcon(card.device.os)
                        iconSize: Appearance.font.pixelSize.huge
                        color: card.online ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext
                    }
                    StyledToolTip {
                        text: root.osName(card.device.os)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        StyledText {
                            text: card.device.displayName || card.device.hostName || ""
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: card.device.isSelf ? Font.DemiBold : Font.Normal
                            color: card.online ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                        MaterialSymbol {
                            visible: card.device.isExitNode === true
                            text: "alt_route"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.m3colors.m3tertiary
                        }
                        Item { Layout.fillWidth: true }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const parts = []
                            if (card.device.os) parts.push(root.osName(card.device.os))
                            if (card.device.tailscaleIPs?.length > 0) parts.push(card.device.tailscaleIPs[0])
                            parts.push(card.connectionText)
                            return parts.join(" • ")
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }

                // Online: filled dot. Offline: hollow ring.
                Rectangle {
                    implicitWidth: 10
                    implicitHeight: 10
                    radius: Appearance.rounding.full
                    color: card.online ? Appearance.colors.colPrimary : "transparent"
                    border.width: card.online ? 0 : 1.5
                    border.color: Appearance.m3colors.m3outline
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                MaterialSymbol {
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                    rotation: card.expanded ? 180 : 0
                    Behavior on rotation {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }

            // ---- expanded details ----
            ColumnLayout {
                visible: card.expanded
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 6

                StyledText {
                    visible: (card.device.dnsName?.length ?? 0) > 0
                    Layout.fillWidth: true
                    text: card.device.dnsName || ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideMiddle
                }
                RowLayout {
                    spacing: 12
                    StyledText {
                        visible: (root.pingResults[card.device.nodeId] ?? "").length > 0
                        text: Translation.tr("Ping: %1").arg(root.pingResults[card.device.nodeId] ?? "")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        visible: card.online && (card.device.rxBytes > 0 || card.device.txBytes > 0)
                        text: "↓ " + root.formatBytes(card.device.rxBytes) + "   ↑ " + root.formatBytes(card.device.txBytes)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 4

                    DeviceActionButton {
                        id: copyIpButton
                        visible: card.device.tailscaleIPs?.length > 0
                        symbol: "content_copy"
                        tooltipText: Translation.tr("Copy IP")
                        onClicked: {
                            root.copyIP(card.device.tailscaleIPs[0])
                            copyIpButton.symbol = "inventory"
                            copyIpResetTimer.restart()
                        }
                        Timer {
                            id: copyIpResetTimer
                            interval: 1500
                            repeat: false
                            onTriggered: copyIpButton.symbol = "content_copy"
                        }
                    }
                    DeviceActionButton {
                        visible: card.online && !card.device.isSelf
                        symbol: "network_check"
                        tooltipText: Translation.tr("Ping")
                        onClicked: root.pingDevice(card.device.nodeId, card.target)
                    }
                    DeviceActionButton {
                        visible: card.online && !card.device.isSelf && card.device.os === "linux"
                        symbol: "terminal"
                        tooltipText: Translation.tr("SSH")
                        onClicked: root.sshDevice(card.target)
                    }
                    DeviceActionButton {
                        visible: card.online && !card.device.isSelf
                        symbol: "send"
                        tooltipText: Translation.tr("Send file")
                        onClicked: root.sendFile(card.target)
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
