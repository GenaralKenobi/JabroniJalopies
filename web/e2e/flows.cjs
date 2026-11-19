// End-to-end check of the website against the Firebase emulators and the real security rules:
// a manager and a newly invited driver do real tasks, and the run fails if any save is rejected.
// Needs: emulators running with the demo data (firebase/scripts/seed-demo.mjs) and the website
// served at BASE, built with VITE_EMULATOR=1. Screenshots go to e2e/shots.
const { chromium, devices } = require('playwright');
const BASE = process.env.BASE ?? 'http://127.0.0.1:5173';
const FIRESTORE = 'http://127.0.0.1:8080/v1/projects/demo-maintenance/databases/(default)/documents/fleets/demo-fleet';
const OUT = __dirname + '/shots';
require('fs').mkdirSync(OUT, { recursive: true });
const AUTH = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';

async function emulatorUser(email, password) {
  let r = await fetch(`${AUTH}/accounts:signUp?key=demo-key`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password, returnSecureToken: true }) });
  let body = await r.json();
  if (!r.ok) {
    r = await fetch(`${AUTH}/accounts:signInWithPassword?key=demo-key`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password, returnSecureToken: true }) });
    body = await r.json();
  }
  await fetch(`${AUTH}/accounts:update`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' }, body: JSON.stringify({ localId: body.localId, emailVerified: true }) });
}

