import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { session } from '../data/session';
import { useObservable } from '../data/store';
import { Banner, Field, Page, Row, Section } from '../ui/kit';
import { roleName, type Invite } from '../logic/model';

/** Switch fleets, accept invites, or create a new fleet. */
export function FleetPickerPage({ initial = false }: { initial?: boolean }) {
  useObservable(session);
  const navigate = useNavigate();
  const [creating, setCreating] = useState(false);
  const [accepting, setAccepting] = useState<Invite>();

  if (creating) return <CreateFleet onDone={() => { setCreating(false); navigate('/'); }} onCancel={() => setCreating(false)} />;
  if (accepting) return <AcceptInvite invite={accepting} onDone={() => { setAccepting(undefined); navigate('/'); }} onCancel={() => setAccepting(undefined)} />;

  return (
    <Page title={initial ? 'Get Started' : 'Fleets'} back={!initial}>
      {initial && !session.memberships.length && !session.invites.length && (
        <Section>
          <div className="pad">
            <div className="strong" style={{ fontSize: 20, marginBottom: 6 }}>Welcome!</div>
            <p style={{ margin: '0 0 6px' }}><b>Managers:</b> create a fleet, then invite your drivers.</p>
            <p style={{ margin: 0 }}><b>Drivers:</b> ask your manager to invite <b>{session.email}</b>. The invite will appear here.</p>
          </div>
        </Section>
      )}
      {session.invites.length > 0 && (
        <Section header="Invitations">
          {session.invites.map((invite) => (
            <div className="pad" key={invite.id}>
              <div className="strong">{invite.fleetName}</div>
              <div className="subtitle mb">{invite.invitedByName} invited you as a {roleName(invite.role).toLowerCase()}.</div>
              <div className="btn-row">
                <button className="btn small" onClick={() => setAccepting(invite)}>Join</button>
                <button className="btn small red" onClick={() => session.decline(invite)}>Decline</button>
              </div>
            </div>
          ))}
        </Section>
      )}
      {session.memberships.length > 0 && (
        <Section header="Your Fleets" footer="Each fleet keeps its own profile, role and vehicles.">
          {session.memberships.map((m) => (
            <Row key={m.id} icon="🚚" onClick={() => { session.select(m.id); navigate('/'); }}
              value={m.id === session.fleet?.fleetId ? '✓' : undefined} chevron={false}>{m.fleetName}</Row>
          ))}
        </Section>
      )}
      <Section>
        <Row className="accent" icon="＋" onClick={() => setCreating(true)} chevron={false}>Create a New Fleet</Row>
      </Section>
      {initial && (
        <Section footer={`Signed in as ${session.email}`}>
          <Row className="destructive" onClick={() => session.signOut()} chevron={false}>Sign Out</Row>
        </Section>
      )}
    </Page>
  );
}

function ProfileFields({ name, phone, setName, setPhone }: { name: string; phone: string; setName: (v: string) => void; setPhone: (v: string) => void }) {
  return (
    <>
      <Field><input placeholder="Your name" autoComplete="name" value={name} onChange={(e) => setName(e.target.value)} aria-label="Your name" /></Field>
      <Field><input placeholder="Phone (optional)" type="tel" autoComplete="tel" value={phone} onChange={(e) => setPhone(e.target.value)} aria-label="Phone" /></Field>
    </>
  );
}

function CreateFleet({ onDone, onCancel }: { onDone: () => void; onCancel: () => void }) {
  const [name, setName] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [phone, setPhone] = useState('');
  const [unit, setUnit] = useState<'mi' | 'km'>('mi');
  const [error, setError] = useState<string>();
  return (
    <Page title="New Fleet" inlineTitle back={false} actions={<button className="btn plain" onClick={onCancel}>Cancel</button>}>
      <h1 className="page-title">New Fleet</h1>
      <Section footer={<>You'll be the fleet's manager. You can invite drivers and other managers next.<br /><br />If your company already uses Jabroni Jalopies, don't create a new fleet: ask your manager to invite {session.email} instead.</>}>
        <Field><input placeholder="Fleet name (e.g. Acme Delivery)" value={name} onChange={(e) => setName(e.target.value)} aria-label="Fleet name" /></Field>
        <Field label="Distance">
          <select value={unit} onChange={(e) => setUnit(e.target.value as 'mi' | 'km')}>
            <option value="mi">Miles</option><option value="km">Kilometers</option>
          </select>
        </Field>
      </Section>
      <Section header="Your Profile in This Fleet" footer="Your name is shown to the fleet. Your phone number and email are only visible to managers.">
        <ProfileFields name={displayName} phone={phone} setName={setDisplayName} setPhone={setPhone} />
      </Section>
      {error && <Banner color="red">{error}</Banner>}
      <div style={{ margin: '0 16px' }}>
        <button className="btn" disabled={!name.trim() || !displayName.trim()} onClick={() => {
          try { session.createFleet(name, { displayName, phone }, unit); onDone(); } catch (e) { setError((e as Error).message); }
        }}>Create Fleet</button>
      </div>
    </Page>
  );
}

function AcceptInvite({ invite, onDone, onCancel }: { invite: Invite; onDone: () => void; onCancel: () => void }) {
  const [displayName, setDisplayName] = useState('');
  const [phone, setPhone] = useState('');
  return (
    <Page title="Join Fleet" inlineTitle back={false} actions={<button className="btn plain" onClick={onCancel}>Cancel</button>}>
      <h1 className="page-title">Join Fleet</h1>
      <Section>
        <Row value={invite.fleetName}>Fleet</Row>
        <Row value={roleName(invite.role)}>Role</Row>
        <Row value={invite.invitedByName}>Invited by</Row>
      </Section>
      <Section header="Your Profile in This Fleet" footer="Each fleet has its own profile. Your name is shown to the fleet; your phone number and email are only visible to its managers.">
        <ProfileFields name={displayName} phone={phone} setName={setDisplayName} setPhone={setPhone} />
      </Section>
      <div style={{ margin: '0 16px' }}>
        <button className="btn" disabled={!displayName.trim()} onClick={() => { session.accept(invite, { displayName, phone }); onDone(); }}>Join</button>
      </div>
    </Page>
  );
}
