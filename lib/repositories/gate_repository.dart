import '../data/mock_data.dart';
import '../models/vehicle_model.dart';
import '../services/vehicle_lookup_service.dart';

class GateRepository {
  const GateRepository();
  List<VehicleRecord> getRegisteredVehicles() {
    return MockData.registeredVehicles;
  }

  List<AuditLogEntry> getInitialAuditLogs() {
    return MockData.getInitialAuditLogs();
  }

  VehicleRecord resolveVehicle(String rawQr) {
    return VehicleLookupService.resolveVehicleFromQr(
      rawQrCode: rawQr,
      registeredVehicles: getRegisteredVehicles(),
    );
  }
}
