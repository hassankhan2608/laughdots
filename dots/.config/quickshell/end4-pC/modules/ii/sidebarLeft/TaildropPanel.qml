pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.calendar
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Taildrop inbox panel, styled after the right sidebar's bottom widget group:
 * fixed height, collapsible to a slim summary bar, calendar-style header.
 */
Rectangle {
    id: root
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    clip: true

    property bool collapsed: Persistent.states.sidebar.taildropCollapsed
    implicitHeight: collapsed ? collapsedRow.implicitHeight : 350

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }

    function setCollapsed(state: bool): void {
        Persistent.states.sidebar.taildropCollapsed = state
    }

    component RailButton: CalendarHeaderButton {
        property string symbol
        forceCircle: true
        contentItem: MaterialSymbol {
            text: (parent as RailButton)?.symbol ?? ""
            iconSize: Appearance.font.pixelSize.larger
            horizontalAlignment: Text.AlignHCenter
            color: Appearance.colors.colOnLayer1
        }
    }

    // ---- collapsed bar ----
    RowLayout {
        id: collapsedRow
        opacity: root.collapsed ? 1 : 0
        visible: opacity > 0
        spacing: 15
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration / 2
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }

        RailButton {
            Layout.margins: 10
            Layout.rightMargin: 0
            symbol: "keyboard_arrow_up"
            tooltipText: Translation.tr("Expand")
            downAction: () => root.setCollapsed(false)
        }

        StyledText {
            Layout.margins: 10
            Layout.leftMargin: 0
            text: Taildrop.count > 0
                ? Translation.tr("%1 file(s) waiting").arg(Taildrop.count)
                : Translation.tr("No incoming files")
            font.pixelSize: Appearance.font.pixelSize.large
            font.weight: Taildrop.count > 0 ? Font.Medium : Font.Normal
            color: Taildrop.count > 0 ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
        }
    }

    // ---- expanded ----
    ColumnLayout {
        opacity: root.collapsed ? 0 : 1
        visible: opacity > 0
        anchors {
            fill: parent
            margins: 10
        }
        spacing: 6
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration / 2
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }

        // header: collapse | title chip | folder + refresh
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            RailButton {
                symbol: "keyboard_arrow_down"
                tooltipText: Translation.tr("Collapse")
                downAction: () => root.setCollapsed(true)
            }
            Item { Layout.fillWidth: true }
            CalendarHeaderButton {
                clip: true
                buttonText: Taildrop.count > 0
                    ? Translation.tr("Incoming files (%1)").arg(Taildrop.count)
                    : Translation.tr("Incoming files")
            }
            Item { Layout.fillWidth: true }
            RailButton {
                tooltipText: Translation.tr("Open ~/Tailnet")
                symbol: "folder_open"
                downAction: () => Quickshell.execDetached(["xdg-open", Taildrop.targetDir])
            }
            RailButton {
                id: refreshButton
                tooltipText: Translation.tr("Check for new files")
                symbol: "refresh"
                downAction: () => {
                    refreshSpin.restart()
                    Taildrop.refresh()
                }
                RotationAnimation {
                    id: refreshSpin
                    target: refreshButton.contentItem
                    from: 0
                    to: 360
                    duration: 500
                    easing.type: Easing.OutCubic
                }
            }
        }

        // busy indicator while receiving
        StyledIndeterminateProgressBar {
            visible: Taildrop.receiving
            Layout.fillWidth: true
        }

        // empty state
        ColumnLayout {
            visible: Taildrop.count === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4

            Item { Layout.fillHeight: true }
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "inbox"
                iconSize: 48
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("No incoming files")
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Files sent to this device land in %1").arg("~/Tailnet")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
            Item { Layout.fillHeight: true }
        }

        // file list
        StyledListView {
            visible: Taildrop.count > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            animateAppearance: false

            model: ScriptModel {
                objectProp: "Name"
                values: Taildrop.waitingFiles
            }
            delegate: Rectangle {
                id: fileRow
                required property var modelData
                required property int index
                width: ListView.view?.width ?? 0
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                implicitHeight: rowContent.implicitHeight + 12

                RowLayout {
                    id: rowContent
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10
                        rightMargin: 6
                    }
                    spacing: 10

                    StyledText {
                        Layout.preferredWidth: 18
                        horizontalAlignment: Text.AlignHCenter
                        text: fileRow.index + 1
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: fileRow.modelData.Name || "?"
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideMiddle
                        }
                        StyledText {
                            text: Taildrop.formatSize(fileRow.modelData.Size)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                    CalendarHeaderButton {
                        forceCircle: true
                        enabled: !Taildrop.receiving
                        tooltipText: Translation.tr("Receive %1").arg(fileRow.modelData.Name)
                        downAction: () => Taildrop.receiveFile(fileRow.modelData.Name)
                        contentItem: MaterialSymbol {
                            text: "download"
                            iconSize: Appearance.font.pixelSize.larger
                            horizontalAlignment: Text.AlignHCenter
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }

        // receive all
        DialogButton {
            visible: Taildrop.count > 0
            Layout.fillWidth: true
            enabled: !Taildrop.receiving
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            colText: Appearance.colors.colOnPrimary
            buttonText: Taildrop.receiving
                ? Translation.tr("Receiving...")
                : Translation.tr("Receive all (%1)").arg(Taildrop.count)
            onClicked: Taildrop.receiveAll()
        }
    }
}
