# Your to-do list and open questions

This file has three parts:
- **Part 1** is what only you can do.
- **Part 2** is questions only you can answer.
- **Part 3** is what still hasn't been tested.

Decisions I made that you should check are in [DECISIONS.md](DECISIONS.md).

## 1. Things for you to do

### Now: Firebase (about 15 minutes in a browser)

Full steps are in [FIREBASE_SETUP.md](FIREBASE_SETUP.md).

- [ ] Create the Firebase project, with **Google Analytics off**.
- [ ] Add the iOS app with bundle ID `com.genaralkenobi.maintenance`, unless you change it (see question 3).
- [ ] Download `GoogleService-Info.plist` and upload it to `VehicleMaintenance/Resources/` in this repository.
- [ ] Turn on **Email/Password** sign-in.
- [ ] Create the Firestore database in **us-central1**. You can't change the location later.
- [ ] Deploy the security rules and the 5-year automatic deletion settings. The automatic option needs a service-account key added as a GitHub secret; the manual option means pasting the rules in.
- [ ] **Recommended:** switch to the **Blaze** (pay-as-you-go) plan and **set a budget alert** of about $5.
  - It's required for photos.
  - With around 25 people opening the app several times a day, daily database reads can get close to the free plan's limit. On Blaze the extra costs cents; on the free plan the app stops syncing for the rest of the day.
- [ ] **Optional, for photos:** enable Cloud Storage, deploy the storage rules and photo retention, then turn on Settings → Defect Photos in the app.
- [ ] **Optional:** in Authentication → Templates, change the verification and password-reset emails to show your company name. Tell drivers to check their spam folder for the confirmation email.

### When your Apple developer account is approved

Full steps are in [TESTFLIGHT.md](TESTFLIGHT.md).

- [ ] Register the bundle ID and create the app in App Store Connect.
- [ ] Create an App Store Connect API key with **Admin** access.
- [ ] Add the four GitHub secrets, then tell me so I can run and fix the first TestFlight upload.
- [ ] Decide how drivers get the app (see question 5).
  - **Internal TestFlight testers** must be users on your App Store Connect team, up to 100.
  - **Everyone else** joins as an external tester through a public link, after a short Apple beta review.

### Before the App Store (if you publish there)

- [ ] **Privacy policy:**
  - Fill in the brackets in [PRIVACY.md](PRIVACY.md).
  - Host it at a public web address.
  - Send me the address so I can update the in-app link. It currently points at this repository, which won't open for others if the repository is private.
- [ ] **App Store Connect listing:**
  - name, subtitle and description
  - support URL or email
  - age rating questionnaire
  - screenshots (6.9" iPhone; also iPad if you keep iPad support)
- [ ] **App Privacy questions in App Store Connect.** Answer them as:
  - **Data collected:** name, email address, phone number, photos, other user content, and user ID.
  - **Use:** all of it is linked to the user, used for App Functionality, and **not** used for tracking.
- [ ] **Demo account for Apple's reviewers:** the app requires a login, so App Review needs a manager account with a sample fleet. Create one in your real Firebase project and enter it under App Review Information.

### Before rolling out to the crew

- [ ] Try it on two real iPhones:
  - one as a manager and one as a driver
  - invite → confirm email → join
  - complete a checklist **in airplane mode**, then turn airplane mode off and watch it sync
  - take a defect photo on weak signal
- [ ] Tell drivers to sign up with the **same email** you invite, and to confirm it.

## 2. Questions for you

1. **Is the GitHub repository public or private?** This affects where the privacy policy can live and whether the Firebase config file should be in the repository.
2. **What should the app be called?**
   - The home-screen name is currently "Maintenance".
   - The sign-in screen says "Fleet Maintenance".
   - The App Store name has to be unique.
3. **Is `com.genaralkenobi.maintenance` the bundle ID you want?** It can't be changed after release. If you'd prefer your company's domain (e.g. `com.yourcompany.fleet`), tell me **before** registering it with Apple or Firebase.
4. **iPhone only, or iPhone and iPad?** Supporting iPad means also providing iPad screenshots and checking the iPad layout. iPhone-only is simpler.
5. **How will drivers install it?**
   - TestFlight only
   - an unlisted App Store link: not searchable, anyone with the link can install
   - fully public on the App Store
   - private distribution to your company through Apple Business Manager
6. **Daily checklist reminder:** every day, weekdays only, or a different time per driver? (DECISIONS.md #21)
7. **Instant alerts:** do you want managers to get a push notification the moment a driver reports a defect? This needs the Blaze plan, a small server function and an Apple push key. It should cost $0 at your size.
8. **Company name and contact email** for the privacy policy and App Store listing.
9. **Currency:** service costs show in the phone's local currency. Is everything in US dollars?
10. **Members list:** should drivers see each other's phone numbers and emails? Right now every member can see the members list.
11. **App icon:** keep the orange wrench, or use your company logo? I'd need a square image.
12. **DECISIONS.md:** 26 items. Reply with any numbers you want changed.

## 3. Not tested yet

- **What has been tested:** everything builds on GitHub's Macs, and the unit tests pass. Every screen was checked on an **iPhone simulator** against **local Firebase emulators**. **Security rules tests** run against the emulators on every push; the latest run passed 38 of 38.
- **What hasn't:**
  - a **real iPhone**
  - your **real Firebase project**
  - the real **camera**
  - background photo uploads
  - notifications
  - the **TestFlight upload**
- **Sign-out:** wiping the on-device copy of the data on sign-out is untested on a real phone.
