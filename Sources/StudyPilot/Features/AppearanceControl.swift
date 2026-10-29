import SwiftUI

enum AppAccent: String, CaseIterable, Identifiable {
    case forest = "Forest", ocean = "Ocean", violet = "Violet", rose = "Rose", sunset = "Sunset", graphite = "Graphite"

    var id: String { rawValue }
    static var current: AppAccent { AppAccent(rawValue: UserDefaults.standard.string(forKey: "accentColor") ?? "") ?? .forest }
    static var selectedColor: Color {
        color(name: UserDefaults.standard.string(forKey: "accentColor") ?? "Forest",
              customHex: UserDefaults.standard.string(forKey: "customAccentHex") ?? "355F9C")
    }
    static var selectedSecondaryColor: Color {
        if UserDefaults.standard.string(forKey: "accentColor") == "Custom" { return selectedColor }
        return current.secondaryColor
    }
    static func color(name: String, customHex: String) -> Color {
        if name == "Custom" { return customColor(hex: customHex) }
        return (AppAccent(rawValue: name) ?? .forest).color
    }
    static func customColor(hex: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            accessibleCustom(hex: hex, dark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        })
    }
    var lightHex: String {
        switch self {
        case .forest: "206852"
        case .ocean: "245F9B"
        case .violet: "6749A6"
        case .rose: "9C4B62"
        case .sunset: "865918"
        case .graphite: "4D6072"
        }
    }
    var darkHex: String {
        switch self {
        case .forest: "72C7A3"
        case .ocean: "83BAF1"
        case .violet: "BAA0ED"
        case .rose: "F0A1B5"
        case .sunset: "EBC078"
        case .graphite: "A9BBCB"
        }
    }
    private var secondaryLightHex: String {
        switch self {
        case .forest: "43785F"
        case .ocean: "497EAD"
        case .violet: "8067B0"
        case .rose: "B46679"
        case .sunset: "A47734"
        case .graphite: "687A8A"
        }
    }
    private var secondaryDarkHex: String {
        switch self {
        case .forest: "9AD7B7"
        case .ocean: "ACD1F4"
        case .violet: "D0BEF2"
        case .rose: "F4BCCC"
        case .sunset: "F5D69C"
        case .graphite: "C2D0DB"
        }
    }
    var color: Color { resolved(light: lightHex, dark: darkHex) }
    var secondaryColor: Color { resolved(light: secondaryLightHex, dark: secondaryDarkHex) }
    func swatch(for scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? darkHex : lightHex) }

    private func resolved(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            Self.nsColor(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
    }
    private static func nsColor(_ hex: String) -> NSColor {
        let value = UInt64(hex, radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    private static func accessibleCustom(hex: String, dark: Bool) -> NSColor {
        var color = nsColor(hex)
        let background = dark ? NSColor(srgbRed: 0.06, green: 0.066, blue: 0.073, alpha: 1)
                              : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let target = dark ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
                          : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        for _ in 0..<20 {
            if contrast(color, background) >= 4.5 { break }
            color = NSColor(srgbRed: color.redComponent * 0.85 + target.redComponent * 0.15,
                            green: color.greenComponent * 0.85 + target.greenComponent * 0.15,
                            blue: color.blueComponent * 0.85 + target.blueComponent * 0.15, alpha: 1)
        }
        return color
    }
    private static func contrast(_ first: NSColor, _ second: NSColor) -> Double {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    private static func luminance(_ color: NSColor) -> Double {
        func linear(_ value: CGFloat) -> Double {
            let component = Double(value)
            return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
    }
}

struct AccentPicker: View {
    @AppStorage("accentColor") private var accentColor = AppAccent.forest.rawValue
    @AppStorage("customAccentHex") private var customAccentHex = "355F9C"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                ForEach(AppAccent.allCases) { accent in
                    let selected = accentColor == accent.rawValue
                    Button { accentColor = accent.rawValue } label: {
                        VStack(spacing: 7) {
                            Circle().fill(accent.swatch(for: colorScheme))
                                .frame(width: 32, height: 32)
                                .overlay { if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(colorScheme == .dark ? Color.black : Color.white) } }
                                .padding(4)
                                .overlay(Circle().stroke(selected ? accent.swatch(for: colorScheme) : .clear, lineWidth: 1.5))
                            Text(accent.rawValue).font(.caption).foregroundStyle(selected ? .primary : .secondary)
                        }.frame(maxWidth: .infinity).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(accent.rawValue) accent color")
                        .accessibilityValue(selected ? "Selected" : "Not selected")
                }
            }
            HStack {
                ColorPicker("Choose any color with the color wheel", selection: Binding(
                    get: { Color(hex: customAccentHex) },
                    set: { newColor in
                        guard let rgb = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                        customAccentHex = String(format: "%02X%02X%02X",
                                                 Int((rgb.redComponent * 255).rounded()),
                                                 Int((rgb.greenComponent * 255).rounded()),
                                                 Int((rgb.blueComponent * 255).rounded()))
                        accentColor = "Custom"
                    }
                ), supportsOpacity: false)
                Spacer()
                if accentColor == "Custom" {
                    Label("Custom selected", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(AppAccent.selectedColor)
                } else {
                    Button("Use saved custom color") { accentColor = "Custom" }.font(.caption)
                }
            }
        }.padding(.vertical, 6)
    }
}

struct AppearanceControl: View {
    @Environment(AppState.self) private var app
    @AppStorage("appearance") private var appearance = "System"
    @AppStorage("accentColor") private var accentColor = AppAccent.forest.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Menu {
            Picker("Appearance", selection: $appearance) {
                Label("Light mode", systemImage: "sun.max").tag("Light")
                Label("Dark mode", systemImage: "moon").tag("Dark")
                Label("Follow Mac appearance", systemImage: "desktopcomputer").tag("System")
            }
            Divider()
            Menu("Accent color", systemImage: "paintpalette") {
                ForEach(AppAccent.allCases) { accent in
                    Button { accentColor = accent.rawValue } label: {
                        Label(accent.rawValue, systemImage: accentColor == accent.rawValue ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
                Divider()
                Button { accentColor = "Custom" } label: {
                    Label("Use custom color", systemImage: accentColor == "Custom" ? "checkmark.circle.fill" : "circle.fill")
                }
                Button("Custom color settings…", systemImage: "paintpalette") { app.showingSettings = true }
            }
            Divider()
            Button(colorScheme == .dark ? "Switch to Light Mode" : "Switch to Dark Mode") {
                appearance = colorScheme == .dark ? "Light" : "Dark"
            }.keyboardShortcut("d", modifiers: [.command, .shift])
        } label: {
            Label("Appearance", systemImage: colorScheme == .dark ? "moon.fill" : "sun.max")
        }
        .help("Choose appearance and accent color")
        .accessibilityLabel("Appearance")
    }
}
