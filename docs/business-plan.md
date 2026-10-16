# Grove — business plan (draft)

Status: draft, written with the owner on 2026-10-15. It grows as we answer more questions.
Use it to choose what to build next. `PLAN.md` still says how each feature behaves.

## 1. Who Grove is for

University students, about 18 to 28 years old.

## 2. What Grove is

One app for the whole student life: schedule, tasks, notes and study goals.
The schedule is easy to change.
Grove is a mirror of the student: it shows what they really did.

## 3. The main promise

**Grove fixes your plan when you fall behind.**

Other apps (Google Calendar, Notion, Todoist) let missed work turn red and stay there.
Grove sees the missed work and suggests a new plan before the deadline.

## 4. Product decisions

| # | Topic | Decision | Why |
|---|-------|----------|-----|
| 1 | How Grove fixes the plan | Grove **suggests** a new plan. The student accepts with one tap, or drags blocks. Grove never moves work by itself. | Students keep control and learn to trust the plan. |
| 2 | Daily hook | A **mirror of progress**: weekly review (what I did, hours per subject, goals moved forward, what slipped). The plant grows with real work. No guilt streaks. | Fits "Grove is a reflection of the user". Streaks make people quit when they break. |
| 3 | First-day setup | **Import the uni timetable** by its calendar link (.ics from the university, Canvas, Moodle). Also import Google, Outlook and Apple calendars. | A full week in one minute. Slow setup loses students on day one. |
| 4 | Calendar link depth | **Read-only** at first. Grove shows outside events and does not change them. Two-way sync maybe later. | Cheap, fast to build, no Google security review. |
| 5 | Social | **Private first.** Shared group-project plans and "find a free time with friends" come later. | Simpler, safer for privacy. |
| 6 | Goals | **Study goals with a deadline**, for example "Pass Calculus exam on 12 Jan". Grove splits the goal into study blocks up to the date and warns when the student falls behind. | Links straight to the main promise. |
| 7 | Device focus | **Laptop first** for the first test, **Mac and Windows equally**. The phone app is for quick checks. | Students plan the week on a laptop. The drag-and-drop planner is best on a big screen. |
| 8 | Fall-behind message | **One calm daily check-in** (evening, or when the laptop opens): "2 blocks slipped. Here is a new plan for tomorrow." No live alerts. | Low annoyance. Students do not mute it. |
| 9 | Account | **Try first, no sign-up.** Data stays on the device. An account only to sync laptop and phone. | Fewer students leave on the first screen. |
| 10 | Task length | The student **guesses** a size (30m, 1h, 2h). Grove **tracks real time and learns**: "Your essays take 1.5x longer than you guess." | Better guesses make the fix-it plan work. Also feeds the weekly mirror. |
| 11 | AI | **Simple rules first** for the new plan (nearest deadline first, fill free gaps, keep breaks). AI maybe later, maybe as a paid extra. | Free to run, works offline, easy to explain, no student data sent out. |
| 12 | Notes | **Notes that serve the plan**: short notes linked to tasks, goals and days, a daily journal, links to lecture files. A full lecture-note feature comes later: issue #32. | Do not fight Notion and OneNote now. Keep the build small. |
| 13 | Look and feel | Two moods. **Calm and natural** (Grove theme) stays the default. A new **Bold** theme (strong colours, big numbers) comes too: issue #33. Keep Grove, Minimal, Futuristic. Vintage goes when Bold comes. | Calm fits the daily check-in. Bold suits students who like a push. |
| 14 | Breaks | **Stay useful in breaks**: summer jobs, internship applications, resits, personal goals. | Students keep the habit and do not drop Grove over summer. |
| 15 | Privacy promise | **Kept open.** No promise now about ads or data. | More money options later. Note: Grove holds very personal data, so any later choice must be clear to students and follow the law (GDPR in the EU/UK). |
| 16 | Test feedback | **Both.** (a) A "Send feedback" button in Settings and the Help menu, not on the main screens. Every 2 weeks, a small optional "How is Grove going?" card in the weekly review. (b) Anonymous usage counts (opens, plans fixed, check-ins done). | Words tell us why. Numbers tell us what. Usage counts need a consent screen; the service choice is still open. |

## 5. Launch

- Start at **one university** (the owner's). Test with 20 to 50 real students.
- Test starts at the **start of the next semester** (about late January or February 2027).
  Students set up a fresh timetable then, so calendar import is the perfect first step.
- Then grow to more universities by word of mouth.

## 6. How we know it works

Main number: **students still use Grove after 4 weeks.**
Target: 40% of testers still open Grove each week after one month.

## 7. Money

How Grove earns money: not decided yet. The owner wants to talk about it later.

### Costs before Grove earns anything

The owner chose a **small budget**, about €150 to €250 a year:

- Apple developer account: $99 a year. Needed for iPhone testers (TestFlight) and a trusted Mac app.
- Google Play account: $25 once.
- Supabase: free tier.
- Windows signing: **not for the test.** Testers get a 1-page install guide ("More info", then "Run anyway"). Pay for a Windows signing certificate (often €100 to €300 a year) before a public launch.

## 8. Open questions

- How Grove makes money.
- Who is in the first test group: mixed courses, or one course.
- Which service counts anonymous usage (extra Supabase tables, or a new service). Needs the owner's yes.

## 9. What this means for the build (first ideas)

1. Calendar import: paste a .ics link (uni timetable, Google, Outlook, Apple). Read-only.
2. "Fell behind" detection: find unfinished blocks at the end of the day.
3. Daily check-in screen: shows slipped work and a suggested new plan. One tap to accept.
4. Study goals with a deadline: split into blocks backward from the date (builds on the goal panel, PR #29).
5. Time tracking per task, and a "you guess X, it takes Y" insight.
6. Weekly review screen (the mirror). Plant growth tied to real finished work.
7. Start without an account. Ask for one only to turn on sync.
