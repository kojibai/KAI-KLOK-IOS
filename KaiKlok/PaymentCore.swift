//
//  PaymentCore.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/13/25.
//

// PaymentCore.swift
// Shared payment abstractions for KaiKlok
// PaymentCore.swift
// Shared payment abstractions for KaiKlok (iOS)

import Foundation

public enum PurchaseOutcome {
  case success(String)   // transactionId
  case cancelled
  case pending
}

public enum PurchaseError: Error, LocalizedError {
  case productNotFound
  case failed(String)

  public var errorDescription: String? {
    switch self {
    case .productNotFound: return "Product not found."
    case .failed(let msg): return msg
    }
  }
}

public protocol PaymentProvider {
  func buy(productId: String) async throws -> PurchaseOutcome
}