(async () => {
  const browser = await chromium.launch();
  const failures = []; global.__failures = failures;
  let step = '';
  async function session(email, password, run) {
    const context = await browser.newContext({ ...devices['iPhone 15'] });
    const page = await context.newPage();
    page.on('pageerror', (e) => failures.push(`[${step}] pageerror: ${e.message}`));
    page.on('dialog', (d) => d.accept(d.type() === 'prompt' ? (page.__promptAnswer ?? '') : undefined));
    page.on('console', (m) => { if (m.type() === 'error' && !/favicon|apis.google/.test(m.text())) failures.push(`[${step}] console: ${m.text().slice(0, 200)}`); });
    const check = async (name) => {
      step = name;
      await page.waitForTimeout(1800);
      const text = await page.locator('body').innerText();
      const m = text.match(/[^\n]*didn't work[^\n]*/);
      if (m) failures.push(`[${name}] ${m[0]}`);
      await page.screenshot({ path: `${OUT}/flow-${name}.png` });
    };
    await page.goto(BASE + '/');
    await page.getByLabel('Email').fill(email);
    await page.getByRole('textbox', { name: 'Password' }).fill(password);
    await page.locator('form button[type=submit]').click();
    await page.waitForTimeout(3000);
    try { await run(page, check); } catch (e) { await page.screenshot({ path: `${OUT}/flow-ERROR.png`, fullPage: true }); throw e; }
    await context.close();
  }

  // ---------- Manager ----------
  await session('mia.manager@demo.test', 'demo-password', async (page, check) => {
    // Checklist on Car 2 (single morning checklist? pick from list)
    await page.getByText('Car 2').first().click();
    await page.getByRole('button', { name: /Start Checklist/ }).click();
    await page.waitForTimeout(500);
    if (!page.url().includes('/checklist/')) await page.getByRole('button', { name: /Morning Checklist/ }).first().click();
    await check('checklist-open');
    // Fail the tire pressure (with a reading and description), pass everything else.
    const card = (title) => page.locator('div.pad', { has: page.locator('span.strong', { hasText: title }) }).first();
    await page.waitForSelector('.verdicts');
    const pressure = card('Lowest tire pressure');
    await pressure.getByPlaceholder('Enter number').fill('20');
    await pressure.getByRole('button', { name: /Fail/ }).click();
    await pressure.getByPlaceholder('Describe the problem').fill('Rear left low');
    for (let i = 0; i < 30; i++) {
      const pass = page.locator('.verdicts button.pass:not(.on)').first();
      if (!(await pass.count())) break;
      await pass.click();
      await page.waitForTimeout(100);
    }
    await page.screenshot({ path: `${OUT}/flow-checklist-filled.png`, fullPage: true });
    // Every checklist needs today's reading: first try without it (must be refused), then fill it in.
    await page.getByRole('button', { name: /Submit Checklist/ }).click();
    if (!(await page.getByText(/Enter today's odometer reading/).count())) failures.push('[reading] Submitting without a reading was not refused.');
    await page.locator('input[aria-label="Reading"]').fill('53,010');
    await page.getByRole('button', { name: /Submit Checklist/ }).click();
    await check('checklist-submitted');
    await page.getByRole('button', { name: 'OK' }).click();

    // Report and close a problem
    await page.goto(BASE + '/');
    await page.getByText('Car 2').first().click();
    await page.getByText('Report a Problem').click();
    await page.getByLabel('Problem').fill('Check engine light');
    await page.getByRole('button', { name: 'Report Problem' }).click();
    await check('report-problem');
    await page.getByText('Check engine light').first().click();
    await page.getByText('Mark Repaired').click();
    await check('close-defect');

    // Log a service with a cost; add a reminder
    await page.goto(BASE + '/');
    await page.getByText('Car 2').first().click();
    const carUrl = page.url();
    await page.getByText('Log a Service').click();
    await page.locator('input[placeholder="$0.00"]').fill('49.95');
    await page.getByRole('button', { name: 'Save' }).click();
    await check('log-service');
    await page.goto(carUrl + '/reminders/new');
    await page.getByRole('button', { name: 'Save' }).click();
    await check('add-reminder');

    // Approve Dan's pending service from the Defects tab
    await page.goto(BASE + '/defects');
    await page.getByText('Wiper Blades').first().click();
    await page.getByRole('button', { name: 'Approve' }).click();
    await check('approve-service');

    // Plan Van 12's monthly service
    await page.goto(BASE + '/upcoming');
    await page.getByRole('button', { name: 'Expand All' }).click();
    await page.getByRole('link', { name: 'Plan' }).first().click();
    await page.getByRole('checkbox').uncheck();
    await page.getByRole('button', { name: 'Save' }).click();
    await check('plan-checklist');

    // Edit a checklist template
    await page.goto(BASE + '/settings/checklists');
    await page.getByText('Belts & Filters').click();
    await page.getByText('＋ Add Item').click();
    await page.locator('input[aria-label="Item 4"]').fill('Hoses');
    await page.getByRole('button', { name: 'Save' }).click();
    await check('edit-checklist');

    // Invite someone
    await page.goto(BASE + '/settings/invite');
    await page.getByPlaceholder('Email address').fill('new.driver@demo.test');
    await page.getByRole('button', { name: 'Send Invite' }).click();
    await check('invite');

    // Chains: used box on Van 12
    await page.goto(BASE + '/');
    await page.getByText('Van 12').first().click();
    await page.getByText('Log Chains').click();
    await page.locator('input[aria-label="dull-in16"]').fill('2');
    await page.getByRole('button', { name: 'Log Used Box' }).click();
    await check('chains-used-box');
    await page.getByRole('button', { name: 'Count' }).click();
    await page.locator('input[aria-label="count-in18"]').fill('8');
    await page.getByRole('button', { name: 'Save Count' }).click();
    await check('chains-count');

    // Truck contents
    await page.goBack();
    await page.getByText("What's on the Truck").click();
    await page.getByRole('button', { name: '＋ Add' }).click();
    await page.getByLabel('Item').fill('Fire blanket');
    await page.getByRole('button', { name: 'Save' }).click();
    await check('contents-add');

    // Equipment: add a rope, cut it, approve
    await page.goto(BASE + '/equipment/new');
    await page.getByRole('button', { name: 'Rope' }).click();
    await page.locator('input[placeholder="e.g. Rigging rope A"]').fill('Test Rope');
    await page.locator('.field', { hasText: 'Length' }).first().locator('input').fill('150');
    await page.getByRole('button', { name: 'Save' }).click();
    await check('equipment-add');
    await page.locator('input[placeholder="e.g. 12"]').fill('10');
    await page.getByText('Submit Length Change').click();
    await check('length-change');
    await page.getByRole('button', { name: 'Approve' }).first().click();
    await check('length-approve');

    // Vehicle: add one
    await page.goto(BASE + '/v/new');
    await page.locator('.field', { hasText: 'Name' }).first().locator('input').fill('Truck 99');
    await page.getByRole('button', { name: 'Save' }).click();
    await check('vehicle-add');
    await page.goto(BASE + '/settings/storage');
    await check('storage');

    // A problem with a photo: the photo must reach Cloud Storage and attach to the defect.
    await page.goto(BASE + '/settings');
    const photos = page.getByRole('checkbox', { name: 'Defect Photos' });
    if (!(await photos.isChecked())) await photos.check();
    await page.goto(BASE + '/');
    await page.getByText('Van 7').first().click();
    await page.getByText('Report a Problem').click();
    await page.getByLabel('Problem').fill('Dent in rear door');
    await page.locator('input[type=file]').setInputFiles(require('path').join(__dirname, 'photo.jpg'));
    await page.waitForTimeout(800);
    await page.getByRole('button', { name: 'Report Problem' }).click();
    let uploaded = false;
    for (let i = 0; i < 30 && !uploaded; i++) {
      await page.waitForTimeout(1000);
      const res = await fetch(`${FIRESTORE}/vehicles/van-7/defects`, { headers: { Authorization: 'Bearer owner' } });
      const docs = (await res.json()).documents ?? [];
      const defect = docs.find((d) => d.fields.title.stringValue === 'Dent in rear door');
      const photo = defect && Object.values(defect.fields.photos?.mapValue?.fields ?? {})[0];
      uploaded = photo?.mapValue?.fields?.status?.stringValue === 'uploaded';
    }
    if (!uploaded) failures.push('[photo] The defect photo never finished uploading.');
    await page.getByText('Dent in rear door').first().click();
    await check('photo-defect');
  });

  // ---------- A new driver accepts the seeded invite ----------
  await emulatorUser('sam.new@demo.test', 'sam-password');
  await session('sam.new@demo.test', 'sam-password', async (page, check) => {
    await check('driver-invites');
    await page.getByRole('button', { name: 'Join' }).click();
    await page.getByLabel('Your name').fill('Sam New');
    await page.getByRole('button', { name: 'Join' }).click();
    await page.waitForTimeout(3000);
    await check('driver-joined');
    await page.getByText('Van 7').first().click();
    await page.getByRole('button', { name: /Start Checklist/ }).click();
    await page.waitForTimeout(500);
    if (!page.url().includes('/checklist/')) await page.getByRole('button', { name: /Morning Checklist/ }).first().click();
    await page.waitForSelector('.verdicts');
    for (const input of await page.getByPlaceholder('Enter number').all()) await input.fill('35');
    for (let i = 0; i < 30; i++) {
      const pass = page.locator('.verdicts button.pass:not(.on)').first();
      if (!(await pass.count())) break;
      await pass.click();
      await page.waitForTimeout(100);
    }
    for (const why of await page.getByPlaceholder(/Why does it look fixed/).all()) await why.fill('Replaced');
    await page.locator('input[aria-label="Reading"]').fill('999,999');
    await page.getByRole('button', { name: /Submit Checklist/ }).click();
    await check('driver-checklist');
    await page.getByRole('button', { name: 'OK' }).click();
    await page.getByText('Report a Problem').click();
    await page.getByLabel('Problem').fill('Door won\'t lock');
    await page.getByRole('button', { name: 'Report Problem' }).click();
    await check('driver-report');
    await page.getByText('Log a Service').click();
    await page.getByRole('button', { name: 'Save' }).click();
    await check('driver-service');
    await page.goto(BASE + '/settings/profile');
    await page.getByRole('button', { name: 'Save' }).click();
    await check('driver-profile');
  });

  await browser.close();
  console.log(failures.length ? 'FAILURES:\n' + failures.join('\n') : 'ALL FLOWS OK');
})().catch((e) => { console.error('FAILURES SO FAR:\n' + (global.__failures||[]).join('\n')); console.error('SCRIPT ERROR', e.message.split('\n').slice(0, 6).join('\n')); process.exit(1); });
