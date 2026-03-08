import SwiftUI

@main
struct HapiClientApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var fontSettings = FontSettings.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(fontSettings)
                .frame(minWidth: 700, minHeight: 450)
        }
        .defaultSize(width: 1100, height: 700)
        .onChange(of: scenePhase) { _, newPhase in
            appState.handleScenePhase(newPhase)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            AppSettingsView()
                .environmentObject(fontSettings)
        }
    }
}

// MARK: - App Settings (Cmd+,)

struct AppSettingsView: View {
    @EnvironmentObject var fontSettings: FontSettings

    var body: some View {
        TabView {
            FontSettingsView()
                .environmentObject(fontSettings)
                .tabItem {
                    Label("Fonts", systemImage: "textformat.size")
                }
        }
        .frame(width: 450, height: 350)
    }
}

struct FontSettingsView: View {
    @EnvironmentObject var fs: FontSettings

    var body: some View {
        Form {
            Section("Text") {
                Picker("Font Family", selection: $fs.fontFamily) {
                    ForEach(FontSettings.availableFontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                HStack {
                    Text("Size")
                    Slider(value: $fs.fontSize, in: 10...24, step: 1)
                    Text("\(Int(fs.fontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            Section("Code") {
                Picker("Font Family", selection: $fs.codeFontFamily) {
                    ForEach(FontSettings.availableMonoFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                HStack {
                    Text("Size")
                    Slider(value: $fs.codeFontSize, in: 10...24, step: 1)
                    Text("\(Int(fs.codeFontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            Section("Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The quick brown fox jumps over the lazy dog.")
                        .font(fs.bodyFont)
                    Text("func hello() { print(\"world\") }")
                        .font(fs.codeFont)
                        .padding(6)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(.vertical, 4)
            }

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    fs.fontSize = 14
                    fs.codeFontSize = 13
                    fs.fontFamily = "System"
                    fs.codeFontFamily = "Menlo"
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
