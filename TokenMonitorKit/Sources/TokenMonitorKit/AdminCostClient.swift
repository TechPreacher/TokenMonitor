import Foundation

public protocol CostProviding: Sendable {
    func fetchMonthToDateCost(now: Date) async throws -> CostSnapshot
}

/// Anthropic Admin API cost report -> month-to-date USD.
public struct AdminCostClient: CostProviding {
    private let credentials: CredentialStore
    private let session: URLSession

    public init(credentials: CredentialStore, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    public func fetchMonthToDateCost(now: Date) async throws -> CostSnapshot {
        guard let key = credentials.readAdminAPIKey() else {
            throw FetchError.credentialsUnavailable
        }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let monthStart = utc.date(from: utc.dateComponents([.year, .month], from: now))!
        let iso = ISO8601DateFormatter()

        var totalCents = 0.0
        var page: String? = nil
        repeat {
            var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/cost_report")!
            var items = [
                URLQueryItem(name: "starting_at", value: iso.string(from: monthStart)),
                URLQueryItem(name: "ending_at", value: iso.string(from: now)),
                URLQueryItem(name: "limit", value: "31"),
            ]
            if let page { items.append(URLQueryItem(name: "page", value: page)) }
            components.queryItems = items
            var request = URLRequest(url: components.url!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw FetchError.decoding }
            guard http.statusCode == 200 else { throw FetchError.httpStatus(http.statusCode) }

            struct Report: Decodable {
                struct Bucket: Decodable {
                    struct Item: Decodable { let amount: String }
                    let results: [Item]
                }
                let data: [Bucket]
                let hasMore: Bool
                let nextPage: String?
                enum CodingKeys: String, CodingKey {
                    case data, hasMore = "has_more", nextPage = "next_page"
                }
            }
            guard let report = try? JSONDecoder().decode(Report.self, from: data) else {
                throw FetchError.decoding
            }
            for bucket in report.data {
                for item in bucket.results {
                    totalCents += Double(item.amount) ?? 0
                }
            }
            page = report.hasMore ? report.nextPage : nil
        } while page != nil

        return CostSnapshot(monthToDateUSD: totalCents / 100.0, fetchedAt: now)
    }
}
