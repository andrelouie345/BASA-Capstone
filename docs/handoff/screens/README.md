# Screens

What each screen of BASA needs from the backend: which ViewModel calls serve it, what it can refuse, and which console command shows the real output. Layout, visuals and navigation are yours and are not in here. Start with `../README.md` (the start-here guide); `../checklist.md` lists every screen.

## Files

| File | Covers |
|------|--------|
| `common.md` | what every screen needs: who is signed in, pickers, online/offline, errors |
| `auth.md` | sign-in (online/offline), password change, server settings, version check |
| `admin.md` | users, schools, sections, learners, tutor assignments, SF1 import, login logs, first admin |
| `crla.md` | CRLA assessment, results, stories, thresholds, scoresheet import/export |
| `phil-iri.md` | GST, Phil-IRI sessions, readings, miscues, answers, rubric, results, content, thresholds |
| `aral.md` | ARAL roster, classes, sessions/attendance, IRIP, check-ins, materials, readability, reports, settings |
| `reports.md` | NLA report, progress monitoring, BOSY masterlist, SRP, report settings |
| `dashboard.md` | dashboard summary, round calendar, reminders, trends |
| `sync.md` | pull, upload, status, conflicts, approver review |

## How to read a screen block

```
### <Screen name>
Build: tutor | admin | both    Roles: tutor / coordinator / admin / superadmin
Purpose: one line.
Calls:
- `Vm.method(args)` → `ReturnType` — what for
Live previews: synchronous calls used while the user types (or "none").
Errors: refusals the ViewModel raises (`ViewModelException.message`, shown as is).
Console: the command(s) that show the real output.
```

- `Vm` is the ViewModel's class; a screen gets it from `BasaScope.of(context)` (both builds) or `AdminScope.of(context)` (admin build only). See `common.md`.
- "admin:" in front of a call = admins and coordinators only (the ViewModel refuses tutors); those screens are in the admin build.
- "Not available yet: …" = a need the backend does not serve yet; leave it out of the screen or ask the backend owner.
- `Console:` = run that command in the debug console to see what the call returns with real data.

History of how these lists were checked: `gap-history.md` (not needed to build screens).
