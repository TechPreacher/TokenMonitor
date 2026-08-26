import Foundation

/// Serves canned responses keyed by URL path. Register per-test via ephemeral config.
///
/// Deviation from brief: `responses` and `lastRequest` are mutated by multiple
/// `.serialized` test suites that can run in parallel with each other. To avoid
/// data races, `responses` must only ever be mutated via per-path subscript
/// assignment (never wholesale `responses = [...]`), and `lastRequest` is
/// replaced with `lastRequests`, a dictionary keyed by request path.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (status: Int, body: Data)] = [:]
    nonisolated(unsafe) static var lastRequests: [String: URLRequest] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.lastRequests[path] = request
        let entry = Self.responses[path] ?? (status: 404, body: Data())
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
