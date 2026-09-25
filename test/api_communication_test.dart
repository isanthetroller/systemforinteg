import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:systemforinteg/core/constants/api_constants.dart';
import 'package:systemforinteg/models/vehicle_model.dart';
import 'package:systemforinteg/services/api_service.dart';

void main() {
  late HttpServer mockServer;
  late int mockPort;

  setUpAll(() async {
    // Spin up a mock HTTP server mimicking InfinityFree PHP endpoints
    mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mockPort = mockServer.port;
    ApiConstants.baseUrl = 'http://${InternetAddress.loopbackIPv4.host}:$mockPort/api';

    mockServer.listen((HttpRequest request) async {
      final path = request.uri.path;
      final method = request.method;

      // Enable CORS headers as configured on InfinityFree .htaccess
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.headers.set('Content-Type', 'application/json');

      if (method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }

      // 1. GET /api/vehicles.php
      if (path == '/api/vehicles.php' && method == 'GET') {
        final plate = request.uri.queryParameters['plate'];
        if (plate == 'NDK-4821') {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode({
            'status': 'success',
            'data': {
              'id': 'veh-1001',
              'plate_number': 'NDK-4821',
              'vehicle_type': 'Sedan',
              'make_model_color': 'White Toyota Vios',
              'owner_name': 'Prof. Juan Dela Cruz',
              'owner_role': 'Faculty - CCS',
              'owner_id_number': 'NCST-FAC-2024',
              'sticker_year': '2026',
              'owner_photo_url': 'http://server.example.com/photos/owner.jpg',
              'vehicle_photo_url': 'uploads/vehicles/vios.jpg',
              'qr_pass_code': 'NCST-QR-NDK4821',
              'status': 'Active',
              'authorized_drivers': [
                {
                  'id': 'drv-1',
                  'full_name': 'Maria Dela Cruz',
                  'relationship': 'Spouse',
                  'license_no': 'N01-20-112233',
                  'photo_url': 'http://server.example.com/photos/maria.jpg',
                },
                {
                  'id': 'drv-2',
                  'full_name': 'Mark Dela Cruz',
                  'relationship': 'Son (Student)',
                  'license_no': 'N02-23-445566',
                  'photo_url': 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
                }
              ]
            }
          }));
        } else {
          // Return list of vehicles
          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode({
            'status': 'success',
            'count': 1,
            'data': [
              {
                'id': 'veh-1001',
                'plate_number': 'NDK-4821',
                'vehicle_type': 'Sedan',
                'make_model_color': 'White Toyota Vios',
                'owner_name': 'Prof. Juan Dela Cruz',
                'owner_role': 'Faculty - CCS',
                'owner_id_number': 'NCST-FAC-2024',
                'sticker_year': '2026',
                'owner_photo_url': 'http://server.example.com/photos/owner.jpg',
                'vehicle_photo_url': 'uploads/vehicles/vios.jpg',
                'qr_pass_code': 'NCST-QR-NDK4821',
                'status': 'Active',
                'authorized_drivers': []
              }
            ]
          }));
        }
        await request.response.close();
        return;
      }

      // 2. POST /api/logs.php
      if (path == '/api/logs.php' && method == 'POST') {
        final content = await utf8.decoder.bind(request).join();
        final body = jsonDecode(content);
        expect(body['plateNumber'], equals('NDK-4821'));
        expect(body['status'], equals('Inside Campus'));

        request.response.statusCode = HttpStatus.created;
        request.response.write(jsonEncode({
          'status': 'success',
          'message': 'Gate log recorded successfully',
          'log_id': 'log-9999'
        }));
        await request.response.close();
        return;
      }

      // 3. POST /api/incidents.php
      if (path == '/api/incidents.php' && method == 'POST') {
        final content = await utf8.decoder.bind(request).join();
        final body = jsonDecode(content);
        expect(body['plateNumber'], equals('NDK-4821'));
        expect(body['reason'], equals('Unregistered Pass'));

        request.response.statusCode = HttpStatus.created;
        request.response.write(jsonEncode({
          'status': 'success',
          'message': 'Security incident recorded',
          'case_number': 'INC-2026-001'
        }));
        await request.response.close();
        return;
      }

      // 4. GET /photos/test_driver.jpg
      if (path == '/photos/test_driver.jpg' && method == 'GET') {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType('image', 'jpeg');
        request.response.add([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]);
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await mockServer.close();
  });

  group('Automated Web Server <-> Mobile App Communication Tests', () {
    test('Mobile App can fetch vehicle details and authorized drivers from backend', () async {
      final vehicle = await ApiService.lookupVehicleByPlate('NDK-4821');

      expect(vehicle, isNotNull);
      expect(vehicle!.plateNumber, equals('NDK-4821'));
      expect(vehicle.ownerName, equals('Prof. Juan Dela Cruz'));
      expect(vehicle.ownerIdNumber, equals('NCST-FAC-2024'));
      expect(vehicle.stickerYear, equals('2026'));
      expect(vehicle.vehicleType, equals('Sedan'));
      expect(vehicle.ownerPhotoUrl, equals('http://server.example.com/photos/owner.jpg'));

      // Authorized drivers parsing
      expect(vehicle.authorizedDrivers.length, equals(2));
      final maria = vehicle.authorizedDrivers[0];
      expect(maria.fullName, equals('Maria Dela Cruz'));
      expect(maria.relationship, equals('Spouse'));
      expect(maria.licenseNo, equals('N01-20-112233'));
      expect(maria.photoUrl, equals('http://server.example.com/photos/maria.jpg'));

      final mark = vehicle.authorizedDrivers[1];
      expect(mark.fullName, equals('Mark Dela Cruz'));
      expect(mark.photoUrl, startsWith('data:image/png;base64,'));
    });

    test('Mobile App can fetch full vehicle catalog from backend', () async {
      final list = await ApiService.fetchVehicles();
      expect(list, isNotEmpty);
      expect(list.first.plateNumber, equals('NDK-4821'));
    });

    test('Mobile App can post real-time gate passage log to backend', () async {
      final success = await ApiService.postGateLog(
        plateNumber: 'NDK-4821',
        driverName: 'Maria Dela Cruz',
        driverRelationship: 'Spouse',
        gatePoint: 'Gate 1 (Main Ingress)',
        action: 'Entry Recorded',
        status: 'Inside Campus',
        vehicleType: 'Sedan',
        ownerName: 'Prof. Juan Dela Cruz',
      );

      expect(success, isTrue);
    });

    test('Mobile App can report a security incident block to backend', () async {
      final success = await ApiService.reportIncident(
        plateNumber: 'NDK-4821',
        driverName: 'Unknown Driver',
        reason: 'Unregistered Pass',
        gatePoint: 'Gate 1 (Main Ingress)',
      );

      expect(success, isTrue);
    });

    test('Mobile App image resolution handles relative server paths, full URLs and data URIs', () {
      // 1. Relative server path
      final relUrl = ApiConstants.resolveImageUrl('uploads/drivers/driver1.jpg');
      expect(relUrl, equals('http://${InternetAddress.loopbackIPv4.host}:$mockPort/uploads/drivers/driver1.jpg'));

      // 2. Full HTTP URL
      final fullUrl = ApiConstants.resolveImageUrl('https://images.unsplash.com/sample.jpg');
      expect(fullUrl, equals('https://images.unsplash.com/sample.jpg'));

      // 3. Base64 Data URI
      final dataUri = ApiConstants.resolveImageUrl('data:image/jpeg;base64,/9j/4AAQSkZJRg==');
      expect(dataUri, equals('data:image/jpeg;base64,/9j/4AAQSkZJRg=='));

      // 4. Asset URI
      final assetUri = ApiConstants.resolveImageUrl('assets/images/kriz_monares.jpg');
      expect(assetUri, equals('assets/images/kriz_monares.jpg'));
    });

    test('ApiService can fetch image bytes and provides image headers', () async {
      final headers = ApiService.imageHeaders;
      expect(headers['Accept'], contains('image/'));
      expect(headers['User-Agent'], isNotEmpty);

      final imgUrl = 'http://${InternetAddress.loopbackIPv4.host}:$mockPort/photos/test_driver.jpg';
      final bytes = await ApiService.fetchImageBytes(imgUrl);
      expect(bytes, isNotNull);
      expect(bytes!.length, equals(8));
      expect(bytes[0], equals(0xFF));
      expect(bytes[1], equals(0xD8));
    });

    test('VehicleRecord inherits owner photo for owner driver when driver photo is omitted', () {
      final json = {
        'plateNumber': 'XYZ-999',
        'ownerName': 'Prof. Test Owner',
        'ownerPhoto': 'data:image/jpeg;base64,12345',
        'authorizedDrivers': [
          {
            'fullName': 'Prof. Test Owner',
            'relationship': 'Self (Owner)',
            'licenseNo': 'N01-00-000000',
          }
        ]
      };
      final record = VehicleRecord.fromQrJson(json);
      expect(record.ownerPhotoUrl, equals('data:image/jpeg;base64,12345'));
      expect(record.authorizedDrivers.first.photoUrl, equals('data:image/jpeg;base64,12345'));
    });
  });
}
