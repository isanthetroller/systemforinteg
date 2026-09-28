import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systemforinteg/features/scanner/screens/qr_scanner_screen.dart';
import 'package:systemforinteg/main.dart';

void main() {
  testWidgets('NCST Gate Security App renders Login screen by default', (WidgetTester tester) async {
    // 1. Launch App
    await tester.pumpWidget(const NcstGateSecurityApp());
    await tester.pump();

    // 2. Verify Login Screen elements
    expect(find.text('NCST SECUREPARK'), findsOneWidget);
    expect(find.text('Gate Security Terminal'), findsOneWidget);
    expect(find.text('Guard 1 (Entrance)'), findsOneWidget);
    expect(find.text('Guard 2 (Exit)'), findsOneWidget);
    expect(find.text('SIGN IN TO GATE TERMINAL'), findsOneWidget);
  });

  testWidgets('QrScannerScreen renders clean viewfinder and verifies scanned pass', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrScannerScreen(
          onDecision: (_) {},
        ),
      ),
    );
    await tester.pump();

    // 1. Verify Camera Viewfinder elements
    expect(find.text('Scan Driver QR Pass'), findsOneWidget);
    expect(find.text('CAMERA AUTO-SCAN ACTIVE'), findsOneWidget);
    expect(find.text('Enter QR Manually'), findsWidgets);

    // 2. Open Manual QR Entry to simulate pass scan
    final manualBtn = find.text('Enter QR Manually').first;
    await tester.tap(manualBtn);
    await tester.pump();

    expect(find.text('Enter QR Pass / Plate Number'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      '{"ownerFullName":"Prof. Roberto D. Reyes","plateNumber":"ABC-1234","authorizedDrivers":[{"fullName":"Maria Elena Reyes","relationship":"Spouse","licenseNo":"N01-18-094821"}]}',
    );
    await tester.tap(find.text('Verify QR Pass'));
    await tester.pump();

    // 3. Verify Scanned Verification elements
    expect(find.text('Scanned Verification'), findsOneWidget);
    expect(find.text('SCANNED QR PASS VERIFIED'), findsOneWidget);
    expect(find.text('REGISTERED VEHICLE OWNER'), findsOneWidget);
    expect(find.text('AUTHORIZED DRIVERS (IF NOT OWNER)'), findsOneWidget);
    expect(find.text('BLOCKED'), findsOneWidget);
    expect(find.text('CLEARED (TO GO)'), findsOneWidget);
  });

  testWidgets('Login as Guard 1 routes to Entrance Dashboard and navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const NcstGateSecurityApp());
    await tester.pump();

    // 1. Initial State: On Login Screen
    expect(find.text('SIGN IN TO GATE TERMINAL'), findsOneWidget);

    // 2. Tap Sign In (default is guard1 / password123)
    await tester.tap(find.text('SIGN IN TO GATE TERMINAL'));
    await tester.pumpAndSettle();

    // 3. Should arrive at Guard 1 Entrance Dashboard
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Scan / Entry'), findsOneWidget);
    expect(find.text('Visitor'), findsOneWidget);
    expect(find.text('AUDIT LOG'), findsOneWidget);
  });

  testWidgets('Login as Guard 2 routes to Exit Dashboard and navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const NcstGateSecurityApp());
    await tester.pump();

    // 1. Switch to Guard 2 Demo Role
    await tester.tap(find.text('Guard 2 (Exit)'));
    await tester.pump();

    // 2. Tap Sign In
    await tester.tap(find.text('SIGN IN TO GATE TERMINAL'));
    await tester.pumpAndSettle();

    // 3. Should arrive at Guard 2 Exit Dashboard
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Scan / Exit'), findsOneWidget);
    expect(find.text('Active Passes'), findsOneWidget);
  });
}
