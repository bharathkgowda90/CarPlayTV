import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var reason: String?

    var body: some View {
        let store = model.pro
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CarPlayTV Pro").font(.title.bold())
                        if let reason { Text(reason).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 4)
                }
                Section("Pro unlocks") {
                    Label("Unlimited sources", systemImage: "list.bullet.rectangle")
                    Label("Unlimited casting and screen mirroring", systemImage: "rectangle.on.rectangle")
                    Label("Subtitle timing adjustment", systemImage: "captions.bubble")
                }
                Section {
                    if store.products.isEmpty {
                        ProgressView()
                    }
                    ForEach(store.products, id: \.id) { product in
                        Button {
                            Task {
                                await store.purchase(product)
                                if store.isPro { dismiss() }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(product.displayName).foregroundStyle(.primary)
                                    Text(product.description).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(product.displayPrice).bold()
                            }
                        }
                        .disabled(store.isPurchasing)
                    }
                    Button("Restore Purchases") { Task { await store.restore() } }
                } footer: {
                    Text("The monthly plan renews automatically until cancelled in your App Store account settings. Lifetime is a one-time purchase.")
                }
                if let error = store.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onChange(of: store.isPro) { _, isPro in if isPro { dismiss() } }
        }
    }
}
