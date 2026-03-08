import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var baseURL = "http://localhost:3000"
    @State private var accessToken = ""
    @State private var isLoggingIn = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("HAPI")
                    .font(.largeTitle.bold())
                Text("Connect to your HAPI server")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server URL")
                        .font(.headline)
                    TextField("http://localhost:3000", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Access Token")
                        .font(.headline)
                    SecureField("Paste your HAPI access token", text: $accessToken)
                        .textFieldStyle(.roundedBorder)
                }

                if let error = appState.authError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                Button {
                    Task { await login() }
                } label: {
                    HStack {
                        if isLoggingIn {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text("Connect")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(accessToken.isEmpty || baseURL.isEmpty || isLoggingIn)
                .keyboardShortcut(.return, modifiers: [])
            }
            .frame(width: 360)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let savedURL = appState.savedBaseURL { baseURL = savedURL }
        }
    }

    private func login() async {
        isLoggingIn = true
        await appState.login(baseURLString: baseURL, accessToken: accessToken)
        isLoggingIn = false
    }
}
