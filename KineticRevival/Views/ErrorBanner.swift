import SwiftUI

private struct ErrorBanner: ViewModifier {
    let message: String?
    let dismiss: () -> Void

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if let message {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(message)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Dismiss", systemImage: "xmark", action: dismiss)
                        .labelStyle(.iconOnly)
                }
                .font(.subheadline)
                .padding()
                .foregroundStyle(.white)
                .background(.red.gradient, in: .rect(cornerRadius: 12))
                .padding(.horizontal)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: message)
    }
}

extension View {
    func errorBanner(_ message: String?, dismiss: @escaping () -> Void) -> some View {
        modifier(ErrorBanner(message: message, dismiss: dismiss))
    }
}
