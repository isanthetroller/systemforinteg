# NCST SecurePark — Mobile Gate Security Terminal (Flutter)

## Latest synchronization update

See [October 9 mobile update](../docs/mobile-realtime-update-2026-10-09.md) for authenticated five-second
polling, session revocation, live visitor cards, verification results and compatible backend setup.
The tested update passes automated checks; physical phone/camera and deployment MySQL validation remain outstanding.

A specialized cross-platform mobile application engineered for National College of Science and Technology (NCST) gate security officers. Built on Flutter 3 / Material Design 3, the terminal provides rapid QR gate pass scanning, optical verification against campus databases, multi-driver authorization checks, and immediate synchronization with the campus backend.

---

## 🚀 Key Features

- **High-Performance QR Scanning**: Integrated with `mobile_scanner: ^7.4.2` for zero-latency camera viewfinder scanning, auto-focus, and torch control.
- **Visual Identity & Verification**:
  - Displays registered owner and designated authorized drivers (family, spouse, student).
  - High-resolution driver photo view with base64, network URL, and asset decoding.
  - Sticker validation year badge and vehicle make/model/color identification.
- **InfinityFree Challenge Solver**:
  - Built-in AES decryption engine solving InfinityFree anti-bot JavaScript challenges (`slowAES.decrypt`) automatically on live endpoints.
- **Offline / Standalone Resilience**:
  - Robust mock dataset and offline fallbacks when Wi-Fi or cellular networks drop.
  - Gate passages, visitor checkouts and incident reports made offline are queued with the time they happened and sent to
    `/api/sync.php` as soon as the connection is back (checked every 5 seconds and when the app returns to the foreground).
    A resend never duplicates a log, and a refused event never blocks the ones behind it (it is kept for review).
  - Visitor passes can be issued offline: the pass and its QR work on this phone straight away and sync to the server later,
    keeping the same pass code. A pass the server refuses (a registered vehicle's plate, or a duplicate pass for the day) is
    only refused while online; the guard sees the reason.
  - A refused entry (banned, unregistered) is not kept in the phone's audit list; the guard sees "NOT RECORDED" with the
    server's reason.
- **Sign-in**: there are no demo accounts and nothing is pre-filled; a guard signs in with the account an administrator
  created in the web portal (Staff Accounts).
- **First sign-in**: a guard whose account has a temporary password (set by an administrator) is asked to choose their own
  before using the terminal.
- **Visitor pass validity**: a day pass is valid all day on its date (until midnight). A visitor still on campus after
  midnight is let out at the exit gate, with a note for the guard.
  - Dynamically synthesizes unverified guest passes for unregistered visitor vehicles.
- **Audit Logging**:
  - Instantly logs entries and exits (time, guard officer, lane direction, vehicle metadata) to live MySQL database.
  - Incident reporting modal with customizable hold reasons.

---

## 📂 Architecture & Directory Structure

```
mobile-app/
├── android/                   # Native Android configuration (Manifest, Gradle, Proguard)
├── ios/                       # Native iOS configuration (Runner, Info.plist, Podfile)
├── assets/
│   └── images/                # Static assets & test driver photographs
├── test/                      # Unit, widget, and API communication test suite
├── lib/
│   ├── main.dart              # Application entrypoint & theme initialization
│   ├── theme/
│   │   └── ncst_theme.dart    # NCST Collegiate theme (Navy, Gold, Crimson, Green, Slate)
│   ├── models/
│   │   └── vehicle_model.dart # VehicleRecord, AuthorizedDriver, AuditLogEntry, GateStatus
│   ├── services/
│   │   ├── api_service.dart   # HTTP client, InfinityFree challenge solver, image caching
│   │   └── vehicle_lookup_service.dart # QR payload parser & multi-criteria lookup
│   ├── repositories/
│   │   └── gate_repository.dart # Abstracted gate data repository
│   ├── data/
│   │   └── mock_data.dart     # Test environment fixtures & fallback datasets
│   ├── core/
│   │   ├── constants/         # API endpoints & application metadata
│   │   ├── utils/             # Date/time formatters
│   │   └── widgets/           # DriverPhotoView, PlateBadge, StatusBadge
│   └── features/
│       ├── dashboard/         # Dashboard screen, KPI statistics, real-time audit logs
│       └── scanner/           # QR scanner viewfinder, driver switch cards, decision actions
├── analysis_options.yaml      # Dart static analysis configuration
├── pubspec.yaml               # Project dependencies and asset declarations
└── pubspec.lock               # Exact package dependency lockfile
```

---

## 🛠️ Requirements & Setup

### Prerequisites
- **Flutter SDK**: `^3.13.3` or later (tested on Flutter 3.27+)
- **Dart SDK**: `^3.1.0` or later
- **Android Studio / VS Code** with Flutter & Dart extensions
- **Android SDK**: API level 21 (Android 5.0 Lollipop) minimum; Target SDK 34 (Android 14)

### Getting Started

1. **Navigate to the directory**:
   ```bash
   cd mobile-app
   ```

2. **Install Flutter dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run static analysis**:
   ```bash
   flutter analyze
   ```

4. **Execute test suite**:
   ```bash
   flutter test
   ```

5. **Run on connected device or emulator**:
   ```bash
   flutter run
   ```

---

## 🌐 API Configuration

API endpoints are configured in `lib/core/constants/api_constants.dart`:

```dart
class ApiConstants {
  // Live InfinityFree Endpoint or Local IP
  static String baseUrl = 'https://securepark.site.je/api';
  
  static const String vehiclesEndpoint = '/vehicles.php';
  static const String logsEndpoint     = '/logs.php';
  static const String statsEndpoint    = '/stats.php';
  static const String incidentsEndpoint = '/incidents.php';
}
```

To test against a local backend server during development, update `baseUrl` to your machine's LAN IP (e.g., `http://192.168.1.100/api` or `http://10.0.2.2/api` for Android Emulator).

---

## 📦 Building Production Release

### Build Android APK
```bash
flutter build apk --release
```
The output APK will be located at:
`build/app/outputs/flutter-apk/app-release.apk`

### Build Android App Bundle (AAB for Google Play)
```bash
flutter build appbundle --release
```

---

## 🎨 Official Brand Identity (NCST Theme)

| Color Name | Hex Code | Purpose |
| :--- | :--- | :--- |
| **Academic Navy** | `#1A3B8B` | Primary app bars, active tabs, header branding |
| **Navy Dark** | `#0F265C` | Deep container backgrounds, contrast accents |
| **Academic Gold** | `#F5B800` | Secondary accents, sticker year tags, warnings |
| **Academic Crimson**| `#D92128` | Blocked alerts, hold incident actions, error pips |
| **Academic Green**  | `#16A34A` | Verified pass indicators, ingress badges |
| **Slate Neutrals**  | `#F8FAFC` - `#0F172A` | Backgrounds, surface cards, divider borders |
