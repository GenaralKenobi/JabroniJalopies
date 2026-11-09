# Your to-do list and open questions

- **App:** CrewReady
- **Bundle ID:** `com.generalkenobi.crewready`
- **Company:** Tailgate Labs
- **Devices:** iPhone and iPad
- **Release:** public App Store (eventually)

Decisions for you to check are in [DECISIONS.md](DECISIONS.md).

## 1. Things for you to do

### Now: GitHub (5 minutes)

- [ ] **Rename the repository to `CrewReady`.** Go to Settings → General → Repository name. The app's Privacy Policy and Help links point at `https://genaralkenobi.github.io/CrewReady/`. If you'd rather keep the current name, tell me and I'll change the links.
- [ ] **Turn on GitHub Pages.** Go to Settings → Pages → Build and deployment. Choose **Deploy from a branch**, then branch **main** and folder **/docs**. This publishes:
  - Support page: `https://genaralkenobi.github.io/CrewReady/`
  - Privacy policy: `https://genaralkenobi.github.io/CrewReady/privacy`
- [ ] **Create your iCloud Hide My Email address.** On iPhone, go to Settings → your name → iCloud → Hide My Email → Create New Address. Label it "CrewReady support". Send it to me, or replace `[CONTACT EMAIL]` in `docs/privacy.md` and `docs/index.md` yourself.

### Now: Firebase (about 15 minutes in a browser)

Full steps are in [FIREBASE_SETUP.md](FIREBASE_SETUP.md).

- [ ] Create the Firebase project, with **Google Analytics off**.
- [ ] Add the iOS app with bundle ID **`com.generalkenobi.crewready`**.
- [ ] Download `GoogleService-Info.plist` and upload it to `VehicleMaintenance/Resources/` in this repository. The repository is public, so after uploading, also do the next step.
- [ ] **Restrict the API key**, because the repository is public. In Google Cloud console → APIs & Services → Credentials, open the "iOS key", choose **iOS apps**, and add the bundle ID `com.generalkenobi.crewready`. The security rules are what actually protect the data; this step stops other apps from using your key.
- [ ] Turn on **Email/Password** sign-in.
- [ ] Create the Firestore database in **us-central1**.
- [ ] Deploy the security rules (automatic GitHub workflow, or paste them in by hand).
- [ ] Switch to the **Blaze** plan and set a **$5 budget alert**. This is recommended, and required for photos and instant alerts.
- [ ] Optional: enable Cloud Storage for defect photos.
- [ ] Optional: in Authentication → Templates, set the sender name to **CrewReady**.

### When your Apple developer account is approved

Full steps are in [TESTFLIGHT.md](TESTFLIGHT.md).

- [ ] Register the bundle ID **`com.generalkenobi.crewready`**.
- [ ] In App Store Connect, create the app named **CrewReady**.
- [ ] Create an App Store Connect API key with **Admin** access.
- [ ] Add the four GitHub secrets, then tell me. I'll run the first TestFlight upload and fix anything that comes up.
- [ ] **Seller name.** If you enrolled as an **individual**, the App Store shows your legal name as the seller. "Tailgate Labs" appears in the app and on its website, but not as the seller. To show "Tailgate Labs" as the seller, you'd need a registered business and an Organization developer account, which requires a D-U-N-S number.

### Before the public App Store release

- [ ] **Listing:**
  - name **CrewReady**
  - subtitle (suggestion: "Truck checklists & defects")
  - description
  - **support URL** `https://genaralkenobi.github.io/CrewReady/`
  - **privacy policy URL** `https://genaralkenobi.github.io/CrewReady/privacy`
- [ ] **Screenshots:** CI now captures iPhone and 13" iPad screenshots on every push; see the `ci-screenshots` branch. Pick the ones you like.
- [ ] **App Privacy questions:**
  - **Data collected:** name, email address, phone number, photos, other user content, and user ID.
  - **Use:** all of it is linked to the user, used for App Functionality, and **not** used for tracking.
- [ ] **Age rating questionnaire:** answer "none" for everything.
- [ ] **Demo account for Apple's reviewers:** create a manager account with a sample fleet in your real Firebase project and enter it under App Review Information.

### Before rolling out to the crew

- [ ] Test on two real iPhones, one manager and one driver: invite, join, a checklist in **airplane mode**, and a photo on weak signal.
- [ ] Tell drivers to sign up with the **same email** you invite and to confirm it.

## 2. Open questions

1. **Instant defect alerts for managers:** do you want them? See the cost answer in my message. It can only be built once your Apple developer account is approved, because it needs an Apple push key.
2. **[DECISIONS.md](DECISIONS.md):** reply with the numbers of any decisions you want changed.

## 3. Not tested yet

- **What has been tested:** everything builds and passes its tests on GitHub's Macs. Every screen was checked on iPhone and iPad simulators against local Firebase emulators.
- **What hasn't:**
  - a real iPhone
  - your real Firebase project
  - the real camera
  - background photo uploads
  - notifications
  - the TestFlight upload
