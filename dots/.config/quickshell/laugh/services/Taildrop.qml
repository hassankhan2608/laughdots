pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Taildrop inbox watcher. Lists files waiting in tailscaled's inbox
 * (read-only via the local API) and moves them into ~/Tailnet on demand.
 */
Singleton {
    id: root

    property var waitingFiles: []
    readonly property int count: waitingFiles.length
    property bool receiving: false
    readonly property alias refreshing: listProc.running
    property int notifiedCount: 0
    readonly property string targetDir: (Quickshell.env("HOME") || "") + "/Tailnet"

    function formatSize(bytes): string {
        if (!bytes || bytes < 0) return "-"
        const units = ["B", "KB", "MB", "GB"]
        let i = 0
        let v = bytes
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024
            i++
        }
        return v.toFixed(i === 0 ? 0 : 1) + " " + units[i]
    }

    function refresh(): void {
        listProc.running = true
    }

    function receiveAll(): void {
        if (root.receiving) return
        root.receiving = true
        receiveProc.exec(["bash", "-c",
            `mkdir -p '${root.targetDir}' && tailscale file get --conflict=rename --verbose '${root.targetDir}'`])
    }

    function receiveFile(name: string): void {
        if (root.receiving) return
        root.receiving = true
        singleRecvProc.fileName = name
        const url = "http://local-tailscaled.sock/localapi/v0/files/" + encodeURIComponent(name)
        singleRecvProc.exec(["bash", "-c",
            `d="${root.targetDir}"; mkdir -p "$d"; n="$1"; out="$d/$n"; ` +
            `[ -e "$out" ] && out="$d/$(date +%s)-$n"; ` +
            `curl -sf --unix-socket /var/run/tailscale/tailscaled.sock -o "$out" "${url}" && ` +
            `curl -sf -X DELETE --unix-socket /var/run/tailscale/tailscaled.sock "${url}"`,
            "_", name])
    }

    Process {
        id: listProc
        command: ["curl", "-s", "--unix-socket", "/var/run/tailscale/tailscaled.sock",
            "http://local-tailscaled.sock/localapi/v0/files/"]
        stdout: StdioCollector {
            id: listCollector
            onStreamFinished: {
                if (root === null) return
                let files = []
                try {
                    const data = JSON.parse(listCollector.text || "null")
                    if (Array.isArray(data)) files = data
                } catch (e) {} // tailscaled down or no access; treat as empty
                root.waitingFiles = files
                if (files.length > root.notifiedCount) {
                    Quickshell.execDetached(["notify-send", Translation.tr("Taildrop"),
                        Translation.tr("%1 file(s) waiting to be received").arg(files.length),
                        "-a", "Shell"])
                }
                root.notifiedCount = files.length
            }
        }
    }

    Process {
        id: receiveProc
        stdout: StdioCollector {
            id: recvCollector
        }
        onExited: (exitCode, exitStatus) => {
            if (root === null) return
            root.receiving = false
            const out = recvCollector.text.trim()
            const m = out.match(/moved (\d+)\/(\d+) files/)
            if (exitCode === 0 && m && parseInt(m[1]) > 0) {
                Quickshell.execDetached(["notify-send", Translation.tr("Taildrop"),
                    Translation.tr("Received %1 file(s) into %2").arg(m[1]).arg("~/Tailnet"),
                    "-a", "Shell"])
            } else if (exitCode !== 0) {
                Quickshell.execDetached(["notify-send", Translation.tr("Taildrop"),
                    Translation.tr("Receive failed: %1").arg(out || Translation.tr("unknown error")),
                    "-a", "Shell"])
            }
            root.refresh()
        }
    }

    Process {
        id: singleRecvProc
        property string fileName: ""
        onExited: (exitCode, exitStatus) => {
            if (root === null) return
            root.receiving = false
            Quickshell.execDetached(["notify-send", Translation.tr("Taildrop"),
                exitCode === 0
                    ? Translation.tr("Received %1 into %2").arg(singleRecvProc.fileName).arg("~/Tailnet")
                    : Translation.tr("Failed to receive %1").arg(singleRecvProc.fileName),
                "-a", "Shell"])
            root.refresh()
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
