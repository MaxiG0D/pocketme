import SwiftUI

extension View {
    func kicker() -> some View {
        font(Typo.kicker).textCase(.uppercase).tracking(0.4).foregroundStyle(Theme.muted)
    }
}

struct PillButtonStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Typo.pill)
            .padding(.horizontal, 14).frame(minHeight: 34)
            .background(selected ? Theme.ink : Theme.chip, in: Capsule())
            .foregroundStyle(selected ? Theme.paper : Theme.pillInactiveText)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Theme.ink
    var foreground: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Typo.button)
            .frame(maxWidth: .infinity).frame(minHeight: 50)
            .background(fill, in: Capsule()).foregroundStyle(foreground ?? Theme.paper)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Typo.button)
            .frame(maxWidth: .infinity).frame(minHeight: 50)
            .background(Theme.chip, in: Capsule()).foregroundStyle(Theme.ink)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct CircleIconButtonStyle: ButtonStyle {
    enum Kind { case plain, accent }
    var kind: Kind = .plain

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 20, weight: .regular))
            .frame(width: 44, height: 44)
            .background(kind == .accent ? Theme.accent : Theme.accent.opacity(0), in: Circle())
            .foregroundStyle(kind == .accent ? Theme.onAccent : Theme.icon)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

#Preview("Light") {
    Fonts.register()
    return VStack {
        Button("Unread · 0") {}.buttonStyle(PillButtonStyle(selected: true))
        Button("Archive") {}.buttonStyle(SecondaryButtonStyle())
        Button("Save") {}.buttonStyle(PrimaryButtonStyle())
        Button {} label: { Image(systemName: "plus") }.buttonStyle(CircleIconButtonStyle(kind: .accent))
    }.padding().background(Theme.paper).preferredColorScheme(.light)
}

#Preview("Dark") {
    Fonts.register()
    return VStack {
        Button("Unread · 0") {}.buttonStyle(PillButtonStyle(selected: false))
        Button("Archive") {}.buttonStyle(SecondaryButtonStyle())
        Button("Save") {}.buttonStyle(PrimaryButtonStyle())
    }.padding().background(Theme.paper).preferredColorScheme(.dark)
}
