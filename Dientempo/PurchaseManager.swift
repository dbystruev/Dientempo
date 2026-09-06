import Foundation
import StoreKit
import Combine

/// Wraps the StoreKit 1 (`SKPaymentQueue`) purchase flow for the single
/// non-consumable "Unlimited Access" product. StoreKit 1 is used rather than
/// StoreKit 2 because the deployment target is iOS 16.0 and a single
/// non-consumable purchase does not need anything StoreKit 2 adds.
@MainActor
final class PurchaseManager: NSObject, ObservableObject {
    static let shared = PurchaseManager()

    // MARK: - Product ID

    /// Must match exactly the IAP Product ID created in App Store Connect
    /// (see PLAN.md Phase 0, Step 0.2).
    let productID = "com.bystruev.dientempo.premium"

    // MARK: - Published state

    @Published var premiumProduct: SKProduct?
    @Published var isLoading = false
    @Published var lastError: Error?
    @Published var restoreCompleted = false

    // MARK: - Setup

    private override init() {
        super.init()
        SKPaymentQueue.default().add(self)
        loadProduct()
    }

    // MARK: - Product loading

    func loadProduct() {
        isLoading = true
        let request = SKProductsRequest(productIdentifiers: [productID])
        request.delegate = self
        request.start()
    }

    // MARK: - Purchase

    func purchase() {
        guard let product = premiumProduct else {
            lastError = NSError(
                domain: "com.bystruev.dientempo",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Product not loaded yet"]
            )
            return
        }
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
        lastError = nil
        restoreCompleted = false
    }

    // MARK: - Restore

    func restore() {
        restoreCompleted = false
        lastError = nil
        SKPaymentQueue.default().restoreCompletedTransactions()
    }

    // MARK: - Grandfathering pre-existing paid purchasers

    /// The only MARKETING_VERSION ever actually released to the App Store as
    /// the paid $4.99 app (confirmed via App Store Connect: appStoreState
    /// READY_FOR_SALE, version 1.0 -- every later "1.x" bump was internal
    /// TestFlight testing only, never released). Anyone whose original
    /// purchase was at or before this version bought the app back when
    /// buying it WAS the unlock, so they should get unlimited access for
    /// free going forward, with no action required from them.
    private static let lastPaidVersion = "1.0"

    /// Call once per launch (see ContentView.onAppear). Uses StoreKit 2's
    /// `AppTransaction` (available iOS 16+, no extra capability, and safe to
    /// mix with the StoreKit 1 purchase/restore flow above -- SK2's
    /// transaction-reading APIs are read-only and don't touch the payment
    /// queue) to read which version of the app the user ORIGINALLY
    /// downloaded -- not the version currently installed -- and unlocks
    /// premium automatically if that was at or before `lastPaidVersion`.
    /// Idempotent and cheap: does nothing once already unlocked, and
    /// `unlockPremium()` itself is idempotent.
    func grandfatherExistingPaidUserIfNeeded() {
        guard !PremiumManager.shared.isPremiumUnlocked else { return }

        Task {
            do {
                let result = try await AppTransaction.shared
                switch result {
                case .verified(let appTransaction):
                    if Self.isVersion(appTransaction.originalAppVersion, atOrBefore: Self.lastPaidVersion) {
                        await MainActor.run {
                            PremiumManager.shared.unlockPremium()
                        }
                    }
                case .unverified:
                    // Apple's own guidance: don't act on an unverified
                    // result. A permanent free unlock is exactly the kind of
                    // decision that must not be based on unverified data.
                    break
                }
            } catch {
                // No original transaction available (e.g. simulator without
                // a signed receipt, or a genuinely fresh install that was
                // never paid for) -- nothing to grandfather, not an error
                // worth surfacing to the user.
            }
        }
    }

    /// Component-wise numeric version comparison ("1.0" <= "1.0" -> true,
    /// "1.0" <= "1.4" -> true, "2.0" <= "1.0" -> false). Missing trailing
    /// components are treated as 0, so "1" and "1.0" compare equal.
    private static func isVersion(_ version: String, atOrBefore reference: String) -> Bool {
        let v = version.split(separator: ".").compactMap { Int($0) }
        let r = reference.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(v.count, r.count) {
            let vPart = i < v.count ? v[i] : 0
            let rPart = i < r.count ? r[i] : 0
            if vPart != rPart {
                return vPart < rPart
            }
        }
        return true
    }
}

// MARK: - SKProductsRequestDelegate

extension PurchaseManager: SKProductsRequestDelegate {
    nonisolated func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        Task { @MainActor in
            self.premiumProduct = response.products.first
            self.isLoading = false
        }
    }

    nonisolated func request(_ request: SKRequest, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = error
            self.isLoading = false
        }
    }
}

// MARK: - SKPaymentTransactionObserver

extension PurchaseManager: SKPaymentTransactionObserver {
    nonisolated func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        Task { @MainActor in
            for transaction in transactions {
                switch transaction.transactionState {
                case .purchased, .restored:
                    PremiumManager.shared.unlockPremium()
                    queue.finishTransaction(transaction)
                case .failed:
                    self.lastError = transaction.error
                    queue.finishTransaction(transaction)
                case .purchasing, .deferred:
                    break
                @unknown default:
                    queue.finishTransaction(transaction)
                }
            }
        }
    }

    nonisolated func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        Task { @MainActor in
            self.restoreCompleted = true
        }
    }

    nonisolated func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        Task { @MainActor in
            self.lastError = error
        }
    }
}
