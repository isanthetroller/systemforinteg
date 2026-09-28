import 'package:flutter_test/flutter_test.dart';
import 'package:systemforinteg/core/utils/id_ocr_parser.dart';

void main() {
  group('IdOcrParser Tests', () {
    test('Philippine Driver License text dump extracts only name', () {
      const ocrText = '''
REPUBLIC OF THE PHILIPPINES
DEPARTMENT OF TRANSPORTATION
LAND TRANSPORTATION OFFICE
DRIVER'S LICENSE
DELA CRUZ, JUAN PEDRO
SEX: M   BLOOD TYPE: O+
DATE OF BIRTH: 1992/08/15
WEIGHT: 68 kg   HEIGHT: 172 cm
ADDRESS: BRGY SAN JOSE, DASMARINAS CITY, CAVITE
LICENSE NO: N01-14-123456
EXPIRATION DATE: 2028/08/15
AGENCY CODE: N01
SIGNATURE OF LICENSEE
''';
      final name = IdOcrParser.extractNameFromOcr(ocrText);
      expect(name, equals('Juan Pedro Dela Cruz'));
    });

    test('PhilSys National ID text dump with split fields', () {
      const ocrText = '''
REPUBLIKA NG PILIPINAS
PAMBANSANG PAGKAKAKILANLAN
PHILIPPINE IDENTIFICATION SYSTEM
Apelyido / Last Name:
SANTOS
Mga Pangalan / Given Names:
MARIA CLARA
Gitnang Apelyido / Middle Name:
REYES
Kasarian / Sex: Babae / Female
Petsa ng Kapanganakan / Date of Birth: 1995/10/24
Tirahan / Address: BLK 4 LOT 12 PALIPARAN 3 DASMARINAS CAVITE
PhilSys Card Number: 1234-5678-9012-3456
''';
      final name = IdOcrParser.extractNameFromOcr(ocrText);
      expect(name, equals('Maria Clara Reyes Santos'));
    });

    test('NCST Student ID text dump', () {
      const ocrText = '''
NATIONAL COLLEGE OF SCIENCE AND TECHNOLOGY
EMILIANO TRIA TIRONA HIGHWAY DASMARINAS CITY CAVITE
STUDENT IDENTIFICATION CARD
NAME: KRIZ MONARES
STUDENT NO: 2022-108234
COURSE: BS INFORMATION TECHNOLOGY
VALID UNTIL: MARCH 2027
EMERGENCY CONTACT: 0917-123-4567
''';
      final name = IdOcrParser.extractNameFromOcr(ocrText);
      expect(name, equals('Kriz Monares'));
    });

    test('UMID Card dump with name label', () {
      const ocrText = '''
SOCIAL SECURITY SYSTEM
UNIFIED MULTI-PURPOSE ID
CRN-0033-8742918-4
Full Name: MARK ANTHONY BAUTISTA
Date of Birth: 1988-04-12
Address: IMUS CAVITE
''';
      final name = IdOcrParser.extractNameFromOcr(ocrText);
      expect(name, equals('Mark Anthony Bautista'));
    });

    test('Noisy raw OCR with only uppercase name line and no labels', () {
      const ocrText = '''
VISITOR PASS
SECURITY CLEARANCE
ETHAN GABRIEL SANTOS
GATE 1 ENTRY ONLY
EXPIRES 10:00 PM
''';
      final name = IdOcrParser.extractNameFromOcr(ocrText);
      expect(name, equals('Ethan Gabriel Santos'));
    });

    test('Returns empty when no valid name is present', () {
      const ocrText = '''
REPUBLIC OF THE PHILIPPINES
LAND TRANSPORTATION OFFICE
DATE: 2024-01-01
EXPIRATION: 2029-01-01
''';
      final name = IdOcrParser.extractNameFromOcr(ocrText);
      expect(name, isEmpty);
    });

    test('Extracts standard Philippine car plates from OCR', () {
      expect(IdOcrParser.extractPlateFromOcr('PILIPINAS NDK 4821 MATATAG NA REPUBLIKA'), equals('NDK-4821'));
      expect(IdOcrParser.extractPlateFromOcr('ABC-1234'), equals('ABC-1234'));
      expect(IdOcrParser.extractPlateFromOcr('WXY 789 REGION 4A'), equals('WXY-789'));
    });

    test('Extracts motorcycle plates from OCR', () {
      expect(IdOcrParser.extractPlateFromOcr('NC 12345'), equals('NC-12345'));
      expect(IdOcrParser.extractPlateFromOcr('123 ABC'), equals('123-ABC'));
    });
  });
}
