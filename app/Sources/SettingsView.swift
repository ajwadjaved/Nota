import SwiftUI

struct SettingsView: View {
    private let permissions = PermissionsManager.shared
    private let loginItem = LoginItemManager.shared

    var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Launch Kuroko at login",
                    isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.setEnabled($0) }
                    )
                )
                if let error = loginItem.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }

            Section("Permissions") {
                row(
                    "Screen Recording",
                    detail: "Capture the focused window when text alone is not enough.",
                    granted: permissions.hasScreenRecording,
                    pane: .screenRecording
                )
                row(
                    "Accessibility",
                    detail: "Read the focused field and its value without a screenshot.",
                    granted: permissions.hasAccessibility,
                    pane: .accessibility
                )
                row(
                    "Microphone",
                    detail: "Hear spoken questions while the hotkey is held.",
                    granted: permissions.hasMicrophone,
                    pane: .microphone
                )
            }

            Section("Hotkey") {
                LabeledContent("Toggle overlay", value: "Option-Command-K")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear {
            permissions.refresh()
            loginItem.refresh()
        }
    }

    private func row(
        _ title: String,
        detail: String,
        granted: Bool,
        pane: PermissionsManager.Pane
    ) -> some View {
        LabeledContent {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.tint)
            } else {
                Button("Open Settings") {
                    permissions.openSettings(for: pane)
                }
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}
