import '../data/mock_data.dart';
import '../models/vehicle_model.dart';
import '../services/local_cache_service.dart';
import '../services/vehicle_lookup_service.dart';

class GateRepository {
  const GateRepository();

  List<VehicleRecord> getRegisteredVehicles() {
    final cached = LocalCacheService.getCachedVehicles();
    if (cached.isNotEmpty) {
      return cached;
    }
    return MockData.registeredVehicles;
  }

  List<AuditLogEntry> getInitialAuditLogs() {
    final cached = LocalCacheService.getCachedLogs();
    if (cached.isNotEmpty) {
      return cached;
    }
    return MockData.getInitialAuditLogs();
  }

  VehicleRecord resolveVehicle(String rawQr) {
    return VehicleLookupService.resolveVehicleFromQr(
      rawQrCode: rawQr,
      registeredVehicles: getRegisteredVehicles(),
    );
  }
}
