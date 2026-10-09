class AppConstants {
  static const List<String> auditLogFilters = ['All', 'Inside', 'Exited', 'Blocked'];

  /// Violation types the server accepts (lib/violations.php violationPresetTypes)
  static const List<String> violationTypes = [
    'Overnight / Unauthorized Overtime Parking',
    'Unauthorized Driver at Helm',
    'Expired Campus Registration Sticker',
    'Reckless / Prohibited Driving on Campus',
    'Parking in Fire Lane / Restricted Zone',
    'Refusal of Inspection / Gate Bypass',
    'Other',
  ];

  static const List<String> defaultBlockReasons = [
    'Unauthorized / Unregistered Driver',
    'Plate & Vehicle Profile Mismatch',
    'Expired Campus Parking Sticker',
    'Invalid / Revoked QR Pass',
    'Security Officer Intervention',
  ];
}
