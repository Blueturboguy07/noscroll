import SwiftUI

/// Per-service blocking settings. Every block is a switch the user owns; the
/// product's opinion lives in the defaults, not in taking the choice away.
struct ServiceSettingsView: View {
    let service: AppState.Service

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(state.surfaces(for: service.id)) { group in
                        Toggle(group.label,
                               isOn: state.binding(service: service.id, surfaces: group.keys))
                    }
                } header: {
                    Text("What's blocked")
                } footer: {
                    if service.beta {
                        Text("\(service.name) is in beta: its rules are written but not yet verified against the live site by the automated probes.")
                    }
                }
            }
            .navigationTitle("\(service.name) Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
