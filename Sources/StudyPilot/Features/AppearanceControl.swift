import SwiftUI

struct AppearanceControl: View {
    @AppStorage("appearance") private var appearance = "System"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Menu {
            Picker("Appearance", selection: $appearance) {
                Label("Light mode", systemImage: "sun.max").tag("Light")
                Label("Dark mode", systemImage: "moon").tag("Dark")
                Label("Follow Mac appearance", systemImage: "desktopcomputer").tag("System")
            }
            Divider()
            Button(colorScheme == .dark ? "Switch to Light Mode" : "Switch to Dark Mode") {
                appearance = colorScheme == .dark ? "Light" : "Dark"
            }.keyboardShortcut("d", modifiers: [.command, .shift])
        } label: {
            Label("Appearance", systemImage: colorScheme == .dark ? "moon.fill" : "sun.max")
        }
        .help("Choose Light, Dark, or your Mac’s appearance")
        .accessibilityLabel("Appearance")
    }
}
