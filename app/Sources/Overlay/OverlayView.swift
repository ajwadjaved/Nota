import SwiftUI

struct OverlayView: View {
    let model: OverlayModel

    private let cornerRadius: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let guidance = model.guidance {
                header(for: guidance)
                ForEach(guidance.steps) { step in
                    row(for: step)
                }
            } else {
                Text("Kuroko is watching")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        )
    }

    private func header(for guidance: Guidance) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(guidance.title)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let source = guidance.source {
                Text(source)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func row(for step: GuidanceStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(step.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text(step.text)
                .font(.system(size: 12))
                .foregroundStyle(step.isDone ? .secondary : .primary)
                .strikethrough(step.isDone, color: .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
