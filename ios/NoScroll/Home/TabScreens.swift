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

/// Settings: the publik account, sign-out for each service, privacy, and About
/// (how blocking works, the rule versions, the source code, the app version).
struct ProfileTab: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var gate: PublikGateModel

    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    /// A page in the in-app browser (help and support, the privacy policy, the source code), or nil.
    @State private var webPage: PublikGateModel.BrowserPage?

    static let sourceCodeURL = URL(string: "https://github.com/Blueturboguy07/noscroll")!

    var body: some View {
        NavigationStack {
            List {
                publikSection
                servicesSection

                Section {
                    // publik's bare in-app support page, in the in-app browser.
                    Button("Help and support") { webPage = PublikGateModel.BrowserPage(url: Publik.supportURL) }
                } header: {
                    Text("Help")
                }

                Section {
                    Button("Privacy policy") { webPage = PublikGateModel.BrowserPage(url: Publik.privacyURL) }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Blocking runs on this iPhone. \(AppState.appName) sends nothing about what you look at. Your logins for the services stay in \(AppState.appName) on this iPhone.")
                }

                Section {
                    NavigationLink("How blocking works") { HowBlockingWorksView() }
                    NavigationLink("Blocking rules") { RuleDetailsView() }
                    Button("Source code") { webPage = PublikGateModel.BrowserPage(url: Self.sourceCodeURL) }
                    Text(AppState.versionLine)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Version: \(AppState.versionLine)")
                } header: {
                    Text("About")
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
        // Help and support, the privacy policy and the source code: in the in-app browser, not the Safari app.
        .sheet(item: $webPage) { page in
            PublikBrowser(url: page.url).ignoresSafeArea()
        }
        .confirmationDialog("Sign out of publik?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { gate.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(signOutMessage)
        }
        // Delete account, step 1: say what is deleted.
        .alert("Delete your publik account?", isPresented: $confirmDelete) {
            Button("Delete account", role: .destructive) { gate.deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your publik account for all publik apps, not only for \(AppState.appName). First, \(AppState.appName) signs you out and deletes its publik data on this iPhone. Then the publik page opens. Confirm the deletion on that page.")
        }
    }

    private var signOutMessage: String {
        gate.mode == .required
            ? "\(AppState.appName) asks you to sign in with publik again before you can use it."
            : "The app stops telling publik about app use until you sign in again."
    }

    private var publikSection: some View {
        Section {
            if gate.signedIn {
                // The account email when publik gives one; else the handle; else no name at all.
                if let email = gate.email {
                    LabeledContent("Signed in as", value: email)
                } else if let handle = gate.handle {
                    LabeledContent("Signed in as", value: "@\(handle)")
                } else {
                    Text("Signed in with publik")
                }
                Button("Sign out", role: .destructive) { confirmSignOut = true }
                // Only with an account: usage counting and account deletion.
                Toggle("Count app use", isOn: $gate.usageCounting)
                Button("Delete account", role: .destructive) { confirmDelete = true }
            } else {
                Button("Sign in with publik") { gate.signInSheet = true }
            }
        } header: {
            Text("publik account")
        } footer: {
            Text(gate.signedIn ? "\(AppState.appName) tells publik when it opens and each 30 minutes that it stays open, so publik can count app use. It sends nothing about what you look at. Turn off Count app use to stop this." : "When you are signed in, \(AppState.appName) tells publik when it opens and each 30 minutes that it stays open, so publik can count app use. It sends nothing about what you look at. After you sign in, you can turn this off here (Count app use).")
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

/// Settings > About > How blocking works: the rules, in plain words.
struct HowBlockingWorksView: View {
    var body: some View {
        List {
            Section("What it does") {
                Text("\(AppState.appName) opens each service in its own browser inside the app. When a page loads, \(AppState.appName) hides the parts that keep you scrolling, for example Reels, Shorts and suggested posts.")
                Text("It also stops pages such as Reels or Shorts from opening. You go to the start page of the service instead.")
            }
            Section("You choose") {
                Text("Each block has a switch. Find the switches in the Blocks tab, or tap the Settings card of a service on the home screen. Turn a switch off to see that part again.")
            }
            Section("On your iPhone only") {
                Text("All of this happens on your iPhone. \(AppState.appName) sends nothing about what you look at.")
            }
            Section("Sign-in pages") {
                Text("On a sign-in page, \(AppState.appName) stops. It does not hide, read or change anything on that page. A sign at the top of the screen says that \(AppState.appName) is paused. Blocking starts again after you sign in.")
            }
            Section("The rules") {
                Text("A list of rules for each service tells \(AppState.appName) what to hide. The lists come with the app, and each list has a signature. \(AppState.appName) checks the signature and does not use a list that was changed.")
                Text("Web sites change. A rule can stop working until the next update of the app.")
                if !appStoreBuild {
                    // Not in the App Store build: it has no BETA services and says no "beta" (guideline 2.2).
                    Text("Services marked BETA are newer, and their rules are tested less.")
                }
            }
        }
        .navigationTitle("How blocking works")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings > About > Blocking rules: the version of each service's rule list and of the engine.
struct RuleDetailsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            Section {
                ForEach(AppState.services) { service in
                    LabeledContent(service.name, value: state.bundleVersion(for: service.id))
                }
            } header: {
                Text("Rule lists")
            } footer: {
                Text("Each service has its own list of rules. A new version comes with an update of the app.")
            }
            Section("Blocking engine") {
                LabeledContent("Engine", value: "Version 1")
            }
        }
        .navigationTitle("Blocking rules")
        .navigationBarTitleDisplayMode(.inline)
    }
}
