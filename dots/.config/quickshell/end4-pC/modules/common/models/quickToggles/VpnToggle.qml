import QtQuick
import qs.modules.common
import qs.services

QuickToggleModel {
    name: Translation.tr("VPN")
    statusText: Vpn.profiles.length === 0
        ? Translation.tr("No profiles")
        : Vpn.statusText
    tooltipText: Vpn.profiles.length === 0
        ? Translation.tr("VPN | Open to import a configuration")
        : Translation.tr("%1 | Open to manage VPN connections").arg(Vpn.statusText)
    icon: Vpn.connected ? "vpn_lock" : "vpn_key"

    toggled: Vpn.connected
    mainAction: () => Vpn.togglePreferred()
    hasMenu: true
}
