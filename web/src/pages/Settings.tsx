import { useState } from 'react';
import { Banner, Field, Page, Row, Section, ToggleRow, confirmAction, fromDateInput, toDateInput, useFleet, useOnline, useSafeNavigate } from '../ui/kit';
import { session } from '../data/session';
import { friendlyError } from '../data/store';
import { photoQueue } from '../data/photos';
import { useObservable } from '../data/store';
import {
  deleteRecordsBefore, renameFleet, setChecklistReminder, setDistanceUnit, setPhotosEnabled, updateMyProfile,
} from '../data/actions';
import { BYTES_PER_RECORD, DATABASE_ALLOWANCE, PHOTO_ALLOWANCE, addYears, formatBytes } from '../logic/logic';
import { roleName } from '../logic/model';

const SUPPORT = 'https://genaralkenobi.github.io/JabroniJalopies/';

export function SettingsPage() {
  const fleet = useFleet();
  const navigate = useSafeNavigate();
  useObservable(photoQueue);
  const contact = fleet.contacts[fleet.uid];
  const usage = fleet.fleet?.usage ?? {};
  const usageLevel = Math.max((usage.photoBytes ?? 0) / PHOTO_ALLOWANCE, ((usage.recordCount ?? 0) * BYTES_PER_RECORD) / DATABASE_ALLOWANCE);
  const days = fleet.fleet?.checklistReminderDays;

  async function leave() {
    if (!confirmAction(`Leave ${fleet.fleet?.name ?? 'this fleet'}? Your past checklists stay in the fleet's records. It needs a connection.`)) return;
    try {
      await session.leave(fleet.fleetId);
      navigate('/');
    } catch (e) { window.alert((e as Error).message); }
  }

  async function signOut() {
    if (photoQueue.pending.length && !confirmAction(`This browser has ${photoQueue.pending.length} photo(s) still waiting to upload. Signing out now will lose them. Sign out anyway?`)) return;
    await photoQueue.clear();
    await session.signOut();
  }

  return (
    <Page title="Settings">
      <Section header={`Your Profile in ${fleet.fleet?.name ?? 'This Fleet'}`}>
        <Row to="/settings/profile">
          {fleet.me?.displayName}
          <div className="caption">{fleet.me ? roleName(fleet.me.role) : ''} · {contact?.email ?? fleet.email}</div>
        </Row>
      </Section>

      <Section header="Fleet">
        <Row value={fleet.fleet?.name}>Fleet</Row>
        <Row to="/settings/members" value={fleet.members.length}>Members</Row>
        <Row to="/settings/fleets">Switch or Join Fleet</Row>
        <Row className="destructive" onClick={leave} chevron={false}>Leave Fleet</Row>
      </Section>

      {fleet.isManager && (
        <Section header="Manager">
          <Row to="/settings/checklists" value={fleet.checklists.length}>Checklists</Row>
          <Row to="/settings/equipment" value={fleet.equipment.length}>Chainsaws &amp; Ropes</Row>
          <Row to="/settings/chains">Chain Totals</Row>
          <ToggleRow label="Defect Photos" checked={fleet.photosEnabled} onChange={(v) => setPhotosEnabled(fleet, v)} />
          <Row to="/settings/storage" value={usageLevel >= 0.8 ? '⚠︎' : undefined}>Data &amp; Storage</Row>
          <Field label="Distance">
            <select value={fleet.fleetUnit} onChange={(e) => setDistanceUnit(fleet, e.target.value as 'mi' | 'km')}>
              <option value="mi">Miles</option><option value="km">Kilometers</option>
            </select>
          </Field>
          <Row onClick={() => {
            const name = window.prompt('Fleet name', fleet.fleet?.name ?? '');
            if (name?.trim()) renameFleet(fleet, name);
          }} chevron={false} className="accent">Rename Fleet</Row>
        </Section>
      )}
      {fleet.isManager && (
        <Section header="Daily Checklist Reminder" footer="A notification on everyone's iPhone app at this time (the website can't send notifications). Leave the time empty to turn it off.">
          <Field label="Time">
            <input type="time" className="right" value={fleet.fleet?.checklistReminderTime ?? ''}
              onChange={(e) => setChecklistReminder(fleet, e.target.value || undefined, days ?? [1, 2, 3, 4, 5, 6, 7])} />
          </Field>
          {fleet.fleet?.checklistReminderTime && (
            <div className="inline-actions">
              {['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((label, i) => {
                const day = i + 1;
                const on = !days || days.includes(day);
                return (
                  <button key={i} className={`btn small ${on ? '' : 'secondary'}`} aria-pressed={on} onClick={() => {
                    const current = days ?? [1, 2, 3, 4, 5, 6, 7];
                    const next = on ? current.filter((d) => d !== day) : [...current, day];
                    if (next.length) setChecklistReminder(fleet, fleet.fleet?.checklistReminderTime, next);
                  }}>{label}</button>
                );
              })}
            </div>
          )}
        </Section>
      )}

      <Section header="Account">
        <Row value={session.email}>Signed in as</Row>
        <Row onClick={() => window.open(SUPPORT, '_blank')} icon="❓">Help &amp; Support</Row>
        <Row onClick={() => window.open(`${SUPPORT}privacy`, '_blank')} icon="✋">Privacy Policy</Row>
        <Row onClick={signOut} chevron={false} className="accent">Sign Out</Row>
        <Row to="/settings/delete-account" className="destructive">Delete Account</Row>
      </Section>

      <Section header="About" footer="Jabroni Jalopies helps you record inspections and problems. It doesn't replace inspections required by law, or your company's safety procedures.">
        <Row value="Website">Jabroni Jalopies</Row>
        <Row onClick={() => window.open('/licenses.txt', '_blank')}>Open-Source Licenses</Row>
        <div className="row"><span className="caption">Made by Tailgate Labs</span></div>
      </Section>
    </Page>
  );
}

