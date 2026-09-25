// SecurePark - NCST Campus Vehicle Custody Management System
// Clean System Initialization without Mock/Fake Data

const INITIAL_DATA = {
  systemInfo: {
    institution: "National College of Science and Technology (NCST)",
    systemName: "SecurePark — QR Digital Custody & Exit Verification",
    version: "2.4.0",
    campus: "Main Campus - Dasmariñas, Cavite",
    activeGates: [
      { id: "gate-1", name: "Gate 1 (Main Ingress)", type: "Entry", guardOnDuty: "Sgt. R. Mendoza", status: "Active" },
      { id: "gate-2", name: "Gate 2 (Main Egress)", type: "Exit", guardOnDuty: "Officer J. Valenzuela", status: "Active" },
      { id: "gate-3", name: "Gate 3 (Motorcycle & Bike Lane)", type: "Bi-directional", guardOnDuty: "Officer D. Soriano", status: "Active" }
    ]
  },

  // Empty datasets populated dynamically from InfinityFree MySQL database
  vehicles: [],
  auditLogs: [],
  incidents: []
};
