# Firebase setup

The app stores fleets, vehicles, checklists and defects in Firebase, Google's backend for mobile apps. You can do all of this setup in a web browser, and it takes about 15 minutes.

You'll set up three things:

- **Authentication** — each person's email and password login.
- **Firestore** — the database. It keeps a copy of the data on each phone so the app works offline.
- **Cloud Storage** — defect photos. This one is optional and needs the pay-as-you-go plan.

## 1. Create the project

1. Go to <https://console.firebase.google.com> and click **Create a project**.
2. Name it, for example `fleet-maintenance`.
3. **Turn off Google Analytics.** The app doesn't use it, and leaving it off keeps your privacy disclosures short.

## 2. Add the iOS app

1. On the project overview, click **Add app**, then **iOS**.
2. Enter the bundle ID `com.generalkenobi.jabronijalopies`.
3. Download **GoogleService-Info.plist**. Skip the "Add Firebase SDK" and "Add initialization code" steps, because the project already includes them.
4. Add the file to this repository at `VehicleMaintenance/Resources/GoogleService-Info.plist`. On GitHub, open that folder, then click **Add file** → **Upload files**.

The file identifies your Firebase project. It doesn't grant access on its own (the security rules control access), so it's normal to keep it in the repository. If your repository is public, you can restrict the API key in Google Cloud to iOS apps with your bundle ID.

## 3. Turn on email sign-in

1. Go to **Build** → **Authentication** → **Get started**.
2. Under **Sign-in method**, enable **Email/Password**. Leave "Email link" off.

## 4. Create the database

1. Go to **Build** → **Firestore Database** → **Create database**.
2. Choose **Standard edition**.
3. For location, choose **us-central1 (Iowa)**. You can't change the location later, and photo storage is only free in a few US regions, including this one.
4. Choose **Start in production mode**. This blocks all access until the rules in the next step are deployed.

## 5. Deploy the security rules

The rules control who can see and change what. They're in `firebase/firestore.rules`, and the tests in `firebase/tests/` check them. Pick one of these ways to deploy them.

### Option A: automatic (recommended)

GitHub deploys the rules and the 5-year automatic deletion settings, and redeploys whenever they change.

1. In the [Google Cloud console](https://console.cloud.google.com/iam-admin/serviceaccounts), select your Firebase project.
2. Click **Create service account**, name it `github-deploy`, and give it the **Firebase Admin** role. Add **Storage Admin** too if you'll use photos.
3. Open the new account, go to **Keys** → **Add key** → **JSON**, and download the file.
4. In this GitHub repository, go to **Settings** → **Secrets and variables** → **Actions**:
   - On the **Secrets** tab, add `FIREBASE_SERVICE_ACCOUNT` and paste the whole JSON file as its value.
   - On the **Variables** tab, add `FIREBASE_PROJECT_ID` with your project ID (shown in Firebase under ⚙️ → **Project settings**).
5. Go to **Actions** → **Deploy Firebase Rules** → **Run workflow**.

### Option B: by hand

1. Go to **Firestore Database** → **Rules**, paste the contents of `firebase/firestore.rules`, and click **Publish**.
2. Go to **Firestore Database** → **Time-to-live (TTL)**. Create one policy for each of these collection groups, all using the field `expireAt`:
   - `inspections`
   - `defects`
   - `services`
   - `costs`

   These policies delete records automatically after 5 years.

## 6. Optional: defect photos

Photos need Cloud Storage. New projects can only use Cloud Storage on the **Blaze** (pay-as-you-go) plan, which requires a credit card.

Blaze includes the same free allowances as the free plan, plus about 5 GB of photo storage at no cost. A small fleet usually pays $0.

1. Click **Upgrade** (bottom left in Firebase) and choose **Blaze**.
2. **Set a budget alert right away.** In the [Google Cloud Billing console](https://console.cloud.google.com/billing), go to **Budgets & alerts** → **Create budget**. Set an amount such as $5 and email alerts at 50%, 90% and 100%.
3. Go to **Build** → **Storage** → **Get started**. Choose **us-central1** and production mode.
4. Copy the bucket name shown at the top, for example `fleet-maintenance.firebasestorage.app`.
5. Deploy the photo settings:
   - **If you used Option A:** add a GitHub variable `FIREBASE_STORAGE_BUCKET` with the bucket name and re-run **Deploy Firebase Rules**. This deploys `storage.rules` and a lifecycle rule that deletes photos after 5 years.
   - **If you used Option B:** paste `firebase/storage.rules` into **Storage** → **Rules**. Then, in the Google Cloud console, open the bucket's **Lifecycle** tab and add a rule to delete objects older than 1,827 days.
6. In the app, a manager turns on **Settings** → **Defect Photos**.

If photo uploads fail, download `GoogleService-Info.plist` again after enabling Storage and replace the old one, so it includes the bucket.

## What happens when free limits are reached

**On the free (Spark) plan:**
- You get 1 GiB of stored data, 50,000 reads a day and 20,000 writes a day.
- If the fleet goes over a daily limit, syncing stops until the next day. Over the storage limit, writes are rejected until data is deleted. Phones keep working offline in the meantime.
- Nothing is ever charged.
- **Reads add up faster than you'd expect.** Each time someone opens the app after a while away, it re-reads the fleet's trucks, defects, reminders and so on. That's roughly 10 reads per truck. With 25 trucks and 25 people opening the app a few times a day, you can reach 50,000 reads.
- **Recommendation:** use Blaze with a budget alert. The free allowance is the same, and going over costs about 6 cents per 100,000 reads.

**On Blaze:**
- Usage over the free allowances is billed. It's usually cents, at about $0.026 per GB of photos per month.

The app keeps a running estimate under **Settings** → **Data & Storage**:
- At 80% of the free allowance, it shows a warning banner.
- Managers also get a notification on their phone.
- From that screen, a manager can delete records older than any date.
- Records are deleted automatically after 5 years either way.

The budget alert from step 6 is your backstop: it emails you if real charges ever start.

## Testing locally (developers)

The `firebase/` folder runs everything against local emulators, so you don't need a real project:

```bash
cd firebase && npm install && npm test
```

To see the app with demo data on a Mac:

1. Run `npm run emulators` in one terminal.
2. Run `node scripts/seed-demo.mjs` in another.
3. Launch the app from Xcode with the arguments `-useEmulator YES -demoSeed YES`.
