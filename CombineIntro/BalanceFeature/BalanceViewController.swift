import Combine
import Foundation
import UIKit

@dynamicMemberLookup
class BalanceViewController: UIViewController {
    private let rootView = BalanceView()
    private let viewModel: BalanceViewModel
    private let formatDate: (Date) -> String
    private var cancellables: Set<AnyCancellable> = []
    
    init(
        service: BalanceService,
        formatDate: @escaping (Date) -> String = BalanceViewState.relativeDateFormatter.string(from:)
    ) {
        self.viewModel = .init(service: service)
        self.formatDate = formatDate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = rootView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        let formatDate = self.formatDate

        cancellables = [
            viewModel.$state
                .map(\.isRefreshing)
                .removeDuplicates()
                .assign(to: \.isHidden, on: rootView.refreshButton),

            viewModel.$state
                .map(\.isRefreshing)
                .removeDuplicates()
                .assign(
                    to: \.writableIsAnimating,
                    on: rootView.activityIndicator
                ),

            viewModel.$state
                .map(\.formattedBalance)
                .removeDuplicates()
                .map(Optional.some)
                .assign(to: \.text, on: rootView.valueLabel),

            viewModel.$state
                .map { $0.infoText(formatDate: formatDate) }
                .removeDuplicates()
                .map(Optional.some)
                .assign(to: \.text, on: rootView.infoLabel),

            viewModel.$state
                .map(\.infoColor)
                .removeDuplicates()
                .map(Optional.some)
                .assign(to: \.textColor, on: rootView.infoLabel),

            viewModel.$state
                .map(\.isRedacted)
                .removeDuplicates()
                .map { isRedacted in
                    isRedacted ? BalanceView.alphaForRedactedValueLabel : 1
                }
                .assign(to: \.alpha, on: rootView.valueLabel),

            viewModel.$state
                .map(\.isRedacted)
                .removeDuplicates()
                .map { !$0 }
                .assign(to: \.isHidden, on: rootView.redactedOverlay),

            rootView.refreshButton.touchUpInsidePublisher
                .map { _ in BalanceViewEvent.refreshButtonWasTapped }
                .subscribe(viewModel.eventSubject)
        ]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.eventSubject.send(.viewDidAppear)
    }
}

#if DEBUG
import SwiftUI

struct BalanceViewController_Previews: PreviewProvider {
    static private func makePreview() -> some View {
        BalanceViewController(service: LiveBalanceService())
            .staticRepresentable
    }
    
    static var previews: some View {
        Group {
            makePreview()
                .preferredColorScheme(.dark)
            
            makePreview()
                .preferredColorScheme(.light)
        }
    }
}

// To help with tests
extension BalanceViewController {
    subscript<T>(dynamicMember keyPath: KeyPath<BalanceView, T>) -> T {
        rootView[keyPath: keyPath]
    }
}
#endif
