import Foundation
import Cocoa
import AsyncXPCConnection

final class XPCHelperClient: NSObject {
    nonisolated static let shared = XPCHelperClient()
    
    private let serviceName = "theboringteam.boringnotch.BoringNotchXPCHelper"
    
    private var remoteService: RemoteXPCService<BoringNotchXPCHelperProtocol>?
    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?
    private var monitoringTask: Task<Void, Never>?
    
    deinit {
        connection?.invalidate()
        stopMonitoringAccessibilityAuthorization()
    }
    
    // MARK: - Connection Management (Main Actor Isolated)
    
    @MainActor
    private func ensureRemoteService() -> RemoteXPCService<BoringNotchXPCHelperProtocol> {
        if let existing = remoteService {
            return existing
        }
        
        let conn = NSXPCConnection(serviceName: serviceName)
        
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }
        
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }
        
        conn.resume()
        
        let service = RemoteXPCService<BoringNotchXPCHelperProtocol>(
            connection: conn,
            remoteInterface: BoringNotchXPCHelperProtocol.self
        )
        
        connection = conn
        remoteService = service
        return service
    }
    
    @MainActor
    private func getRemoteService() -> RemoteXPCService<BoringNotchXPCHelperProtocol>? {
        remoteService
    }
    
    @MainActor
    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": granted]
        )
    }

    // MARK: - Monitoring
    nonisolated func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        // Ensure only one monitor exists
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Call the helper method periodically which will notify on change
                _ = await self.isAccessibilityAuthorized()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { break }
            }
        }
    }

    nonisolated func stopMonitoringAccessibilityAuthorization() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // Expose whether the client is actively monitoring (useful for tests/debug)
    var isMonitoring: Bool {
        return monitoringTask != nil
    }
    
    // MARK: - Accessibility
    
    nonisolated func requestAccessibilityAuthorization() {
        Task {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            try? await service.withService { service in
                service.requestAccessibilityAuthorization()
            }
        }
    }
    
    nonisolated func isAccessibilityAuthorized() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.isAccessibilityAuthorized { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.ensureAccessibilityAuthorization(promptIfNeeded) { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    // MARK: - Keyboard Brightness
    
    nonisolated func isKeyboardBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isKeyboardBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentKeyboardBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentKeyboardBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
    
    // MARK: - Screen Brightness
    
    nonisolated func isScreenBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isScreenBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentScreenBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentScreenBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }

    // MARK: - Agent Hook Installation

    nonisolated func agentHookStatus(for tool: String) async throws -> AgentHookStatus {
        let service = await MainActor.run {
            ensureRemoteService()
        }
        let configRootPath = agentConfigRootPath(for: tool)
        let result: Result<AgentHookStatus, Error> = try await service.withContinuation { service, continuation in
            service.agentHookStatus(forTool: tool, configRootPath: configRootPath) { status in
                continuation.resume(returning: Self.agentHookResult(status: status))
            }
        }
        return try result.get()
    }

    nonisolated func installAgentHooks(for tool: String) async throws -> AgentHookStatus {
        let service = await MainActor.run {
            ensureRemoteService()
        }
        let sourcePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/BoringNotchAgentHooks")
            .path
        let configRootPath = agentConfigRootPath(for: tool)
        let result: Result<AgentHookStatus, Error> = try await service.withContinuation { service, continuation in
            service.installAgentHooks(forTool: tool, hookBinarySourcePath: sourcePath, configRootPath: configRootPath) { status in
                continuation.resume(returning: Self.agentHookResult(status: status))
            }
        }
        return try result.get()
    }

    nonisolated func uninstallAgentHooks(for tool: String) async throws -> AgentHookStatus {
        let service = await MainActor.run {
            ensureRemoteService()
        }
        let configRootPath = agentConfigRootPath(for: tool)
        let result: Result<AgentHookStatus, Error> = try await service.withContinuation { service, continuation in
            service.uninstallAgentHooks(forTool: tool, configRootPath: configRootPath) { status in
                continuation.resume(returning: Self.agentHookResult(status: status))
            }
        }
        return try result.get()
    }

    nonisolated func runningAgentProcesses() async throws -> [AgentProcessSnapshot] {
        let service = await MainActor.run {
            ensureRemoteService()
        }
        let result: Result<[AgentProcessSnapshot], Error> = try await service.withContinuation { service, continuation in
            service.runningAgentProcesses { data in
                let observedAt = Date()
                let object = Self.agentPayloadObject(data: data)
                let snapshots = (object as? [[String: Any]])?.compactMap {
                    AgentProcessSnapshot(xpcDictionary: $0, observedAt: observedAt)
                } ?? []
                continuation.resume(returning: .success(snapshots))
            }
        }
        return try result.get()
    }

    nonisolated func terminateAgentProcess(pid: Int) async throws -> Bool {
        let service = await MainActor.run {
            ensureRemoteService()
        }
        let result: Result<Bool, Error> = try await service.withContinuation { service, continuation in
            service.terminateAgentProcess(pid) { data in
                let object = Self.agentPayloadObject(data: data)
                let terminated = (object as? [String: Any])?["terminated"] as? Bool ?? false
                continuation.resume(returning: .success(terminated))
            }
        }
        return try result.get()
    }

    nonisolated func resetConnection() {
        Task { @MainActor in
            connection?.invalidate()
            connection = nil
            remoteService = nil
        }
    }

    private nonisolated static func agentHookResult(status: String?) -> Result<AgentHookStatus, Error> {
        guard let payload = agentPayloadObject(data: status),
              let dictionary = payload as? [String: Any],
              let parsedStatus = AgentHookStatus(xpcDictionary: dictionary) else {
            return .failure(XPCHelperClientError.invalidAgentHookStatus)
        }
        return .success(parsedStatus)
    }

    private nonisolated static func agentPayloadObject(data: String?) -> Any? {
        guard let data = data?.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if envelope["ok"] as? Bool == true {
            return envelope["payload"]
        }
        return nil
    }

    private nonisolated func agentConfigRootPath(for tool: String) -> String {
        let key = tool.lowercased().contains("claude")
            ? "agentActivityClaudeConfigPath"
            : "agentActivityCodexConfigPath"
        return UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}

private enum XPCHelperClientError: Error, LocalizedError {
    case invalidAgentHookStatus
    case agentHookInstallFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAgentHookStatus:
            "The helper returned an invalid hook install status."
        case let .agentHookInstallFailed(message):
            message
        }
    }
}
