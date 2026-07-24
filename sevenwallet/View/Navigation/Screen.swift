import Foundation

enum Screen: Hashable {
    case addWallet
    case editWallet(UUID)
    case detail
    case manage
    case token(String)
}
