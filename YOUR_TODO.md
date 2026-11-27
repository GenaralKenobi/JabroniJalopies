# Your to-do list and open questions

- **App:** Jabroni Jalopies
- **Bundle ID:** `com.generalkenobi.jabronijalopies`
- **Company:** Tailgate Labs (tailgatelabshr@icloud.com)
- **Devices:** iPhone and iPad
- **Release:** version 1.0 approved by Apple (Nov 2026); version 1.1 is next

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
- App Store listing filled in: name, description, support and privacy URLs, screenshots, App Privacy answers, age rating, copyright and content rights.
- Reviewer account made with the **App Review demo fleet** workflow and entered in App Store Connect.
- Version 1.0 submitted for review (Nov 20, 2026) with the unlisted distribution request, and the latest build (kits, problem tags, truck lead pickers, morning template) attached.

## 1. Things for you to do

### Allow yourself to create fleets (2 minutes)

- [ ] Only accounts on the fleet-creator list can create fleets now, and the list starts empty. GitHub → **Actions** → **Allow fleet creation** → **Run workflow**, enter **your own account's email**, choose **allow**. "Create a New Fleet" then appears in Fleets for you. (The email is hidden in the run's log.)

### Firebase and Google (about 10 minutes, if you haven't already)

I can't see these settings, so if you've done them, tick them off and ignore them.

- [ ] **Restrict the API key**, because the repository is public. In Google Cloud console → APIs & Services → Credentials, open the "iOS key", choose **iOS apps**, and add the bundle ID `com.generalkenobi.jabronijalopies`. The security rules are what actually protect the data; this step stops other apps from using your key.
- [ ] Optional: delete the service account JSON key file you downloaded for GitHub, if it's still on your computer. GitHub has its own copy.

### Before rolling out to the crew

- [ ] Test on two real iPhones, one manager and one driver: invite, join, a checklist in **airplane mode**, and a photo on weak signal.
- [ ] Tell drivers to sign up with the **same email** you invite and to confirm it.
- [ ] Once the app is approved: invite each person in **Settings → Members → Invite**, then send them the App Store link. (TestFlight is only needed for testing builds before they're released; see [TESTFLIGHT.md](TESTFLIGHT.md).)

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

### App Store review (in progress)

- [ ] **Apple asked for more information.** Make the screen recording on your iPhone, upload it and paste its link at the top of the Notes in **App Review Information**, then reply to Apple's message. Ask me for the recording steps and the notes text any time.
- [ ] After recording, run **App Review demo fleet** on GitHub again to reset the sample fleet.
- [ ] Wait for the review result and the unlisted request. If either is rejected, send me the exact message.
- [ ] Keep the reviewer account and "Sample Fleet (App Review)" as they are. Apple reuses them for every update.
- [ ] When the status is **Pending Developer Release**, click **Release This Version** (unless you chose automatic release). Share the link only once it says **Ready for Distribution**.

### Good to know before selling to other companies

- **Employee-monitoring notices.** The app records who did each checklist and when. Some states (for example New York, Connecticut and Delaware) require employers to tell employees in writing about electronic monitoring. That's the employer's job, and the draft Terms say so, but mention it when you sign up a company.
- **Seller name.** If you enrolled as an **individual**, the App Store shows your legal name as the seller. To show "Tailgate Labs", you'd need a registered business and an Organization developer account, which requires a D-U-N-S number.

### Coming up (I'll handle these; nothing for you to do)

- After 1.0 is approved, the next update becomes **version 1.1**. Apple reviews each update; small updates are usually quicker.
- From **April 2027** Apple only accepts apps built with Xcode 27. The build workflows already pick the newest Xcode on GitHub's Macs, so it's one rebuild once GitHub installs it.

## 2. Open questions

1. **Pricing:** I suggested charging per vehicle per month with unlimited users, and invoicing the first few customers by hand. Tell me if you'd like me to plan the billing side.

## 3. Not confirmed on a real phone yet

- **Confirmed:** the app installs from TestFlight, every build passes all automated tests on GitHub's Macs and simulators, instant defect alerts reach a manager's device, and defect photo uploads work.
- **Not confirmed yet** (these need a real phone):
  - a checklist completed in airplane mode and syncing afterwards
  - reminder notifications and calendar events
