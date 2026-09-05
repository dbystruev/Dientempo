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
