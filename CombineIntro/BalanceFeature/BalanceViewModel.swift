import Combine
import Foundation
import UIKit

final class BalanceViewModel {
    let eventSubject = PassthroughSubject<BalanceViewEvent, Never>()
    @Published private(set) var state = BalanceViewState()

    private let service: BalanceService
    private var cancellables: Set<AnyCancellable> = []

    init(service: BalanceService) {
        self.service = service

        NotificationCenter.default
            .publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.state.isRedacted = true
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.state.isRedacted = false
            }
            .store(in: &cancellables)

        eventSubject
            .sink { [weak self] in self?.handleEvent($0) }
            .store(in: &cancellables)
    }

    private func handleEvent(_ event: BalanceViewEvent) {
        switch event {
        case .refreshButtonWasTapped, .viewDidAppear:
            refreshBalance()
        }
    }

    private func refreshBalance() {
        state.didFail = false
        state.isRefreshing = true
        service.refreshBalance { [weak self] result in
            self?.handleResult(result)
        }
    }

    private func handleResult(_ result: Result<BalanceResponse, Error>) {
        state.isRefreshing = false
        do {
            state.lastResponse = try result.get()
        } catch {
            state.didFail = true
        }
    }
}
