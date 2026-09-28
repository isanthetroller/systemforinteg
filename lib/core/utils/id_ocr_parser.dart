/// High-precision OCR Text Parser for Visitor Identification Cards.
///
/// Designed specifically for Philippine National IDs (PhilSys), Driver's Licenses (LTO),
/// NCST Student/Faculty IDs, UMID/SSS/GSIS Cards, PRC IDs, and Company/Visitor Badges.
///
/// Filters out administrative headers, agency titles, dates, addresses,
/// card numbers, and returns ONLY the sanitized, formatted full name of the ID owner.
class IdOcrParser {
  IdOcrParser._();

  /// Stop words that indicate headers, labels, government agencies, or card fields.
  /// If a line contains any of these, it is not a pure person name.
  static final Set<String> _blacklistedWords = {
    // Government / Agency Titles
    'REPUBLIC', 'REPUBLIKA', 'PHILIPPINES', 'PILIPINAS', 'DEPARTMENT', 'TRANSPORTATION',
    'LAND', 'OFFICE', 'LTO', 'LTFRB', 'COMMISSION', 'GOVERNMENT', 'NATIONAL', 'BUREAU',
    'INTERNAL', 'REVENUE', 'BIR', 'POSTAL', 'PHILPOST', 'ELECTION', 'COMELEC', 'SOCIAL',
    'SECURITY', 'SYSTEM', 'SSS', 'GSIS', 'PAGIBIG', 'PHILHEALTH', 'POLICE', 'PNP', 'NBI',
    'COLLEGE', 'SCIENCE', 'TECHNOLOGY', 'NCST', 'UNIVERSITY', 'SCHOOL', 'ACADEMY',
    'INSTITUTE', 'COMMISSIONER', 'REGULATION', 'PRC', 'ARMED', 'FORCES', 'AFP',

    // Card Types & Categories
    'DRIVER', 'DRIVERS', 'LICENSE', 'LICENCE', 'NONPROFESSIONAL', 'PROFESSIONAL',
    'STUDENT', 'FACULTY', 'EMPLOYEE', 'PASSPORT', 'IDENTIFICATION', 'PAGKAKAKILANLAN',
    'PAMBANSANG', 'IDENTITY', 'VISITOR', 'PASS', 'CARD', 'OFFICIAL', 'RECEIPT',
    'CERTIFICATE', 'REGISTRATION', 'PERMIT', 'SENIOR', 'CITIZEN', 'PWD', 'VOTER', 'VOTERS',
    'BARANGAY', 'CLEARANCE', 'RESIDENCE', 'POSTAL ID', 'TIN CARD', 'COMPANY ID',

    // Metadata Labels & Form Fields
    'LAST', 'FIRST', 'MIDDLE', 'SURNAME', 'GIVEN', 'NAMES', 'NAME', 'APELYIDO',
    'PANGALAN', 'GITNANG', 'DOB', 'BIRTH', 'BIRTHDATE', 'DATE', 'SEX', 'GENDER',
    'KASARIAN', 'NATIONALITY', 'CITIZENSHIP', 'BLOOD', 'TYPE', 'WEIGHT', 'HEIGHT',
    'EXPIRATION', 'EXPIRES', 'VALID', 'UNTIL', 'RESTRICTIONS', 'CONDITIONS', 'AGENCY',
    'SERIAL', 'NUMBER', 'NO', 'NUM', 'CRN', 'PCN', 'TIN', 'VIN', 'EMERGENCY',
    'CONTACT', 'SIGNATURE', 'HOLDER', 'BEARER', 'AUTHORISED', 'AUTHORIZED', 'OFFICER',
    'PLACE', 'CIVIL', 'STATUS', 'MARITAL', 'ORGAN', 'DONOR', 'RESTRICTION',

    // Geographic / Address Markers
    'ROAD', 'STREET', 'ST', 'RD', 'BRGY', 'CITY', 'PROVINCE', 'MUNICIPALITY',
    'CAVITE', 'MANILA', 'LAGUNA', 'BATANGAS', 'RIZAL', 'QUEZON', 'DASMARINAS',
    'DASMARIÑAS', 'IMUS', 'BACOOR', 'SILANG', 'GENERAL', 'TRIAS', 'TRECE', 'MARTIRES',
    'TAGAYTAY', 'SUBDIVISION', 'SUBD', 'VILLAGE', 'AVENUE', 'AVE', 'BLVD', 'BOULEVARD',
    'BLDG', 'BUILDING', 'FLOOR', 'PHASE', 'BLK', 'BLOCK', 'LOT', 'ZONE', 'DISTRICT',
    'POBLACION', 'REGION', 'POSTAL CODE', 'ZIP',

    // Common Noise
    'HTTP', 'HTTPS', 'WWW', 'COM', 'ORG', 'NET', 'GOV', 'PH', 'SCAN', 'PHOTO',
  };

