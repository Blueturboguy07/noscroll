import SwiftUI

/// Sleep Mode: a nightly window during which the shielded apps stay shut.
///
/// The schedule maths lives in `SleepSchedule`, which is recomputed from the
/// wall clock and the current timezone every time rather than cached — the bug
/// that leaves people staring at "you should be asleep" at 9am.
struct SleepTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Sleep Mode", isOn: $state.sleepEnabled)
                    DatePicker("Starts", selection: $state.sleepStart, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $state.sleepEnd, displayedComponents: .hourAndMinute)
                } footer: {
                    Text("Between these times the apps you've shielded stay closed. The window is recalculated from your device clock, so changing timezone takes effect immediately.")
                }

                Section("Right now") {
                    LabeledContent("Status",
                                   value: state.sleepActiveNow ? "Sleeping" : "Awake")
                    if !state.hasScreenTimeAccess {
                        Text("Sleep Mode can only close apps once Screen Time access is granted.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Sleep")
        }
    }
}

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
                            BrandMark(service: service.id, size: 15)
                                .padding(5)
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

/// The enforcement layer's state, stated plainly.
struct ShieldTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Screen Time access",
                                   value: state.hasScreenTimeAccess ? "Granted" : "Not granted")
                    LabeledContent("Enforcement",
                                   value: state.hasScreenTimeAccess ? "Apps are shielded" : "Wrapper only")
                } header: {
                    Text("Shield")
                } footer: {
                    // The degraded mode is stated rather than glossed: claiming
                    // an enforcement the build cannot deliver is both a lie and
                    // an App Review risk.
                    Text(state.hasScreenTimeAccess
                         ? "Opening a shielded app sends you here instead."
                         : "Without Screen Time access NoScroll blocks inside its own browser, but cannot stop you opening the real apps.")
                }

                if !state.hasScreenTimeAccess {
                    Section {
                        Button("Grant Screen Time access") {
                            Task { await state.requestScreenTimeAccess() }
                        }
                    }
                }

                Section("Post Mode") {
                    LabeledContent("Unlocks left today", value: "\(state.postModeUnlocksRemaining)")
                    Button("Unlock for 10 minutes") { state.beginPostMode() }
                        .disabled(!state.hasScreenTimeAccess || state.postModeUnlocksRemaining == 0)
                }
            }
            .navigationTitle("Shield")
        }
    }
}

/// Accounts, privacy, and the rule bundle's provenance.
struct ProfileTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("Rules") {
                    ForEach(AppState.services) { service in
                        LabeledContent(service.name,
                                       value: state.bundleVersion(for: service.id))
                    }
                }

                Section {
                    LabeledContent("Engine", value: "v1")
                    Toggle("Share rule health", isOn: $state.telemetryEnabled)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Rule health reports which blocking rules stopped matching — a rule id and a count, nothing else. Never a URL, never anything you looked at. Your logins never leave this device either way.")
                }

                Section {
                    Link("Source code", destination: URL(string: "https://github.com/Blueturboguy07/noscroll")!)
                    Link("How rules work", destination: URL(string: "https://github.com/Blueturboguy07/noscroll/blob/main/docs/RULES.md")!)
                } footer: {
                    Text("NoScroll is free and open source under AGPL-3.0. It is not affiliated with any of the services it opens.")
                }
            }
            .navigationTitle("You")
        }
    }
}
