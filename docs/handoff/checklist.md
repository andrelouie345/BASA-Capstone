# Screen checklist

One row per screen. Write your name in **Assigned** when you take a screen, and keep **Status** up to date: `not started`, `in progress`, `pushed`, `done`. Each **Doc** link opens the screen block with the ViewModel calls it needs.

**Kind:** `screen` = a screen of its own; `menu item` = an action in a menu, not a screen; `shared part` = something every screen uses (build it once, reuse it); `app-wide` = a whole-app job.

## Examples to replace

These exist only to show how things fit together. Restyle or replace them in your own style:

- `ExampleScreen` (`lib/ui/example/example_screen.dart`): the worked example (Dashboard home). Debug build only, opened from the debug console. Replace it with the real screen.
- `BasaHomeScreen` (`lib/app_shell.dart`): placeholder home that shows one text value. Replace it with the real home screen and navigation.
- `BasaStartupErrorApp` (`lib/app_shell.dart`): shown when the data folder cannot be prepared. Keep what it does; restyle it freely.

The debug console (`lib/ui/debug/`) is a developer tool, not an app screen: leave it as it is.

## Screens

| # | Screen | Kind | Build | Doc | Assigned | Status |
|---|--------|------|-------|-----|----------|--------|
| 1 | Signed-in user | shared part | both | [common.md](screens/common.md#signed-in-user) | Andre | pushed |
| 2 | Pickers | shared part | both | [common.md](screens/common.md#pickers) | Andre | pushed |
| 3 | Online / offline and pending work | shared part | both | [common.md](screens/common.md#online--offline-and-pending-work) | Andre | pushed |
| 4 | Version refusal | shared part | both | [common.md](screens/common.md#version-refusal) | Andre | pushed |
| 5 | Error display | shared part | both | [common.md](screens/common.md#error-display) | Andre | pushed |
| 6 | Sign in (online), with the server settings dropdown | screen | both | [auth.md](screens/auth.md#sign-in-online) | Andre | pushed |
| 7 | Sign in offline | screen | both | [auth.md](screens/auth.md#sign-in-offline) | Andre | pushed |
| 8 | Change password | screen | both | [auth.md](screens/auth.md#change-password) | Andre | pushed |
| 9 | Sign out | menu item | both | [auth.md](screens/auth.md#sign-out) | Andre | pushed |
| 10 | Server settings | screen | both | [auth.md](screens/auth.md#server-settings) | Andre | pushed |
| 11 | About / version | menu item | both | [auth.md](screens/auth.md#about--version) | Andre | pushed |
| 12 | Users | screen | admin | [admin.md](screens/admin.md#users) |  |  |
| 13 | Tutor assignments | screen | admin | [admin.md](screens/admin.md#tutor-assignments) |  |  |
| 14 | Schools | screen | both (list) / admin (edit) | [admin.md](screens/admin.md#schools) |  |  |
| 15 | Sections | screen | both (list) / admin (edit) | [admin.md](screens/admin.md#sections) |  |  |
| 16 | Learners and roster CSV | screen | both | [admin.md](screens/admin.md#learners-and-roster-csv) |  |  |
| 17 | Learner history | screen | admin | [admin.md](screens/admin.md#learner-history) |  |  |
| 18 | SF1 import (also in the hub) | screen | admin | [admin.md](screens/admin.md#sf1-import) |  |  |
| 19 | Login logs | screen | admin | [admin.md](screens/admin.md#login-logs) |  |  |
| 20 | First admin (bootstrap) | screen | admin | [admin.md](screens/admin.md#first-admin-bootstrap) |  |  |
| 21 | Section CRLA list | screen | both | [crla.md](screens/crla.md#section-crla-list) |  |  |
| 22 | Start a CRLA attempt | screen | both | [crla.md](screens/crla.md#start-a-crla-attempt) |  |  |
| 23 | Part 1 and Part 2 entry | screen | both | [crla.md](screens/crla.md#part-1-and-part-2-entry) |  |  |
| 24 | CRLA thresholds | screen | both (view) / admin (edit) | [crla.md](screens/crla.md#crla-thresholds) |  |  |
| 25 | Scoresheet export (CRLA2 template) | screen | both | [crla.md](screens/crla.md#scoresheet-export-crla2-template) |  |  |
| 26 | Scoresheet import (also in the hub) | screen | admin | [crla.md](screens/crla.md#scoresheet-import) |  |  |
| 27 | GST (Group Screening Test) | screen | both | [phil-iri.md](screens/phil-iri.md#gst-group-screening-test) |  |  |
| 28 | Section Phil-IRI sessions | screen | both | [phil-iri.md](screens/phil-iri.md#section-phil-iri-sessions) |  |  |
| 29 | Assessment session (reading, miscues, answers, rubric) | screen | both | [phil-iri.md](screens/phil-iri.md#assessment-session-reading-miscues-answers-rubric) |  |  |
| 30 | Learner results | screen | both | [phil-iri.md](screens/phil-iri.md#learner-results) |  |  |
| 31 | Finalize | screen | admin | [phil-iri.md](screens/phil-iri.md#finalize) |  |  |
| 32 | Content (collections, passages, questions, rubric) | screen | both (read) / admin (edit) | [phil-iri.md](screens/phil-iri.md#content-collections-passages-questions-rubric) |  |  |
| 33 | Phil-IRI thresholds | screen | both (view) / admin (edit) | [phil-iri.md](screens/phil-iri.md#phil-iri-thresholds) |  |  |
| 34 | Roster (section / school / tutor) | screen | both (view) / admin (edit) | [aral.md](screens/aral.md#roster-section--school--tutor) |  |  |
| 35 | Tutors | screen | both | [aral.md](screens/aral.md#tutors) |  |  |
| 36 | Classes | screen | both (view) / admin (edit) | [aral.md](screens/aral.md#classes) |  |  |
| 37 | Sessions and attendance | screen | both | [aral.md](screens/aral.md#sessions-and-attendance) |  |  |
| 38 | IRIP | screen | both | [aral.md](screens/aral.md#irip) |  |  |
| 39 | Check-ins | screen | both (take) / admin (report, cut-off) | [aral.md](screens/aral.md#check-ins) |  |  |
| 40 | ARAL settings | screen | both (view) / admin (set) | [aral.md](screens/aral.md#aral-settings) |  |  |
| 41 | Materials and recommendations | screen | both (read, recommend) / admin (catalog) | [aral.md](screens/aral.md#materials-and-recommendations) |  |  |
| 42 | Readability log (SHARP only) | screen | both | [aral.md](screens/aral.md#readability-log-sharp-only) |  |  |
| 43 | Implementation report and roster files (also in the hub) | screen | admin | [aral.md](screens/aral.md#implementation-report-and-roster-files) |  |  |
| 44 | NLA portal report (Phil-IRI JHS Form 2b + Division ARAL) | screen | admin | [reports.md](screens/reports.md#nla-portal-report-phil-iri-jhs-form-2b--division-aral) |  |  |
| 45 | Progress monitoring | screen | admin | [reports.md](screens/reports.md#progress-monitoring) |  |  |
| 46 | BOSY masterlist | screen | admin | [reports.md](screens/reports.md#bosy-masterlist) |  |  |
| 47 | SRP (Summer Remediation Program) | screen | both (own classes) / admin (build, edit) | [reports.md](screens/reports.md#srp-summer-remediation-program) |  |  |
| 48 | Report settings (done threshold, auto-approve, offline days) | screen | admin | [reports.md](screens/reports.md#report-settings-done-threshold-auto-approve-offline-days) |  |  |
| 49 | Reports & files (hub) | screen | admin | [reports.md](screens/reports.md#reports--files-hub) |  |  |
| 50 | Dashboard home | screen | both | [dashboard.md](screens/dashboard.md#dashboard-home) |  |  |
| 51 | Round calendar | screen | both (view) / admin (set) | [dashboard.md](screens/dashboard.md#round-calendar) |  |  |
| 52 | Reminders | screen | tutor reminders both; coordinator reminders admin | [dashboard.md](screens/dashboard.md#reminders) |  |  |
| 53 | Trends | screen | tutor activity both; the others admin | [dashboard.md](screens/dashboard.md#trends) |  |  |
| 54 | Get the latest from the server (pull) | screen | both | [sync.md](screens/sync.md#get-the-latest-from-the-server-pull) |  |  |
| 55 | Send my work (upload) | screen | both | [sync.md](screens/sync.md#send-my-work-upload) |  |  |
| 56 | Review uploads (approver) | screen | admin | [sync.md](screens/sync.md#review-uploads-approver) |  |  |
| 57 | Light and dark mode (whole app) | app-wide | both | [README.md](README.md#light-and-dark-mode) | Andre | pushed |
| 58 | Colours (customize light and dark, defaults preset) | screen | both | [auth.md](screens/auth.md#colours-light-and-dark-mode) | Andre | pushed |
