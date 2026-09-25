import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systemforinteg/features/scanner/screens/qr_scanner_screen.dart';
import 'package:systemforinteg/main.dart';

void main() {
  testWidgets('NCST Gate Security App renders Dashboard with scan bar and clean zero state', (WidgetTester tester) async {
    // 1. Launch Dashboard
    await tester.pumpWidget(const NcstGateSecurityApp());
    await tester.pump();

    // 2. Verify Dashboard elements
    expect(find.text('Gate Security Terminal'), findsOneWidget);
    expect(find.text('AUDIT LOG'), findsOneWidget);
    expect(find.text('INSIDE CAMPUS'), findsOneWidget);
    expect(find.text('TOTAL ENTRIES'), findsOneWidget);
    expect(find.text('SCAN QR PASS'), findsOneWidget);
    // Audit log should start in a clean zero-state without fake initial logs
    expect(find.text('No entries found for this filter.'), findsOneWidget);
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

  testWidgets('Bottom bar switch to 2nd page, scans phone QR, and clears vehicle into entry log', (WidgetTester tester) async {
    await tester.pumpWidget(const NcstGateSecurityApp());
    await tester.pump();

    // 1. Initial State: On Dashboard
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('AUDIT LOG'), findsOneWidget);

    // 2. Click SCAN QR PASS on the bottom bar
    final bottomScanBtn = find.widgetWithText(ElevatedButton, 'SCAN QR PASS');
    expect(bottomScanBtn, findsOneWidget);
    await tester.tap(bottomScanBtn);
    await tester.pump();
    await tester.pump();

    // 3. Verify 2nd Page (Camera Scanner) is active
    expect(find.text('Scan Driver QR Pass'), findsOneWidget);

    // 4. Enter QR pass manually to simulate driver presenting phone
    final manualBtn = find.text('Enter QR Manually').first;
    await tester.tap(manualBtn);
    await tester.pump();

    await tester.enterText(
      find.byType(TextField),
      '{"ownerFullName":"Prof. Roberto D. Reyes","plateNumber":"ABC-1234","authorizedDrivers":[{"fullName":"Maria Elena Reyes","relationship":"Spouse","licenseNo":"N01-18-094821"}]}',
    );
    await tester.tap(find.text('Verify QR Pass'));
    await tester.pump();

    // 5. Verify Verification Details Card
    expect(find.text('SCANNED QR PASS VERIFIED'), findsOneWidget);
    expect(find.text('CLEARED (TO GO)'), findsOneWidget);

    // 6. Tap CLEARED (TO GO)
    await tester.tap(find.text('CLEARED (TO GO)'));
    await tester.pump(const Duration(milliseconds: 200));

    // 7. Should automatically return to Dashboard & show new entry in Audit Log
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('AUDIT LOG'), findsOneWidget);
    expect(find.textContaining('ENTRY CLEARED'), findsOneWidget);

    // 8. Verify NO exit or departed terms appear
    expect(find.text('Exit'), findsNothing);
    expect(find.text('Log Exit'), findsNothing);
    expect(find.text('Departed'), findsNothing);
  });

  testWidgets('Can test QR scanning via manual input dialog and unknown visitor pass', (WidgetTester tester) async {
    await tester.pumpWidget(const NcstGateSecurityApp());
    await tester.pump();

    // 1. Go to QR Scanner page
    await tester.tap(find.widgetWithText(ElevatedButton, 'SCAN QR PASS'));
    await tester.pump();
    await tester.pump();

    // 2. Tap "Enter QR Manually" button from AppBar
    final manualBtn = find.byTooltip('Enter QR Manually');
    expect(manualBtn, findsOneWidget);
    await tester.tap(manualBtn);
    await tester.pump();

    // 3. Enter custom QR payload in dialog
    expect(find.text('Enter QR Pass / Plate Number'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'NCST-QR-NCY8821');
    await tester.tap(find.text('Verify QR Pass'));
    await tester.pump();

    // 4. Verify vehicle pass details and CLEARED button
    expect(find.text('NCY-8821'), findsWidgets);
    expect(find.text('CLEARED (TO GO)'), findsOneWidget);
  });
}
