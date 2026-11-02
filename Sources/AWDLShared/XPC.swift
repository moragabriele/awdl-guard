import Foundation

/// Interface exported by the daemon. Payloads are JSON-encoded models to keep the
/// XPC surface small and easy to audit.
@objc public protocol AWDLGuardXPC {
    func getStatus(withReply reply: @escaping (Data?) -> Void)
    func report(activity: Data, withReply reply: @escaping (Bool) -> Void)
    func requestOverride(minutes: Int, withReply reply: @escaping (Bool, String) -> Void)
    func cancelOverride(withReply reply: @escaping (Bool) -> Void)
    func reload(withReply reply: @escaping (Bool) -> Void)
}

public enum DaemonClientError: Error, CustomStringConvertible {
    case unreachable(String)
    case timeout

    public var description: String {
        switch self {
        case .unreachable(let why): return "daemon unreachable: \(why)"
        case .timeout: return "daemon did not answer in time"
        }
    }
}

public final class DaemonClient {
    private var connection: NSXPCConnection?
    private let lock = NSLock()

    /// Called after the connection is interrupted or invalidated (e.g. daemon restart).
    public var onDisconnect: (() -> Void)?

    public init() {}

    public func proxy(errorHandler: @escaping (Error) -> Void) -> AWDLGuardXPC? {
        lock.lock()
        defer { lock.unlock() }
        if connection == nil {
            let c = NSXPCConnection(machServiceName: Constants.machServiceName, options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: AWDLGuardXPC.self)
            c.interruptionHandler = { [weak self] in self?.onDisconnect?() }
            c.invalidationHandler = { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.connection = nil
                self.lock.unlock()
                self.onDisconnect?()
            }
            c.resume()
            connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler(errorHandler) as? AWDLGuardXPC
    }

    public func invalidate() {
        lock.lock()
        let c = connection
        connection = nil
        lock.unlock()
        c?.invalidate()
    }

    /// Blocking call for command-line use.
    public func sync<T>(timeout: TimeInterval = 5,
                        _ body: (AWDLGuardXPC, @escaping (T) -> Void) -> Void) -> Result<T, DaemonClientError> {
        let sem = DispatchSemaphore(value: 0)
        var result: Result<T, DaemonClientError> = .failure(.timeout)
        let p = proxy { error in
            result = .failure(.unreachable(error.localizedDescription))
            sem.signal()
        }
        guard let p else { return .failure(.unreachable("no proxy")) }
        body(p) { value in
            result = .success(value)
            sem.signal()
        }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            return .failure(.timeout)
        }
        return result
    }
}
