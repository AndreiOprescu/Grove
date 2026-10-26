# ADR 0007 · Notes live in notebooks with sections, and archived notes leave the list

Status: Proposed (2026-10-26; the owner marks it Accepted)

## Context
Notes were one list with a few filters (All, Daily, Weekly, Pinned, a tag). With many notes the list is hard to use.
The owner picked "layout A": a sidebar of sections and notebooks, a list in groups, and the note.

## Decision
- **Data.** A new synced table of notebooks (name, colour, order) and one of their sections (name, order). A note gets `notebook_id`, `section_id`, `sort_order` and `archived_at`. Schema 14, migration `supabase/migrations/20261026000000_grove_sync_notebooks.sql`. A note is in one notebook or none, and in one section of it or none.
- **The home of a note** (`NotesRules.homeOf`): Archive when archived; else its notebook; else Daily or Weekly by kind; else Meetings when it is linked to an event; else Inbox. The breadcrumb and the place chip show it.
- **Sections of the sidebar** are fixed: All notes, Inbox, Daily, Weekly, Pinned, Meetings, With tasks, Archive. Then the notebooks, then the tags. An archived note shows only in Archive.
- **Order.** Notes in a notebook, notebooks and sections keep a fractional `sort_order`, so a drag changes one row and only it syncs. Outside a notebook the list is in date groups, the pinned notes on top.
- **Layout.** Three columns from a notes area 1000 wide; under that, a section picker above the list; on a phone, one page at a time (sections, list, note).
- **Deleting** a notebook or a section keeps its notes (in no notebook, or in no section). Undo brings back the places.

## Consequences
- The owner runs the schema 14 SQL once, or notebooks do not sync.
- An older Grove ignores the new columns: it shows archived notes in its list and does not keep the order of a notebook.
- Drag to sort works on a computer; a phone moves notes with the menu. Sorting notebooks by drag is not built yet.
