import Foundation

/// Serves canned responses keyed by URL path. Register per-test via ephemeral config.
///
/// Deviation from brief: `responses` and `lastRequest` are mutated by multiple
/// `.serialized` test suites that can run in parallel with each other. To avoid
/// data races, `responses` must only ever be mutated via per-path subscript
/// assignment (never wholesale `responses = [...]`), and `lastRequest` is
/// replaced with `lastRequests`, a dictionary keyed by request path.
///
/// Extended for pagination coverage: `responseQueues` holds an ordered list of
/// responses per path. Each request first pops the head of that path's queue
/// (if one exists and is non-empty); once the queue is drained, requests fall
/// back to the static `responses[path]` entry, so a queue never needs
/// resetting once exhausted. `requestHistory` records every request seen per
/// path, in order, so tests can assert on e.g. the *second* request's query
/// string rather than only the most recent one (`lastRequests` still tracks
/// the most recent for existing single-request tests). As with `responses`,
/// mutate `responseQueues`/`requestHistory` only via per-path subscript
/// assignment, never wholesale.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (status: Int, body: Data)] = [:]
    nonisolated(unsafe) static var responseQueues: [String: [(status: Int, body: Data)]] = [:]
    nonisolated(unsafe) static var lastRequests: [String: URLRequest] = [:]
    nonisolated(unsafe) static var requestHistory: [String: [URLRequest]] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.lastRequests[path] = request
        Self.requestHistory[path, default: []].append(request)

        let entry: (status: Int, body: Data)
        if var queue = Self.responseQueues[path], !queue.isEmpty {
            entry = queue.removeFirst()
            Self.responseQueues[path] = queue
        } else {
            entry = Self.responses[path] ?? (status: 404, body: Data())
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: entry.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: entry.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func stubbedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}
