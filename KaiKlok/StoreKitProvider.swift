//
//  StoreKitProvider.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/13/25.
//
// StoreKitProvider.swift
// In-app purchase provider for digital goods (StoreKit 2)

import StoreKit

actor StoreKitProvider: PaymentProvider {
  func buy(productId: String) async throws -> PurchaseOutcome {
    let products = try await Product.products(for: [productId])
    guard let product = products.first else { throw PurchaseError.productNotFound }

    let result = try await product.purchase()
    switch result {
    case .success(let verification):
      let transaction = try checkVerified(verification)
      await transaction.finish()
      return .success(String(transaction.id))
    case .userCancelled:
      return .cancelled
    case .pending:
      return .pending
    @unknown default:
      throw PurchaseError.failed("Unknown purchase state")
    }
  }

  private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .unverified(_, let err):
      throw PurchaseError.failed("Unverified transaction: \(err)")
    case .verified(let safe):
      return safe
    }
  }
}
