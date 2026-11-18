# The website (backup for the iPhone app)

The `web/` folder is Jabroni Jalopies as a website, laid out for iPhone Safari. It uses the same Firebase project, accounts, data and security rules as the app, so people sign in with the same email and password and see the same fleet. Use it if the app won't open, isn't installed yet, or someone is on an Android phone or a computer.

It's free: Firebase Hosting's free allowance (10 GB stored, about 10 GB of downloads a month) is far more than this needs.

## One-time setup (about 10 minutes, in a browser)

1. **Turn on Hosting.** In the [Firebase console](https://console.firebase.google.com/project/jabroni-jalopies/hosting), open **Hosting** (under Build, or "Hosting & Serverless") and click **Get started**. Click **Next** through the steps; you don't need to run any of the commands it shows. Stop when it says **Continue to console**.
2. **Register the website with Firebase.** Firebase → ⚙️ **Project settings** → **General** → **Your apps** → **Add app** → the web icon (`</>`). Nickname: `Jabroni Jalopies Web`. Tick **Also set up Firebase Hosting** if it's offered and pick the default site. Click **Register app**, then **Continue to console**. You don't need to copy the code it shows: the website reads these settings from Firebase Hosting automatically.
3. **Let GitHub publish the website.** In [Google Cloud console → IAM](https://console.cloud.google.com/iam-admin/iam?project=jabroni-jalopies), find the `github-deploy` service account, click the pencil, **Add another role**: **Firebase Hosting Admin**. Save.
4. **Publish.** GitHub → **Actions** → **Deploy Firebase Rules** → **Run workflow**. The **website** job builds and publishes it. When it finishes, its summary shows the address: **https://jabroni-jalopies.web.app**.

After that, the website updates itself whenever its code changes.

## Using it

- Open **https://jabroni-jalopies.web.app** in Safari and sign in.
- **Add it to the Home Screen** (Share → Add to Home Screen) so it opens full screen like an app, with the Jalopies icon.
- Managers have everything they have in the app: vehicles, checklists, members and invites, reminders, service sign-off, defects, equipment, chains and storage clean-up.

## What's different from the app

- **No notifications.** Instant defect alerts, reminders and the daily checklist reminder come through the iPhone app only.
- **Offline is limited.** The website keeps working through brief signal drops and saves changes in the browser until they're sent, but **keep the page open until they've sent**: unlike the app, a closed browser tab can't send in the background.
- **Calendar:** "Add to My Calendar" downloads a calendar event. On iPhone, tap **Add** on the screen that opens.
- A checklist saved for later on the website stays in that browser; it isn't shared with the app.

## Optional

- **Your own address**, e.g. `app.tailgatelabs.com` (about $12 a year for the domain): Firebase → Hosting → **Add custom domain** and follow the steps.
- **Tighten the website's API key:** in Google Cloud → APIs & Services → Credentials, open the **Browser key (auto created by Firebase)** and under **Website restrictions** add `jabroni-jalopies.web.app/*` and `jabroni-jalopies.firebaseapp.com/*`. The key isn't a secret (every website using Firebase shows it); the security rules are what protect the data.

## Tests

Every change to `web/` runs **Website Build & Test** on GitHub: unit tests for the shared logic, a production build, and end-to-end tests where a manager and a newly invited driver do real tasks (checklists, problems with a photo, services, sign-offs, invites, equipment, chains) against the real security rules in the Firebase emulators. Screenshots are attached to each run.
