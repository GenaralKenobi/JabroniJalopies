# Fleet Maintenance (iOS)

A SwiftUI app for running a vehicle fleet. It covers morning checklists, defect reporting, a quick-reference spec card for each vehicle, maintenance reminders, and service history. Managers and drivers share a fleet, and checklists work without signal.

**Built with:**
- SwiftUI on iOS 17 or later
- Firebase: Authentication, Firestore and Cloud Storage

[Screenshots](../../tree/ci-screenshots) are captured automatically by CI on every push to `main`.

**Start here:** [YOUR_TODO.md](YOUR_TODO.md) lists what you need to do and the open questions. [DECISIONS.md](DECISIONS.md) lists choices waiting for your review.

## Features

### Fleets, people and roles
- People are invited by email. Each person creates their own login and confirms their email.
- One login can belong to several fleets. Each fleet has its own profile (name, phone) and role.
- Roles:
  - **Manager:** edits vehicles, checklists and specs; approves services; closes defects; manages members; sees costs.
  - **Driver:** completes checklists, reports problems, logs services (which need sign-off) and updates the odometer.
- Everyone sees every vehicle by default. A manager can limit a driver to the vehicles assigned to them.

### Morning checklists
- Managers build checklist templates. Every item is pass/fail.
- For each item, the manager decides whether it also asks for a number reading (for example tire pressure in PSI) and whether it's a safety item.
- When an item fails, the app asks for a photo, but a photo isn't required.
- A failed safety item marks the vehicle **UNSAFE TO DRIVE**. Everyone sees a strong warning, including anyone who starts another checklist on that vehicle.
- **Repeating items:** an item can repeat weekly, monthly or every N days instead of on every checklist.
  - Each truck remembers when each repeating item was last done, and this works offline.
  - When an item isn't due, it moves to a "Not due yet" section and can be done early.
  - The truck page shows how many repeating items are due.
- If an item already has an open defect, the driver chooses **Still a problem** or **Looks fixed** (with a required note) instead of plain pass/fail. A later "pass" never erases an earlier problem.
- **Checked today:** the fleet list shows which trucks have been checked today, and each truck shows when and by whom its last checklist was done.
- **Daily reminder:** a manager can turn on a daily checklist reminder at a set time. It appears on every member's phone.

### Defects
- Defects can only be closed by a manager, as **Repaired** or **Not a defect**.
- Each defect keeps a full history of who reported, confirmed or reported it fixed, and when.
- When a report reaches the server late, the defect shows both the time it was reported on the phone and the time it reached the server.

### Offline first
- Firestore's on-device cache lets drivers view vehicles and specs, and submit checklists, with no connection.
- Changes sync automatically when the phone is back online.
- Defect **text uploads first**. **Photos are saved on the phone** and upload separately whenever there's signal. They retry after the app restarts and in background refreshes, so a problem gets flagged even when a photo can't get through.
- A banner shows when the phone is offline or photos are waiting to upload. Records that haven't synced yet are marked "Waiting to sync".

### Vehicle specs quick view
- A glanceable card for each vehicle: fluids, tires and wheels (with pressures emphasized), and parts and capacities.
- Managers can edit values and add, rename or remove fields and whole sections. Empty fields are hidden from drivers.

### Chainsaws, ropes and chains
- **Chainsaws and ropes** are tracked individually on each truck. Only managers can add them, edit them, or move them between trucks, and each item's history moves with it.
- **Equipment problems:** anyone on the truck can report a problem on a saw or rope, with an optional photo, even offline.
  - These problems don't flag the truck itself. Instead, an orange or red banner on the truck page, and a badge in the fleet list, warn everyone who uses that truck.
  - Saws can be marked **Do not use** by anyone. Ropes can be marked **Do not use** by managers only.
- **Rope length:** anyone can submit a length reduction, which applies only after a manager approves it. Submissions can't be withdrawn. A rope shorter than its optional minimum length is flagged.
- **Chains:** each truck has its own chain sizes, set by managers, and shows how many sharp chains of each size it has.
  - **Empty Used Chain Box:** at the end of the day, record how many chains are dull and need resharpening, and how many are thrown away.
  - **Add Chains:** anyone can record chains put on any truck, new or back from sharpening.
  - Counts change by adding and subtracting, so logs made offline by several people all count. If a count goes below zero, it's flagged for a manager to correct.
- **Managers only:** fleet-wide chain totals per size for the week, month and year, plus an all-equipment list that includes items not currently on a truck.

### Maintenance and services
- Maintenance reminders can be based on distance, time, or whichever comes first. Managers get a notification when time-based reminders come due.
- Drivers can log services, but they count only after a manager signs off. An approved service resets matching reminders.
- Costs, the 12-month cost chart and cost totals are visible to managers only. Service history can be exported as CSV.

### Data, storage and privacy
- Records are deleted automatically after 5 years. Managers can delete old records earlier.
- Storage use is tracked against Firebase's free allowances. Managers get an in-app warning and a notification at 80%.
- In-app account deletion is included.
- Signing out wipes the on-device copy of the fleet's data. It warns first if checklists or photos haven't synced yet.
- The distance unit (miles or kilometres) is a fleet setting, so everyone enters odometer readings the same way.
- There's no analytics, no ads and no location tracking. See [PRIVACY.md](PRIVACY.md) for the draft privacy policy.

## Setup

1. **Firebase:** follow [FIREBASE_SETUP.md](FIREBASE_SETUP.md). It takes about 15 minutes in a browser and ends with adding `GoogleService-Info.plist`. Builds without that file show a "Firebase not set up" screen.
2. **Install on iPhone without a Mac:** follow [TESTFLIGHT.md](TESTFLIGHT.md). GitHub Actions builds, signs and uploads to TestFlight.
3. **With a Mac (optional):**

```bash
brew install xcodegen
```

```bash
xcodegen generate && open VehicleMaintenance.xcodeproj
```

## Project layout

```
VehicleMaintenance/
├── App/          Entry point, routing, tab bar
├── Models/       Firestore documents (fleets, members, vehicles, checklists, inspections, defects…)
├── Logic/        Pure, unit-tested logic: checklist → defect planning, due dates, usage, specs, CSV
├── Backend/      Firebase setup, auth, session/fleet models and actions, offline photo queue
└── Views/        SwiftUI screens by feature
VehicleMaintenanceTests/   Swift Testing unit tests
firebase/
├── firestore.rules, storage.rules   Security rules (roles, visibility, defect lifecycle)
├── firestore.indexes.json           5-year TTL policies
├── storage-lifecycle.json           5-year photo retention
├── tests/                           Rules tests run against the emulators
└── scripts/seed-demo.mjs            Demo data for screenshots
```

## Continuous integration

`.github/workflows/ios.yml` runs on every push:

1. **Security rules tests** against the Firebase emulators. These check roles, vehicle visibility, invites, defect closing, service sign-off and photos.
2. The app build and **unit tests** on an iPhone simulator, plus an unsigned **Release** build.
3. **Screenshots:** starts the Firebase emulators, seeds a demo fleet, and screenshots the main screens. They're published to the [`ci-screenshots`](../../tree/ci-screenshots) branch.

`.github/workflows/firebase-deploy.yml` deploys the rules, TTL policies and photo lifecycle once it's configured. `.github/workflows/testflight.yml` uploads builds to TestFlight.
