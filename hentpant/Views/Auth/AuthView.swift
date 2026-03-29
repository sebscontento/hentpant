//
//  AuthView.swift
//  hentpant
//

import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @State private var mode: AuthMode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var canGive = true
    @State private var canReceive = true

    enum AuthMode: String, CaseIterable, Identifiable {
        case login
        case signUp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .login: return String(localized: "Log in")
            case .signUp: return String(localized: "Sign up")
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker(String(localized: "Mode"), selection: $mode) {
                    ForEach(AuthMode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                Section {
                    TextField(String(localized: "Email"), text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField(String(localized: "Password"), text: $password)
                        .textContentType(mode == .login ? .password : .newPassword)
                }

                if mode == .signUp {
                    Section {
                        TextField(String(localized: "Display name"), text: $displayName)
                            .textContentType(.name)
                        Toggle(String(localized: "I give away items"), isOn: $canGive)
                        Toggle(String(localized: "I claim items"), isOn: $canReceive)
                    } footer: {
                        Text(String(localized: "You can enable both. You can apply for moderator after creating your account."))
                    }
                }

                if let err = appState.authError {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button(mode == .login ? String(localized: "Log in") : String(localized: "Create account")) {
                        submitEmail()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.authInFlight)
                }

                Section {
                    SignInWithAppleButton(.signIn) { request in
                        appState.prepareAppleSignInRequest(request)
                    } onCompletion: { result in
                        appState.handleAppleCompletion(result)
                    }
                    .frame(height: 44)
                } header: {
                    Text(String(localized: "Apple"))
                }

                Section {
                    Text(String(localized: "Accounts are stored in Supabase. Participation roles can be changed later from the profile screen."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "PantCollect"))
            .disabled(appState.authInFlight)
            .overlay {
                if appState.authInFlight {
                    ZStack {
                        Color.black.opacity(0.08)
                            .ignoresSafeArea()
                        ProgressView(mode == .login ? String(localized: "Logging in...") : String(localized: "Creating account..."))
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private func submitEmail() {
        Task {
            if mode == .login {
                await appState.signIn(email: email, password: password)
            } else {
                await appState.signUp(
                    email: email,
                    password: password,
                    displayName: displayName,
                    canGive: canGive,
                    canReceive: canReceive
                )
            }
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AppState(skipAuthListener: true))
}
