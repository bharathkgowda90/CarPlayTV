import Foundation
import Observation
import StoreKit

/// CarPlayTV Pro via StoreKit 2: a monthly subscription or a one-time lifetime unlock.
/// Purchases are verified on device against Apple's signature; there is no server.
@MainActor
@Observable
final class ProStore {
    static let monthlyID = "com.bharathkgowda.carplaytv.pro.monthly"
    static let lifetimeID = "com.bharathkgowda.carplaytv.pro.lifetime"

    /// Free tier limits.
    static let freeSourceLimit = 1
    static let freeCastingSeconds: TimeInterval = 15 * 60

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var isPurchasing = false
    var errorMessage: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task { await load() }
    }

    func load() async {
        do {
            products = try await Product.products(for: [Self.monthlyID, Self.lifetimeID])
                .sorted { $0.type == .autoRenewable && $1.type != .autoRenewable }
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshEntitlements()
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshEntitlements()
            case .success(.unverified):
                errorMessage = "The purchase couldn't be verified."
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement, transaction.revocationDate == nil else { continue }
            if [Self.monthlyID, Self.lifetimeID].contains(transaction.productID) { active = true }
        }
        isPro = active
    }
}
