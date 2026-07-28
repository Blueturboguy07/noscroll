import SwiftUI

/// Per-service blocking settings. Every block is a switch the user owns.
/// The structure mirrors the product's spine: locked surfaces render as a padlock
/// and the words "Always On" — they are not switches. Block Reels, Block Explore
/// and Block Shorts cannot be turned off, so there is no "I'll just disable it
/// for a second" failure mode. Everything else is a real toggle, and every one of
/// them is free.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

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
                        Label(service.name, systemImage: service.symbol)
                            .foregroundStyle(service.tint)
                    }
                }

                Section {
                    LabeledContent("Engine", value: "v1")
                    LabeledContent("Rules", value: rulesVersion)
                    LabeledContent("Enforcement", value: "Wrapper only")
                } header: {
                    Text("About")
                } footer: {
                    // Honest about the degraded mode rather than claiming an
                    // enforcement this build cannot deliver.
                    Text("This build blocks inside NoScroll. It does not stop you opening the real apps — that needs Apple's Screen Time entitlement, which is still pending.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var rulesVersion: String {
        let versions = state.bundles.values.map { "v\($0.version)" }
        return Set(versions).sorted().joined(separator: " / ")
    }

}
