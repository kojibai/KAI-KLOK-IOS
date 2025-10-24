//  IAPManager.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/13/25.
//
//  Apple-compliant StoreKit 2 IAP for Sigil-Glyph mints (consumables).
//  - One consumable per Fibonacci USD tier.
//  - Links each transaction to a user via appAccountToken derived from userPhiKey.

import Foundation
import StoreKit
import CryptoKit

@MainActor
final class IAPManager: ObservableObject {

    // 1) Register these in App Store Connect as CONSUMABLE products.
    //    Replace these with your real product IDs.
    static let productIDs: Set<String> = [
        "com.kaiklok.phi.inhale.1597",
        "com.kaiklok.phi.inhale.2584",
        "com.kaiklok.phi.inhale.4181",
        "com.kaiklok.phi.inhale.6765",
        "com.kaiklok.phi.inhale.10946",
        "com.kaiklok.phi.inhale.17711",
        "com.kaiklok.phi.inhale.28657",
        "com.kaiklok.phi.inhale.46368",
        "com.kaiklok.phi.inhale.75025",
        "com.kaiklok.phi.inhale.121393",
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    init() {
        Task { await listenForTransactions() }
    }

    // Load products and sort by numeric price (ascending).
    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: Array(Self.productIDs))
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            lastError = "Unable to load products: \(error.localizedDescription)"
        }
    }

    /// Deterministic appAccountToken from the user's ΦKey (stable UUID).
    func accountToken(for userPhiKey: String) -> UUID {
        // SHA256(userPhiKey) → first 16 bytes → UUID
        let digest = SHA256.hash(data: Data(userPhiKey.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    struct PurchaseResult {
        let transactionID: UInt64
        let productID: String
        let priceLocale: Locale
        let displayPrice: String
    }

    func purchase(_ product: Product, userPhiKey: String) async throws -> PurchaseResult {
        lastError = nil
        let token = accountToken(for: userPhiKey)

        let result = try await product.purchase(options: [.appAccountToken(token)])
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            // Consumables: finish immediately.
            await transaction.finish()
            return PurchaseResult(
                transactionID: transaction.id,
                productID: transaction.productID,
                priceLocale: product.priceFormatStyle.locale,
                displayPrice: product.displayPrice
            )

        case .userCancelled:
            throw NSError(domain: "IAP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cancelled."])

        case .pending:
            throw NSError(domain: "IAP", code: 2, userInfo: [NSLocalizedDescriptionKey: "Purchase pending."])

        @unknown default:
            throw NSError(domain: "IAP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown purchase state."])
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let err):
            throw err
        case .verified(let safe):
            return safe
        }
    }

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            do {
                let transaction: Transaction = try checkVerified(update)
                await transaction.finish()
            } catch {
                // Non-fatal: continue listening.
            }
        }
    }
}

// (Optional) Keep a numeric accessor if you want one; uses StoreKit's true price.
fileprivate extension Product {
    var numericPrice: Decimal { price }
}
