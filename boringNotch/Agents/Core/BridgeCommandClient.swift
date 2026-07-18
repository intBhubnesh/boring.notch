//
//  BridgeCommandClient.swift
//  boringNotch
//
//  Lightweight client used by tests and mirrored by the hook CLI.
//

import Darwin
import Foundation

enum BridgeCommandClientError: Error {
    case socketCreationFailed
    case connectFailed(errno: Int32)
    case sendFailed(errno: Int32)
}

struct BridgeCommandClient {
    var socketPath: String = AgentBridgeTransport.socketPath

    func send(_ message: AgentBridgeMessage) throws {
        let data = try AgentBridgeTransport.encoder.encode(message) + Data([0x0A])
        try send(data)
    }

    func send(_ data: Data) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeCommandClientError.socketCreationFailed }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let sunPathSize = MemoryLayout.size(ofValue: address.sun_path)
        try socketPath.withCString { pathPointer in
            guard strlen(pathPointer) < sunPathSize else {
                throw BridgeCommandClientError.connectFailed(errno: ENAMETOOLONG)
            }
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                destination.withMemoryRebound(to: CChar.self, capacity: sunPathSize) {
                    strcpy($0, pathPointer)
                }
            }
        }

        let addressLength = socklen_t(MemoryLayout<sa_family_t>.size + strlen(socketPath) + 1)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, addressLength)
            }
        }
        guard connected == 0 else { throw BridgeCommandClientError.connectFailed(errno: errno) }

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var totalSent = 0
            while totalSent < data.count {
                let sent = Darwin.send(fd, baseAddress.advanced(by: totalSent), data.count - totalSent, 0)
                guard sent > 0 else { throw BridgeCommandClientError.sendFailed(errno: errno) }
                totalSent += sent
            }
        }
    }
}
