import Foundation
import SystemConfiguration

/// Decides whether traffic is going over Wi-Fi: a Wi-Fi interface has a routable
/// address and no wired Ethernet interface does. Works with VPNs, where the
/// primary interface is a utun and says nothing about the physical link.
final class NetworkWatcher {
    private let queue: DispatchQueue
    private var store: SCDynamicStore?
    private(set) var onWiFi = false

    var onChange: ((Bool) -> Void)?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func start() {
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            Unmanaged<NetworkWatcher>.fromOpaque(info).takeUnretainedValue().refresh()
        }
        guard let store = SCDynamicStoreCreate(nil, "awdl-guardd" as CFString, callback, &context) else {
            return
        }
        let patterns = [
            "State:/Network/Interface/[^/]+/IPv4",
            "State:/Network/Interface/[^/]+/IPv6",
            "State:/Network/Global/IPv4",
        ] as CFArray
        SCDynamicStoreSetNotificationKeys(store, nil, patterns)
        SCDynamicStoreSetDispatchQueue(store, queue)
        self.store = store
        refresh()
    }

    func refresh() {
        guard let store else { return }
        var wifi = false
        var wired = false
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        for iface in interfaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(iface) as String?,
                  let type = SCNetworkInterfaceGetInterfaceType(iface) as String? else { continue }
            let isWiFi = type == (kSCNetworkInterfaceTypeIEEE80211 as String)
            let isWired = type == (kSCNetworkInterfaceTypeEthernet as String)
            guard isWiFi || isWired, Self.hasRoutableAddress(store: store, bsdName: bsd) else { continue }
            if isWiFi { wifi = true } else { wired = true }
        }
        let value = wifi && !wired
        if value != onWiFi {
            onWiFi = value
            onChange?(value)
        }
    }

    private static func hasRoutableAddress(store: SCDynamicStore, bsdName: String) -> Bool {
        func addresses(_ family: String) -> [String] {
            let key = "State:/Network/Interface/\(bsdName)/\(family)" as CFString
            let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any]
            return dict?["Addresses"] as? [String] ?? []
        }
        let v4 = addresses("IPv4").filter { !$0.hasPrefix("169.254.") }
        let v6 = addresses("IPv6").filter { !$0.lowercased().hasPrefix("fe80") }
        return !v4.isEmpty || !v6.isEmpty
    }
}
