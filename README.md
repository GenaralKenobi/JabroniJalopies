# Vehicle Maintenance (iOS)

A SwiftUI + SwiftData app for tracking vehicle maintenance: service history, recurring
reminders by distance and/or time, costs, and due-date notifications.

**Requirements:** Xcode 15 or later, iOS 17 or later. No third-party dependencies.

## Features

- **Garage**: multiple vehicles with a photo, make, model, year, VIN, license plate and odometer reading.
- **Service log**: the date, odometer reading, service type, cost, shop and notes for each service. You can search it, and it's grouped by year with yearly totals.
- **Maintenance reminders**: due every *N* miles/km and/or *N* months, whichever comes first.
  - Status: *Up to date*, *Due soon* (within 500 units or 30 days) or *Overdue*.
  - Picking a service type pre-fills a typical interval (oil change: 5,000 mi / 6 months, and so on).
  - Logging a service automatically resets the matching reminder.
  - A local notification is sent on the morning a time-based reminder comes due.
- **Upcoming tab**: overdue and due-soon items across all vehicles.
- **Costs**: total spent, spending this year, and a 12-month bar chart (Swift Charts).
- **Export**: a vehicle's service history as CSV through the share sheet.
- **Settings**: miles or kilometers, and notification permission.

## Getting started

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
open VehicleMaintenance.xcodeproj
```

Then select your development team under *Signing & Capabilities*, change the bundle ID
(`com.example.VehicleMaintenance`) and run. In debug builds, **Settings → Load Sample Data**
fills the app with demo vehicles.

<details>
<summary>Without XcodeGen</summary>

1. In Xcode, choose File → New → Project → iOS App (SwiftUI interface, SwiftData storage), name it `VehicleMaintenance` and set iOS 17 as the minimum.
2. Delete the generated `ContentView.swift`, `Item.swift` and `VehicleMaintenanceApp.swift`.
3. Drag the `VehicleMaintenance/` source folders into the project.
4. Add `VehicleMaintenanceTests/LogicTests.swift` to a unit-test target.
</details>

## Continuous integration

`.github/workflows/ios.yml` runs on every push on a GitHub-hosted Mac. It:

1. generates the project with XcodeGen
2. builds the app and runs the unit tests on an iPhone simulator
3. launches the app with demo data and screenshots each tab in light and dark mode

The build log, test results and screenshots are uploaded as the `ios-build-results` artifact on each run.

## Project layout

```
VehicleMaintenance/
├── App/            App entry point and tab bar
├── Models/         SwiftData models (Vehicle, ServiceRecord, MaintenanceReminder) and enums
├── Logic/          Pure, unit-tested logic: due-date math, cost aggregation, CSV, number parsing
├── Services/       Notifications, image downscaling, CSV export, sample data
├── Views/          SwiftUI screens grouped by feature
└── Resources/      Asset catalog (app icon, accent color)
VehicleMaintenanceTests/  Swift Testing unit tests
```

## Notes

- All model properties have defaults and relationships are optional, so the schema is ready
  for iCloud sync. To turn it on, add the iCloud (CloudKit) and Background Modes (Remote
  notifications) capabilities.
- Odometer values are stored in whichever unit you choose. Switching units doesn't convert existing readings.
- Add a 1024×1024 PNG to `Resources/Assets.xcassets/AppIcon.appiconset` for the app icon.

## Ideas for next steps

- Fuel log with MPG/L per 100 km tracking
- Receipt photos and documents attached to service records
- VIN decoding to fill in make, model and year automatically
- Home screen widget showing the next due item
- iCloud sync and sharing a vehicle with family members
