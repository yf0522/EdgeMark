import Foundation

@Observable
final class AppNavigation {
    static let shared = AppNavigation()

    enum Section {
        case memo
        case clipboard
    }

    var section: Section = .memo

    private init() {}

    func showMemo() {
        section = .memo
    }

    func showClipboard() {
        section = .clipboard
    }
}
