/// Which way the guard is working: the entry lane records vehicles coming in, the exit lane vehicles going out.
/// The phone sends the lane with every scan so the server can tell a real exit from a second entry scan (anti-passback).
enum ScanLane { entry, exit }

extension ScanLaneText on ScanLane {
  /// What the server expects in `direction`.
  String get code => this == ScanLane.entry ? 'IN' : 'OUT';
  String get label => this == ScanLane.entry ? 'Entry lane' : 'Exit lane';
  String get verb => this == ScanLane.entry ? 'entry' : 'exit';

  /// Gate that normally handles this lane (entry = Gate 1, exit = Gate 2).
  String get defaultGate => this == ScanLane.entry ? 'Gate 1' : 'Gate 2';
  ScanLane get other => this == ScanLane.entry ? ScanLane.exit : ScanLane.entry;
}

/// The lanes a guard may use, worked out from the account's gate and the server's gate policy.
class LaneConfig {
  final Set<ScanLane> allowed;

  /// 'Gate 1' / 'Gate 2' when the account is tied to a gate, null for All Gates / Gate 3 / blank accounts.
  final String? fixedGate;
  final bool eventMode;

  const LaneConfig({
    required this.allowed,
    this.fixedGate,
    this.eventMode = false,
  });

  /// One lane only: the guard cannot switch.
  bool get locked => allowed.length == 1;
  ScanLane get defaultLane => allowed.contains(ScanLane.entry) ? ScanLane.entry : ScanLane.exit;

  /// The gate shown for [lane]: the account's own gate, or the gate that normally handles the lane.
  String gateFor(ScanLane lane) => fixedGate ?? lane.defaultGate;

  String get subtitle => locked
      ? 'Set by your account'
      : eventMode
      ? 'Event mode: entry and exit at both gates'
      : 'Choose the lane you are working';

  /// [policy] is the answer of gate_policy.php (may be null when the phone is offline or has not loaded it yet).
  factory LaneConfig.from({String? assignedGate, Map<String, dynamic>? policy}) {
    final gate = RegExp(
      r'\b(?:gate|checkpoint)\s*[-#]?\s*([12])\b',
      caseSensitive: false,
    ).firstMatch(assignedGate ?? '')?.group(1);
    final number = policy?['gateNumber']?.toString() ?? gate;
    final event = policy?['mode'] == 'event';

    Set<ScanLane> allowed;
    final fromServer = policy?['allowedDirections'];
    if (fromServer is List && fromServer.isNotEmpty) {
      allowed = {
        for (final d in fromServer)
          if (d == 'Ingress') ScanLane.entry else if (d == 'Egress') ScanLane.exit,
      };
    } else if (number == '1' && !event) {
      allowed = {ScanLane.entry};
    } else if (number == '2' && !event) {
      allowed = {ScanLane.exit};
    } else {
      allowed = {ScanLane.entry, ScanLane.exit};
    }
    if (allowed.isEmpty) allowed = {ScanLane.entry, ScanLane.exit};
    return LaneConfig(
      allowed: allowed,
      fixedGate: (number == '1' || number == '2') ? 'Gate $number' : null,
      eventMode: event,
    );
  }

  /// The lane to use: the saved choice when the guard may switch, otherwise the only lane allowed.
  ScanLane resolve(ScanLane? saved) =>
      saved != null && allowed.contains(saved) ? saved : defaultLane;
}
