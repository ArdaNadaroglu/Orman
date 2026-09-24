import StoreKit

// Tracks which forest decorations the player owns — unlocked for free by
// keeping a long enough streak, or bought outright — and drives the
// one-time purchase flow for each. Ownership is stored locally; nothing
// here is required to use the rest of the app.
@MainActor
final class DecorationStore: ObservableObject {
    private static let ownedKey = "forest.decorations.owned.v1"

    @Published private(set) var ownedIDs: Set<String>
    @Published private(set) var products: [String: Product] = [:]
    @Published var purchasingID: String?
    @Published var errorMessage: String?
    @Published var justUnlocked: ForestDecoration?

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.ownedKey) ?? ""
        ownedIDs = Set(saved.split(separator: ",").map(String.init))
        Task { await loadProducts() }
    }

    func isOwned(_ decoration: ForestDecoration) -> Bool { ownedIDs.contains(decoration.id) }

    func product(for decoration: ForestDecoration) -> Product? { products[decoration.productID] }

    var sortedDecorations: [ForestDecoration] {
        let catalog = ForestDecorCatalog.all
        // Never mix TRY fallback amounts with another storefront's currency.
        let useStorePrices = catalog.allSatisfy { product(for: $0) != nil }
        return catalog.enumerated().sorted { a, b in
            let left = useStorePrices ? product(for: a.element)!.price : a.element.priceAmount
            let right = useStorePrices ? product(for: b.element)!.price : b.element.priceAmount
            return left == right ? a.offset < b.offset : left < right
        }.map(\.element)
    }

    func loadProducts() async {
        let ids = ForestDecorCatalog.all.map(\.productID)
        guard let loaded = try? await Product.products(for: ids) else { return }
        products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
    }

    func purchase(_ decoration: ForestDecoration) async {
        guard let product = products[decoration.productID], purchasingID == nil else { return }
        purchasingID = decoration.id
        defer { purchasingID = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    grant(decoration, celebrate: false)
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

    // Called whenever the live streak changes; grants any not-yet-owned
    // decoration whose streak requirement has now been met.
    func checkStreakRewards(streak: Int) {
        for decoration in ForestDecorCatalog.all where !isOwned(decoration) {
            guard let reward = decoration.streakReward, streak >= reward else { continue }
            grant(decoration, celebrate: true)
        }
    }

    private func grant(_ decoration: ForestDecoration, celebrate: Bool) {
        guard !ownedIDs.contains(decoration.id) else { return }
        ownedIDs.insert(decoration.id)
        UserDefaults.standard.set(ownedIDs.sorted().joined(separator: ","), forKey: Self.ownedKey)
        if celebrate { justUnlocked = decoration }
    }
}
