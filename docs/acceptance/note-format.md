# Note format: no marks on screen, a bigger toolbar — proof

Branch `feat/xp-note-format`, from `feat/cross-platform-flutter` at base commit `bb33cd4` (`git merge-base HEAD origin/feat/cross-platform-flutter`). Flutter app only. No new package. No change to the database, the sync or the Supabase SQL.
The owner's wish: rich text boxes that people who know nothing technical can use. No marks on screen, every format on the toolbar, and more tools. The owner answered every question in a grilling session on 2026-10-15. The decision is ADR 0003 (`docs/adr/0003-hidden-editor-marks.md`). Words: `CONTEXT.md` (Rich text box, Format, Mark). Small decisions: the "Note format" lines in `docs/assumptions.md`.
Check: `./scripts/flutter_test.sh` (2026-10-16: 3043 tests passed, none skipped, analyze clean, format clean, pure-Dart check clean).

## What was built

| Part | File |
|---|---|
| The reader of the marks: strike, underline, highlight with a colour, link with words, divider, empty pair | `app/lib/core/parsing/markdown_spans.dart` |
| Plain words with no marks | `app/lib/core/parsing/markdown_plain.dart` (`MarkdownPlain.text`) |
| Plain words in search, the note preview, checklist task titles and `@date` titles | `app/lib/core/parsing/reference_parser.dart`, `app/lib/state/rules/notes_rules.dart`, `app/lib/state/store_note_tasks.dart`, `app/lib/core/parsing/at_date.dart` (`AtDatePlan.plainTitle`), `app/lib/state/store_at_date.dart` |
| The edit rules: formats on a selection or at a caret, headings, clear format, links, divider, delete and type beside marks | `app/lib/core/parsing/markdown_edit.dart` (`MarkdownEdit`) |
| Undo and redo in a text box | `app/lib/core/parsing/edit_history.dart` (`EditHistory`) |
| The part of a text that a copy takes | `app/lib/core/parsing/markdown_slice.dart` (`MarkdownSlice.of`) |
| Hidden marks, the caret over them, the looks of the new formats, the divider line | `app/lib/ui/editor/markdown_controller.dart` (`MarkdownController`, `EditorDivider`) |
| The toolbar with a "…" menu, the keys, the link bubble | `app/lib/ui/editor/rich_text_field.dart` (`EditorToolbar`, `ToolSpec`, `RichTextFieldState`) |
| The link window and the link bubble | `app/lib/ui/editor/link_dialog.dart` (`LinkDialog`, `LinkBubble`, `linkTarget`) |
| Copy, cut and paste | `app/lib/ui/editor/rich_clipboard.dart` (`RichClipboard`) |
| The "Show marks" switch and its pref `notes.showMarks` | `app/lib/ui/settings/settings_tabs.dart`, `app/lib/state/editor_services.dart`, `app/lib/state/store_editor.dart`, `app/lib/ui/calendar/event_editor.dart` |
| Save is off in a window until the input is right | `app/lib/ui/planner/planner_dialogs.dart` (`dialogButtons`) |

## Proof for each choice of the owner

