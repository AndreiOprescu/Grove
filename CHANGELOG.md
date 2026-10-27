# Grove versions

Each version is one merge into `main`. Work on other branches waits for that merge, which
makes the next version. Each line is one feature. The newest version is first.

`scripts/github_release.sh` puts the lines of the version on its GitHub release.

## 1.3.0 · 2026-10-26

- **Notebooks:** the Notes screen has a sidebar with All notes, Inbox, Daily, Weekly, Pinned, Meetings, With tasks and Archive, your own notebooks with sections and colours, and your tags. Drag a note to sort it, move it with "Move to notebook…", and archive notes you are done with.
- **Reorganise rest of day:** a button next to "Timeline" on today's planner. Say how much of each open task and goal block you have done with a bar or a number, and Grove plans what is left from now until your sleep line: tasks with a deadline first, then goals, then other tasks. What does not fit goes back to today's list. One ⌘Z undoes it all.
- **Notes panel removed from the dock:** the dock at the top left now has Tasks, Goals and Deadlines. Notes live on the Notes screen.

## 1.2.0 · 2026-10-21

- **Plan tomorrow:** Grove learns when you usually fall asleep from when you stop using your phone and Mac, and reminds you to plan tomorrow before bed. On the Mac, closing the window keeps Grove in the menu bar, and it opens at login.
- **No empty day notes:** Grove no longer makes a note for a day by itself. Press "Start a note" to make one. A day note you leave empty is deleted.
- **Weather low and high:** each day shows its lowest and highest temperature.
- **Activities:** reserve time that is not a task, like lunch or a train ride. Drag a new block in the Planner and press "Activity" under the title. It has soft stripes and no checkbox, and it never counts as done or late.
- **Agents screen:** a new tab shows what each agent does, live, on every device. Chat with the agent, link notes, tasks and files with "+", answer its questions, and press Apply on the plan changes it proposes. Jobs queue and run in the background. You can stop a job at any time.

## 1.1.0 · 2026-10-21

- **Ask the agent:** a computer with the `claude` command reads a task and writes a draft for you. It only reads and drafts. A phone can ask, and the computer does the work.
- **Day menu:** right-click a day name in the Planner or a day in the Calendar (on a phone, press and hold). Add an event, a deadline or a task to that day, or open its daily or weekly note.
- **Weather:** each day in the Planner shows the weather at the top, from your location or a town you pick.
- **Wake-up and sleep lines anywhere:** right-click empty time in any day of the Planner to add the wake-up or sleep line at that time, or to move it there.
- **Scrolling is safe:** a two-finger scroll over the edge of a block no longer makes the block longer or shorter.

## 1.0.0

- **First Grove for macOS, Windows, Android and iOS:** the Flutter app, with sync between your devices.
