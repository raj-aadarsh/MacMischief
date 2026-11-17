import SwiftUI

struct MischiefCardInfo: Identifiable {
    let id: String
    let title: String
    let emoji: String
    let tagline: String
    let colors: [Color]
}

@MainActor
final class MenuModel: ObservableObject {
    @Published var activeID: String?
    @Published var hideInFullScreen: Bool
    let items: [MischiefCardInfo]
    var onSelect: (String?) -> Void = { _ in }
    var onHideInFullScreen: (Bool) -> Void = { _ in }
    var onQuit: () -> Void = {}

    init(items: [MischiefCardInfo], activeID: String?, hideInFullScreen: Bool) {
        self.items = items
        self.activeID = activeID
        self.hideInFullScreen = hideInFullScreen
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

struct MenuView: View {
    @ObservedObject var model: MenuModel
    @State private var tagline = MenuView.taglines.randomElement()!
    @State private var bob = false

    static let taglines = [
        "Pick your chaos ✨",
        "One trick at a time 🎩",
        "Your desktop looks lonely…",
        "Choose wisely. Or don't.",
        "Professional nonsense, on tap.",
        "Mischief? Managed. 🪄",
    ]

    private var activeItem: MischiefCardInfo? { model.items.first { $0.id == model.activeID } }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 8) {
                ForEach(model.items) { item in
                    MischiefCard(item: item, active: item.id == model.activeID) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            model.onSelect(item.id == model.activeID ? nil : item.id)
                        }
                    }
                }
                quietRow
            }
            .padding(12)
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 310)
        .onAppear {
            tagline = Self.taglines.randomElement()!
            bob = true
        }
    }

    private var header: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [Color(hex: 0xFF9A5A), Color(hex: 0xFF5E8A), Color(hex: 0x8F6BFF)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Sprinkles
            ForEach(0..<7, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: CGFloat(6 + (i * 5) % 14))
                    .offset(x: CGFloat(150 + (i * 37) % 150), y: CGFloat(-26 + (i * 23) % 52))
            }
            HStack(spacing: 12) {
                Text(activeItem?.emoji ?? "😼")
                    .font(.system(size: 34))
                    .rotationEffect(.degrees(bob ? 9 : -9))
                    .offset(y: bob ? -2 : 2)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: bob)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacMischief")
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(tagline)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 78)
        .clipped()
    }

    @ViewBuilder
    private var quietRow: some View {
        if model.activeID != nil {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { model.onSelect(nil) }
            } label: {
                HStack(spacing: 6) {
                    Text("😴")
                    Text("All quiet — stop the mischief")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.primary.opacity(0.05)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        } else {
            Text("Nothing running. Suspiciously calm… 🤫")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var footer: some View {
        HStack {
            Toggle(isOn: Binding(get: { model.hideInFullScreen },
                                 set: { model.hideInFullScreen = $0; model.onHideInFullScreen($0) })) {
                Text("Hide during full-screen 🍿")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            Spacer()
            Button(action: model.onQuit) {
                HStack(spacing: 4) {
                    Text("Quit")
                    Text("👋")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct MischiefCard: View {
    let item: MischiefCardInfo
    let active: Bool
    let action: () -> Void
    @State private var hover = false

    private var gradient: LinearGradient {
        LinearGradient(colors: item.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(item.emoji)
                    .font(.system(size: 26))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(gradient).opacity(active ? 1 : 0.28))
                    .scaleEffect(active ? 1.06 : (hover ? 1.04 : 1))
                    .rotationEffect(.degrees(hover && !active ? -8 : 0))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(item.tagline)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if active {
                    Text("ON")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(gradient))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(gradient)
                        .opacity(hover ? 1 : 0.45)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(active ? AnyShapeStyle(gradient.opacity(0.16))
                                 : AnyShapeStyle(Color.primary.opacity(hover ? 0.07 : 0.035)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(active ? AnyShapeStyle(gradient) : AnyShapeStyle(Color.primary.opacity(0.08)),
                                  lineWidth: active ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(hover ? 1.015 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hover)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: active)
        .onHover { hover = $0 }
    }
}
