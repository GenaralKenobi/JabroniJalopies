import type { ChecklistItem, ChecklistTemplate, SpecSection, Vehicle } from './model';

const uuid = () => crypto.randomUUID().toUpperCase();

/** The starter checklist created with every new fleet (ChecklistDefaults.swift). */
export function morningChecklist(): Omit<ChecklistTemplate, 'id'> {
  const item = (title: string, reading?: string, unsafe = false): ChecklistItem => ({
    id: uuid(), title, requiresReading: reading != null, readingLabel: reading ?? '', unsafeIfFailed: unsafe,
  });
  return {
    name: 'Morning Checklist',
    items: [
      item('Tires — inflation and tread', undefined, true),
      item('Lowest tire pressure', 'PSI'),
      item('Brakes and parking brake', undefined, true),
      item('Headlights, brake lights and turn signals', undefined, true),
      item('Windshield, wipers and washer fluid'),
      item('Mirrors'),
      item('Horn'),
      item('Seat belts', undefined, true),
      item('Fluid leaks under vehicle'),
      item('Engine oil level'),
      item('Warning lights on dash'),
      item('Fire extinguisher and first-aid kit'),
    ],
    vehicleIds: [],
    updatedAt: new Date(),
  };
}

export const newChecklistItem = (title = ''): ChecklistItem =>
  ({ id: uuid(), title, requiresReading: false, readingLabel: '', unsafeIfFailed: false });

const SPEC_TEMPLATE: [string, string[]][] = [
  ['Fluids', ['Engine oil', 'Oil capacity', 'Coolant', 'Transmission fluid', 'Brake fluid',
    'Power steering fluid', 'Differential / axle oil', 'DEF', 'Washer fluid', 'Fuel type']],
  ['Tires & Wheels', ['Tire size', 'Brand / model', 'Load index / speed rating', 'Front pressure (cold, PSI)',
    'Rear pressure (cold, PSI)', 'Spare pressure (PSI)', 'Lug nut torque', 'Dual rear wheels']],
  ['Parts & Capacities', ['Oil filter', 'Engine air filter', 'Cabin air filter', 'Battery (group / CCA)',
    'Wiper blades', 'Headlight bulb', 'GVWR', 'Towing capacity']],
];

export function defaultSpecSections(): SpecSection[] {
  return SPEC_TEMPLATE.map(([title, rows]) => ({
    id: uuid(), title, rows: rows.map((label) => ({ id: uuid(), label, value: '' })),
  }));
}

/** Sections with only the rows that have values (what the quick view shows). */
export function filledSpecs(sections: SpecSection[]): SpecSection[] {
  return sections.map((s) => ({ ...s, rows: s.rows.filter((r) => r.value.trim()) })).filter((s) => s.rows.length);
}

export function newVehicle(): Omit<Vehicle, 'id'> {
  return {
    name: '', make: '', model: '', year: new Date().getFullYear(), vin: '', licensePlate: '', odometer: 0,
    assignedUids: [], specSections: defaultSpecSections(),
  };
}

export { uuid };
