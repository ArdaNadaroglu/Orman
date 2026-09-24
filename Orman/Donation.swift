import StoreKit

// A single optional, non-consumable "tip" purchase, entirely voluntary.
// No content in the app is gated behind this — it's just a way for someone
// who enjoys Silva to say thanks.
@MainActor
final class DonationStore: ObservableObject {
    static let donationProductID = "com.arda.orman.donate50"

    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing = false
    @Published var showThankYou = false
    @Published var errorMessage: String?

    init() {
        Task { await loadProduct() }
    }

    func loadProduct() async {
        product = try? await Product.products(for: [Self.donationProductID]).first
    }

    func donate() async {
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    showThankYou = true
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
