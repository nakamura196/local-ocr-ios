import Foundation
import StoreKit

/// Tips (consumable in-app purchases), the same three tiers and prices as KotenOCR.
/// The products belong to the App Store record "Local OCR", which the macOS app shares.
@MainActor
final class TipJarManager: ObservableObject {
    static let productIDs: [String] = [
        "com.nakamura.localocr.tip.small",
        "com.nakamura.localocr.tip.medium",
        "com.nakamura.localocr.tip.large"
    ]

    @Published var products: [Product] = []
    @Published var isLoading = true
    @Published var purchaseState: PurchaseState = .idle

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case success
        case error(String)
    }

    func loadProducts() async {
        isLoading = true
        do {
            let storeProducts = try await Product.products(for: Self.productIDs)
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            products = []
        }
        isLoading = false
    }

    func purchase(_ product: Product) async {
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    purchaseState = .success
                case .unverified:
                    purchaseState = .error(String(localized: "tipjar_error_unverified", defaultValue: "購入の検証に失敗しました"))
                }
            case .userCancelled, .pending:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .error(error.localizedDescription)
        }
    }

    func resetState() {
        purchaseState = .idle
    }

    /// The mark shown beside each tier.
    static func emoji(for productID: String) -> String {
        switch productIDs.firstIndex(of: productID) {
        case 0: return "☕️"
        case 1: return "🍵"
        default: return "🎉"
        }
    }
}
