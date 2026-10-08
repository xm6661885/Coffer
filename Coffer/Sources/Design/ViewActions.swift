import SwiftUI
import Observation

@MainActor @Observable final class ViewActions {
    private struct Action { let id = UUID(); let operation: @MainActor () async -> Void }
    private var queue: [Action] = []
    var hasPending: Bool { !queue.isEmpty }
    func submit(_ operation: @escaping @MainActor () async -> Void) { queue.append(Action(operation: operation)) }
    func drain() async {
        while let action = queue.first {
            guard !Task.isCancelled else { return }
            await action.operation()
            queue.removeAll { $0.id == action.id }
        }
    }
    func cancel() { queue.removeAll() }
}
private struct ViewActionsModifier: ViewModifier {
    let actions: ViewActions
    func body(content: Content) -> some View { content.task(id: actions.hasPending) { if actions.hasPending { await actions.drain() } }.onDisappear { actions.cancel() } }
}
extension View { func managedTasks(_ actions: ViewActions) -> some View { modifier(ViewActionsModifier(actions: actions)) } }
