pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

Singleton {
    id: root

    signal dialogRequested()

    property var profiles: []
    property string preferredUuid: ""
    property string pendingUuid: ""
    property string pendingOperation: ""
    property string lastError: ""
    property bool initialRefreshComplete: false
    property bool restoreAttempted: false

    readonly property bool refreshing: refreshProcess.running
    readonly property bool busy: actionProcess.running
    readonly property bool importing: importProcess.running
    readonly property var activeProfiles: profiles.filter(profile => profile.active)
    readonly property bool connected: activeProfiles.length > 0
    readonly property string activeName: activeProfiles[0]?.name ?? ""
    readonly property string statusText: {
        if (busy && pendingOperation === "connect") return Translation.tr("Connecting...")
        if (busy && pendingOperation === "disconnect") return Translation.tr("Disconnecting...")
        if (connected) return activeName
        return Translation.tr("Disconnected")
    }

    readonly property var importTypes: [
        { id: "wireguard", name: "WireGuard", extensions: ["*.conf"] },
        { id: "openvpn", name: "OpenVPN", extensions: ["*.ovpn", "*.conf"] },
        { id: "openconnect", name: "OpenConnect", extensions: ["*.xml", "*.conf"] },
        { id: "vpnc", name: "Cisco VPN (vpnc)", extensions: ["*.pcf", "*.conf"] },
        { id: "fortisslvpn", name: "Fortinet SSLVPN", extensions: ["*.conf"] },
        { id: "libreswan", name: "IPsec (Libreswan)", extensions: ["*.conf"] },
        { id: "strongswan", name: "IPsec (strongSwan)", extensions: ["*.conf"] },
        { id: "l2tp", name: "L2TP", extensions: ["*.conf"] },
        { id: "pptp", name: "PPTP", extensions: ["*.conf"] },
        { id: "sstp", name: "SSTP", extensions: ["*.conf"] },
        { id: "iodine", name: "Iodine", extensions: ["*.conf"] },
        { id: "ssh", name: "SSH tunnel", extensions: ["*.conf"] }
    ]

    function splitEscaped(line) {
        const fields = []
        let field = ""
        let escaped = false

        for (let index = 0; index < line.length; index++) {
            const character = line[index]
            if (escaped) {
                field += character
                escaped = false
            } else if (character === "\\") {
                escaped = true
            } else if (character === ":") {
                fields.push(field)
                field = ""
            } else {
                field += character
            }
        }

        if (escaped) field += "\\"
        fields.push(field)
        return fields
    }

    function applyProfileOutput(output) {
        const nextProfiles = []
        for (const line of output.trim().split("\n")) {
            if (!line) continue
            const fields = splitEscaped(line)
            if (fields.length < 4) continue

            const type = fields[2]
            if (type !== "vpn" && type !== "wireguard") continue

            const device = fields.slice(3).join(":")
            nextProfiles.push({
                name: fields[0],
                uuid: fields[1],
                type: type,
                typeName: type === "wireguard" ? "WireGuard" : "VPN",
                device: device === "--" ? "" : device,
                active: device !== "" && device !== "--"
            })
        }

        nextProfiles.sort((left, right) => {
            if (left.active !== right.active) return left.active ? -1 : 1
            return left.name.localeCompare(right.name)
        })
        profiles = nextProfiles

        const activeProfile = nextProfiles.find(profile => profile.active)
        if (activeProfile) {
            preferredUuid = activeProfile.uuid
        } else if (!nextProfiles.some(profile => profile.uuid === preferredUuid)) {
            preferredUuid = nextProfiles[0]?.uuid ?? ""
        }
        if (!initialRefreshComplete) initialRefreshComplete = true
        if (!restorePreviousConnection()) saveCurrentConnection()
    }


    function clearSavedConnection() {
        if (!Persistent.ready) return
        Persistent.states.vpn.restoreOnStartup = false
        Persistent.states.vpn.lastConnectedUuid = ""
    }

    function saveCurrentConnection() {
        if (!Persistent.ready || !restoreAttempted || busy || pendingOperation !== "") return
        const activeProfile = profiles.find(profile => profile.active)
        Persistent.states.vpn.restoreOnStartup = activeProfile !== undefined
        Persistent.states.vpn.lastConnectedUuid = activeProfile?.uuid ?? ""
    }

    function restorePreviousConnection() {
        if (restoreAttempted || !initialRefreshComplete || !Persistent.ready) return false
        restoreAttempted = true

        const activeProfile = profiles.find(profile => profile.active)
        if (activeProfile) {
            saveCurrentConnection()
            return false
        }

        const savedUuid = Persistent.states.vpn.lastConnectedUuid
        if (Persistent.states.vpn.restoreOnStartup && profileForUuid(savedUuid)) {
            connectProfile(savedUuid)
            return true
        }

        clearSavedConnection()
        return false
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready && !root.restorePreviousConnection()) {
                root.saveCurrentConnection()
            }
        }

    }

    function profileForUuid(uuid) {
        return profiles.find(profile => profile.uuid === uuid) ?? null
    }

    function refreshProfiles() {
        if (!refreshProcess.running) refreshProcess.running = true
    }

    function startAction(operation, uuid, command) {
        if (busy || importing) return
        pendingOperation = operation
        pendingUuid = uuid
        lastError = ""
        actionProcess.exec(command)
    }

    function connectProfile(uuid) {
        if (!profileForUuid(uuid)) return
        preferredUuid = uuid
        startAction("connect", uuid, [
            "nmcli", "--wait", "15", "connection", "up", "uuid", uuid
        ])
    }

    function disconnectProfile(uuid) {
        if (!profileForUuid(uuid)) return
        if (busy || importing) return
        clearSavedConnection()
        startAction("disconnect", uuid, [
            "nmcli", "--wait", "10", "connection", "down", "uuid", uuid
        ])
    }

    function disconnectAll() {
        if (activeProfiles.length === 0 || busy || importing) return
        clearSavedConnection()
        const command = ["nmcli", "--wait", "10", "connection", "down"]
        for (const profile of activeProfiles) command.push("uuid", profile.uuid)
        startAction("disconnect", "", command)
    }

    function toggleProfile(uuid) {
        const profile = profileForUuid(uuid)
        if (!profile) return
        if (profile.active) disconnectProfile(uuid)
        else connectProfile(uuid)
    }

    function togglePreferred() {
        if (connected) {
            disconnectAll()
            return
        }

        const profile = profileForUuid(preferredUuid) ?? profiles[0] ?? null
        if (profile) connectProfile(profile.uuid)
        else dialogRequested()
    }

    function deleteProfile(uuid) {
        if (!profileForUuid(uuid)) return
        startAction("delete", uuid, [
            "nmcli", "connection", "delete", "uuid", uuid
        ])
    }

    function importProfile(type, filePath) {
        if (busy || importing || !filePath) return
        if (!importTypes.some(importType => importType.id === type)) {
            lastError = Translation.tr("Unsupported VPN type")
            return
        }

        lastError = ""
        importProcess.importType = type
        importProcess.filePath = filePath
        importProcess.exec([
            "nmcli", "connection", "import", "type", type, "file", filePath
        ])
    }

    function fileFilter(type) {
        const importType = importTypes.find(candidate => candidate.id === type)
        if (!importType) return Translation.tr("VPN configuration") + " (*.conf *.ovpn)"
        return `${importType.name} (${importType.extensions.join(" ")})`
    }

    function operationError(stderrText, fallback) {
        const message = stderrText.trim().replace(/^Error:\s*/, "")
        return message || fallback
    }

    function importedUuid(output) {
        const match = output.match(/\(([0-9a-fA-F-]{36})\)/)
        return match?.[1] ?? ""
    }

    Process {
        id: refreshProcess
        running: true
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: root.applyProfileOutput(text)
        }
    }

    Timer {
        interval: 3000
        repeat: true
        triggeredOnStart: true
        running: GlobalStates.sidebarRightOpen
        onTriggered: root.refreshProfiles()
    }

    Process {
        id: actionProcess
        stderr: StdioCollector { id: actionError }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.lastError = root.operationError(
                    actionError.text,
                    Translation.tr("VPN operation failed")
                )
            }
            root.pendingOperation = ""
            root.pendingUuid = ""
            root.refreshProfiles()
        }
    }

    Process {
        id: importProcess
        property string importType: ""
        property string filePath: ""
        stdout: StdioCollector { id: importOutput }
        stderr: StdioCollector { id: importError }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.lastError = root.operationError(
                    importError.text,
                    Translation.tr("Failed to import VPN configuration")
                )
                root.refreshProfiles()
                return
            }

            const uuid = root.importedUuid(importOutput.text)
            if (uuid === "") {
                root.refreshProfiles()
                return
            }

            importedProfileSetup.exec([
                "nmcli", "connection", "modify", "uuid", uuid,
                "connection.autoconnect", "no"
            ])
        }
    }

    Process {
        id: importedProfileSetup
        stderr: StdioCollector { id: importedProfileSetupError }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.lastError = root.operationError(
                    importedProfileSetupError.text,
                    Translation.tr("Failed to disable VPN autoconnect")
                )
            }
            root.refreshProfiles()
        }
    }
}