  /// Common Filipino surnames and name particles to boost confidence.
  static final Set<String> _filipinoNameMarkers = {
    'DELA', 'DE', 'DEL', 'DELOS', 'SAN', 'SANTA', 'SANTO',
    'SANTOS', 'REYES', 'CRUZ', 'BAUTISTA', 'GARCIA', 'MENDOZA', 'TORRES', 'RAMOS',
    'FLORES', 'GONZALES', 'GONZALEZ', 'LOPEZ', 'HERNANDEZ', 'CASTILLO', 'AQUINO',
    'MORALES', 'TAN', 'LIM', 'SY', 'ONG', 'DAVID', 'RIVERA', 'VILLANUEVA', 'MERCADO',
    'NAVARRO', 'PEREZ', 'SALAZAR', 'CORPUZ', 'AGUILAR', 'PASCUAL', 'VALDEZ',
    'TOLENTINO', 'FERNANDEZ', 'OCAMPO', 'SORIANO', 'MANALO', 'ESPIRITU', 'CASTRO',
    'CORTEZ', 'SANTIAGO', 'DIAZ', 'ALVAREZ', 'ROMERO', 'ROBLES', 'GUERRERO',
    'ENRIQUEZ', 'DOMINGO', 'PINEDA', 'MARQUEZ', 'ROSARIO', 'PADILLA', 'DELEON',
    'LEON', 'VALENTIN', 'VILLAMOR', 'MALLARI', 'ESTRADA', 'DELFIN', 'MONTEVERDE',
    'MONARES', 'KRIZ', 'MARK', 'JOHN', 'JUAN', 'MARIA', 'JOSE', 'CARLOS', 'PAULO',
    'ANGELO', 'CHRISTIAN', 'MICHAEL', 'GABRIEL', 'ETHAN', 'JOSHUA', 'DANIEL',
  };

  /// Main extraction method: accepts a list of raw text lines or full OCR text,
  /// and returns strictly the parsed, capitalized full name of the ID holder.
  static String extractNameFromOcr(String fullText) {
    if (fullText.trim().isEmpty) return '';

    // Split text into individual lines and normalize
    final rawLines = fullText
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (rawLines.isEmpty) return '';

    // Strategy 1: Look for explicit labeled fields:
    // "Name: JUAN DELA CRUZ" or "Full Name: JUAN DELA CRUZ"
    final labeledName = _extractFromLabeledFields(rawLines);
    if (labeledName.isNotEmpty) {
      return _cleanAndFormatName(labeledName);
    }

    // Strategy 2: Look for Driver's License / PhilSys split fields:
    // "Last Name: SANTOS" + "Given Names: MARIA CLARA"
    final splitFieldName = _extractFromSplitFields(rawLines);
    if (splitFieldName.isNotEmpty) {
      return _cleanAndFormatName(splitFieldName);
    }

    // Strategy 3: Look for "LASTNAME, FIRSTNAME MIDDLENAME" format (standard on Philippine IDs)
    final commaFormatName = _extractCommaSeparatedName(rawLines);
    if (commaFormatName.isNotEmpty) {
      return _cleanAndFormatName(commaFormatName);
    }

    // Strategy 4: Score all candidate lines to find the most probable person name line
    final bestScoredName = _findBestCandidateLine(rawLines);
    if (bestScoredName.isNotEmpty) {
      return _cleanAndFormatName(bestScoredName);
    }

    return '';
  }

