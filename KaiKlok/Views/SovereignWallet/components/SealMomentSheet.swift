//
//  SealMomentSheet.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

//
//  SealMomentSheet.swift
//  KaiKlok
//

import SwiftUI

public struct SealMomentSheet: View {
    public let urlString: String
    @Environment(\.dismiss) private var dismiss
    public init(urlString: String) { self.urlString = urlString }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Seal Complete").font(.title3.bold())
            Text(urlString).font(.footnote.monospaced()).textSelection(.enabled)
                .multilineTextAlignment(.center)
                .padding()
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 10) {
                Button("Copy Link") {
                    UIPasteboard.general.string = urlString
                }
                .buttonStyle(.bordered)

                if let url = URL(string: urlString) {
                    ShareLink("Share", item: url).buttonStyle(.borderedProminent)
                }
            }

            Button("Close") { dismiss() }.padding(.top, 6)
        }
        .padding()
        .presentationDetents([.medium, .large])
    }
}
