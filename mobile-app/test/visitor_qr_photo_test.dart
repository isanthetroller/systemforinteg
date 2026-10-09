import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:systemforinteg/core/utils/photo_compress.dart';
import 'package:systemforinteg/core/widgets/qr_code_widget.dart';
import 'package:systemforinteg/core/widgets/vehicle_photo_panel.dart';
import 'package:systemforinteg/features/scanner/widgets/scanned_visitor_card.dart';
import 'package:systemforinteg/models/scanned_visitor_pass.dart';
import 'package:systemforinteg/models/visitor_pass_model.dart';

// A real 1x1 PNG
const String tinyPng =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

// What the server puts in a visitor pass QR (api/visitors.php qrPayload)
const String signedVisitorPayload =
    '{"v":1,"pid":"VP-20261008-RMVK","plate_number":"VIS7777","type":"visitor_temp","valid":"2026-10-08","sig":"00k3vCKgeZDL0MvbXSQU9g"}';

ScannedVisitorPass scanned({String? photo}) => ScannedVisitorPass(
      id: 1,
      passCode: 'VP-20261008-RMVK',
      visitorName: 'Vicky Visitor',
      plateNumber: 'VIS 7777',
      validDate: '2026-10-08',
      status: 'Active',
      result: 'VALID',
      accepted: true,
      currentlyInside: true,
      vehiclePhoto: photo,
    );

void main() {
  group('The visitor QR code is a real, scannable QR code', () {
    test('the server\'s signed payload fits a standard QR code, and is much bigger than the old 25x25 fake', () {
      final result = QrValidator.validate(data: signedVisitorPayload, version: QrVersions.auto, errorCorrectionLevel: QrErrorCorrectLevel.M);
      expect(result.status, QrValidationStatus.valid);
      final code = result.qrCode!;
      // The old widget always drew 25 x 25 cells from a hash; a real code for this text needs a higher version
      expect(code.moduleCount, greaterThan(25));
    });

    testWidgets('QrCodeWidget draws it with the real encoder', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: QrCodeWidget(data: signedVisitorPayload, size: 240)))));
      expect(find.byKey(const Key('realQrCode')), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(tester.widget<QrCodeWidget>(find.byType(QrCodeWidget)).data, signedVisitorPayload);
    });

    test('a pass created from the server answer shows the server\'s QR, not a locally invented one', () {
      final fromServer = VisitorPass.fromJson({
        'id': 16,
        'passCode': 'VP-20261008-RMVK',
        'visitorName': 'Vicky Visitor',
        'plateNumber': 'VIS7777',
        'status': 'Active',
        'qrPayload': signedVisitorPayload,
      });
      expect(fromServer.toQrPayload(), signedVisitorPayload);
    });
  });

  group('Visitor vehicle photo', () {
    test('toJson sends the photo as vehiclePhoto; the phone\'s cache never keeps it', () {
      final pass = VisitorPass(
        passId: 'VP-1',
        visitorName: 'Vicky',
        plateNumber: 'VIS 7777',
        entryTime: DateTime(2026, 10, 8, 8),
        expiryTime: DateTime(2026, 10, 8, 23, 59),
        registeredByGuard: 'Guard',
        gatePoint: 'Gate 1',
        vehiclePhotoUrl: tinyPng,
      );
      expect(pass.toJson()['vehiclePhoto'], tinyPng);
      expect(pass.toCacheJson()['vehiclePhoto'], isNull);
      expect(pass.toCacheJson()['vehiclePhotoUrl'], isNull);
    });

    test('an old placeholder asset path is not sent as a photo', () {
      final pass = VisitorPass(
        passId: 'VP-2',
        visitorName: 'Vicky',
        plateNumber: 'VIS 7777',
        entryTime: DateTime(2026, 10, 8, 8),
        expiryTime: DateTime(2026, 10, 8, 23, 59),
        registeredByGuard: 'Guard',
        gatePoint: 'Gate 1',
        vehiclePhotoUrl: 'assets/images/kriz_monares.jpg',
      );
      expect(pass.toJson()['vehiclePhoto'], isNull);
    });

    test('the scan answer carries the photo to the exit guard', () {
      final pass = ScannedVisitorPass.fromVerify({
        'result': 'VALID',
        'accepted': true,
        'currentlyInside': true,
        'visitor': {'id': 7, 'passCode': 'VP-1', 'visitorName': 'Vicky', 'plateNumber': 'VIS7777', 'validDate': '2026-10-08', 'status': 'Active', 'vehiclePhoto': tinyPng},
      });
      expect(pass!.vehiclePhoto, tinyPng);
      expect(ScannedVisitorPass.fromVerify({'visitor': {'id': 7, 'visitorName': 'V'}, 'result': 'VALID', 'accepted': true})!.vehiclePhoto, isNull);
    });

    testWidgets('the exit screen shows the vehicle photo, large and tappable, when the pass has one', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ScannedVisitorCard(pass: scanned(photo: tinyPng), checkedItems: const {}, onToggleItem: (_) {}, isExit: true)))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vehiclePhotoPanel')), findsOneWidget);
      expect(find.textContaining('compare it with the vehicle leaving'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vehiclePhotoPanel')));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget); // enlarged
    });

    testWidgets('no photo, no panel', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ScannedVisitorCard(pass: scanned(), checkedItems: const {}, onToggleItem: (_) {}, isExit: true)))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vehiclePhotoPanel')), findsNothing);
    });

    test('VehiclePhotoPanel.decode understands data URLs and bare base64, and ignores paths', () {
      expect(VehiclePhotoPanel.decode(tinyPng), isNotNull);
      expect(VehiclePhotoPanel.decode(tinyPng.split(',').last), isNotNull);
      expect(VehiclePhotoPanel.decode('assets/images/x.jpg'), isNull);
      expect(VehiclePhotoPanel.decode(''), isNull);
    });
  });

  group('PhotoCompress', () {
    test('a large camera photo is shrunk to a size the server accepts', () {
      final random = Random(7);
      final big = img.Image(width: 2400, height: 1800);
      for (final p in big) {
        p..r = random.nextInt(256)..g = random.nextInt(256)..b = random.nextInt(256);
      }
      final original = Uint8List.fromList(img.encodeJpg(big, quality: 95));
      expect(original.length, greaterThan(PhotoCompress.maxBytes)); // too big to send as it is

      final small = PhotoCompress.shrinkJpeg(original);
      expect(small, isNotNull);
      expect(small!.length, lessThanOrEqualTo(PhotoCompress.maxBytes));
      expect(img.decodeImage(small)!.width, lessThanOrEqualTo(1024));
      expect(PhotoCompress.toDataUrl(small), startsWith('data:image/jpeg;base64,'));
      expect(base64Decode(PhotoCompress.toDataUrl(small).split(',').last), small);
    });

    test('bytes that are not an image and are small pass through; huge garbage is refused', () {
      final tiny = Uint8List.fromList(List.filled(100, 1));
      expect(PhotoCompress.shrinkJpeg(tiny), tiny);
      expect(PhotoCompress.shrinkJpeg(Uint8List(PhotoCompress.maxBytes + 10)), isNull);
    });
  });
}
