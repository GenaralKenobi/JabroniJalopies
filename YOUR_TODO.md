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
- Blaze plan, Cloud Storage and the photo permissions are set up, with a budget alert for surprise charges.
- Apple developer account approved, bundle ID registered, app created in App Store Connect, API key made, and the four GitHub secrets added.
- TestFlight upload works, and the app is installed on your iPhone.
- The website is live at https://jabroni-jalopies.web.app and sign-in works.
- Defect photo uploads work.
- Sign-in emails are signed "Jabroni Jalopies" (public-facing name and sender name).
- Instant defect alerts are set up (push key uploaded to Firebase for development and production, alert function deployed) and tested between two devices.

## 1. Things for you to do

### Firebase and Google (about 10 minutes, if you haven't already)

I can't see these settings, so if you've done them, tick them off and ignore them.

- [ ] **Restrict the API key**, because the repository is public. In Google Cloud console → APIs & Services → Credentials, open the "iOS key", choose **iOS apps**, and add the bundle ID `com.generalkenobi.jabronijalopies`. The security rules are what actually protect the data; this step stops other apps from using your key.
- [ ] Optional: delete the service account JSON key file you downloaded for GitHub, if it's still on your computer. GitHub has its own copy.

### Before rolling out to the crew

- [ ] Test on two real iPhones, one manager and one driver: invite, join, a checklist in **airplane mode**, and a photo on weak signal.
- [ ] Tell drivers to sign up with the **same email** you invite and to confirm it.
- [ ] To get drivers the app, create an external TestFlight group with a **Public Link** (see [TESTFLIGHT.md](TESTFLIGHT.md)). The first build for external testers goes through a short Apple beta review.

### Legal and business (before you charge anyone or release publicly)

None of this is legal advice; these are the things worth getting a professional to look at.

- [ ] **Terms of Use:** have a lawyer review and finish [TERMS_DRAFT.md](TERMS_DRAFT.md), then publish it. It's important for an app that tells people a vehicle is safe or unsafe: it says the app doesn't replace legally required inspections and limits your liability.
- [ ] **Privacy policy:** have the same lawyer read [docs/privacy.md](docs/privacy.md).
- [ ] **Business name:** "Tailgate Labs" appears in the app and the policies, but it isn't a registered business yet. Register it as an assumed name (DBA) or form an LLC before taking money, and put the legal name in the policies.
- [ ] **Trademark:** there's a live US trademark registration for "JABRONI" (business services, class 35, registered 2021) and a pending "JABRONI BRAWL" video-game application. I found nothing for software like yours, but a trademark attorney's clearance search is worth it before you spend on branding, and they can file "Jabroni Jalopies" for you.
- [ ] **Where to sell:** in App Store Connect, start with **United States only** (add Canada if needed). Selling in the EU means GDPR, and Apple asks EU sellers for "trader" details that are shown publicly on the App Store.
- [ ] **Don't call it a DVIR system.** US commercial-vehicle inspection reports (49 CFR 396.11) have specific requirements (signatures, mechanic certification, retention) that the app doesn't claim to meet. The support page and the app say so.
- [ ] **Taxes and insurance:** ask an accountant about sales tax on software subscriptions in your state, and an insurance agent about general liability and technology errors-and-omissions cover.
- [ ] **Big customers** will ask for a data processing agreement (how you handle their employees' data). Have the lawyer prepare one when the first one asks.

### Before the public App Store release

- [ ] **Demo account for Apple's reviewers** (5 minutes):
  1. On the website, **Create Account** with an email used only for this (Apple will see it), and a password you'll give Apple. You don't need to confirm the email.
  2. Sign out of the website.
  3. GitHub → **Actions** → **App Review demo fleet** → **Run workflow**, enter that email. It confirms the email and makes the account the manager of "Sample Fleet (App Review)" with trucks, checklists, a problem, reminders and history.
  4. In App Store Connect → **App Review Information**, tick **Sign-in required** and enter the email and password, with a note: "Internal fleet app. This account manages a sample fleet."
- [ ] **Listing:**
  - name **Jabroni Jalopies**
  - subtitle (suggestion: "Truck checklists & defects")
  - description
  - **support URL** `https://genaralkenobi.github.io/JabroniJalopies/`
  - **privacy policy URL** `https://genaralkenobi.github.io/JabroniJalopies/privacy`
- [ ] **Screenshots:** CI captures iPhone and 13" iPad screenshots on every push; see the `ci-screenshots` branch. Pick the ones you like.
- [ ] **App Privacy questions:**
  - **Data collected:** name, email address, phone number, photos, other user content, user ID, and **device ID** (the notification token).
  - **Use:** all of it is linked to the user, used for App Functionality, and **not** used for tracking.
- [ ] **Age rating questionnaire:** answer "none" for everything.
- [ ] **Tell customers about employee-monitoring notices.** The app records who did each checklist and when. Some states (for example New York, Connecticut and Delaware) require employers to tell employees in writing about electronic monitoring. That's the employer's job, and the draft Terms say so, but mention it when you sign up a company.
- [ ] **Seller name (for your information).** If you enrolled as an **individual**, the App Store shows your legal name as the seller. "Tailgate Labs" appears in the app and on its website, but not as the seller. To show "Tailgate Labs" as the seller, you'd need a registered business and an Organization developer account, which requires a D-U-N-S number.

## 2. Open questions

1. **Who can create a fleet:** right now anyone who downloads the app, creates an account and confirms their email can create a fleet (that's how a new company signs up). Tell me if you'd rather only approved accounts could, for now.
2. **Pricing:** I suggested charging per vehicle per month with unlimited users, and invoicing the first few customers by hand. Tell me if you'd like me to plan the billing side.

## 3. Not confirmed on a real phone yet

- **Confirmed:** the app installs from TestFlight, the fixed build passes all automated tests on GitHub's Macs and simulators, and instant defect alerts reach a manager's device.
- **Not confirmed yet** (these need a real phone):
  - a checklist completed in airplane mode and syncing afterwards
  - reminder notifications and calendar events
