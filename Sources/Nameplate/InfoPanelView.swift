import SwiftUI
import AppKit
import NameplateCore

/// The panel that opens from the menu bar icon. Drag it away from the menu bar to detach it.
@MainActor
struct InfoPanelView: View {
    @ObservedObject var store: InfoStore

    private var app: AppDelegate? { NSApp.delegate as? AppDelegate }

    var body: some View {
        let lines = store.lines
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 3) {
                    ForEach(lines) { line in
                        lineView(line)
                    }
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: min(estimatedHeight(lines), 560))
            Divider()
            footer
        }
        .frame(width: 400)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: modelSymbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.snapshot.computerName)
                    .font(.headline)
                    .textSelection(.enabled)
                Text(store.snapshot.model)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                app?.copyAll(feedback: false)
            } label: {
                Label("Copy All", systemImage: "doc.on.doc")
            }
            Button {
                app?.copyJSON()
            } label: {
                Text("Copy JSON")
            }
            Spacer()
            Text("Updated \(store.snapshot.collectedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button {
                app?.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            Button {
                app?.showSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func lineView(_ line: InfoLine) -> some View {
        switch line.kind {
        case .section:
            Text(line.value.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, line.id == 0 ? 0 : 8)
        case .subheader:
            Text(line.value)
                .font(.callout.weight(.semibold))
                .padding(.top, 6)
        case .spacer:
            Color.clear.frame(height: 6)
        case .row:
            GridRow {
                Text(line.label)
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                Text(line.value)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func estimatedHeight(_ lines: [InfoLine]) -> CGFloat {
        var height: CGFloat = 24
        for line in lines {
            switch line.kind {
            case .row: height += 19
            case .section: height += 24
            case .subheader: height += 25
            case .spacer: height += 9
            }
        }
        return height
    }

    private var modelSymbol: String {
        let model = store.snapshot.model
        if model.contains("MacBook") { return "laptopcomputer" }
        if model.contains("Mac mini") { return "macmini" }
        if model.contains("Mac Studio") { return "macstudio" }
        if model.contains("Mac Pro") { return "macpro.gen3" }
        return "desktopcomputer"
    }
}
