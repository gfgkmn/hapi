import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var baseURL = "http://localhost:3000"
    @State private var accessToken = ""
    @State private var isLoggingIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("http://localhost:3000", text: $baseURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                }

                Section("Access Token") {
                    SecureField("Paste your HAPI access token", text: $accessToken)
                        .textContentType(.password)
                }

                if let error = appState.authError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section {
                    Button {
                        Task { await login() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoggingIn {
                                ProgressView()
                            } else {
                                Text("Connect")
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(accessToken.isEmpty || baseURL.isEmpty || isLoggingIn)
                }
            }
            .navigationTitle("HAPI")
        }
        .onAppear {
            // Pre-fill from saved credentials
            if let savedURL = appState.savedBaseURL { baseURL = savedURL }
        }
    }

    private func login() async {
        isLoggingIn = true
        await appState.login(baseURLString: baseURL, accessToken: accessToken)
        isLoggingIn = false
    }
}
