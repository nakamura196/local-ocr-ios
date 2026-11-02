import SwiftUI
import StoreKit

/// "Support development": three tip tiers (from KotenOCR).
struct TipJarView: View {
    @StateObject private var manager = TipJarManager()

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 28))
                        .foregroundColor(LOColor.ai)
                        .accessibilityHidden(true)
                    Text(String(localized: "tipjar_title", defaultValue: "Local OCR を応援"))
                        .font(.mincho(22, relativeTo: .title2, bold: true))
                        .foregroundColor(LOColor.ink)
                    Text(String(localized: "tipjar_description",
                                defaultValue: "Local OCR をお役立ていただけましたら、\n開発を支えるチップをお願いいたします。"))
                        .font(.subheadline)
                        .foregroundColor(LOColor.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                if manager.isLoading {
                    HStack {
                        Spacer()
                        ProgressView().tint(LOColor.ai)
                        Spacer()
                    }
                    .padding()
                } else if manager.products.isEmpty {
                    Text(String(localized: "tipjar_unavailable", defaultValue: "現在、商品を取得できません。"))
                        .foregroundColor(LOColor.inkSecondary)
                        .font(.subheadline)
                } else {
                    ForEach(manager.products, id: \.id) { product in
                        tipRow(product)
                    }
                }
            }
            .listRowBackground(LOColor.washiCard)

            if case .success = manager.purchaseState {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 32))
                            .foregroundColor(LOColor.ai)
                            .accessibilityHidden(true)
                        Text(String(localized: "tipjar_thanks", defaultValue: "ご支援ありがとうございます！"))
                            .font(.headline)
                            .foregroundColor(LOColor.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .listRowBackground(Color.clear)
                }
            }

            if case .error(let message) = manager.purchaseState {
                Section {
                    Text(message)
                        .foregroundColor(LOColor.danger)
                        .font(.caption)
                }
                .listRowBackground(LOColor.washiCard)
            }
        }
        .scrollContentBackground(.hidden)
        .washiBackground()
        .navigationTitle(String(localized: "tipjar_nav_title", defaultValue: "応援する"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await manager.loadProducts() }
    }

    private func tipRow(_ product: Product) -> some View {
        Button {
            Task { await manager.purchase(product) }
        } label: {
            HStack {
                Text(TipJarManager.emoji(for: product.id))
                    .font(.title2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.body)
                        .foregroundColor(LOColor.ink)
                    Text(product.description)
                        .font(.caption)
                        .foregroundColor(LOColor.inkSecondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.headline)
                    .foregroundColor(LOColor.ai)
            }
            .padding(.vertical, 4)
        }
        .disabled(manager.purchaseState == .purchasing)
        .accessibilityLabel(Text("\(product.displayName) \(product.displayPrice)"))
        .accessibilityIdentifier(product.id)
    }
}
