import Foundation
import os

@MainActor
protocol ControlPointWriter: AnyObject {
    func writeControlPoint(_ data: Data) throws
}

enum ControlPointError: Error, Equatable, LocalizedError {
    case notConnected
    case timedOut(ControlPointCommand)
    case rejected(ControlPointCommand, ControlPointResultCode)
    case writeFailed(ControlPointCommand, reason: String)
    case disconnected(ControlPointCommand)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "The trainer is not connected."
        case let .timedOut(command):
            "The trainer did not answer \"\(command)\" in time."
        case let .rejected(command, result):
            "The trainer rejected \"\(command)\": \(result)."
        case let .writeFailed(command, reason):
            "Could not send \"\(command)\": \(reason)"
        case let .disconnected(command):
            "The trainer disconnected before answering \"\(command)\"."
        }
    }
}

/// Sends FTMS control point commands one at a time and waits for each `80 <op> <result>` indication.
///
/// FTMS allows only one outstanding control point procedure, so commands are serialized.
@MainActor
final class ControlPointClient {
    private struct InFlight {
        let id: UUID
        let command: ControlPointCommand
        let continuation: CheckedContinuation<Data, Error>
    }

    private static let logger = Logger(subsystem: "com.kineticrevival.trainer", category: "ControlPoint")

    private weak var writer: ControlPointWriter?
    private let timeout: Duration
    private var inFlight: InFlight?
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(timeout: Duration = .seconds(5)) {
        self.timeout = timeout
    }

    var isAttached: Bool { writer != nil }

    func attach(_ writer: ControlPointWriter) {
        self.writer = writer
    }

    func detach() {
        writer = nil
        if let inFlight {
            complete(inFlight.id, with: .failure(ControlPointError.disconnected(inFlight.command)))
        }
    }

    /// - Returns: Any response parameters after the `80 <op> <result>` header (e.g. spin-down target speeds).
    @discardableResult
    func send(_ command: ControlPointCommand) async throws -> Data {
        await acquire()
        defer { release() }

        guard let writer else { throw ControlPointError.notConnected }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let id = UUID()
            inFlight = InFlight(id: id, command: command, continuation: continuation)
            Self.logger.debug("Sending \(command.description, privacy: .public): \(command.encoded.hexDescription, privacy: .public)")

            do {
                try writer.writeControlPoint(command.encoded)
            } catch {
                complete(id, with: .failure(ControlPointError.writeFailed(command, reason: error.localizedDescription)))
                return
            }

            Task { [weak self, timeout] in
                try? await Task.sleep(for: timeout)
                self?.complete(id, with: .failure(ControlPointError.timedOut(command)))
            }
        }
    }

    func handleIndication(_ data: Data) {
        let response: ControlPointResponse
        do {
            response = try ControlPointResponse(data: data)
        } catch {
            Self.logger.error("Ignoring malformed control point indication \(data.hexDescription, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }

        guard let inFlight, inFlight.command.opCode.rawValue == response.requestOpCode else {
            Self.logger.warning("Ignoring unsolicited control point response \(data.hexDescription, privacy: .public)")
            return
        }

        let result: Result<Data, Error> = response.result == .success
            ? .success(response.parameters)
            : .failure(ControlPointError.rejected(inFlight.command, response.result))
        complete(inFlight.id, with: result)
    }

    func handleWriteFailure(_ error: Error) {
        guard let inFlight else { return }
        complete(inFlight.id, with: .failure(ControlPointError.writeFailed(inFlight.command, reason: error.localizedDescription)))
    }

    /// Resumes the in-flight continuation exactly once; later calls for the same id (e.g. a timeout
    /// firing after the response arrived) are ignored.
    private func complete(_ id: UUID, with result: Result<Data, Error>) {
        guard let inFlight, inFlight.id == id else { return }
        self.inFlight = nil
        if case let .failure(error) = result {
            Self.logger.error("\(inFlight.command.description, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        inFlight.continuation.resume(with: result)
    }

    private func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
