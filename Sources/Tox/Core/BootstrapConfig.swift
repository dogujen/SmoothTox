import Foundation

struct BootstrapConfig: Decodable {
    let bootstrapNodes: [BootstrapNode]
    let network: NetworkConfig
    let ui: UIConfig

    init(
        bootstrapNodes: [BootstrapNode],
        network: NetworkConfig = .init(),
        ui: UIConfig = .init()
    ) {
        self.bootstrapNodes = bootstrapNodes
        self.network = network
        self.ui = ui
    }

    enum CodingKeys: String, CodingKey {
        case bootstrapNodes
        case network
        case ui
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bootstrapNodes = try container.decodeIfPresent([BootstrapNode].self, forKey: .bootstrapNodes) ?? []
        network = try container.decodeIfPresent(NetworkConfig.self, forKey: .network) ?? .init()
        ui = try container.decodeIfPresent(UIConfig.self, forKey: .ui) ?? .init()
    }
}

struct NetworkConfig: Decodable {
    let tor: TorProxyConfig
    let customProxy: CustomProxyConfig

    init(tor: TorProxyConfig = .init(), customProxy: CustomProxyConfig = .init()) {
        self.tor = tor
        self.customProxy = customProxy
    }

    var effectiveProxy: ProxyRuntimeConfig {
        if tor.enabled {
            return .init(type: .socks5, host: tor.host, port: tor.port)
        }

        if customProxy.enabled {
            return .init(type: customProxy.type, host: customProxy.host, port: customProxy.port)
        }

        return .disabled
    }
}

struct TorProxyConfig: Decodable {
    let enabled: Bool
    let host: String
    let port: UInt16

    init(enabled: Bool = false, host: String = "127.0.0.1", port: UInt16 = 9050) {
        self.enabled = enabled
        self.host = host
        self.port = port
    }
}

struct CustomProxyConfig: Decodable {
    let enabled: Bool
    let type: ProxyType
    let host: String
    let port: UInt16

    init(enabled: Bool = false, type: ProxyType = .socks5, host: String = "127.0.0.1", port: UInt16 = 1080) {
        self.enabled = enabled
        self.type = type
        self.host = host
        self.port = port
    }
}

struct UIConfig: Decodable {
    let messageBubbleMinHeight: Double

    init(messageBubbleMinHeight: Double = 44) {
        self.messageBubbleMinHeight = messageBubbleMinHeight
    }
}

enum ProxyType: String, Decodable {
    case http
    case socks5
}

struct ProxyRuntimeConfig {
    let type: ProxyType?
    let host: String
    let port: UInt16

    static let disabled = ProxyRuntimeConfig(type: nil, host: "", port: 0)

    var isEnabled: Bool { type != nil }
}

struct BootstrapNode: Decodable {
    let host: String
    let port: UInt16
    let publicKey: String
}

enum BootstrapConfigLoader {
    static func loadFromBundle() -> BootstrapConfig {
        guard let url = Bundle.module.url(forResource: "config", withExtension: "json") else {
            return BootstrapConfig(bootstrapNodes: [])
        }

        guard let data = try? Data(contentsOf: url) else {
            return BootstrapConfig(bootstrapNodes: [])
        }

        let decoder = JSONDecoder()
        guard let config = try? decoder.decode(BootstrapConfig.self, from: data) else {
            return BootstrapConfig(bootstrapNodes: [])
        }

        return config
    }
}