//
//  SigilExplorerView.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

//
//  SigilExplorerView.swift
//  KaiKlok
//

import SwiftUI

public struct SigilExplorerView: View {
    public init() {}
    public var body: some View {
        NavigationStack {
            List {
                Section("Recent") {
                    Text("Coming soon — browse sealed sigils here.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("ΦStream")
        }
    }
}
