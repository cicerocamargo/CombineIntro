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
        
        rootView.refreshButton.touchUpInsidePublisher
            .sink(receiveValue: viewModel.refreshBalance)
            .store(in: &cancellables)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.refreshBalance()
    }
    
    private func updateView() {
        rootView.refreshButton.isHidden = viewModel.state.isRefreshing
        if viewModel.state.isRefreshing {
            rootView.activityIndicator.startAnimating()
        } else {
            rootView.activityIndicator.stopAnimating()
        }
        rootView.valueLabel.text = viewModel.state.formattedBalance
        rootView.valueLabel.alpha = viewModel.state.isRedacted
            ? BalanceView.alphaForRedactedValueLabel
            : 1
        rootView.infoLabel.text = viewModel.state.infoText(formatDate: formatDate)
        rootView.infoLabel.textColor = viewModel.state.infoColor
        rootView.redactedOverlay.isHidden = !viewModel.state.isRedacted
        
        view.setNeedsLayout()
    }
}

#if DEBUG
import SwiftUI

struct BalanceViewController_Previews: PreviewProvider {
    static private func makePreview() -> some View {
        BalanceViewController(service: FakeBalanceService())
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
