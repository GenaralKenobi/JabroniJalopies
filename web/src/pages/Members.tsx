import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { Banner, Empty, Field, Page, Row, Section, ToggleRow, confirmAction, useFleet, useSafeNavigate } from '../ui/kit';
import { invite, removeMember, revokeInvite, setAssigned, setRole, setSeesAllVehicles, setTruckLead } from '../data/actions';
import { roleName, vehicleName, type Role } from '../logic/model';

export function MembersPage() {
  const fleet = useFleet();
  return (
    <Page back title="Members" inlineTitle actions={fleet.isManager ? <Link className="btn plain" to="/settings/invite">＋ Invite</Link> : undefined}>
      <h1 className="page-title" style={{ fontSize: 26 }}>Members</h1>
      <Section footer={fleet.isManager ? 'Phone numbers and emails are only visible to managers.' : undefined}>
        {fleet.members.map((m) => {
          const contact = fleet.contacts[m.id];
          return (
            <Row key={m.id} to={fleet.isManager ? `/settings/members/${m.id}` : undefined} value={roleName(m.role)}>
              {m.displayName}{m.id === fleet.uid ? ' (you)' : ''}
              {fleet.isManager && contact && <div className="caption">{[contact.email, contact.phone].filter(Boolean).join(' · ')}</div>}
              {m.role === 'driver' && !m.seesAllVehicles && <div className="caption">Sees assigned vehicles only</div>}
            </Row>
          );
        })}
      </Section>
      {fleet.isManager && fleet.invites.length > 0 && (
        <Section header="Waiting to Join" footer="They'll see the invite after signing in with that email address and confirming it.">
          {fleet.invites.map((inv) => (
            <div className="row" key={inv.id}>
              <span className="grow stack"><span>{inv.email}</span><span className="caption">{roleName(inv.role)} · invited by {inv.invitedByName}</span></span>
              <button className="btn small red" onClick={() => { if (confirmAction(`Cancel the invite to ${inv.email}?`)) revokeInvite(fleet, inv); }}>Cancel</button>
            </div>
          ))}
        </Section>
      )}
    </Page>
  );
}

export function InvitePage() {
  const fleet = useFleet();
  const navigate = useSafeNavigate();
  const [email, setEmail] = useState('');
  const [role, setRoleValue] = useState<Role>('driver');
  const [error, setError] = useState<string>();
  if (!fleet.isManager) return <Page back title="Invite"><Empty title="Managers only" /></Page>;
  return (
    <Page back title="Invite" inlineTitle>
      <h1 className="page-title" style={{ fontSize: 26 }}>Invite Someone</h1>
      <Section footer="They create an account in the app (or on this website) with this exact email, confirm it, and the invite appears for them to accept.">
        <Field><input type="email" autoCapitalize="none" placeholder="Email address" value={email} onChange={(e) => setEmail(e.target.value)} /></Field>
        <Field label="Role">
          <select value={role} onChange={(e) => setRoleValue(e.target.value as Role)}><option value="driver">Driver</option><option value="manager">Manager</option></select>
        </Field>
      </Section>
      {error && <Banner color="red">{error}</Banner>}
      <Section plain>
        <button className="btn" disabled={!email.trim()} onClick={() => {
          try { invite(fleet, email, role); navigate(-1); } catch (e) { setError((e as Error).message); }
        }}>Send Invite</button>
      </Section>
    </Page>
  );
}

export function MemberPage() {
  const { memberId = '' } = useParams();
  const fleet = useFleet();
  const navigate = useSafeNavigate();
  const member = fleet.member(memberId);
  const [error, setError] = useState<string>();
  if (!member) return <Page back title="Member"><Empty title="Member not found" /></Page>;
  if (!fleet.isManager) return <Page back title="Member"><Empty title="Managers only" /></Page>;
  const contact = fleet.contacts[member.id];
  return (
    <Page back title={member.displayName} inlineTitle>
      <h1 className="page-title" style={{ fontSize: 26 }}>{member.displayName}</h1>
      <Section>
        {contact?.email && <Row onClick={() => window.open(`mailto:${contact.email}`)} value={contact.email} chevron={false}>Email</Row>}
        {contact?.phone && <Row onClick={() => window.open(`tel:${contact.phone}`)} value={contact.phone} chevron={false}>Phone</Row>}
        <Field label="Role">
          <select value={member.role} onChange={(e) => { try { setRole(fleet, member, e.target.value as Role); setError(undefined); } catch (err) { setError((err as Error).message); } }}>
            <option value="driver">Driver</option><option value="manager">Manager</option>
          </select>
        </Field>
      </Section>
      {error && <Banner color="red">{error}</Banner>}
      {member.role === 'driver' && (
        <Section header="Vehicles" footer={member.seesAllVehicles ? 'Turn off to choose which vehicles they can see.' : 'They only see the vehicles ticked below.'}>
          <ToggleRow label="Sees All Vehicles" checked={member.seesAllVehicles} onChange={(v) => setSeesAllVehicles(fleet, member, v)} />
          {!member.seesAllVehicles && fleet.sortedVehicles.map((v) => (
            <ToggleRow key={v.id} label={vehicleName(v)} checked={v.assignedUids.includes(member.id)} onChange={(on) => setAssigned(fleet, member.id, v.id, on)} />
          ))}
        </Section>
      )}
      {(member.role === 'driver' || fleet.sortedVehicles.some((v) => v.contentsEditorUid === member.id)) && fleet.sortedVehicles.length > 0 && (
        <Section header="Truck Lead For" footer="The truck lead keeps the truck's list of what's on it up to date. Each truck has one lead; ticking a truck replaces its current lead.">
          {fleet.sortedVehicles.map((v) => {
            const other = v.contentsEditorUid && v.contentsEditorUid !== member.id ? fleet.truckLeadName(v) : undefined;
            return (
              <ToggleRow key={v.id} label={vehicleName(v)} detail={other ? `Lead now: ${other}` : undefined} checked={v.contentsEditorUid === member.id}
                onChange={(on) => setTruckLead(fleet, v.id, on ? member.id : undefined)} />
            );
          })}
        </Section>
      )}
      {member.id !== fleet.uid && (
        <Section footer="Their past checklists and reports stay in the fleet's records.">
          <Row className="destructive" chevron={false} onClick={() => {
            if (!confirmAction(`Remove ${member.displayName} from the fleet?`)) return;
            try { removeMember(fleet, member); navigate(-1); } catch (e) { setError((e as Error).message); }
          }}>Remove from Fleet</Row>
        </Section>
      )}
    </Page>
  );
}
