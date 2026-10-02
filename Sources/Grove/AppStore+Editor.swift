import AppKit
import GroveCore

/// What the rich text editor reads and writes in the store.
extension AppStore {
    /// `excluding` is the item whose text is being edited. It is left out of the `[[` list.
    func editorServices(excluding: ItemRef? = nil) -> EditorServices {
        var s = EditorServices()
        s.suggest = { [unowned self] query in mentionSuggestions(for: query, excluding: excluding) }
        s.isLive = { [unowned self] id in (try? repos.refs.resolve(title: "", id: id)) != nil }
        s.title = { [unowned self] id in (try? repos.refs.resolve(title: "", id: id))?.title }
        s.open = { [unowned self] id, title in openMention(id: id, title: title) }
        s.storeImage = { [unowned self] data in (try? repos.attachments.addImage(data))?.id }
        s.loadImage = { [unowned self] id in image(id) }
        s.notify = { [unowned self] message in showToast(message) }
        return s
    }

    func mentionSuggestions(for query: String, excluding: ItemRef?) -> [MentionSuggestion] {
        let wanted = 8
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var out: [MentionSuggestion] = []
        if trimmed.isEmpty {
            // Nothing typed yet: today's open tasks first, then the inbox.
            for t in openTasks(in: .day(selectedDay)) + openTasks(in: .inbox) where ItemRef(.task, t.id) != excluding {
                out.append(MentionSuggestion(ref: ItemRef(.task, t.id), title: t.title, kind: "Task"))
            }
        } else {
            for hit in (try? repos.search.search(trimmed, limit: wanted + 1)) ?? [] where hit.ref != excluding {
                out.append(MentionSuggestion(ref: hit.ref, title: hit.title, kind: Self.kindName(hit.ref.type)))
            }
        }
        return Array(out.prefix(wanted))
    }

    private static func kindName(_ type: ItemType) -> String {
        switch type {
        case .task: "Task"
        case .note: "Note"
        case .event: "Event"
        }
    }

    /// Opens the item a mention points at.
    func openMention(id: String?, title: String) {
        guard let target = try? repos.refs.resolve(title: title, id: id) else {
            showToast("That item is gone.")
            return
        }
        open(target.ref)
    }

    func open(_ ref: ItemRef) {
        switch ref.type {
        case .task:
            if let t = task(ref.id) {
                if let day = t.planDate { selectedDay = day }
                selectedTaskId = t.id
            }
        case .event:
            if let e = try? repos.events.get(ref.id) {
                selectedDay = e.start.day
                selection = [e.id]
            }
        case .note:
            openNote(ref.id)
        }
    }

    func image(_ id: String) -> NSImage? {
        if let hit = imageCache.object(forKey: id as NSString) { return hit }
        guard let stored = try? repos.attachments.get(id), let img = NSImage(data: stored.data) else { return nil }
        imageCache.setObject(img, forKey: id as NSString)
        return img
    }
}