  /// Strategy 1: Look for lines with "Name:", "Full Name:", "Visitor Name:", "Student Name:"
  static String _extractFromLabeledFields(List<String> lines) {
    final labelRegex = RegExp(
      r'^(?:full\s*name|visitor(?:\s*name)?|student(?:\s*name)?|bearer|holder|name|pangalan)\s*[:=\-]\s*(.+)$',
      caseSensitive: false,
    );

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final match = labelRegex.firstMatch(line);
      if (match != null) {
        final candidate = match.group(1)?.trim() ?? '';
        if (_isValidNameCandidate(candidate)) {
          return candidate;
        }
      }

      // Check if line is just "NAME:" or "FULL NAME:" and the actual name is on the next line
      if (RegExp(r'^(?:full\s*name|visitor|student\s*name|name|pangalan)\s*[:=]?$', caseSensitive: false).hasMatch(line)) {
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          if (_isValidNameCandidate(nextLine)) {
            return nextLine;
          }
        }
      }
    }

    return '';
  }

  /// Strategy 2: Look for PhilSys / LTO separate field pairs:
  /// e.g. "Apelyido / Last Name" -> "DELA CRUZ"
  ///      "Mga Pangalan / Given Names" -> "JUAN PEDRO"
  static String _extractFromSplitFields(List<String> lines) {
    String lastName = '';
    String givenNames = '';
    String middleName = '';

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final upper = line.toUpperCase();

      // Check Middle Name first
      if (upper.contains('MIDDLE NAME') || upper.contains('GITNANG APELYIDO') || upper.contains('GITNANG')) {
        final afterColon = _getAfterColonOrNext(lines, i);
        if (afterColon.isNotEmpty && _isAlphaWord(afterColon)) {
          middleName = afterColon;
        }
      }
      // Check Given Names / First Name / Mga Pangalan
      else if (upper.contains('GIVEN') || upper.contains('FIRST NAME') || upper.contains('MGA PANGALAN')) {
        final afterColon = _getAfterColonOrNext(lines, i);
        if (afterColon.isNotEmpty && _isValidNameCandidate(afterColon)) {
          givenNames = afterColon;
        }
      }
      // Check Last Name / Apelyido (excluding Middle Name)
      else if (upper.contains('LAST NAME') || upper.contains('APELYIDO') || upper.contains('SURNAME')) {
        final afterColon = _getAfterColonOrNext(lines, i);
        if (afterColon.isNotEmpty && _isAlphaWord(afterColon)) {
          lastName = afterColon;
        }
      }
    }

    if (givenNames.isNotEmpty && lastName.isNotEmpty) {
      if (middleName.isNotEmpty) {
        return '$givenNames $middleName $lastName';
      }
      return '$givenNames $lastName';
    }

    return '';
  }

  static String _getAfterColonOrNext(List<String> lines, int index) {
    final line = lines[index];
    if (line.contains(':')) {
      final val = line.split(':').last.trim();
      if (val.isNotEmpty) return val;
    }
    if (index + 1 < lines.length) {
      return lines[index + 1].trim();
    }
    return '';
  }

  /// Strategy 3: Philippine ID standard: "DELA CRUZ, JUAN PEDRO" or "DELA CRUZ, JUAN P."
  static String _extractCommaSeparatedName(List<String> lines) {
    for (final line in lines) {
      if (!line.contains(',')) continue;

      // Ensure no blacklisted words
      if (_containsBlacklist(line)) continue;

      final parts = line.split(',');
      if (parts.length != 2) continue;

      final last = parts[0].trim();
      final first = parts[1].trim();

      if (_isAlphaWord(last) && _isValidNameCandidate(first)) {
        // Return in Natural order: "Juan Pedro Dela Cruz"
        return '$first $last';
      }
    }
    return '';
  }

  /// Strategy 4: Find the highest scoring candidate line in the OCR dump
  static String _findBestCandidateLine(List<String> lines) {
    String bestLine = '';
    int highestScore = -100;

    for (final line in lines) {
      final score = _scoreCandidateLine(line);
      if (score > highestScore && score >= 10) {
        highestScore = score;
        bestLine = line;
      }
    }

    return bestLine;
  }

  /// Evaluates and scores how likely a text line is to be a person's full name.
  static int _scoreCandidateLine(String rawLine) {
    final clean = rawLine.trim();

    // 1. Length check: Person names are usually between 5 and 35 chars
    if (clean.length < 4 || clean.length > 40) return -100;

    // 2. Reject if line contains any blacklisted word
    if (_containsBlacklist(clean)) return -100;

    // 3. Reject if contains numbers, URLs, dates, or symbols
    if (RegExp(r'[0-9@#\$\^&*_{}\[\]<>\/\\~`|\+=]').hasMatch(clean)) return -100;

    // 4. Split into words
    final words = clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 2 || words.length > 5) return -50;

    int score = 0;

    // Check each word
    bool allAlphabetic = true;
    for (final word in words) {
      final sanitized = word.replaceAll(RegExp(r"[\.,\-']"), '');
      if (sanitized.isEmpty || !RegExp(r'^[a-zA-Z]+$').hasMatch(sanitized)) {
        allAlphabetic = false;
        break;
      }
      if (sanitized.length == 1 && word.endsWith('.')) {
        // Middle initial like "M."
        score += 8;
      } else if (sanitized.length < 2) {
        allAlphabetic = false;
        break;
      }

      // Bonus if matches known Filipino names
      if (_filipinoNameMarkers.contains(sanitized.toUpperCase())) {
        score += 15;
      }
    }

    if (!allAlphabetic) return -100;

    // Having 2 to 4 valid words is ideal for full name
    score += (words.length * 6);

    // Uppercase formatting is typical for Philippine IDs
    if (clean == clean.toUpperCase()) {
      score += 5;
    }

    return score;
  }

  /// Helper: Check if line contains any blacklisted government/header term
  static bool _containsBlacklist(String line) {
    final upper = line.toUpperCase();
    for (final blacklisted in _blacklistedWords) {
      // Word boundary match
      final pattern = RegExp('\\b${RegExp.escape(blacklisted)}\\b');
      if (pattern.hasMatch(upper)) {
        return true;
      }
    }
    return false;
  }

  /// Helper: Validate if string is a valid alphabetic candidate
  static bool _isValidNameCandidate(String str) {
    final clean = str.trim();
    if (clean.length < 3 || clean.length > 40) return false;
    if (_containsBlacklist(clean)) return false;
    if (RegExp(r'[0-9@#\$\^&*_{}\[\]<>\/\\~`|\+=]').hasMatch(clean)) return false;

    final words = clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return words.isNotEmpty && words.every((w) {
      final stripped = w.replaceAll(RegExp(r"[\.,\-']"), '');
      return stripped.isNotEmpty && RegExp(r'^[a-zA-Z]+$').hasMatch(stripped);
    });
  }

  /// Helper: Check if a single token is strictly alphabetic letters
  static bool _isAlphaWord(String str) {
    final clean = str.trim().replaceAll(RegExp(r"[\.,\-']"), '');
    return clean.isNotEmpty && RegExp(r'^[a-zA-Z\s]+$').hasMatch(clean);
  }

  /// Extracts vehicle license plates from OCR text (supporting standard 3-letter,
  /// 2-letter, motorcycle, and conduction plate formats).
  static String extractPlateFromOcr(String fullText) {
    if (fullText.trim().isEmpty) return '';
    final clean = fullText.toUpperCase();

    // 1. Standard Car/SUV/Van/Truck plate: 3 letters + 3 or 4 digits (e.g. "NDK 4821", "ABC-1234", "ABC 123")
    final standardMatch = RegExp(r'\b([A-Z]{3})[\s\-]?(\d{3,4})\b').firstMatch(clean);
    if (standardMatch != null) {
      return '${standardMatch.group(1)}-${standardMatch.group(2)}';
    }

    // 2. Motorcycle plate: 2 letters + 4 or 5 digits (e.g. "NC 12345", "AB-1234") or 3/4 numbers + 2/3 letters
    final mcMatch1 = RegExp(r'\b([A-Z]{2})[\s\-]?(\d{4,5})\b').firstMatch(clean);
    if (mcMatch1 != null) {
      return '${mcMatch1.group(1)}-${mcMatch1.group(2)}';
    }
    final mcMatch2 = RegExp(r'\b(\d{3,4})[\s\-]?([A-Z]{2,3})\b').firstMatch(clean);
    if (mcMatch2 != null) {
      return '${mcMatch2.group(1)}-${mcMatch2.group(2)}';
    }

    // 3. 2-letter + 3/4 digits fallback (e.g. "NA 1234")
    final twoLetterMatch = RegExp(r'\b([A-Z]{2})[\s\-]?(\d{3,4})\b').firstMatch(clean);
    if (twoLetterMatch != null) {
      return '${twoLetterMatch.group(1)}-${twoLetterMatch.group(2)}';
    }

    return '';
  }

  /// Cleans punctuation and capitalizes properly in Title Case.

  /// Handles particles like "Dela", "Del", "San", etc. correctly.
  static String _cleanAndFormatName(String raw) {
    String clean = raw
        .replaceAll(RegExp(r'[:=]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (clean.isEmpty) return '';

    final words = clean.split(' ');
    final formattedWords = words.map((w) {
      if (w.isEmpty) return '';
      // Middle initial with dot (e.g. "M.")
      if (w.length <= 2 && w.endsWith('.')) {
        return '${w[0].toUpperCase()}.';
      }
      final lower = w.toLowerCase();
      // Handle particles like "de", "del", "dela" nicely or standard Title Case
      return w[0].toUpperCase() + (w.length > 1 ? lower.substring(1) : '');
    }).toList();

    return formattedWords.join(' ').trim();
  }
}
