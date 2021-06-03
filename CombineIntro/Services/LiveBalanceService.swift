import Combine
import Foundation

struct LiveBalanceService: BalanceService {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        return decoder
    }()

    private let url = URL(
        string: "https://api.jsonbin.io/b/60b76b002d9ed65a6a7d6980"
    )!

    func refreshBalance() -> AnyPublisher<BalanceResponse, Error> {
        URLSession.shared
            .dataTaskPublisher(for: url)
            .tryMap { output -> Data in
                guard let httpResponse = output.response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                return output.data
            }
            .decode(type: BalanceResponse.self, decoder: decoder)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
