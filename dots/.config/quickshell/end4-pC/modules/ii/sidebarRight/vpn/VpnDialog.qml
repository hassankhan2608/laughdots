import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

WindowDialog {
    id: root

    backgroundHeight: 620
    readonly property var selectedImportType: Vpn.importTypes[importTypeCombo.currentIndex]
        ?? Vpn.importTypes[0]

    Component.onCompleted: Vpn.refreshProfiles()

    Process {
        id: fileChooser
        property string importType: "wireguard"

        function choose(type) {
            importType = type
            command = [
                "kdialog",
                "--getopenfilename",
                Quickshell.env("HOME"),
                Vpn.fileFilter(type)
            ]
            running = true
        }

        stdout: StdioCollector { id: fileChooserOutput }
        onExited: exitCode => {
            if (exitCode !== 0) return
            let path = fileChooserOutput.text.trim()
            if (path.startsWith("file://")) path = path.slice(7)
            if (path) Vpn.importProfile(importType, path)
        }
    }

    WindowDialogTitle {
        text: Translation.tr("VPN connections")
    }

    WindowDialogSeparator {
        visible: !(Vpn.refreshing || Vpn.busy || Vpn.importing)
    }

    StyledIndeterminateProgressBar {
        visible: Vpn.refreshing || Vpn.busy || Vpn.importing
        Layout.fillWidth: true
        Layout.topMargin: -8
        Layout.bottomMargin: -8
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Import a VPN configuration")
            color: Appearance.colors.colOnSurfaceVariant
            font.weight: Font.Medium
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledComboBox {
                id: importTypeCombo
                Layout.fillWidth: true
                model: Vpn.importTypes
                textRole: "name"
                currentIndex: 0
                buttonIcon: "vpn_key"
                enabled: !Vpn.busy && !Vpn.importing
            }

            DialogButton {
                enabled: !Vpn.busy && !Vpn.importing
                buttonText: Vpn.importing
                    ? Translation.tr("Importing...")
                    : Translation.tr("Choose file")
                onClicked: fileChooser.choose(root.selectedImportType.id)
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("The selected NetworkManager plugin must be installed. WireGuard is supported natively.")
            color: Appearance.colors.colOnSurfaceVariant
            opacity: 0.6
            font.pixelSize: Appearance.font.pixelSize.smallest
            wrapMode: Text.WordWrap
        }
    }

    Rectangle {
        visible: Vpn.lastError !== ""
        Layout.fillWidth: true
        implicitHeight: errorText.implicitHeight + 20
        radius: Appearance.rounding.small
        color: Appearance.colors.colErrorContainer

        StyledText {
            id: errorText
            anchors {
                fill: parent
                margins: 10
            }
            text: Vpn.lastError
            textFormat: Text.PlainText
            color: Appearance.colors.colOnErrorContainer
            font.pixelSize: Appearance.font.pixelSize.smaller
            wrapMode: Text.WordWrap
        }
    }

    RowLayout {
        Layout.fillWidth: true

        StyledText {
            Layout.fillWidth: true
            text: Vpn.connected
                ? Translation.tr("Active: %1").arg(Vpn.activeName)
                : Translation.tr("Saved VPN profiles")
            color: Appearance.colors.colOnSurfaceVariant
            font.weight: Font.Medium
        }

        DialogButton {
            visible: Vpn.connected
            enabled: !Vpn.busy && !Vpn.importing
            buttonText: Translation.tr("Disconnect all")
            onClicked: Vpn.disconnectAll()
        }
    }

    Item {
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -6
        Layout.bottomMargin: -8
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large

        ColumnLayout {
            anchors.centerIn: parent
            visible: !Vpn.refreshing && Vpn.profiles.length === 0
            spacing: 6

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "vpn_key_off"
                iconSize: 40
                color: Appearance.colors.colOnSurfaceVariant
                opacity: 0.6
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("No VPN profiles")
                color: Appearance.colors.colOnSurfaceVariant
                font.weight: Font.Medium
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Choose a VPN type and import its configuration file")
                color: Appearance.colors.colOnSurfaceVariant
                opacity: 0.6
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }

        ListView {
            anchors.fill: parent
            visible: Vpn.profiles.length > 0
            clip: true
            spacing: 0

            model: ScriptModel {
                values: Vpn.profiles
                objectProp: "uuid"
            }

            delegate: VpnProfileItem {
                required property var modelData
                profile: modelData
                width: ListView.view.width
            }
        }
    }

    WindowDialogSeparator {}

    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Network settings")
            onClicked: {
                Quickshell.execDetached([
                    "bash", "-c",
                    `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`
                ])
                GlobalStates.sidebarRightOpen = false
            }
        }

        Item { Layout.fillWidth: true }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
