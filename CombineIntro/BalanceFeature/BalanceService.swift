import Combine
import Foundation

struct BalanceResponse: Decodable {
    let balance: Double
    let date: Date
}

protocol BalanceService {
    func refreshBalance() -> AnyPublisher<BalanceResponse, Error>
}
