import SwiftUI

struct TransferIndicator: View {
    @Environment(TransferManager.self) private var transfers
    var body: some View {
        ZStack { Circle().stroke(Color.hairline, lineWidth: 3); Circle().trim(from: 0, to: transfers.overallProgress).stroke(Color.pink, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90)); Image(systemName: "arrow.down").font(.caption) }.frame(width: 28, height: 28).animation(.linear(duration: 0.25), value: transfers.overallProgress)
    }
}
struct TransfersView: View {
    @Environment(TransferManager.self) private var transfers
    @Environment(AppSettings.self) private var settings
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    private var visible: [TransferTask] { transfers.tasks.filter { $0.kind != .cache && $0.state != .cancelled && ($0.state != .completed || $0.groupID == nil || transfers.groups[$0.groupID!]?.finished != false) } }
    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                if transfers.activeCount > 0 {
                    Text("\(transfers.activeCount) active · \(Formatters.bytes(Int64(transfers.speed)))/s" + remaining).font(.cofferCaption).contentTransition(.numericText()).foregroundStyle(Color.inkSecondary).listRowBackground(Color.surface)
                }
                section("In Progress", states: [.running, .paused, .waitingForNetwork])
                section("Queued", states: [.queued])
                section("Failed", states: [.failed])
                if !failedGroups.isEmpty { Section("Folder Actions Failed") { ForEach(failedGroups) { group in VStack(alignment: .leading, spacing: 8) { Text(group.name).foregroundStyle(Color.ink); Text(group.lastError ?? "Couldn't finish this folder.").font(.cofferCaption).foregroundStyle(Color.danger); HStack { Button("Retry") { transfers.retryGroup(group.id) }.buttonStyle(.glass); Button("Cancel") { transfers.cancelGroup(group.id) }.buttonStyle(.glass) } }.listRowBackground(Color.surface) } } }
                section("Completed", states: [.completed])
            }.paperList().overlay { if visible.isEmpty && failedGroups.isEmpty { EmptyState(title: "No transfers", symbol: "arrow.up.arrow.down", description: "Downloads and uploads will appear here.") } }
                .navigationTitle("Transfers").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Menu { Button("Pause All") { transfers.pauseAll() }; Button("Resume All") { transfers.resumeAll() }; Button("Clear Completed") { transfers.clearFinished() }; Toggle("Only on Wi-Fi", isOn: $settings.wifiOnly) } label: { Label("More", systemImage: "ellipsis.circle") } }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }.presentationDetents([.medium, .large]).presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
    private var failedGroups: [TransferGroup] { transfers.groups.values.filter { $0.lastError != nil && !$0.finished }.sorted { $0.name < $1.name } }
    private var remaining: String { let left = visible.filter(\.isActive).reduce(Int64(0)) { $0 + max(0, $1.totalBytes - $1.completedBytes) }; return transfers.speed > 0 ? " · About \(Formatters.duration(Double(left) / transfers.speed)) left" : "" }
    @ViewBuilder private func section(_ title: String, states: [TransferTask.State]) -> some View {
        let entries = visible.filter { states.contains($0.state) }
        if !entries.isEmpty {
            Section(title) {
                ForEach(entries.filter { $0.groupID == nil }) { row($0) }
                ForEach(Array(Set(entries.compactMap(\.groupID))).sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
                    if let group = transfers.groups[id] {
                        DisclosureGroup {
                            ForEach(entries.filter { $0.groupID == id }) { row($0) }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(group.name + " (Folder)", systemImage: "folder").foregroundStyle(Color.ink)
                                Text("\(group.taskIDs.filter { id in transfers.tasks.contains { $0.id == id && $0.state == .completed } }.count) of \(group.taskIDs.count) files").font(.cofferCaption).contentTransition(.numericText()).foregroundStyle(Color.inkSecondary)
                            }
                        }.listRowBackground(Color.surface)
                    }
                }
            }
        }
    }
    private func row(_ task: TransferTask) -> some View {
        HStack(spacing: 12) {
            FileIconView(item: task.source)
            VStack(alignment: .leading, spacing: 6) {
                Text(task.source.name).foregroundStyle(Color.ink).lineLimit(1)
                if task.isActive {
                    ProgressBar(value: transfers.progress(for: task.id))
                    Text(status(task)).font(.cofferCaption).contentTransition(.numericText()).foregroundStyle(Color.inkSecondary)
                } else if task.state == .failed { Text("Failed. Tap to retry. — " + (task.lastError ?? "Unknown error")).font(.cofferCaption).foregroundStyle(Color.danger) }
                else { Text("\(task.kind == .download ? "Downloaded" : "Uploaded") to \(PathUtil.parent(task.destPath)) · \(Formatters.relative(task.finishedAt ?? task.createdAt))").font(.cofferCaption).contentTransition(.numericText()).foregroundStyle(Color.inkSecondary) }
            }
            GlassIconButton(title: actionTitle(task), symbol: actionSymbol(task)) { act(task) }.controlSize(.small)
        }.padding(.vertical, 6).listRowBackground(Color.surface)
            .swipeActions { Button(task.state == .completed ? "Remove" : "Cancel", role: .destructive) { transfers.remove(task.id) } }
    }
    private func actionTitle(_ task: TransferTask) -> String { switch task.state { case .running: "Pause"; case .paused, .waitingForNetwork: "Resume"; case .failed: "Retry"; case .completed: "Show in Files"; default: "Cancel" } }
    private func actionSymbol(_ task: TransferTask) -> String { switch task.state { case .running: "pause"; case .paused, .waitingForNetwork: "play"; case .failed: "arrow.clockwise"; case .completed: "magnifyingglass"; default: "xmark" } }
    private func act(_ task: TransferTask) { switch task.state { case .running: transfers.pause(task.id); case .paused, .waitingForNetwork: transfers.resume(task.id); case .failed: transfers.retry(task.id); case .completed: navigator.reveal(location: task.destLocation, path: PathUtil.parent(task.destPath)); navigator.highlightID = task.destLocation.key + ":" + task.destPath; dismiss(); default: transfers.cancel(task.id) } }
    private func status(_ task: TransferTask) -> String {
        if task.state == .paused { return "Paused · \(Formatters.bytes(task.completedBytes)) of \(Formatters.bytes(task.totalBytes))" }
        if task.state == .waitingForNetwork { return settings.wifiOnly ? "Waiting for Wi-Fi" : "Waiting for network" }
        if task.state == .queued { return "Waiting" }
        if let retry = task.retryAt { return "Retrying (\(task.attempts)/\(task.kind == .upload ? 5 : 8)) in \(max(0, Int(retry.timeIntervalSinceNow)))s…" }
        let speed = transfers.taskSpeeds[task.id] ?? 0
        let remaining = speed > 0 ? " · About \(Formatters.duration(Double(max(0, task.totalBytes - task.completedBytes)) / speed)) left" : ""
        return "\(Formatters.bytes(task.completedBytes)) of \(Formatters.bytes(task.totalBytes)) · \(Formatters.bytes(Int64(speed)))/s" + (task.segments.count > 1 ? " · \(task.segments.count) connections" : "") + remaining
    }
}