| Choice (plan, 2026-10-15) | Proof |
|---|---|
| Saved text stays Markdown. Only the screen hides the marks | `rich_text_field_test.dart`: "the marks of a format are hidden", "the mark of a heading is hidden", "each piece keeps its length"; `markdown_controller_test.dart`: "the marks of formats, headings and dividers are hidden". The text of the box still has its marks in each of these |
| Typed and pasted marks still turn into format, then they hide | `markdown_controller_test.dart`: "the marks of formats, headings and dividers are hidden" (the marks are read from the text, however they got there); `rich_text_field_test.dart`: "other text goes in as it is, and its marks make format". By hand: type `**hi**` in a note; "hi" is bold and no stars show |
| It works in every rich text box: notes, a task's notes, an event's notes | `notes_view_test.dart`: "the marks are hidden at first, and show as soon as the switch in Settings is on"; `task_inspector_test.dart`: "the description is the editor with its row of buttons"; pictures drawn again: `notes_desktop_*`, `notes_phone_grove_light_note.png` (`f9_golden_test.dart`), `task_panel_phone_grove_*.png` (`tasks_golden_test.dart`), `event_card_phone_grove_light.png` (`f9_golden_test.dart`). By hand: type `**hi**` in a task's notes and in an event's notes; no stars show |
| Settings → Notes has "Show marks", off at first, kept per device | `settings_view_test.dart`: "\"Show marks\" is off at first and kept on this device"; `rich_text_field_test.dart`, group "\"Show marks\"": "is off at first: the marks are hidden", "the text changes as soon as the switch does"; `markdown_controller_test.dart`: "with \"Show marks\" on nothing is hidden" |
| New tools: underline, strike, highlight in 4 colours, text size, divider, link with own words, undo, redo, clear format, indent in and out | `editor_toolbar_test.dart`: "780: every tool in its group, and no \"…\"", "Text size sets the size of the line", "Highlight uses the last colour; the arrow picks another", "Divider puts a line under the text", "Clear format takes every format off", "Indent in and out move a list item", "Undo and Redo are grey with nothing to take back"; `markdown_edit_test.dart`: "wraps the selected words in each mark", "sets, changes and takes off the heading mark"; `markdown_spans_test.dart`: "strike, underline and highlight", "a highlight can have a colour", "a link with words", "a line of three dashes is a divider"; `rich_text_field_test.dart`: "the keys take back typed words and do them again", "Ctrl-Y does again what undo took back, on Windows" |
| Code moves into "…" | `editor_toolbar_test.dart`: "340: the short row, and \"…\" holds the rest" (Code is in "…" and works from there). In a wide box Code stays in the row, as every tool fits |
| Wide box: all tools. Narrow box: Undo · Text size · Bold · Italic · Underline · Highlight · Bullet list · Checklist · Link · "…" | `editor_toolbar_test.dart`: "780: every tool in its group, and no \"…\"", "340: the short row, and \"…\" holds the rest", "300: the link goes into \"…\" too" |
| Buttons light up when the caret is in that format | `editor_toolbar_test.dart`, group "tools light up": "Bold is on in bold words, and off outside", "Text size shows the size of the line", "Highlight is on, and its menu ticks the colour"; "a row in \"…\" shows a tick when its format is on" |
| Highlight is a split button: a click gives the last colour, the arrow gives 4 colours and "No highlight" | `editor_toolbar_test.dart`: "Highlight uses the last colour; the arrow picks another", "Highlight is on, and its menu ticks the colour"; `markdown_edit_test.dart`: "a highlight changes colour, the same colour takes it off" |
| ⌘K or Ctrl+K in a box makes a link. Outside a box it opens the command palette | `app_menus_test.dart`, group "Command-K and Command-Z in a text box": "on a Mac the key opens the palette out of a text box, and the link window in one", "off a Mac the key opens the palette out of a text box, and the link window in one"; `rich_text_field_test.dart`, group "the link window": "the key opens it with the selected words; Save is off until the address is a web address", "Command-K on a Mac" |
| A click on a link opens a bubble: Open, Edit, Remove (a bare address: Open, Edit). Open allows only http and https | `rich_text_field_test.dart`, group "web links": "a click on a web link shows a bubble and opens nothing yet", "Open in the bubble opens the browser and closes the bubble", "a link with its own words: Open, Edit and Remove", "Remove keeps the words as plain text", "Edit opens the link window with the link filled in", "with no browser the bubble has no Open"; `store_app_tools_test.dart`: "a click shows the bubble; Open opens the browser" |
| Text typed right after a link is plain. Text typed right after bold stays bold | `rich_text_field_test.dart`: "a letter typed right after a link is plain text", "Bold at a caret, then a letter: a bold letter"; `markdown_edit_test.dart`: "the next letter pulls the format forward" |
| Copy to other apps gives plain words. Copy and paste inside Grove keeps the format | `rich_text_field_test.dart`, group "copy, cut and paste": "copy gives plain words to the clipboard", "a copy pasted in another box keeps bold", "a copy of half a bold word keeps bold on that half", "cut gives plain words and keeps the marks in pairs", "Copy and Paste of the menu go the same way" |
| Paste from the web gives plain words. No new package | `rich_text_field_test.dart`: "other text goes in as it is, and its marks make format" (only the plain text of the clipboard is read). `app/pubspec.yaml` and `app/pubspec.lock` did not change on this branch |
| Places with plain words drop the marks | `reference_parser_test.dart`: "search text drops format marks"; `notes_rules_test.dart`: "preview drops the new marks and divider lines"; `note_task_store_test.dart`: "a box with formats makes a task with plain words"; `at_date_test.dart`: "the planner title has no marks, the title keeps them" |

## Still to check by hand

Nobody has looked at this in the running app yet. Build with `./scripts/flutter_build.sh macos`, install with `./scripts/flutter_install.sh`, then:

- ⌘K in a note opens the link window. ⌘K outside a text box opens the command palette.
- A click on a link in a note shows the bubble. Open, Edit and Remove each work.
- Copy bold words from a note and paste them in TextEdit: plain words, no `**`.
- Copy bold words from one note and paste them in another note: they stay bold.
- In the Vintage theme, a divider (`---`) sits on the ruled lines and does not make its line taller.
- At phone width (or in the narrow task panel), the toolbar shows the short row and a "…" menu with the other tools.
