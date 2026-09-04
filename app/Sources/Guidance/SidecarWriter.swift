import Foundation

/// Tier 3: asks the Python sidecar to write the card.
///
/// Writes only. Triage stays on Tier 2, which is free, runs in well under a
/// second and is measurably good at the decision. Sending every settled screen
/// event to a 27B model instead would undo the whole point of the ladder.
struct SidecarWriter: GuidanceWriter {
    let name: String
    let baseURL: URL
    private let session: URLSession

    init(
        name: String = "Sidecar",
        host: String = "127.0.0.1",
        port: Int = 8765,
        timeout: TimeInterval = 20
    ) {
        self.name = name
        baseURL = URL(string: "http://\(host):\(port)")!

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        // Loopback only. A proxy in the way would both break this and send the
        // contents of the user's screen somewhere it must never go.
        configuration.connectionProxyDictionary = [:]
        session = URLSession(configuration: configuration)
    }

    // MARK: - Wire format

    private struct Request: Encodable {
        var kind: String
        var appName: String
        var windowTitle: String?
        var source: String
        var text: String
    }

    private struct Response: Decodable {
        var title: String
        var diagnosis: String?
        var steps: [String]
        var elapsedMs: Int?
    }

    private struct Failure: Decodable {
        var error: String
        /// What the model actually said, when it said something unparseable.
        var raw: String?
    }

    // MARK: - Writing

    func guidance(for brief: ContextBrief) async throws -> Guidance? {
        try await card(
            from: "guidance",
            for: brief,
            maximumSteps: GuidanceDraft.maximumSteps
        )
    }

    func briefing(for brief: ContextBrief) async throws -> Guidance? {
        try await card(
            from: "briefing",
            for: brief,
            maximumSteps: GuidanceDraft.maximumBriefingSteps
        )
    }

    /// Both endpoints speak the same wire format and differ only in the system
    /// prompt the sidecar pairs with it, so the transport is shared and the
    /// question is a path.
    private func card(
        from path: String,
        for brief: ContextBrief,
        maximumSteps: Int
    ) async throws -> Guidance? {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            Request(
                kind: brief.kind.rawValue,
                appName: brief.appName,
                windowTitle: brief.windowTitle,
                source: brief.source,
                text: brief.text
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Connection refused is the ordinary case, not an exception: the
            // sidecar is a separate process the user may simply not be running.
            throw SidecarUnavailable(reason: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GuidanceError(reason: "Sidecar returned a non-HTTP response")
        }

        guard http.statusCode == 200 else {
            throw GuidanceError(reason: Self.describe(status: http.statusCode, body: data))
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)

        // The same card rules as Tier 2, deliberately. A bigger model earns no
        // exemption from the step cap or the plausibility filter.
        return GuidanceDraft(
            title: decoded.title,
            diagnosis: decoded.diagnosis ?? "",
            steps: decoded.steps
        )
        .card(source: brief.source, writer: name, maximumSteps: maximumSteps)
    }

    private static func describe(status: Int, body: Data) -> String {
        guard let failure = try? JSONDecoder().decode(Failure.self, from: body) else {
            return "Sidecar returned HTTP \(status)"
        }

        // 502 is the sidecar telling us the model produced something it could
        // not parse, and it forwards the raw text. That is the only clue worth
        // having when a local model starts answering in prose.
        if let raw = failure.raw, !raw.isEmpty {
            return "\(failure.error) - model said: \(raw.prefix(120))"
        }
        return failure.error
    }
}

/// The sidecar is not running. Distinct from a failure *inside* the sidecar,
/// because the tiered provider handles the two differently: absence is normal
/// and falls back quietly, whereas a real error is worth surfacing.
struct SidecarUnavailable: LocalizedError {
    var reason: String
    var errorDescription: String? { "Sidecar unavailable: \(reason)" }
}

extension SidecarWriter {
    /// Best-effort liveness probe, used to label the inspector rather than to
    /// gate anything. Nothing waits on this.
    func isReachable() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 2

        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }

        return http.statusCode == 200
    }
}
