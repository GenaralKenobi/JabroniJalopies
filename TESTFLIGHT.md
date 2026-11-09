# Shipping to TestFlight without a Mac

GitHub Actions builds, signs and uploads the app for you. Signing uses Apple's
**cloud-managed certificates** through an App Store Connect API key, so you never
need Xcode, Keychain or a certificate file. You can do all of the setup below in a web browser.

Bundle ID used by this project: **`com.generalkenobi.jabronisjalopies`**
(to change it, edit `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`).

## 1. Join the Apple Developer Program

You need this to put apps on TestFlight or the App Store. It costs $99 a year.

- Enroll at <https://developer.apple.com/programs/enroll/>, or in the **Apple Developer** app on your iPhone.
- Approval usually takes from a few minutes to 48 hours.

## 2. Find your Team ID

1. Go to <https://developer.apple.com/account>.
2. Scroll to **Membership details**.
3. Copy the 10-character **Team ID**.

## 3. Register the bundle ID

1. Go to <https://developer.apple.com/account/resources/identifiers/list> and click **+**.
2. Choose **App IDs**, then **App**, then **Continue**.
3. For **Description**, enter `Jabroni's Jalopies`.
4. For **Bundle ID**, choose **Explicit** and enter `com.generalkenobi.jabronisjalopies`.
5. Leave the capabilities as they are, then click **Continue** and **Register**.

## 4. Create the app in App Store Connect

1. Go to <https://appstoreconnect.apple.com/apps>, click **+**, then **New App**.
2. Fill in the form:
   - **Platform:** iOS
   - **Name:** **Jabroni's Jalopies**. If App Store Connect says the name is taken, try "Jabroni's Jalopies Fleet". You can change it later.
   - **Primary language:** your choice
   - **Bundle ID:** `com.generalkenobi.jabronisjalopies`
   - **SKU:** anything, for example `maintenance-001`
   - **User access:** Full Access

## 5. Create an App Store Connect API key

1. In App Store Connect, open **Users and Access**, then **Integrations**, then **App Store Connect API**.
2. Under **Team Keys**, click **Generate API Key**. The first time, you have to click **Request Access** and accept the terms.
3. Name the key `GitHub Actions` and set **Access** to **Admin**. Admin access is required for Xcode to create cloud-managed signing certificates.
4. Write down the **Issuer ID**, shown above the keys table, and the **Key ID**.
5. Click **Download** to save `AuthKey_XXXXXXXXXX.p8`. Apple only lets you download it **once**, so keep it somewhere safe.

## 6. Add the GitHub secrets

1. In this repository, go to **Settings**, then **Secrets and variables**, then **Actions**.
2. Click **New repository secret** and add each of these:

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | Team ID from step 2 |
| `ASC_KEY_ID` | Key ID from step 5 |
| `ASC_ISSUER_ID` | Issuer ID from step 5 |
| `ASC_PRIVATE_KEY` | The whole text of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |

To get the `.p8` text on an iPhone:
1. In the **Files** app, rename the file to `AuthKey.txt`.
2. Open it and copy all of the text.

On a computer, open the file in any text editor.

## 7. Add the Firebase config

The app needs your Firebase project's `GoogleService-Info.plist` in `VehicleMaintenance/Resources/`. If you haven't added it yet, follow [FIREBASE_SETUP.md](FIREBASE_SETUP.md). The TestFlight workflow stops with a clear message if the file is missing.

## 8. Build and upload

1. In this repository, go to **Actions**, then **TestFlight**, then **Run workflow**.
2. The build takes about 10–15 minutes.
3. Apple then needs about 5–30 minutes to process the build.

To publish a new version later, change `MARKETING_VERSION` in `project.yml` and run the workflow again. Each run gets a higher build number automatically.

## 9. Install on your iPhone

1. In App Store Connect, open your app, then the **TestFlight** tab.
2. Under **Internal Testing**, click **+** to create a group, then add yourself.
3. Install **TestFlight** from the App Store on your iPhone.
4. Open the invite email, or open the TestFlight app. The app shows up there, ready to install.

Internal testers can install a build as soon as Apple finishes processing it, with no review. Friends outside your team count as *external* testers, and their builds need a short beta review first.

### Getting the app to your drivers

- **Internal testing:** only people you add as users of your App Store Connect team (up to 100). This is good for you and other managers.
- **External testing:**
  1. Under **TestFlight**, create an external group and turn on **Public Link**.
  2. Share the link with drivers. They install TestFlight, then your app.
  3. The first build for external testers goes through a short Apple beta review, usually about a day.

  TestFlight builds expire after 90 days, so upload a new one at least that often.
- **For the long term,** release on the App Store, either unlisted or public, or distribute privately through Apple Business Manager. App Review needs a demo login with sample data; see YOUR_TODO.md.
