import SwiftUI

/// Shows exactly what the readers produced, so it is obvious whether a given
/// app is giving us usable context or whether it needs an OCR fallback.
struct ContextInspectorView: View {
    let coordinator: ContextCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let context = coordinator.current {
                    appSection(context)
                    scriptedSection(context)
                    accessibilitySection(context)
                } else {
                    Text("No context yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 460, minHeight: 420)
        .onAppear { coordinator.startPolling() }
        .onDisappear { coordinator.stopPolling() }
    }

    private func appSection(_ context: ScreenContext) -> some View {
        section("Frontmost app") {
            field("Name", context.app.name)
            field("Bundle ID", context.app.bundleID ?? "-")
            field("PID", String(context.app.pid))
            field("Window", context.windowTitle ?? "-")
            field("Read time", String(format: "%.1f ms", context.readDuration * 1000))
        }
    }

    @ViewBuilder
    private func scriptedSection(_ context: ScreenContext) -> some View {
        section("Scripted context") {
            switch coordinator.lastAppRead {
            case .unavailable:
                note("No scripted reader for this app. Falling back to Accessibility.")
            case .notPermitted:
                note("Automation was declined for this app. Re-enable it in System Settings > Privacy & Security > Automation.")
            case .failed(let message):
                note("Script failed: \(message)")
            case .facts(let facts) where facts.isEmpty:
                note("Reader ran but returned nothing.")
            case .facts(let facts):
                ForEach(facts) { fact in
                    field(fact.label, fact.value)
                }
            }
        }
    }

    @ViewBuilder
    private func accessibilitySection(_ context: ScreenContext) -> some View {
        section("Accessibility") {
            if let focused = context.focused {
                field("Role", focused.role ?? "-")
                field("Subrole", focused.subrole ?? "-")
                field("Title", focused.title ?? "-")
                field("Value", focused.value ?? "-")
                field("Placeholder", focused.placeholder ?? "-")
                field("Selected text", focused.selectedText ?? "-")
                field("Help", focused.help ?? "-")
            } else if !PermissionsManager.shared.hasAccessibility {
                note("Accessibility permission not granted.")
            } else {
                note("This app exposes no focused element. Common in Electron apps and remote desktops; these need the OCR path.")
            }
        }
    }

    // MARK: - Building blocks

    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