export function ProfilePage() {
  const fleet = useFleet();
  const navigate = useSafeNavigate();
  const [name, setName] = useState(fleet.me?.displayName ?? '');
  const [phone, setPhone] = useState(fleet.contacts[fleet.uid]?.phone ?? '');
  return (
    <Page back title="Your Profile" inlineTitle>
      <h1 className="page-title" style={{ fontSize: 26 }}>Your Profile</h1>
      <Section footer="Your name is shown to the fleet. Your phone number and email are only visible to managers.">
        <Field label="Name"><input value={name} onChange={(e) => setName(e.target.value)} autoComplete="name" /></Field>
        <Field label="Phone"><input type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="Optional" autoComplete="tel" /></Field>
      </Section>
      <Section plain><button className="btn" disabled={!name.trim()} onClick={() => { updateMyProfile(fleet, name, phone); navigate(-1); }}>Save</button></Section>
    </Page>
  );
}

export function DeleteAccountPage() {
  const [password, setPassword] = useState('');
  const [working, setWorking] = useState(false);
  const [error, setError] = useState<string>();
  const online = useOnline();
  return (
    <Page back title="Delete Account" inlineTitle>
      <h1 className="page-title" style={{ fontSize: 26 }}>Delete Account</h1>
      <Section footer="This removes you from every fleet and deletes your login, profile and contact details. Checklists and reports you submitted stay in each fleet's records. If you're the only manager of a fleet with other members, make someone else a manager first. This can't be undone and needs a connection.">
        <Field><input type="password" placeholder="Your password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} /></Field>
      </Section>
      {error && <Banner color="red">{error}</Banner>}
      <Section plain>
        <button className="btn red" disabled={!password || working || !online} onClick={async () => {
          if (!confirmAction('Delete your account permanently?')) return;
          setWorking(true);
          setError(undefined);
          try { await photoQueue.clear(); await session.deleteAccount(password); } catch (e) { setError((e as Error).message); }
          setWorking(false);
        }}>{working ? 'Deleting…' : 'Delete My Account'}</button>
      </Section>
    </Page>
  );
}

export function DataStoragePage() {
  const fleet = useFleet();
  const online = useOnline();
  const [cutoff, setCutoff] = useState(addYears(new Date(), -3));
  const [working, setWorking] = useState(false);
  const [result, setResult] = useState<string>();
  const usage = fleet.fleet?.usage ?? {};
  const photoBytes = Math.max(0, usage.photoBytes ?? 0);
  const records = Math.max(0, usage.recordCount ?? 0);
  const dbBytes = records * BYTES_PER_RECORD;
  const photoFraction = photoBytes / PHOTO_ALLOWANCE;
  const dbFraction = dbBytes / DATABASE_ALLOWANCE;
  const worst = Math.max(photoFraction, dbFraction);
  const bar = (fraction: number) => (
    <div style={{ height: 6, background: 'var(--field)', borderRadius: 3, marginTop: 6 }}>
      <div style={{ width: `${Math.min(100, fraction * 100)}%`, height: '100%', borderRadius: 3, background: fraction >= 0.95 ? 'var(--red)' : fraction >= 0.8 ? 'var(--orange)' : 'var(--accent)' }} />
    </div>
  );
  return (
    <Page back title="Data & Storage" inlineTitle>
      <h1 className="page-title" style={{ fontSize: 26 }}>Data &amp; Storage</h1>
      {worst >= 0.8 && <Banner color={worst >= 0.95 ? 'red' : 'orange'}>{worst >= 0.95 ? 'Storage is nearly at the free allowance. Delete old records or expect small charges.' : 'Storage is over 80% of the free allowance. Consider deleting old records.'}</Banner>}
      <Section header="Usage" footer="Compared with Firebase's free allowances. Record size is an estimate.">
        <div className="pad"><div>Photos</div><div className="caption">{usage.photoCount ?? 0} photos · {formatBytes(photoBytes)} of {formatBytes(PHOTO_ALLOWANCE)}</div>{bar(photoFraction)}</div>
        <div className="pad"><div>Records</div><div className="caption">{records} records · about {formatBytes(dbBytes)} of {formatBytes(DATABASE_ALLOWANCE)}</div>{bar(dbFraction)}</div>
      </Section>
      <Section><div className="row"><span className="subtitle">🕘 Records are deleted automatically 5 years after they're created (defects: 5 years after they're closed).</span></div></Section>
      <Section header="Free Up Space" footer={online ? 'Deletes completed checklists, closed defects with their photos, reviewed service records, chain logs and reviewed rope changes from before this date. Open defects and anything awaiting approval are kept.' : 'Needs a connection.'}>
        <Field label="Delete before"><input type="date" className="right" max={toDateInput(new Date())} value={toDateInput(cutoff)} onChange={(e) => { const d = fromDateInput(e.target.value); if (d) setCutoff(d); }} /></Field>
        <Row className="destructive" chevron={false} disabled={working || !online} onClick={async () => {
          if (!confirmAction(`Permanently delete records from before ${cutoff.toLocaleDateString()}? This can't be undone.`)) return;
          setWorking(true);
          try {
            const total = await deleteRecordsBefore(fleet, cutoff);
            setResult(total ? `Deleted ${total} record${total === 1 ? '' : 's'}.` : 'Nothing to delete before that date.');
          } catch (e) { setResult(`Couldn't finish. ${friendlyError(e)}`); }
          setWorking(false);
        }}>{working ? 'Deleting…' : 'Delete Old Records'}</Row>
        {result && <div className="row"><span className="subtitle">{result}</span></div>}
      </Section>
    </Page>
  );
}
