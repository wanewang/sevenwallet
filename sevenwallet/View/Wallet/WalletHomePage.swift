import SwiftUI

@MainActor
struct WalletHomeView: View {
    @State private var viewModel: WalletHomeViewModel

    init(viewModel: WalletHomeViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? .sample())
    }

    private var theme: Theme {
        viewModel.isThemeLight ? .light : .dark
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                WalletTopBar(
                    theme: theme,
                    isThemeLight: viewModel.isThemeLight,
                    onToggleTheme: {}
                )

                ScrollView {
                    VStack(spacing: 0) {
                        WalletCardView(
                            viewModel: viewModel.walletCard,
                            theme: theme
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)

                        tokensHeader

                        ForEach(
                            Array(viewModel.tokens.enumerated()),
                            id: \.element.id
                        ) { index, token in
                            TokenRowView(
                                viewModel: token,
                                theme: theme,
                                isFirst: index == 0,
                                isLast: index == viewModel.tokens.count - 1
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(Theme.accent)
        .environment(
            \.colorScheme,
            viewModel.isThemeLight ? .light : .dark
        )
    }

    private var tokensHeader: some View {
        HStack {
            Text("Tokens")
                .font(.title2.bold())
                .foregroundStyle(theme.fg1)

            Spacer()

            Button(action: {}) {
                Label("Manage", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(theme.edge, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("manage-tokens-button")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.bg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tokens-header")
    }
}
