import SwiftUI

/// Every service's switches in one place, rather than one sheet at a time.
struct AllSettingsTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            List {
                ForEach(AppState.services) { service in
                    Section {
                        ForEach(state.surfaces(for: service.id)) { group in
                            Toggle(group.label,
                                   isOn: state.binding(service: service.id, surfaces: group.keys))
                        }
                    } header: {
                        HStack(spacing: 8) {
                            // An SF Symbol, not the service's logo.
                            Image(systemName: service.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 25, height: 25)
                                .background(service.gradient, in: RoundedRectangle(cornerRadius: 6))
                            Text(service.name)
                            if service.beta {
                                Text("BETA").font(.caption2.bold())
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.2), in: Capsule())
                            }
                        }
                    }
                }
            }
            .navigationTitle("What's blocked")
        }
    }
}

/// Settings: the publik account, sign-out for each service, privacy, and the
/// rule bundle's provenance.
struct ProfileTab: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var gate: PublikGateModel

    @State private var confirmSignOut = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                publikSection
                servicesSection

                Section("Rules") {
                    ForEach(AppState.services) { service in
                        LabeledContent(service.name,
                                       value: state.bundleVersion(for: service.id))
                    }
                }

                Section {
                    LabeledContent("Engine", value: "v1")
                    Link("Privacy policy", destination: URL(string: "https://publikhq.com/privacy")!)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Blocking runs on this iPhone. \(AppState.appName) sends nothing about what you look at. Your logins for the services stay in \(AppState.appName) on this iPhone.")
                }

                Section {
                    Link("Source code", destination: URL(string: "https://github.com/Blueturboguy07/noscroll")!)
                    Link("How rules work", destination: URL(string: "https://github.com/Blueturboguy07/noscroll/blob/main/docs/RULES.md")!)
                } footer: {
                    Text("\(AppState.appName) is free and open source under AGPL-3.0. It is not affiliated with any of the services it opens.")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $gate.signInSheet) {
                PublikGateView(model: gate)
            }
        }
        // Delete account, step 3: publik's delete page in the in-app browser.
        .sheet(item: $gate.deletePage, onDismiss: { gate.finishDelete() }) { page in
            PublikBrowser(url: page.url).ignoresSafeArea()
        }
        .confirmationDialog("Sign out of publik?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await gate.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(signOutMessage)
        }
        // Delete account, step 1: say what is deleted.
        .alert("Delete your publik account?", isPresented: $confirmDelete) {
            Button("Delete account", role: .destructive) { Task { await gate.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your publik account for all publik apps, not only for \(AppState.appName). First, \(AppState.appName) signs you out and deletes its publik data on this iPhone. Then the publik page opens. Confirm the deletion on that page.")
        }
    }

    private var signOutMessage: String {
        gate.mode == .required
            ? "\(AppState.appName) asks you to sign in with publik again before you can use it."
            : "publik stops counting app use until you sign in again."
    }

    private var publikSection: some View {
        Section {
            if gate.signedIn {
                LabeledContent("Signed in as", value: gate.handle.map { "@\($0)" } ?? "publik")
                Button("Sign out", role: .destructive) { confirmSignOut = true }
            } else {
                Button("Sign in with publik") { gate.signInSheet = true }
            }
            Toggle("Count app use", isOn: $gate.usageCounting)
            Button("Delete account", role: .destructive) { confirmDelete = true }
        } header: {
            Text("publik account")
        } footer: {
            Text("When you are signed in, publik counts when \(AppState.appName) opens and each 30 minutes that it stays open. publik does not see what you look at. Turn off Count app use to stop this.")
        }
    }

    /// One "Sign out" row for each service (App Store guideline 5.1.1(v)).
    private var servicesSection: some View {
        Section {
            ForEach(AppState.services) { service in
                let done = state.signedOutServices.contains(service.id)
                Button {
                    Task { await state.signOut(of: service) }
                } label: {
                    HStack {
                        Text("Sign out of \(service.name)")
                        Spacer()
                        if done {
                            Text("Signed out").foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(done)
            }
        } header: {
            Text("Service accounts")
        } footer: {
            Text("Sign out deletes the cookies and saved data of that service in \(AppState.appName) on this iPhone. Your account at the service stays.")
        }
    }
}
