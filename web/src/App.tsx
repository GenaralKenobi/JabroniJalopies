import { BrowserRouter, Navigate, NavLink, Route, Routes } from 'react-router-dom';
import { session } from './data/session';
import { useObservable } from './data/store';
import { ErrorToast, LoadingScreen } from './ui/kit';
import { SignInPage, VerifyEmailPage } from './pages/Auth';
import { FleetPickerPage } from './pages/Fleets';
import { FleetListPage } from './pages/FleetList';
import { VehiclePage } from './pages/Vehicle';
import { ChecklistPage } from './pages/Checklist';
import { DefectsPage, DefectDetailPage, ReportDefectPage } from './pages/Defects';
import { UpcomingPage, PlanChecklistPage } from './pages/Upcoming';
import { SettingsPage, ProfilePage, DeleteAccountPage, DataStoragePage } from './pages/Settings';
import { SpecsPage, SpecsEditPage } from './pages/Specs';
import { ContentsPage } from './pages/Contents';
import { VehicleFormPage } from './pages/VehicleForm';
import { ReminderFormPage, ServiceFormPage, ServiceReviewPage, HistoryPage, InspectionPage } from './pages/Records';
import { MembersPage, MemberPage, InvitePage } from './pages/Members';
import { ChecklistsAdminPage, ChecklistEditorPage } from './pages/ChecklistsAdmin';
import { PrintChecklistPage, PrintContentsPage } from './pages/Print';
import { EquipmentListPage, EquipmentPage, EquipmentFormPage } from './pages/Equipment';
import { ChainsPage, ChainTotalsPage } from './pages/Chains';

export function App() {
  useObservable(session);
  if (session.loading) return <LoadingScreen waitingFor={['sign-in']} />;
  return (
    <BrowserRouter>
      <ErrorToast />
      <Gate />
    </BrowserRouter>
  );
}

function Gate() {
  if (!session.user) return <div className="app no-tabs"><SignInPage /></div>;
  if (session.needsEmailVerification) return <div className="app no-tabs"><VerifyEmailPage /></div>;
  if (!session.membershipsLoaded) return <LoadingScreen waitingFor={['your fleets']} />;
  if (!session.fleet) {
    return (
      <div className="app no-tabs">
        <Routes><Route path="*" element={<FleetPickerPage initial />} /></Routes>
      </div>
    );
  }
  return <Main key={session.fleet.fleetId} />;
}

function Main() {
  const fleet = useObservable(session.fleet!);
  const defectsBadge = fleet.allOpenDefects.length + (fleet.isManager ? fleet.allPendingServices.length + fleet.allPendingLengthChanges.length : 0);
  if (!fleet.ready) return <LoadingScreen waitingFor={fleet.waitingFor} />;
  return (
    <div className="app">
      <Routes>
        <Route path="/" element={<FleetListPage />} />
        <Route path="/defects" element={<DefectsPage />} />
        <Route path="/upcoming" element={<UpcomingPage />} />
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="/settings/profile" element={<ProfilePage />} />
        <Route path="/settings/fleets" element={<FleetPickerPage />} />
        <Route path="/settings/delete-account" element={<DeleteAccountPage />} />
        <Route path="/settings/storage" element={<DataStoragePage />} />
        <Route path="/settings/members" element={<MembersPage />} />
        <Route path="/settings/members/:memberId" element={<MemberPage />} />
        <Route path="/settings/invite" element={<InvitePage />} />
        <Route path="/settings/checklists" element={<ChecklistsAdminPage />} />
        <Route path="/settings/checklists/:checklistId" element={<ChecklistEditorPage />} />
        <Route path="/settings/equipment" element={<EquipmentListPage />} />
        <Route path="/settings/chains" element={<ChainTotalsPage />} />
        <Route path="/v/new" element={<VehicleFormPage />} />
        <Route path="/v/:vehicleId" element={<VehiclePage />} />
        <Route path="/v/:vehicleId/edit" element={<VehicleFormPage />} />
        <Route path="/v/:vehicleId/checklist/:checklistId" element={<ChecklistPage />} />
        <Route path="/v/:vehicleId/specs" element={<SpecsPage />} />
        <Route path="/v/:vehicleId/specs/edit" element={<SpecsEditPage />} />
        <Route path="/v/:vehicleId/contents" element={<ContentsPage />} />
        <Route path="/v/:vehicleId/report" element={<ReportDefectPage />} />
        <Route path="/v/:vehicleId/reminders/:reminderId" element={<ReminderFormPage />} />
        <Route path="/v/:vehicleId/services/:serviceId" element={<ServiceFormPage />} />
        <Route path="/v/:vehicleId/services/:serviceId/review" element={<ServiceReviewPage />} />
        <Route path="/v/:vehicleId/history" element={<HistoryPage />} />
        <Route path="/v/:vehicleId/inspections/:inspectionId" element={<InspectionPage />} />
        <Route path="/v/:vehicleId/chains" element={<ChainsPage />} />
        <Route path="/v/:vehicleId/plan/:checklistId" element={<PlanChecklistPage />} />
        <Route path="/defect/:kind/:ownerId/:defectId" element={<DefectDetailPage />} />
        <Route path="/print/checklist/:checklistId" element={<PrintChecklistPage />} />
        <Route path="/print/contents/:vehicleId" element={<PrintContentsPage />} />
        <Route path="/equipment/new" element={<EquipmentFormPage />} />
        <Route path="/equipment/:equipmentId" element={<EquipmentPage />} />
        <Route path="/equipment/:equipmentId/edit" element={<EquipmentFormPage />} />
        <Route path="/equipment/:equipmentId/report" element={<ReportDefectPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      <nav className="tabbar" aria-label="Main">
        <NavLink to="/" end><TabIcon>🚚</TabIcon>Fleet</NavLink>
        <NavLink to="/defects"><TabIcon>⚠️</TabIcon>Defects{defectsBadge > 0 && <span className="tab-badge">{defectsBadge}</span>}</NavLink>
        <NavLink to="/upcoming"><TabIcon>📅</TabIcon>Upcoming</NavLink>
        <NavLink to="/settings"><TabIcon>⚙️</TabIcon>Settings</NavLink>
      </nav>
    </div>
  );
}

const TabIcon = ({ children }: { children: string }) => <span aria-hidden style={{ fontSize: 20, lineHeight: 1 }}>{children}</span>;
