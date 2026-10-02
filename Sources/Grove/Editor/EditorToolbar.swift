import SwiftUI
import AppKit
import GroveCore

/// The row of buttons above an editor: bold, italic, code, lists, heading, quote, mention, image.
struct EditorToolbar: View {
    var controller: EditorController
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            button("bold", "Bold  ⌘B") { controller.format(.bold) }
            button("italic", "Italic  ⌘I") { controller.format(.italic) }
            button("chevron.left.forwardslash.chevron.right", "Code  ⌘E") { controller.format(.code) }
            divider
            button("list.bullet", "Bullet list") { controller.format(.line(.bullet)) }
            button("list.number", "Numbered list") { controller.format(.line(.numbered)) }
            button("checklist", "Checklist") { controller.format(.line(.checklist)) }
            divider
            button("textformat.size", "Heading") { controller.format(.line(.heading(2))) }
            button("text.quote", "Quote") { controller.format(.line(.quote)) }
            divider
            button("at", "Mention a task, event or note  [[") { controller.startMention() }
            button("photo", "Add an image") { controller.addImage() }
            Spacer(minLength: 0)
        }
    }

    private var divider: some View {
        Rectangle().fill(theme.line).frame(width: 1, height: 14).padding(.horizontal, 3)
    }

    private func button(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.muted)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Small pictures of the images in a text. The text itself shows only the name of each image.
struct ImageStrip: View {
    var text: String
    var controller: EditorController
    var services: EditorServices
    /// Called with the new text when the user removes an image.
    var onRemove: (String) -> Void
    @Environment(\.theme) private var theme
    @State private var hovered: String?

    var body: some View {
        let ids = ReferenceParser.imageIDs(in: text)
        if !ids.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ids, id: \.self) { id in thumb(id) }
                }
                .padding(.vertical, 2)
            }
            .popover(item: Binding(get: { controller.previewImageId.map(PreviewID.init) }, set: { controller.previewImageId = $0?.id })) { item in
                preview(item.id)
            }
        }
    }

    private struct PreviewID: Identifiable { var id: String }

    private func thumb(_ id: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = services.loadImage(id) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo.badge.exclamationmark").foregroundStyle(theme.muted)
                }
            }
            .frame(width: 72, height: 54)
            .background(theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.line, lineWidth: 1))
            .onTapGesture { controller.previewImageId = id }

            if hovered == id {
                Button { onRemove(MarkdownEdit.removeImage(id: id, from: text)) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white, Color.black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(3)
                .help("Remove this image")
            }
        }
        .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
    }

    private func preview(_ id: String) -> some View {
        Group {
            if let image = services.loadImage(id) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 520, maxHeight: 420)
            } else {
                Text("This image is gone.").foregroundStyle(theme.muted).padding(20)
            }
        }
        .padding(8)
    }
}

/// An editor with its buttons and its image strip. Use this wherever a task or note has text.
struct RichTextField: View {
    @Binding var text: String
    var services: EditorServices
    var placeholder = ""
    var minHeight: CGFloat = 80
    var refreshToken = 0
    var onEnd: () -> Void = {}
    @State private var controller = EditorController()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EditorToolbar(controller: controller)
            RichTextEditor(text: $text, controller: controller, services: services,
                           minHeight: minHeight, placeholder: placeholder, refreshToken: refreshToken, onEnd: onEnd)
            ImageStrip(text: text, controller: controller, services: services) { text = $0 }
        }
    }
}
