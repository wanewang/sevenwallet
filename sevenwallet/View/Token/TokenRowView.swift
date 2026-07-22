import SwiftUI

struct TokenRowView: View {
    let viewModel: TokenViewModel
    let theme: Theme
    let isFirst: Bool
    let isLast: Bool

    private var rowShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: isFirst ? 18 : 0,
                bottomLeading: isLast ? 18 : 0,
                bottomTrailing: isLast ? 18 : 0,
                topTrailing: isFirst ? 18 : 0
            ),
            style: .continuous
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            tokenIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.symbol)
                    .font(.headline)
                    .foregroundStyle(theme.fg1)

                Text(viewModel.name)
                    .font(.subheadline)
                    .foregroundStyle(theme.fg2)

                Text(viewModel.formattedDailyChange)
                    .font(.caption)
                    .foregroundStyle(viewModel.dailyChangeColor(theme: theme))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(viewModel.formattedPrice)
                    .font(.headline)
                    .foregroundStyle(theme.fg1)

                Text(viewModel.formattedBalance)
                    .font(.caption)
                    .foregroundStyle(theme.fg2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(theme.glass)
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.edge).frame(width: 1)
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(theme.edge).frame(width: 1)
        }
        .overlay(alignment: .top) {
            if isFirst {
                Rectangle().fill(theme.edge).frame(height: 1)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isLast ? theme.edge : theme.divider)
                .frame(height: 1)
        }
        .clipShape(rowShape)
    }

    @ViewBuilder
    private var tokenIcon: some View {
        AsyncImage(url: viewModel.logoURL) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } else {
                Text(viewModel.iconText)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(viewModel.iconColor)
                    .clipShape(Circle())
            }
        }
        .accessibilityHidden(true)
    }
}
