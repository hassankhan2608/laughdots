import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

QuickToggleButton {
    toggled: Vpn.connected
    buttonIcon: Vpn.connected ? "vpn_lock" : "vpn_key"
    onClicked: Vpn.togglePreferred()

    StyledToolTip {
        text: Vpn.profiles.length === 0
            ? Translation.tr("VPN | Right-click to import a configuration")
            : Translation.tr("%1 | Right-click to manage").arg(Vpn.statusText)
    }
}
