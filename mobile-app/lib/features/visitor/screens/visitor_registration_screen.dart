import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../../core/utils/id_ocr_parser.dart';
import '../../../core/widgets/plate_badge.dart';
import '../../../models/user_model.dart';
import '../../../models/visitor_pass_model.dart';
import '../../../repositories/visitor_repository.dart';
import '../../../services/api_service.dart';
import '../../../theme/ncst_theme.dart';
import 'visitor_pass_confirmation_screen.dart';

enum CameraScanMode {
  idCard,
  licensePlate,
  vehiclePhoto,
}

class VisitorRegistrationScreen extends StatefulWidget {
  final GuardUser currentGuard;
  final VoidCallback? onReturnToDashboard;

  const VisitorRegistrationScreen({
    super.key,
    required this.currentGuard,
    this.onReturnToDashboard,
  });

  @override
  State<VisitorRegistrationScreen> createState() => _VisitorRegistrationScreenState();
}

class _VisitorRegistrationScreenState extends State<VisitorRegistrationScreen>
    with WidgetsBindingObserver {
  // Live Hardware Camera Controller & State
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _cameraHasError = false;
  bool _isTorchOn = false;
  CameraScanMode _activeScanMode = CameraScanMode.idCard;

  // On-Device OCR Text Recognizer
  late final TextRecognizer _textRecognizer;
  Timer? _autoOcrTimer;
  bool _isOcrBusy = false;

  // OCR Camera Stabilization State
  String? _candidateOcrText;
  DateTime? _candidateOcrStartTime;
  DateTime? _lastSeenOcrTime;
  double _ocrStabilizationProgress = 0.0;
  Timer? _ocrStabilizationTicker;
  bool _isOcrStabilizing = false;
  bool _isOcrLocked = false;
  final bool _ocrSteadyMode = true;
  String _ocrStatusPrompt = 'Align card/plate inside guide frame';
  final Duration _ocrStabilizationDuration = const Duration(milliseconds: 1000);

  // Scan Processing & Loading State
  bool _isScanningProcessing = false;
  String? _scanningProcessingMessage;

  // Checklist State & Data
  String _visitorName = '';
  String _contactNumber = '';
  String _licensePlate = '';
  String _selectedVehicleType = 'Sedan';
  String _vehicleModel = '';
  bool _hasCapturedPhoto = false;
  DateTime? _photoCaptureTime;

  // Form & Dock Controllers
  final _purposeController = TextEditingController();
  final _purposeFocusNode = FocusNode();
  final _nameEditController = TextEditingController();
  final _plateEditController = TextEditingController();
  final _contactEditController = TextEditingController();
  final List<Map<String, dynamic>> _declaredItems = [];

  bool _isGeneratingPass = false;

  final List<String> _vehicleTypes = const [
    'Sedan',
    'SUV',
    'Motorcycle',
    'Van',
    'Pickup',
    'Truck / Delivery',
  ];

  final List<String> _purposeQuickTags = const [
    'Official Business',
    'Registrar / Documents',
    'Admissions Office',
    'Cashier / Billing',
    'Campus Event',
    'Delivery / Service',
    'Parent / Guardian Visit',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _purposeFocusNode.addListener(() {
      setState(() {});
    });
    // Fetch live system settings (e.g. temporary QR pass expiration duration)
    ApiService.fetchSystemSettings().then((_) {
      if (mounted) setState(() {});
    });
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraHasError = true;
            _isCameraInitialized = false;
          });
        }
        return;
      }

      // Default to the rear / back camera
      _selectedCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (_selectedCameraIndex < 0) _selectedCameraIndex = 0;

      await _setupCameraController(_cameras[_selectedCameraIndex]);
    } catch (_) {
      if (mounted) {
        setState(() {
          _cameraHasError = true;
          _isCameraInitialized = false;
        });
      }
    }
  }

  Future<void> _setupCameraController(CameraDescription description) async {
    await _cameraController?.dispose();
    final controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _isCameraInitialized = true;
        _cameraHasError = false;
      });

      _startAutoOcrLoop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _cameraHasError = true;
          _isCameraInitialized = false;
        });
      }
    }
  }

  void _startAutoOcrLoop() {
    _autoOcrTimer?.cancel();
    _autoOcrTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (!mounted) return;
      if (_isScanningProcessing || _isOcrBusy || _isOcrLocked) return;
      if (_activeScanMode == CameraScanMode.vehiclePhoto) return;
      if (_cameraController == null || !_cameraController!.value.isInitialized) return;

      _runOcrOnCurrentFrame();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _autoOcrTimer?.cancel();
      _ocrStabilizationTicker?.cancel();
      _cameraController?.dispose();
      setState(() {
        _isCameraInitialized = false;
        _isOcrStabilizing = false;
        _candidateOcrText = null;
      });
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoOcrTimer?.cancel();
    _ocrStabilizationTicker?.cancel();
    _cameraController?.dispose();
    _textRecognizer.close();
    _purposeController.dispose();
    _purposeFocusNode.dispose();
    _nameEditController.dispose();
    _plateEditController.dispose();
    _contactEditController.dispose();
    super.dispose();
  }

  void _toggleTorch() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      if (_isTorchOn) {
        await _cameraController!.setFlashMode(FlashMode.off);
        setState(() => _isTorchOn = false);
      } else {
        await _cameraController!.setFlashMode(FlashMode.torch);
        setState(() => _isTorchOn = true);
      }
    } catch (_) {
      setState(() => _isTorchOn = !_isTorchOn);
    }
  }

  void _switchCamera() async {
    if (_cameras.length < 2) return;
    try {
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
      await _setupCameraController(_cameras[_selectedCameraIndex]);
    } catch (_) {}
  }

  // -------------------------------------------------------------
  // AUTOMATED OCR SCANNER DATA EXTRACTION
  // -------------------------------------------------------------
  Future<void> _runOcrOnCurrentFrame({bool isUserTriggered = false}) async {
    if (_isOcrBusy || _isScanningProcessing || _isOcrLocked) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    _isOcrBusy = true;
    XFile? capturedFile;
    try {
      capturedFile = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(capturedFile.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      final rawText = recognizedText.text.trim();
      if (rawText.isNotEmpty) {
        if (_activeScanMode == CameraScanMode.idCard) {
          // Extract strictly the person's name using IdOcrParser
          String name = IdOcrParser.extractNameFromOcr(rawText);
          if (name.isEmpty) {
            name = _extractNameFromIdPayload(rawText);
          }
          if (name.isNotEmpty && name != _visitorName) {
            _handleOcrCandidateDetected(name, isId: true, isUserTriggered: isUserTriggered);
            return;
          }
        } else if (_activeScanMode == CameraScanMode.licensePlate) {
          // Extract vehicle plate using IdOcrParser
          String plate = IdOcrParser.extractPlateFromOcr(rawText);
          if (plate.isEmpty) {
            plate = _extractPlateFromPayload(rawText);
          }
          if (plate.isNotEmpty && plate != _licensePlate) {
            _handleOcrCandidateDetected(plate, isId: false, isUserTriggered: isUserTriggered);
            return;
          }
        }
      }

      if (isUserTriggered && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: NcstColors.slate800,
            content: Text(
              _activeScanMode == CameraScanMode.idCard
                  ? 'No name detected on ID. Hold closer or enter manually.'
                  : 'No plate number detected. Position camera closer to plate.',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // Ignored during background auto-loop
    } finally {
      if (capturedFile != null) {
        try {
          final f = File(capturedFile.path);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }
      _isOcrBusy = false;
    }
  }

  void _handleOcrCandidateDetected(String detectedText, {required bool isId, bool isUserTriggered = false}) {
    if (_isOcrLocked || _isScanningProcessing) return;

    if (!_ocrSteadyMode || isUserTriggered) {
      _isOcrLocked = true;
      if (isId) {
        _processIdScan(detectedText);
      } else {
        _processPlateScan(detectedText);
      }
      return;
    }

    final now = DateTime.now();
    if (_candidateOcrText != detectedText) {
      _candidateOcrText = detectedText;
      _candidateOcrStartTime = now;
      _lastSeenOcrTime = now;
      _ocrStabilizationProgress = 0.0;
      _isOcrStabilizing = true;
      _ocrStatusPrompt = 'HOLD CAMERA STEADY... PLEASE STABILIZE';
      _startOcrStabilizationTimer(isId: isId);
      if (mounted) setState(() {});
    } else {
      _lastSeenOcrTime = now;
    }
  }

  void _startOcrStabilizationTimer({required bool isId}) {
    _ocrStabilizationTicker?.cancel();
    final targetMs = _ocrStabilizationDuration.inMilliseconds;
    const intervalMs = 35;

    _ocrStabilizationTicker = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_candidateOcrText == null || _candidateOcrStartTime == null || _lastSeenOcrTime == null) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      // Check if camera moved away (no matching text frame for > 1400ms)
      if (now.difference(_lastSeenOcrTime!).inMilliseconds > 1400) {
        timer.cancel();
        setState(() {
          _candidateOcrText = null;
          _candidateOcrStartTime = null;
          _isOcrStabilizing = false;
          _ocrStabilizationProgress = 0.0;
          _ocrStatusPrompt = 'Camera moved • Please stabilize camera on ${isId ? "ID" : "Plate"}';
        });
        return;
      }

      final elapsedMs = now.difference(_candidateOcrStartTime!).inMilliseconds;
      final progress = (elapsedMs / targetMs).clamp(0.0, 1.0);

      if (progress >= 1.0) {
        timer.cancel();
        final capturedText = _candidateOcrText!;
        setState(() {
          _ocrStabilizationProgress = 1.0;
          _isOcrStabilizing = false;
          _isOcrLocked = true;
          _ocrStatusPrompt = '✓ CAMERA STABILIZED • CAPTURING';
        });

        Future.delayed(const Duration(milliseconds: 140), () {
          if (!mounted) return;
          if (isId) {
            _processIdScan(capturedText);
          } else {
            _processPlateScan(capturedText);
          }
        });
      } else {
        setState(() {
          _ocrStabilizationProgress = progress;
          _ocrStatusPrompt = 'Hold camera steady... ${(progress * 100).toInt()}%';
        });
      }
    });
  }

  Future<void> _processIdScan(String extractedName) async {
    if (_isScanningProcessing) return;
    if (extractedName.trim().isEmpty) return;

    setState(() {
      _isScanningProcessing = true;
      _scanningProcessingMessage = 'Processing Scanned ID...';
    });

    // Loading animation so the guard sees the scan was received and processed
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    setState(() {
      _visitorName = extractedName;
      _isScanningProcessing = false;
      _scanningProcessingMessage = null;
      _candidateOcrText = null;
      _candidateOcrStartTime = null;
      _lastSeenOcrTime = null;
      _isOcrStabilizing = false;
      _isOcrLocked = false;
      _ocrStabilizationProgress = 0.0;
      _ocrStatusPrompt = 'Align card/plate inside guide frame';
      // Auto-advance checklist to vehicle license plate scan!
      _activeScanMode = CameraScanMode.licensePlate;
    });

    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: NcstColors.green,
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'ID Scanned: $extractedName',
                style: const TextStyle(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _extractNameFromIdPayload(String raw) {
    String clean = raw.trim();

    // 1. JSON Payload Check
    if (clean.startsWith('{') && clean.endsWith('}')) {
      try {
        final decoded = jsonDecode(clean);
        if (decoded is Map<String, dynamic>) {
          for (final key in ['fullName', 'name', 'visitorName', 'subject', 'owner', 'ownerName', 'driverName']) {
            if (decoded[key] != null && decoded[key].toString().trim().isNotEmpty) {
              return _formatToTitleCase(decoded[key].toString().trim());
            }
          }
        }
      } catch (_) {}
    }

    // 2. vCard Format (FN:Full Name or N:Last;First)
    if (clean.contains('FN:')) {
      final match = RegExp(r'FN:(.*?)(?:\r?\n|$)', caseSensitive: false).firstMatch(clean);
      if (match != null && match.group(1) != null && match.group(1)!.trim().isNotEmpty) {
        return _formatToTitleCase(match.group(1)!.trim());
      }
    }
    if (clean.contains('N:')) {
      final match = RegExp(r'N:([^;]+);([^;\r\n]+)', caseSensitive: false).firstMatch(clean);
      if (match != null) {
        final last = match.group(1)?.trim() ?? '';
        final first = match.group(2)?.trim() ?? '';
        if (first.isNotEmpty || last.isNotEmpty) {
          return _formatToTitleCase('$first $last'.trim());
        }
      }
    }

    // 3. AAMVA / Driver License Barcode standard (DAC = First, DCS = Last)
    final dacMatch = RegExp(r'DAC([A-Z\s]+)', caseSensitive: false).firstMatch(clean);
    final dcsMatch = RegExp(r'DCS([A-Z\s]+)', caseSensitive: false).firstMatch(clean);
    if (dacMatch != null || dcsMatch != null) {
      final first = dacMatch?.group(1)?.trim() ?? '';
      final last = dcsMatch?.group(1)?.trim() ?? '';
      if (first.isNotEmpty || last.isNotEmpty) {
        return _formatToTitleCase('$first $last'.trim());
      }
    }

    // 4. Key-Value patterns: "Name: Juan Dela Cruz" or "name=Juan+Dela+Cruz"
    final kvMatch = RegExp(r'(?:name|full_name|visitor)\s*[:=]\s*([^,\n\r&]+)', caseSensitive: false).firstMatch(clean);
    if (kvMatch != null && kvMatch.group(1) != null) {
      return _formatToTitleCase(Uri.decodeComponent(kvMatch.group(1)!.trim()));
    }

    return '';
  }

  Future<void> _processPlateScan(String extractedPlate) async {
    if (_isScanningProcessing) return;
    if (extractedPlate.trim().isEmpty) return;

    setState(() {
      _isScanningProcessing = true;
      _scanningProcessingMessage = 'Processing License Plate...';
    });

    // Loading animation so the guard sees the plate scan was received and processed
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    setState(() {
      _licensePlate = extractedPlate;
      _isScanningProcessing = false;
      _scanningProcessingMessage = null;
      _candidateOcrText = null;
      _candidateOcrStartTime = null;
      _lastSeenOcrTime = null;
      _isOcrStabilizing = false;
      _isOcrLocked = false;
      _ocrStabilizationProgress = 0.0;
      _ocrStatusPrompt = 'Align card/plate inside guide frame';
      // Auto-advance checklist to security photo if photo not yet taken
      if (!_hasCapturedPhoto) {
        _activeScanMode = CameraScanMode.vehiclePhoto;
      }
    });

    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: NcstColors.green,
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'License Plate Scanned: $extractedPlate',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _extractPlateFromPayload(String raw) {
    final clean = raw.trim().toUpperCase();

    // Check for standard Philippine plate pattern: ABC-1234 or ABC 1234 or ABC1234
    final plateMatch = RegExp(r'([A-Z]{2,3})[\s\-]?(\d{3,4})').firstMatch(clean);
    if (plateMatch != null) {
      return '${plateMatch.group(1)}-${plateMatch.group(2)}';
    }

    // Fallback alphanumeric
    final alphanumeric = clean.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (alphanumeric.length >= 4 && alphanumeric.length <= 8) {
      return alphanumeric;
    }

    return clean;
  }

  String _formatToTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + (word.length > 1 ? word.substring(1).toLowerCase() : '');
    }).join(' ');
  }

  Future<void> _snapVehiclePhoto() async {
    try {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        await _cameraController!.takePicture();
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _hasCapturedPhoto = true;
      _photoCaptureTime = DateTime.now();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: NcstColors.navy,
        content: Row(
          children: [
            Icon(Icons.camera_alt, color: NcstColors.gold, size: 18),
            SizedBox(width: 8),
            Text('Front vehicle security photo captured & verified.', style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // If purpose is still empty, focus the Messenger-style dock immediately!
    if (_purposeController.text.trim().isEmpty) {
      _purposeFocusNode.requestFocus();
    }
  }

  void _retakePhoto() {
    setState(() {
      _hasCapturedPhoto = false;
      _photoCaptureTime = null;
      _activeScanMode = CameraScanMode.vehiclePhoto;
    });
  }

  // -------------------------------------------------------------
  // MANUAL EDIT DIALOGS (FALLBACK IF OCR FAILS)
  // -------------------------------------------------------------
  void _showManualNameDialog() {
    _nameEditController.text = _visitorName;
    _contactEditController.text = _contactNumber;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Visitor Identity Details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameEditController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Visitor Full Name *',
                hintText: 'e.g. Juan Dela Cruz',
                prefixIcon: Icon(Icons.person, color: NcstColors.navy),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contactEditController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Contact Mobile Number',
                hintText: 'e.g. 0917-123-4567',
                prefixIcon: Icon(Icons.phone_android, color: NcstColors.navy),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _visitorName = _nameEditController.text.trim();
                _contactNumber = _contactEditController.text.trim();
              });
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: NcstColors.navy, foregroundColor: Colors.white),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  void _showManualPlateDialog() {
    _plateEditController.text = _licensePlate;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vehicle Plate Number', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _plateEditController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'License Plate *',
                hintText: 'e.g. ABC 1234 or NDK 4821',
                prefixIcon: Icon(Icons.directions_car, color: NcstColors.navy),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _licensePlate = _plateEditController.text.trim().toUpperCase();
              });
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: NcstColors.navy, foregroundColor: Colors.white),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  void _showAddItemDialog() {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('Declare Items Brought In', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_declaredItems.isNotEmpty) ...[
                  const Text('Currently Declared Items:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: NcstColors.slate600)),
                  const SizedBox(height: 6),
                  ..._declaredItems.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final it = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: NcstColors.slate50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: NcstColors.slate200),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${it['name']} x${it['quantity']}${it['description'] != null && (it['description'] as String).isNotEmpty ? " (${it['description']})" : ""}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16, color: NcstColors.crimson),
                            onPressed: () {
                              setState(() {
                                _declaredItems.removeAt(idx);
                              });
                              setDlgState(() {});
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 16),
                ],
                const Text('Add New Item:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: NcstColors.navy)),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Item Name *',
                    hintText: 'e.g. Event Chairs, Projector',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Qty *',
                          hintText: '1',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: descCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Notes (Optional)',
                          hintText: 'e.g. 50 plastic chairs',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('DONE'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
                final desc = descCtrl.text.trim();
                if (name.isNotEmpty) {
                  setState(() {
                    _declaredItems.add({
                      'name': name,
                      'quantity': qty > 0 ? qty : 1,
                      'description': desc.isNotEmpty ? desc : null,
                    });
                  });
                  nameCtrl.clear();
                  qtyCtrl.text = '1';
                  descCtrl.clear();
                  setDlgState(() {});
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: NcstColors.navy,
                foregroundColor: Colors.white,
              ),
              child: const Text('+ ADD ITEM'),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // REGISTRATION & TEMPORARY PASS GENERATION
  // -------------------------------------------------------------
  bool get _isChecklistReady {
    return _visitorName.trim().isNotEmpty &&
        _licensePlate.trim().isNotEmpty &&
        _purposeController.text.trim().isNotEmpty;
  }

  /// A new pass code such as VP-20260929-K7M2QX. It is made on the phone (so it works with no connection) and is
  /// unique enough for that: 32^6 combinations per day, in the same style as the codes the server makes.
  static String _newPassCode(DateTime now) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final suffix = List.generate(6, (_) => alphabet[random.nextInt(alphabet.length)]).join();
    final date = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'VP-$date-$suffix';
  }

  Future<void> _completeRegistration() async {
    final visitorName = _visitorName.trim();
    final plateNumber = _licensePlate.trim().toUpperCase();
    final purposeOfVisit = _purposeController.text.trim();
    final contactNumber = _contactNumber.trim().isNotEmpty ? _contactNumber.trim() : '0917-000-0000';
    final vehicleModel = _vehicleModel.trim().isNotEmpty
        ? '$_selectedVehicleType ($_vehicleModel)'
        : _selectedVehicleType;

    if (visitorName.isEmpty || plateNumber.isEmpty || purposeOfVisit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: NcstColors.crimson,
          content: Text('Please complete the checklist: ID Name, License Plate, and Purpose of Visit.'),
        ),
      );
      return;
    }

    setState(() {
      _isGeneratingPass = true;
    });

    final now = DateTime.now();
    final passId = _newPassCode(now);
    // A day pass is valid all day on the day it is issued (until midnight): no hour limit
    final validUntil = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final newPass = VisitorPass(
      passId: passId,
      visitorName: visitorName,
      contactNumber: contactNumber,
      vehicleModel: vehicleModel,
      purposeOfVisit: purposeOfVisit,
      personToVisit: purposeOfVisit.contains('-') ? purposeOfVisit.split('-').last.trim() : 'Campus Host',
      plateNumber: plateNumber,
      vehiclePhotoUrl: _hasCapturedPhoto ? 'assets/images/kriz_monares.jpg' : null,
      entryTime: now,
      expiryTime: validUntil,
      status: VisitorPassStatus.active,
      registeredByGuard: widget.currentGuard.fullName,
      gatePoint: widget.currentGuard.assignedGate,
      notes: 'Visitor Entry Registered via Gate Terminal Checklist',
      items: List.from(_declaredItems),
    );

    // With a connection the server records the pass now; without one it is saved on this phone and syncs later.
    // Only a pass the server refuses (registered vehicle, duplicate pass) is not issued.
    final VisitorPass registeredPass;
    try {
      registeredPass = await VisitorRepository().registerPass(newPass);
    } on VisitorPassNotIssued catch (e) {
      if (mounted) {
        setState(() {
          _isGeneratingPass = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: NcstColors.crimson,
            duration: const Duration(seconds: 6),
            content: Text('Visitor pass NOT issued: ${e.message}'),
          ),
        );
      }
      return;
    }

    if (ApiService.lastWriteQueued && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: NcstColors.navy,
          duration: Duration(seconds: 7),
          content: Text('No connection: the pass is saved on this phone and will reach the server automatically when the connection returns.'),
        ),
      );
    }

    final itemsNote = _declaredItems.isNotEmpty
        ? ' | Items declared: ${_declaredItems.map((e) => "${e['name']} x${e['quantity']}").join(', ')}'
        : '';

    // Post to gate audit logs
    await ApiService.postGateLog(
      plateNumber: registeredPass.plateNumber,
      driverName: registeredPass.visitorName,
      driverRelationship: 'Visitor / Guest Driver',
      gatePoint: widget.currentGuard.assignedGate,
      action: 'Entry Recorded',
      status: 'Inside Campus',
      guardName: widget.currentGuard.fullName,
      notes: 'Temporary pass ${registeredPass.passId} generated at gate (valid all day today)$itemsNote',
      vehicleType: registeredPass.vehicleModel ?? 'Visitor Vehicle',
      ownerName: registeredPass.visitorName,
      visitorPassId: registeredPass.dbId,
      itemsVerified: registeredPass.items.isNotEmpty,
    );

    if (mounted) {
      setState(() {
        _isGeneratingPass = false;
      });

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VisitorPassConfirmationScreen(
            pass: registeredPass,
            onFinish: () {
              Navigator.of(context).pop();
              if (widget.onReturnToDashboard != null) {
                widget.onReturnToDashboard!();
              } else {
                setState(() {
                  _visitorName = '';
                  _contactNumber = '';
                  _licensePlate = '';
                  _vehicleModel = '';
                  _hasCapturedPhoto = false;
                  _photoCaptureTime = null;
                  _declaredItems.clear();
                  _purposeController.clear();
                  _activeScanMode = CameraScanMode.idCard;
                });
              }
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NcstColors.slate50,
      appBar: AppBar(
        backgroundColor: NcstColors.navy,
        foregroundColor: NcstColors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NcstColors.gold.withValues(alpha: 0.5), width: 1.5),
              ),
              child: const Center(
                child: Icon(Icons.shield_outlined, color: NcstColors.gold, size: 18),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'VISITOR REGISTRATION',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'SecurePark Clearance • Gate ${widget.currentGuard.assignedGate}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: NcstColors.goldLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Toggle Flashlight',
            icon: Icon(
              _isTorchOn ? Icons.flash_on : Icons.flash_off,
              color: _isTorchOn ? NcstColors.gold : Colors.white70,
              size: 20,
            ),
            onPressed: _toggleTorch,
          ),
          IconButton(
            tooltip: 'Switch Camera',
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white70, size: 19),
            onPressed: _switchCamera,
          ),
          if (widget.onReturnToDashboard != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: widget.onReturnToDashboard,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Header Overview Banner
                        _buildHeaderSummaryBanner(),
                        const SizedBox(height: 14),

                        // 2. Camera Viewfinder Card with Mode Switcher
                        _buildCameraSection(),
                        const SizedBox(height: 14),

                        // 3. Structured Form Sections (Visitor, Vehicle, Purpose)
                        _buildFormSections(),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 4. Primary Registration & Pass Issuance Bottom Dock
            _buildBottomActionDock(),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // HEADER OVERVIEW BANNER
  // -------------------------------------------------------------
  Widget _buildHeaderSummaryBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: NcstColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NcstColors.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: NcstColors.navy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.badge_outlined, color: NcstColors.navy, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Temporary Day Pass Issuance',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: NcstColors.slate900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Scan ID and license plate to generate an encrypted QR gate pass.',
                  style: TextStyle(fontSize: 11, color: NcstColors.slate500, height: 1.25),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isChecklistReady ? NcstColors.greenLight : NcstColors.slate100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isChecklistReady ? NcstColors.green.withValues(alpha: 0.4) : NcstColors.slate200,
              ),
            ),
            child: Text(
              _isChecklistReady ? 'READY' : 'REQUIRED',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: _isChecklistReady ? NcstColors.green : NcstColors.slate500,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // CAMERA SCANNER SECTION
  // -------------------------------------------------------------
  Widget _buildCameraSection() {
    return Container(
      decoration: BoxDecoration(
        color: NcstColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NcstColors.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Segmented Scan Mode Selector
          Row(
            children: [
              _buildModeTab('ID Card', CameraScanMode.idCard, Icons.badge_outlined),
              const SizedBox(width: 8),
              _buildModeTab('License Plate', CameraScanMode.licensePlate, Icons.directions_car_outlined),
              const SizedBox(width: 8),
              _buildModeTab('Photo', CameraScanMode.vehiclePhoto, Icons.camera_alt_outlined),
            ],
          ),
          const SizedBox(height: 12),

          // Live Camera Stream Container
          Container(
            height: 195,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isOcrLocked
                    ? NcstColors.green
                    : (_isOcrStabilizing
                        ? const Color(0xFF38BDF8)
                        : (_activeScanMode == CameraScanMode.idCard
                            ? (_visitorName.isNotEmpty ? NcstColors.green : NcstColors.navy)
                            : (_activeScanMode == CameraScanMode.licensePlate
                                ? (_licensePlate.isNotEmpty ? NcstColors.green : NcstColors.navy)
                                : (_hasCapturedPhoto ? NcstColors.green : NcstColors.navy)))),
                width: 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Live Hardware Camera Feed
                if (!_cameraHasError && _isCameraInitialized && _cameraController != null && _cameraController!.value.isInitialized)
                  ClipRect(
                    child: SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _cameraController!.value.previewSize?.height ?? 720,
                          height: _cameraController!.value.previewSize?.width ?? 1280,
                          child: CameraPreview(_cameraController!),
                        ),
                      ),
                    ),
                  )
                else
                  _buildCameraFallback(),

                // Mode Overlays
                if (_activeScanMode == CameraScanMode.idCard) ...[
                  Container(
                    width: 220,
                    height: 135,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _isOcrLocked
                            ? NcstColors.green
                            : (_isOcrStabilizing ? const Color(0xFF38BDF8) : (_visitorName.isNotEmpty ? NcstColors.green : NcstColors.gold)),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ] else if (_activeScanMode == CameraScanMode.licensePlate) ...[
                  Container(
                    width: 240,
                    height: 75,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _isOcrLocked
                            ? NcstColors.green
                            : (_isOcrStabilizing ? const Color(0xFF38BDF8) : (_licensePlate.isNotEmpty ? NcstColors.green : NcstColors.gold)),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ] else ...[
                  if (_hasCapturedPhoto) ...[
                    Container(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle_rounded, color: NcstColors.green, size: 44),
                            const SizedBox(height: 6),
                            const Text(
                              'SECURITY SNAPSHOT RECORDED',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                            ),
                            if (_licensePlate.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('PLATE: $_licensePlate', style: const TextStyle(color: NcstColors.gold, fontWeight: FontWeight.w800, fontSize: 12)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    Container(
                      width: 190,
                      height: 120,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white70, width: 1.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ],

                // Top HUD Banner
                if (_activeScanMode != CameraScanMode.vehiclePhoto)
                  Positioned(
                    top: 8,
                    left: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _isOcrLocked
                            ? NcstColors.green.withValues(alpha: 0.92)
                            : (_isOcrStabilizing
                                ? const Color(0xFF0369A1).withValues(alpha: 0.92)
                                : Colors.black.withValues(alpha: 0.65)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isOcrStabilizing) ...[
                            const SizedBox(
                              width: 11,
                              height: 11,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ] else if (_isOcrLocked) ...[
                            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 13),
                            const SizedBox(width: 5),
                          ] else ...[
                            const Icon(Icons.center_focus_strong, color: Colors.white70, size: 12),
                            const SizedBox(width: 5),
                          ],
                          Flexible(
                            child: Text(
                              _ocrStatusPrompt,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Bottom Progress Bar
                if (_isOcrStabilizing)
                  Positioned(
                    bottom: 8,
                    left: 20,
                    right: 20,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _ocrStabilizationProgress,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                        minHeight: 4,
                      ),
                    ),
                  ),

                // Processing Indicator
                if (_isScanningProcessing)
                  Container(
                    color: Colors.black.withValues(alpha: 0.82),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(NcstColors.gold),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _scanningProcessingMessage ?? 'Processing Frame...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Camera Action Controls
          if (_activeScanMode == CameraScanMode.vehiclePhoto) ...[
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _hasCapturedPhoto ? _retakePhoto : _snapVehiclePhoto,
                icon: Icon(_hasCapturedPhoto ? Icons.refresh : Icons.camera_alt, size: 18),
                label: Text(
                  _hasCapturedPhoto ? 'RETAKE VEHICLE PHOTO' : 'SNAP VEHICLE PHOTO',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.4),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _hasCapturedPhoto ? NcstColors.slate700 : NcstColors.navy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ] else if (_activeScanMode == CameraScanMode.idCard) ...[
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _isScanningProcessing ? null : () => _runOcrOnCurrentFrame(isUserTriggered: true),
                      icon: const Icon(Icons.document_scanner_rounded, size: 18),
                      label: const Text('SNAP & SCAN ID', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NcstColors.navy,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _showManualNameDialog,
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text('MANUAL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NcstColors.navy,
                      side: const BorderSide(color: NcstColors.navy),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _isScanningProcessing ? null : () => _runOcrOnCurrentFrame(isUserTriggered: true),
                      icon: const Icon(Icons.crop_free_rounded, size: 18),
                      label: const Text('SNAP & SCAN PLATE', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NcstColors.navy,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _showManualPlateDialog,
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text('MANUAL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NcstColors.navy,
                      side: const BorderSide(color: NcstColors.navy),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeTab(String label, CameraScanMode mode, IconData icon) {
    final isSelected = _activeScanMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _activeScanMode = mode;
            _ocrStabilizationTicker?.cancel();
            _isOcrStabilizing = false;
            _isOcrLocked = false;
            _candidateOcrText = null;
            _candidateOcrStartTime = null;
            _lastSeenOcrTime = null;
            _ocrStabilizationProgress = 0.0;
            _ocrStatusPrompt = 'Align card/plate inside guide frame';
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? NcstColors.navy : NcstColors.slate100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: isSelected ? Colors.white : NcstColors.slate700),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? Colors.white : NcstColors.slate700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraFallback() {
    return Container(
      color: const Color(0xFF0F172A),
      child: const Center(
        child: Icon(Icons.videocam_off_outlined, color: Colors.white38, size: 36),
      ),
    );
  }

  // -------------------------------------------------------------
  // STRUCTURED FORM SECTIONS (Grouped by Category)
  // -------------------------------------------------------------
  Widget _buildFormSections() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // GROUP 1: VISITOR INFORMATION
        _buildSectionCard(
          title: 'VISITOR INFORMATION',
          icon: Icons.person_outline_rounded,
          children: [
            _buildFieldTile(
              label: 'Full Name',
              value: _visitorName.isNotEmpty ? _visitorName : 'Awaiting ID scan or manual input',
              isSet: _visitorName.isNotEmpty,
              isRequired: true,
              onTap: () {
                setState(() => _activeScanMode = CameraScanMode.idCard);
                _showManualNameDialog();
              },
            ),
            const SizedBox(height: 8),
            _buildFieldTile(
              label: 'Contact Number',
              value: _contactNumber.isNotEmpty ? _contactNumber : 'Optional (e.g. 0917-123-4567)',
              isSet: _contactNumber.isNotEmpty,
              isRequired: false,
              onTap: _showManualNameDialog,
            ),
          ],
        ),
        const SizedBox(height: 14),

        // GROUP 2: VEHICLE DETAILS
        _buildSectionCard(
          title: 'VEHICLE DETAILS',
          icon: Icons.directions_car_outlined,
          children: [
            _buildFieldTile(
              label: 'License Plate',
              value: _licensePlate.isNotEmpty ? _licensePlate : 'Awaiting plate scan or manual input',
              isSet: _licensePlate.isNotEmpty,
              isRequired: true,
              customWidget: _licensePlate.isNotEmpty ? PlateBadge(plateNumber: _licensePlate) : null,
              onTap: () {
                setState(() => _activeScanMode = CameraScanMode.licensePlate);
                _showManualPlateDialog();
              },
            ),
            const SizedBox(height: 10),

            // Vehicle Type Selector Chips
            const Text(
              'Vehicle Classification',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NcstColors.slate600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _vehicleTypes.map((type) {
                final isSelected = _selectedVehicleType == type;
                return ChoiceChip(
                  label: Text(
                    type,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: NcstColors.navy,
                  labelStyle: TextStyle(color: isSelected ? Colors.white : NcstColors.slate700),
                  backgroundColor: NcstColors.slate100,
                  side: BorderSide(color: isSelected ? NcstColors.navy : NcstColors.slate200),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onSelected: (val) {
                    if (val) setState(() => _selectedVehicleType = type);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),

            // Front Vehicle Photo Status
            _buildFieldTile(
              label: 'Front Security Photo',
              value: _hasCapturedPhoto
                  ? 'Snapshot captured at ${_photoCaptureTime != null ? "${_photoCaptureTime!.hour.toString().padLeft(2, '0')}:${_photoCaptureTime!.minute.toString().padLeft(2, '0')}" : "Gate"}'
                  : 'Tap to take front vehicle photo with camera',
              isSet: _hasCapturedPhoto,
              isRequired: false,
              onTap: () {
                setState(() => _activeScanMode = CameraScanMode.vehiclePhoto);
              },
            ),
          ],
        ),
        const SizedBox(height: 14),

        // GROUP 3: VISIT PURPOSE & CLEARANCE
        _buildSectionCard(
          title: 'PURPOSE & CLEARANCE',
          icon: Icons.assignment_outlined,
          children: [
            const Text(
              'Quick Destination / Department',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NcstColors.slate600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _purposeQuickTags.map((tag) {
                final isSelected = _purposeController.text.contains(tag);
                return ActionChip(
                  label: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? Colors.white : NcstColors.navy,
                    ),
                  ),
                  backgroundColor: isSelected ? NcstColors.navy : NcstColors.slate100,
                  side: BorderSide(
                    color: isSelected ? NcstColors.navy : NcstColors.slate200,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onPressed: () {
                    setState(() {
                      _purposeController.text = tag;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),

            // Purpose Text Input
            TextField(
              controller: _purposeController,
              focusNode: _purposeFocusNode,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Purpose of Visit & Host Destination *',
                hintText: 'e.g. Registrar document inquiry',
                hintStyle: const TextStyle(fontSize: 12, color: NcstColors.slate400),
                prefixIcon: const Icon(Icons.chat_bubble_outline_rounded, color: NcstColors.navy, size: 18),
                filled: true,
                fillColor: NcstColors.slate50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: NcstColors.slate200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: NcstColors.slate200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: NcstColors.navy, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 10),

            // Declared Items Brought In
            _buildFieldTile(
              label: 'Declared Items Brought In',
              value: _declaredItems.isNotEmpty
                  ? '${_declaredItems.length} item(s) declared: ${_declaredItems.map((e) => "${e['name']} x${e['quantity']}").join(', ')}'
                  : 'No equipment or chairs declared (tap to declare items)',
              isSet: _declaredItems.isNotEmpty,
              isRequired: false,
              onTap: _showAddItemDialog,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: NcstColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NcstColors.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: NcstColors.navy),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  color: NcstColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildFieldTile({
    required String label,
    required String value,
    required bool isSet,
    required bool isRequired,
    required VoidCallback onTap,
    Widget? customWidget,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSet ? NcstColors.greenLight.withValues(alpha: 0.25) : NcstColors.slate50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSet ? NcstColors.green.withValues(alpha: 0.35) : NcstColors.slate200,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: NcstColors.slate700,
                        ),
                      ),
                      if (isRequired)
                        const Text(
                          ' *',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: NcstColors.crimson,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (customWidget != null) ...[
                    customWidget,
                  ] else ...[
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSet ? FontWeight.w700 : FontWeight.w400,
                        color: isSet ? NcstColors.slate900 : NcstColors.slate400,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: NcstColors.slate100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                isSet ? Icons.edit_outlined : Icons.chevron_right_rounded,
                size: 16,
                color: NcstColors.slate600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // PRIMARY ACTION BOTTOM DOCK
  // -------------------------------------------------------------
  Widget _buildBottomActionDock() {
    final ready = _isChecklistReady;
    final List<String> missing = [];
    if (_visitorName.trim().isEmpty) missing.add('Visitor Name');
    if (_licensePlate.trim().isEmpty) missing.add('License Plate');
    if (_purposeController.text.trim().isEmpty) missing.add('Purpose');

    return Container(
      decoration: BoxDecoration(
        color: NcstColors.white,
        border: const Border(top: BorderSide(color: NcstColors.slate200, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            offset: const Offset(0, -3),
            blurRadius: 8,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!ready)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.info_outline, size: 14, color: NcstColors.slate500),
                  const SizedBox(width: 5),
                  Text(
                    'Missing: ${missing.join(', ')}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: NcstColors.slate500,
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: (_isGeneratingPass || !ready) ? null : _completeRegistration,
              icon: _isGeneratingPass
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.qr_code_rounded, size: 20),
              label: Text(
                ready ? 'ISSUE VISITOR QR PASS' : 'COMPLETE REQUIRED FIELDS',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: ready ? NcstColors.navy : NcstColors.slate300,
                foregroundColor: Colors.white,
                disabledBackgroundColor: NcstColors.slate200,
                disabledForegroundColor: NcstColors.slate400,
                elevation: ready ? 1 : 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
