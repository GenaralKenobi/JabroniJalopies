# Your to-do list and open questions

- **App:** Jabroni Jalopies
- **Bundle ID:** `com.generalkenobi.jabronijalopies`
- **Company:** Tailgate Labs (tailgatelabshr@icloud.com)
- **Devices:** iPhone and iPad
- **Release:** public App Store (eventually)

Decisions for you to check are in [DECISIONS.md](DECISIONS.md). Anything marked 🆕 there is waiting for you.

## Already done (nothing to do)

- GitHub repository renamed to `JabroniJalopies`, and GitHub Pages is publishing the support and privacy pages.
- Company contact email added to the support page and privacy policy.
- Firebase project created, iOS app added, and `GoogleService-Info.plist` is in the repository.
- Email/Password sign-in, the Firestore database (us-central1), the security rules and the 5-year automatic deletion are set up and deployed. GitHub redeploys them whenever they change.
- Blaze plan, Cloud Storage and the photo permissions are set up.
- Apple developer account approved, bundle ID registered, app created in App Store Connect, API key made, and the four GitHub secrets added.
- TestFlight upload works, and the app is installed on your iPhone.

## 1. Things for you to do

### Firebase and Google (about 10 minutes, if you haven't already)

I can't see these settings, so if you've done them, tick them off and ignore them.

- [ ] **Restrict the API key**, because the repository is public. In Google Cloud console → APIs & Services → Credentials, open the "iOS key", choose **iOS apps**, and add the bundle ID `com.generalkenobi.jabronijalopies`. The security rules are what actually protect the data; this step stops other apps from using your key.
- [ ] **Set a $5 budget alert** in Google Cloud → Billing → Budgets & alerts, with emails at 50%, 90% and 100%. You're on the Blaze plan, so this is your backstop against surprise charges.
- [ ] Optional: in Firebase → Authentication → Templates, set the sender name to **Jabroni Jalopies**.
- [ ] Optional: delete the service account JSON key file you downloaded for GitHub, if it's still on your computer. GitHub has its own copy.

### Now: get the latest build on your phone

- [ ] When I tell you the latest build passed, run **Actions → TestFlight → Run workflow**, then update the app in TestFlight. It includes the checklist crash fix, the camera option for vehicle photos, and a banner that explains why a photo isn't uploading.
- [ ] If the orange photo banner shows an error, send it to me.

### Before rolling out to the crew

- [ ] Test on two real iPhones, one manager and one driver: invite, join, a checklist in **airplane mode**, and a photo on weak signal.
- [ ] Tell drivers to sign up with the **same email** you invite and to confirm it.
- [ ] To get drivers the app, create an external TestFlight group with a **Public Link** (see [TESTFLIGHT.md](TESTFLIGHT.md)). The first build for external testers goes through a short Apple beta review.

### Before the public App Store release

- [ ] **Listing:**
  - name **Jabroni Jalopies**
  - subtitle (suggestion: "Truck checklists & defects")
  - description
  - **support URL** `https://genaralkenobi.github.io/JabroniJalopies/`
  - **privacy policy URL** `https://genaralkenobi.github.io/JabroniJalopies/privacy`
- [ ] **Screenshots:** CI captures iPhone and 13" iPad screenshots on every push; see the `ci-screenshots` branch. Pick the ones you like.
- [ ] **App Privacy questions:**
  - **Data collected:** name, email address, phone number, photos, other user content, and user ID.
  - **Use:** all of it is linked to the user, used for App Functionality, and **not** used for tracking.
- [ ] **Age rating questionnaire:** answer "none" for everything.
- [ ] **Demo account for Apple's reviewers:** create a manager account with a sample fleet in your real Firebase project and enter it under App Review Information.
- [ ] **Seller name (for your information).** If you enrolled as an **individual**, the App Store shows your legal name as the seller. "Tailgate Labs" appears in the app and on its website, but not as the seller. To show "Tailgate Labs" as the seller, you'd need a registered business and an Organization developer account, which requires a D-U-N-S number.

## 2. Open questions

1. **Instant defect alerts for managers:** do you want them? Your Apple developer account is approved, so it can be built now. It needs an Apple push key and Firebase Cloud Functions, and costs a few cents a month at most.
2. **Pricing:** I suggested charging per vehicle per month with unlimited users, and invoicing the first few customers by hand. Tell me if you'd like me to plan the billing side.
3. **Photo uploads:** tell me what the orange banner says, once you have the new build.

## 3. Not confirmed on a real phone yet

- **Confirmed:** the app installs from TestFlight, and the fixed build passes all automated tests on GitHub's Macs and simulators.
- **Not confirmed yet** (these need a real phone):
  - a manager and a driver on two phones at once
  - a checklist completed in airplane mode and syncing afterwards
  - photo uploads (currently being investigated)
  - notifications and calendar events
