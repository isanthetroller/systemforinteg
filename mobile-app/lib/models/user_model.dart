/// Guard roles in the NCST SecurePark gate security ecosystem
enum GuardRole {
  entrance, // Guard 1 — Entrance workflow
  exit,     // Guard 2 — Exit workflow
}

/// Active security guard session profile
class GuardUser {
  final String id;
  final String username;
  final String fullName;
  final String badgeNumber;
  final GuardRole role;
  final String assignedGate;
  final DateTime loginTime;

  /// True while the account still has a temporary password the guard must replace before using the terminal.
  final bool mustChangePassword;

  const GuardUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.badgeNumber,
    required this.role,
    required this.assignedGate,
    required this.loginTime,
    this.mustChangePassword = false,
  });

  bool get isEntranceGuard => role == GuardRole.entrance;
  bool get isExitGuard => role == GuardRole.exit;

  String get roleDisplayName => 'Security Guard — IN / OUT';
  String get gateDisplayName => assignedGate;

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'fullName': fullName,
    'badgeNumber': badgeNumber,
    'role': role.name,
    'assignedGate': assignedGate,
    'loginTime': loginTime.toIso8601String(),
  };

  factory GuardUser.fromJson(Map<String, dynamic> json) {
    final roleRaw = (json['role'] ?? '').toString().toLowerCase();
    final gateRaw = (json['gateAssigned'] ?? json['gate_assigned'] ?? json['assignedGate'] ?? '').toString().toLowerCase();
    final usernameRaw = (json['username'] ?? '').toString().toLowerCase();

    final isExit = gateRaw.contains('egress') ||
        gateRaw.contains('exit') ||
        gateRaw.contains('2') ||
        roleRaw.contains('exit') ||
        usernameRaw.contains('guard2') ||
        usernameRaw.contains('exit');

    final role = isExit ? GuardRole.exit : GuardRole.entrance;
    final defaultGate = isExit ? 'Gate 2 (Main Egress)' : 'Gate 1 (Main Ingress)';
    final assignedGateStr = (json['gateAssigned'] ?? json['gate_assigned'] ?? json['assignedGate'])?.toString().trim();

    return GuardUser(
      id: json['id']?.toString() ?? (isExit ? 'GRD-EXIT-02' : 'GRD-ENTRANCE-01'),
      username: json['username']?.toString() ?? (isExit ? 'guard2' : 'guard1'),
      fullName: json['fullName']?.toString() ?? json['full_name']?.toString() ?? (isExit ? 'Officer R. Mendoza' : 'Officer J. Hernandez'),
      badgeNumber: json['badgeNumber']?.toString() ?? json['badge_number']?.toString() ?? (isExit ? 'NCST-SEC-02' : 'NCST-SEC-01'),
      role: role,
      assignedGate: (assignedGateStr != null && assignedGateStr.isNotEmpty) ? assignedGateStr : defaultGate,
      loginTime: json['loginTime'] != null
          ? DateTime.tryParse(json['loginTime'].toString()) ?? DateTime.now()
          : DateTime.now(),
      mustChangePassword: json['mustChangePassword'] == true,
    );
  }
}
