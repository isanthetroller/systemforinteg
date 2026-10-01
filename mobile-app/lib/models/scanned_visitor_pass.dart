import 'visitor_pass_model.dart';

/// An item a visitor declared they are bringing in (for example "40x Monobloc chairs").
class VisitorPassItem {
  final String name;
  final int quantity;
  final String description;

  const VisitorPassItem({required this.name, required this.quantity, this.description = ''});

  factory VisitorPassItem.fromJson(Map<String, dynamic> json) {
    return VisitorPassItem(
      name: (json['name'] ?? 'Item').toString(),
      quantity: int.tryParse((json['quantity'] ?? 1).toString()) ?? 1,
      description: (json['description'] ?? '').toString(),
    );
  }

  /// "40x Monobloc chairs (for Foundation Day)"
  String get label => description.isEmpty ? '${quantity}x $name' : '${quantity}x $name ($description)';
}

/// A visitor day pass that already exists on the server (issued in the web portal, or scheduled by an
/// administrator), as reported by `verify.php` when a guard scans its pass code or types its plate.
///
/// The server has already decided whether the pass may be used ([accepted], [result], [reason]); the phone only
/// shows that decision, makes the guard tick off the declared items, and then records the entry against the pass.
class ScannedVisitorPass {
  final int id;
  final String passCode;
  final String visitorName;
  final String contactNumber;
  final String plateNumber;
  final String vehicleModel;
  final String purposeOfVisit;
  final String personToVisit;
  final String validDate;
  final String status;
  final List<VisitorPassItem> items;

  /// The server's verdict for this pass at this gate: VALID, MANUAL, NOT_YET_VALID, EXPIRED_TEMP, REVOKED...
  final String result;
  final bool accepted;
  final String reason;
  final List<String> warnings;
  final bool currentlyInside;

  const ScannedVisitorPass({
    required this.id,
    required this.passCode,
    required this.visitorName,
    required this.plateNumber,
    required this.validDate,
    required this.status,
    required this.result,
    required this.accepted,
    this.contactNumber = '',
    this.vehicleModel = '',
    this.purposeOfVisit = '',
    this.personToVisit = '',
    this.items = const [],
    this.reason = '',
    this.warnings = const [],
    this.currentlyInside = false,
  });

  /// Builds the pass from a `verify.php` response body (`data`), or returns null when the response carries no visitor
  /// (an ordinary registered vehicle, or nothing found).
  static ScannedVisitorPass? fromVerify(Map<String, dynamic>? data) {
    if (data == null) return null;
    final raw = data['visitor'];
    if (raw is! Map) return null;
    final v = Map<String, dynamic>.from(raw);
    final id = int.tryParse((v['id'] ?? '').toString());
    if (id == null || id <= 0) return null;

    final items = <VisitorPassItem>[];
    if (v['items'] is List) {
      for (final item in (v['items'] as List)) {
        if (item is Map) items.add(VisitorPassItem.fromJson(Map<String, dynamic>.from(item)));
      }
    }

    return ScannedVisitorPass(
      id: id,
      passCode: (v['passCode'] ?? v['pass_code'] ?? '').toString(),
      visitorName: (v['visitorName'] ?? v['visitor_name'] ?? 'Visitor').toString(),
      contactNumber: (v['contactNumber'] ?? v['contact_number'] ?? '').toString(),
      plateNumber: (v['plateNumber'] ?? v['plate_number'] ?? '').toString(),
      vehicleModel: (v['vehicleModel'] ?? v['vehicle_model'] ?? '').toString(),
      purposeOfVisit: (v['purposeOfVisit'] ?? v['purpose_of_visit'] ?? '').toString(),
      personToVisit: (v['personToVisit'] ?? v['person_to_visit'] ?? '').toString(),
      validDate: (v['validDate'] ?? v['valid_date'] ?? '').toString(),
      status: (v['status'] ?? '').toString(),
      items: items,
      result: (data['result'] ?? '').toString(),
      accepted: data['accepted'] == true,
      reason: (data['reason'] ?? '').toString(),
      warnings: data['warnings'] is List
          ? (data['warnings'] as List).map((w) => w.toString()).toList()
          : const [],
      currentlyInside: data['currentlyInside'] == true,
    );
  }

  /// Constructs a ScannedVisitorPass from an existing VisitorPass record
  factory ScannedVisitorPass.fromVisitorPass(
    VisitorPass pass, {
    String result = 'VALID',
    bool accepted = true,
    String reason = '',
    List<String> warnings = const [],
    bool currentlyInside = false,
    int? id,
  }) {
    final validDateStr = '${pass.entryTime.year}-${pass.entryTime.month.toString().padLeft(2, '0')}-${pass.entryTime.day.toString().padLeft(2, '0')}';
    return ScannedVisitorPass(
      id: id ?? pass.dbId ?? (int.tryParse(pass.passId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1),
      passCode: pass.passId,
      visitorName: pass.visitorName,
      contactNumber: pass.contactNumber ?? '',
      plateNumber: pass.plateNumber,
      vehicleModel: pass.vehicleModel ?? '',
      purposeOfVisit: pass.purposeOfVisit ?? '',
      personToVisit: pass.personToVisit ?? '',
      validDate: validDateStr,
      status: pass.statusDisplay,
      items: pass.items.map((m) => VisitorPassItem(
        name: (m['name'] ?? m['item_name'] ?? 'Item').toString(),
        quantity: int.tryParse((m['quantity'] ?? 1).toString()) ?? 1,
        description: (m['description'] ?? '').toString(),
      )).toList(),
      result: result,
      accepted: accepted,
      reason: reason,
      warnings: warnings,
      currentlyInside: currentlyInside,
    );
  }

  /// The guard may record an entry only when the server accepted the pass at this gate.
  bool get canAdmit => accepted;

  /// True if the pass is blocked, revoked, banned, or under security hold
  bool get isBlocked =>
      status.toLowerCase().contains('block') ||
      status.toLowerCase().contains('hold') ||
      result == 'REVOKED' ||
      result == 'BANNED' ||
      reason.toLowerCase().contains('block') ||
      reason.toLowerCase().contains('hold');

  /// Declared items must each be checked by the guard before the entry can be recorded.
  bool get hasItems => items.isNotEmpty;

  /// Short headline for the verdict, shown on the card.
  String get verdictTitle {
    switch (result) {
      case 'VALID':
        return 'VISITOR PASS VALID';
      case 'MANUAL':
        return 'VISITOR PASS FOUND';
      case 'NOT_YET_VALID':
        return 'PASS NOT YET VALID';
      case 'EXPIRED_TEMP':
        return 'EXPIRED TEMPORARY PASS';
      case 'REVOKED':
        return 'PASS REVOKED OR ALREADY USED';
      default:
        return accepted ? 'VISITOR PASS FOUND' : 'PASS REFUSED';
    }
  }
}
