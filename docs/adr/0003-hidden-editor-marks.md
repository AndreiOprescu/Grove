# ADR 0003 · The saved text stays Markdown, and the screen hides the marks

Status: Proposed (2026-10-16; the owner said yes to it in the plan of 2026-10-15, the owner marks it Accepted)

## Context
A rich text box (a note, a task's notes, an event's notes) showed dim Markdown marks: `**`, `*`, `` ` ``, `# `, `> `.
The owner wants Grove to work for people who know nothing technical.
So no mark may show on screen, and every format must be on the toolbar.
The owner also asked for more formats: underline, strike, highlight in 4 colours, text size, a divider, and links with their own words.
Notes, tasks and events already store their text as Markdown, and the sync, the search, the checklist tasks and `@date` read that text.

## Decision
- The saved text stays Markdown. Nothing in the database, the sync or the export changes.
- The rich text box hides every mark on screen. The words keep their format.
- A switch in Settings → Notes, "Show marks", brings the dim marks back. It is off at first and kept per device (`notes.showMarks`).
- Marks that the user types or pastes still turn into format, and then they hide.
- These are the new stored marks:

| Format | Mark |
|---|---|
| Strike | `~~x~~` |
| Underline | `<u>x</u>` |
| Highlight, yellow | `==x==` |
| Highlight, green, blue or pink | `=={green}x==`, `=={blue}x==`, `=={pink}x==` |
| Link with own words | `[words](https://url)` |
| Divider | a line that is only `---` |
| Text size Big, Medium, Small | `# `, `## `, `### ` (`####` and more show as Small) |

- `~~` and `==` follow the spacing rules of bold, so `a == b` stays plain.
- Places that show plain words (search, the note preview, checklist task titles, `@date` titles) drop the marks (`MarkdownPlain`).

## Options
- A new stored format (for example a tree of styled pieces). Rejected: it rewrites every old note, it needs a change to the sync, and the checklist tasks and `@date` read the lines of the text.
- `++x++` for underline. Rejected: fewer Markdown apps read it. `<u>x</u>` is HTML, and many Markdown apps show it as underline.
- Keep Markdown and hide the marks on screen (chosen). Old notes stay as they are, and other apps can still read the text.

## Consequences
- The editor must move the caret over hidden marks, and keep marks in pairs on delete, cut and paste. These rules are in `app/lib/core/parsing/markdown_edit.dart` and `app/lib/ui/editor/markdown_controller.dart`.
- Copy to another app gives plain words. A copy and paste inside Grove keeps the format (`RichClipboard`). No new package.
- Text with these marks, pasted from another Markdown app, shows its format in Grove.
