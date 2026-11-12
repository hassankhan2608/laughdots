import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

DialogListItem {
    id: root

    required property var profile
    property bool confirmingDelete: false

    readonly property bool pending: Vpn.busy
        && (Vpn.pendingUuid === "" || Vpn.pendingUuid === profile.uuid)

    active: profile.active
    enabled: !Vpn.importing && (!Vpn.busy || pending)
    onClicked: Vpn.toggleProfile(profile.uuid)

    Timer {
        id: deleteConfirmationTimer
        interval: 3000
        onTriggered: root.confirmingDelete = false
    }

    contentItem: RowLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 10

        Item {
            implicitWidth: Appearance.font.pixelSize.larger
            implicitHeight: Appearance.font.pixelSize.larger

            MaterialSymbol {
                anchors.centerIn: parent
                visible: !root.pending
                text: root.profile.active ? "vpn_lock" : "vpn_key_off"
                iconSize: Appearance.font.pixelSize.larger
                color: root.profile.active
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnSurfaceVariant
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.pending
                text: "progress_activity"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colPrimary

                RotationAnimation on rotation {
                    running: root.pending
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: -2

            StyledText {
                Layout.fillWidth: true
                text: root.profile.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Appearance.colors.colOnSurfaceVariant
                font.weight: Font.Medium
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    if (root.confirmingDelete)
                        return Translation.tr("Click delete again to confirm")
                    if (root.pending && Vpn.pendingOperation === "connect")
                        return Translation.tr("Connecting...")
                    if (root.pending && Vpn.pendingOperation === "disconnect")
                        return Translation.tr("Disconnecting...")
                    if (root.profile.active)
                        return root.profile.device
                            ? `${Translation.tr("Connected")} · ${root.profile.device}`
                            : Translation.tr("Connected")
                    return root.profile.typeName
                }
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.confirmingDelete
                    ? Appearance.colors.colError
                    : Appearance.colors.colOnSurfaceVariant
                opacity: root.confirmingDelete ? 1 : 0.6
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }

        StyledSwitch {
            id: profileSwitch
            enabled: !Vpn.busy && !Vpn.importing
            onClicked: Vpn.toggleProfile(root.profile.uuid)

            Binding {
                target: profileSwitch
                property: "checked"
                value: root.profile.active
                restoreMode: Binding.RestoreBinding
            }
        }

        RippleButton {
            visible: !root.profile.active
            enabled: !Vpn.busy && !Vpn.importing
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            colBackground: root.confirmingDelete
                ? Appearance.colors.colErrorContainer
                : "transparent"
            colBackgroundHover: root.confirmingDelete
                ? Appearance.colors.colErrorContainerHover
                : Appearance.colors.colLayer3Hover
            colRipple: root.confirmingDelete
                ? Appearance.colors.colErrorContainerActive
                : Appearance.colors.colLayer3Active
            onClicked: {
                if (root.confirmingDelete) {
                    Vpn.deleteProfile(root.profile.uuid)
                    root.confirmingDelete = false
                    return
                }
                root.confirmingDelete = true
                deleteConfirmationTimer.restart()
            }

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: root.confirmingDelete ? "delete_forever" : "delete"
                iconSize: Appearance.font.pixelSize.normal
                color: root.confirmingDelete
                    ? Appearance.colors.colError
                    : Appearance.colors.colOnSurfaceVariant
            }
        }
    }
}
