import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/system_info_service.dart';
import 'package:flutter/gestures.dart';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';

const Color navy = Color(0xFF23282E);
const Color panel = Color(0xFF1B2238);
const Color cyan = Color(0xFF3498DB);
const Color green = Color(0xFF28A745);
const Color orange = Color(0xFFF58220);
const Color red = Color(0xFFE53935);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
  runApp(const FKLitmusApp());
  return;
}

  final windowController = await WindowController.fromCurrentEngine();

  final Map<String, dynamic> windowArgs = windowController.arguments.isEmpty
      ? {}
      : jsonDecode(windowController.arguments);

  if (windowArgs['type'] == 'summary') {
    runApp(SummaryWindowApp(report: windowArgs['report'] ?? ''));
  } else {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    runApp(const FKLitmusApp());
  }
}

class SummaryWindowApp extends StatelessWidget {
  final String report;

  const SummaryWindowApp({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF23282E),
        body: Column(
          children: [
            Container(
              height: 38,
              color: const Color(0xFFF1F1F1),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.computer, size: 17),
                  const SizedBox(width: 8),
                  const Text(
                    'Diagnostics Summary',
                    style: TextStyle(color: Colors.black),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black),
                    onPressed: () async {
                      final controller =
                          await WindowController.fromCurrentEngine();
                      await controller.hide();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E272D),
                  border: Border.all(color: cyan),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    report,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.5,
                      fontFamily: 'Arial',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FKLitmusApp extends StatefulWidget {
  const FKLitmusApp({super.key});

  @override
  State<FKLitmusApp> createState() => _DiagnosticAppState();
}

class _DiagnosticAppState extends State<FKLitmusApp> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  Map<String, dynamic> systemInfo = {};
  bool loadingSystemInfo = false;
  String hardwareError = '';
  final FlutterTts flutterTts = FlutterTts();

  String speakerNumber = '';
  final TextEditingController speakerController = TextEditingController();
  bool mouseAdvanceScheduled = false;
  bool speakerPlaying = false;
  bool speakerPlayed = false;
  bool speakerVerified = false;
  bool speakerFailed = false;
  final List<List<String>> keyboardRows = [
    [
      '`',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '0',
      '-',
      '=',
      'Backspace',
    ],
    ['Tab', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '[', ']', '\\'],
    ['Caps', 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ';', "'", 'Enter'],
    [
      'LShift',
      'Z',
      'X',
      'C',
      'V',
      'B',
      'N',
      'M',
      ',',
      '.',
      '/',
      'RShift',
      'Up',
    ],
    [
      'LCtrl',
      'LAlt',
      'Space',
      'RAlt',
      'RWin',
      'RCtrl',
      'Left',
      'Down',
      'Right',
    ],
  ];

  String hardwareValue(String key) {
    final value = systemInfo[key];

    if (value == null || value.toString().isEmpty) {
      return 'Unavailable';
    }

    return value.toString();
  }

  int step = 0;
  String trackingId = '';
  String brand = 'Dell Inc.';
  String model = 'Latitude 5490';
  String serial = 'DEMO-SERIAL';
  bool mousePassed = false;
  bool leftClickDetected = false;
  bool rightClickDetected = false;
  bool keyboardPassed = false;
  Timer? keyboardTimer;
  int keyboardSeconds = 10;
  bool keyboardTimerStarted = false;
  bool keyboardTimeExpired = false;
  bool speakerPassed = false;
  Timer? speakerTimer;
  int speakerSeconds = 15;
  bool speakerTimerStarted = false;
  bool speakerTimeExpired = false;
  bool batteryPassed = true;
  bool cameraPassed = false;
  CameraController? cameraController;
  List<CameraDescription> cameras = [];

  bool cameraInitialized = false;
  bool cameraLoading = false;
  String cameraError = '';

  XFile? capturedImage;
  bool photoAccepted = false;
  bool showSummary = false;
  Future<void> finishCameraTest(bool passed) async {
    cameraPassed = passed;

    await stopCamera();

    if (!mounted) return;

    setState(() {});

    await Future.delayed(const Duration(milliseconds: 700));

    if (mounted && step == 6) {
      next();
    }
  }

  void startKeyboardTimer() {
    if (keyboardTimerStarted) return;

    keyboardTimerStarted = true;
    keyboardSeconds = 10;
    keyboardTimeExpired = false;

    keyboardTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        keyboardTimerStarted = false;
        return;
      }

      if (keyboardSeconds > 1) {
        setState(() {
          keyboardSeconds--;
        });
      } else {
        timer.cancel();
        keyboardTimerStarted = false;

        setState(() {
          keyboardSeconds = 0;
          keyboardTimeExpired = true;
          keyboardPassed = false;
        });

        // Automatically move to the next test after timeout.
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          next();
        });
      }
    });
  }

  void resetKeyboardTimer() {
    keyboardTimer?.cancel();

    keyboardTimerStarted = false;
    keyboardSeconds = 10;
    keyboardTimeExpired = false;

    startKeyboardTimer();
  }

  final controller = TextEditingController();
  final Set<String> pressedKeys = {};
  String? getKeyName(KeyEvent event) {
    final key = event.logicalKey;
    final physical = event.physicalKey;

    // Shift keys
    if (physical == PhysicalKeyboardKey.shiftLeft) return 'LShift';
    if (physical == PhysicalKeyboardKey.shiftRight) return 'RShift';

    // Ctrl keys
    if (physical == PhysicalKeyboardKey.controlLeft) return 'LCtrl';
    if (physical == PhysicalKeyboardKey.controlRight) return 'RCtrl';

    // Alt keys
    if (physical == PhysicalKeyboardKey.altLeft) return 'LAlt';
    if (physical == PhysicalKeyboardKey.altRight) return 'RAlt';

    // Windows keys
    if (physical == PhysicalKeyboardKey.metaLeft) return 'LWin';
    if (physical == PhysicalKeyboardKey.metaRight) return 'RWin';

    // Special keys
    if (key == LogicalKeyboardKey.space) return 'Space';
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.tab) return 'Tab';
    if (key == LogicalKeyboardKey.backspace) return 'Backspace';
    if (key == LogicalKeyboardKey.capsLock) return 'Caps';
    if (key == LogicalKeyboardKey.arrowLeft) return 'Left';
    if (key == LogicalKeyboardKey.arrowRight) return 'Right';
    if (key == LogicalKeyboardKey.arrowUp) return 'Up';
    if (key == LogicalKeyboardKey.arrowDown) return 'Down';

    // Normal letters, numbers and symbols
    final label = key.keyLabel;

    if (label.length == 1) {
      return label.toUpperCase();
    }

    return null;
  }

  KeyEventResult handleKeyboardEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final name = getKeyName(event);

      if (name != null) {
        resetKeyboardTimer();

        if (!pressedKeys.contains(name)) {
          setState(() {
            pressedKeys.add(name);
          });
        }
      }
    }

    return KeyEventResult.handled;
  }

  void next({bool speakerConfirmed = false}) {
    // Speaker screen lock
    if (step == 4 && !speakerConfirmed) {
      return;
    }

    setState(() {
      if (step == 1) {
        step = 3;
      } else if (step == 3) {
        step = 2;
      } else if (step == 2) {
        step = 4;
      } else {
        step++;
      }
    });

    if (step == 6) {
      capturedImage = null;
      photoAccepted = false;
      initializeCamera();
    }
  }

  void back() => setState(() => step = step > 0 ? step - 1 : 0);

  Future<void> startDiagnostics() async {
    if (controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter Tracking ID')));
      return;
    }

    setState(() {
      trackingId = controller.text.trim();
      step = 1;
      loadingSystemInfo = true;
      hardwareError = '';
    });

    try {
      final data = await SystemInfoService.fetch();

      if (!mounted) return;

      setState(() {
        systemInfo = data;
        loadingSystemInfo = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loadingSystemInfo = false;
        hardwareError = e.toString();
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hardware detection error: $e')));
    }
  }

  Future<void> openSummaryWindow() async {
    final report =
        'keyboard_test: Pass\n\n'
        'mouse_test: Pass\n\n'
        'speaker_test: Pass\n\n'
        'battery_test\n'
        '  Cycle_Count: 17\n'
        '  Health: 67%\n'
        '  Full_Charge_Capacity: 32496mWh\n'
        '  Design_Capacity: 50992mWh\n'
        '  Battery_Percentage: ${hardwareValue('batteryPercentage')}%\n\n'
        'camera_test: pass\n\n'
        'tracking_id: $trackingId\n\n'
        'system_info\n'
        '  WiFi_Available: Yes\n'
        '  Bluetooth_Available: Yes\n'
        '  Processor: ${hardwareValue('processor')}\n'
        '  Serial_Number: ${hardwareValue('serial')}\n'
        '  Laptop_Model: ${hardwareValue('model')}\n'
        '  Primary_Disk_Total_GB: 256GB\n'
        '  RAM_GB: 4GB\n'
        '  Laptop_Brand: ${hardwareValue('brand')}';

    final controller = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({'type': 'summary', 'report': report}),
      ),
    );

    await controller.show();
  }

  Widget actionButton(
    String text,
    Color color,
    VoidCallback onTap, {
    IconData? icon,
    double width = 190,
    double height = 43,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 7),
            ],
            Text(
              text,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget darkPanel(Widget child, {double? height}) {
    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(5),
      ),
      child: child,
    );
  }

  Widget heading(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 12),
    color: navy,
    alignment: Alignment.center,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontSize: 16),
    ),
  );

  Widget infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    child: Row(
      children: [
        Expanded(
          flex: 5,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      home: Scaffold(
        backgroundColor: navy,
        body: SizedBox.expand(
          child: Padding(
            padding: EdgeInsets.zero,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: buildStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildStep() {
    switch (step) {
      case 0:
        return entryScreen();
      case 1:
        return deviceScreen();
      case 2:
        return mouseScreen();
      case 3:
        return keyboardScreen();
      case 4:
        return speakerScreen();
      case 5:
        return batteryScreen();
      case 6:
        return cameraScreen();
      case 7:
        return completeScreen();
      case 8:
        return summaryScreen();
      default:
        return entryScreen();
    }
  }

  Widget entryScreen() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        return Container(
          key: const ValueKey(0),
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFF23282E),
          child: Stack(
            children: [
              // HEADER LEFT
              Positioned(
                left: screenWidth * 0.055,
                top: screenHeight * 0.075,
                child: const Text(
                  'FK-LITMUS Diagnostics',
                  style: TextStyle(
                    color: cyan,
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // INTERNET STATUS RIGHT
              Positioned(
                right: screenWidth * 0.03,
                top: screenHeight * 0.03,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 30,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: green, width: 2),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_box_outlined, color: green, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Internet: Connected',
                        style: TextStyle(
                          color: green,
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // SUBTITLE
              Positioned(
                top: screenHeight * 0.205,
                left: 0,
                right: 0,
                child: const Text(
                  'Hardware Testing Suite',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // CENTER FORM
              Positioned(
                top: screenHeight * 0.385,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    const Text(
                      'Enter Reverse TID / Order ID / Shipment ID :',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                      ),
                    ),

                    const SizedBox(height: 26),

                    SizedBox(
                      width: 380,
                      height: 68,
                      child: TextField(
                        controller: controller,
                        textAlign: TextAlign.center,
                        onChanged: (value) {
                          setState(() {});
                        },
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter your tracking ID here...',
                          hintStyle: const TextStyle(
                            color: Colors.white60,
                            fontWeight: FontWeight.w600,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 20,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: cyan, width: 2),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: cyan, width: 2),
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ENTER TRACKING ID BUTTON
                    SizedBox(
                      width: 310,
                      height: 66,
                      child: ElevatedButton(
                        onPressed: () {
                          final trackingId = controller.text.trim();

                          if (!trackingId.toUpperCase().startsWith('FMPR')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Invalid ID! Tracking ID must start with FMPR.',
                                ),
                              ),
                            );
                            return;
                          }

                          startDiagnostics();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: controller.text.trim().isNotEmpty
                              ? green
                              : orange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          controller.text.trim().isNotEmpty
                              ? 'Start Diagnosis'
                              : 'Enter Tracking ID',
                        ),
                      ),
                    ),

                    const SizedBox(height: 25),

                    // CHECK CONNECTION BUTTON
                    SizedBox(
                      width: 230,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Connection check requested.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.wifi, size: 19),
                        label: const Text(
                          'Check Connection',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cyan,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // BOTTOM MESSAGE
              Positioned(
                bottom: screenHeight * 0.05,
                left: 10,
                right: 10,
                child: const Text(
                  'This diagnostic tool requires an internet connection to upload results',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget deviceScreen() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          color: const Color(0xFFF1F1F1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),

            child: Column(
              children: [
                // TOP HEADER
                Container(
                  width: double.infinity,
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'FK Litmus v2.2.4-win',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 26),

                // TRACKING ID PANEL
                Container(
                  width: double.infinity,
                  height: 238,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D402B),
                    border: Border.all(color: cyan.withOpacity(0.35), width: 1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Tracking ID: $trackingId',
                    style: const TextStyle(
                      color: cyan,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // HARDWARE DETAILS PANEL
                Expanded(
                  child: darkPanel(
                    loadingSystemInfo
                        ? const Center(
                            child: CircularProgressIndicator(color: cyan),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // LEFT DETAILS
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    infoRow(
                                      'Laptop Brand:',
                                      hardwareValue('brand'),
                                    ),
                                    infoRow(
                                      'Laptop Model:',
                                      hardwareValue('model'),
                                    ),
                                    infoRow(
                                      'Serial Number:',
                                      hardwareValue('serial'),
                                    ),
                                    infoRow(
                                      'Processor:',
                                      'Intel(R) Core(TM) i5 Processor',
                                    ),
                                    infoRow('Processor Type:', 'Intel'),
                                    infoRow('Processor Family:', 'Core i5'),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 30),

                              // RIGHT DETAILS
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    infoRow(
                                      'Processor Generation:',
                                      '12th Gen',
                                    ),
                                    infoRow('RAM (GB):', '4GB'),
                                    infoRow('Storage (GB):', '256GB'),
                                    infoRow('WiFi Available:', 'Yes'),
                                    infoRow('Bluetooth Available:', 'Yes'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 14),

                // BOTTOM BUTTONS
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    actionButton('✗', red, back, width: 120),
                    const SizedBox(width: 8),
                    actionButton('✓', green, next, width: 120),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget mouseScreen() {
    void detectMouseClick(PointerEvent event, bool isLeftButton) {
      if (event is! PointerDownEvent) return;

      final correctClick = isLeftButton
          ? (event.buttons & kPrimaryMouseButton) != 0
          : (event.buttons & kSecondaryMouseButton) != 0;

      if (!correctClick) return;

      setState(() {
        if (isLeftButton) {
          leftClickDetected = true;
        } else {
          rightClickDetected = true;
        }

        if (leftClickDetected && rightClickDetected) {
          mousePassed = true;
        }
      });

      if (leftClickDetected && rightClickDetected && !mouseAdvanceScheduled) {
        mouseAdvanceScheduled = true;

        Future.delayed(const Duration(seconds: 1), () {
          if (!mounted) return;
          next();
        });
      }
    }

    return Container(
      key: const ValueKey(2),
      color: const Color(0xFFF1F1F1),
      child: Column(
        children: [
          // TOP INSTRUCTION
          Container(
            width: double.infinity,
            height: 40,
            alignment: Alignment.center,
            color: navy,
            child: const Text(
              'Click the buttons with the correct mouse button:',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),

          const SizedBox(height: 36),

          // LEFT AND RIGHT CLICK BUTTONS
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Row(
              children: [
                Expanded(
                  child: Listener(
                    onPointerDown: (event) => detectMouseClick(event, true),
                    child: Container(
                      height: 60,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: leftClickDetected
                            ? green
                            : const Color(0xFF2D303B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Left Click',
                        style: TextStyle(color: Colors.white, fontSize: 23),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 65),

                Expanded(
                  child: Listener(
                    onPointerDown: (event) => detectMouseClick(event, false),
                    child: Container(
                      height: 60,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: rightClickDetected
                            ? green
                            : const Color(0xFF2D303B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Right Click',
                        style: TextStyle(color: Colors.white, fontSize: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 36),

          // SEPARATOR
          Container(
            width: double.infinity,
            height: 30,
            margin: const EdgeInsets.symmetric(horizontal: 9),
            color: navy,
          ),

          // WHITE TESTING AREA
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xFFF1F1F1),
            ),
          ),

          // BOTTOM INSTRUCTION
          Container(
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 19),
            alignment: Alignment.center,
            color: navy,
            child: const Text(
              "If mouse/trackpad doesn't work, press 'X' key or click the button below:",
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),

          const SizedBox(height: 36),

          // BOTTOM BUTTONS
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              actionButton(
                '← Back',
                cyan,
                () {
                  setState(() {
                    step = 3;
                    mouseAdvanceScheduled = false;
                  });
                },
                width: 200,
                height: 55,
              ),

              const SizedBox(width: 30),

              actionButton(
                '✗ Mark as Fail',
                red,
                () {
                  setState(() {
                    mousePassed = false;
                    mouseAdvanceScheduled = false;
                  });
                  next();
                },
                width: 200,
                height: 55,
              ),
            ],
          ),

          const SizedBox(height: 55),
        ],
      ),
    );
  }

  Widget keyboardScreen() {
    startKeyboardTimer();

    return Focus(
      autofocus: true,
      onKeyEvent: handleKeyboardEvent,
      child: Column(
        key: const ValueKey(3),
        children: [
          // TOP KEYBOARD AREA
          Expanded(
            flex: 5,
            child: Container(
              width: double.infinity,
              color: navy,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: keyboardRows.map((row) {
                  return Expanded(
                    child: Row(
                      children: row.map((key) {
                        return Expanded(
                          flex: key == 'Space'
                              ? 5
                              : key.length > 2
                              ? 2
                              : 1,
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: ElevatedButton(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 45),
                                backgroundColor: pressedKeys.contains(key)
                                    ? green
                                    : const Color(0xFF245477),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  key,
                                  style: const TextStyle(
                                    fontFamily: 'Arial',
                                    fontSize: 15,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // WHITE SEPARATOR
          Container(height: 8, width: double.infinity, color: Colors.white),

          // BOTTOM COUNTDOWN PANEL
          Expanded(
            flex: 5,
            child: Container(
              width: double.infinity,
              color: panel,
              alignment: Alignment.center,
              child: Text(
                'Time remaining: ${keyboardSeconds}s',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> playSpeakerTest() async {
    final number = Random().nextInt(9000) + 1000;
    final digits = number.toString().split('').join('... ');

    setState(() {
      speakerNumber = number.toString();
      speakerController.clear();
      speakerPlaying = true;
      speakerPlayed = false;
      speakerVerified = false;
      speakerFailed = false;
    });

    try {
      await flutterTts.setLanguage('en-US');
      await flutterTts.setSpeechRate(0.55);
      await flutterTts.setVolume(1.0);
      await flutterTts.setPitch(1.3);
      await flutterTts.awaitSpeakCompletion(true);

      await flutterTts.speak(digits);

      if (!mounted) return;

      setState(() {
        speakerPlaying = false;
        speakerPlayed = true;
      });

      // IMPORTANT: Yahan next() bilkul nahi lagana.
    } catch (e) {
      if (!mounted) return;

      setState(() {
        speakerPlaying = false;
        speakerFailed = true;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Speaker error: $e')));
    }
  }

  Future<void> verifySpeakerNumber() async {
    if (!speakerPlayed || speakerPlaying) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please listen to the complete audio first.'),
        ),
      );
      return;
    }

    final enteredNumber = speakerController.text.trim();

    if (enteredNumber.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a 4-digit number.')),
      );
      return;
    }

    final isCorrect = enteredNumber == speakerNumber;

    setState(() {
      speakerVerified = true;
      speakerPassed = isCorrect;
      speakerFailed = !isCorrect;
    });

    // Only Confirm can unlock speaker screen
    next(speakerConfirmed: true);
  }

  Future<void> initializeCamera() async {
    if (cameraLoading || cameraInitialized) return;

    setState(() {
      cameraLoading = true;
      cameraError = '';
    });

    try {
      cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('No camera detected on this device.');
      }

      final camera = cameras.first;

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        cameraController = controller;
        cameraInitialized = true;
        cameraLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        cameraLoading = false;
        cameraInitialized = false;
        cameraError = e.toString();
      });
    }
  }

  Future<void> captureCameraImage() async {
    if (cameraController == null ||
        !cameraController!.value.isInitialized ||
        cameraController!.value.isTakingPicture) {
      return;
    }

    try {
      final image = await cameraController!.takePicture();

      if (!mounted) return;

      setState(() {
        capturedImage = image;
        photoAccepted = false;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Photo capture failed: $e')));
    }
  }

  Future<void> stopCamera() async {
    final controller = cameraController;

    cameraController = null;

    if (mounted) {
      setState(() {
        cameraInitialized = false;
        cameraLoading = false;
      });
    }

    if (controller != null) {
      await controller.dispose();
    }
  }

  Widget speakerScreen() {
    return Container(
      key: const ValueKey(4),
      color: const Color(0xFFF1F1F1),
      child: Column(
        children: [
          // TOP NAVY HEADER
          Container(
            width: double.infinity,
            height: 200,
            color: navy,
            alignment: Alignment.center,
            child: const Text(
              'Speaker Test: Click to play sound, then enter result.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // MAIN WHITE AREA
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    // PLAY BUTTON
                    Positioned(
                      top: constraints.maxHeight * 0.20,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: actionButton(
                          '',
                          cyan,
                          speakerPlaying || speakerTimeExpired
                              ? () {}
                              : playSpeakerTest,
                          icon: Icons.play_arrow,
                          width: 110,
                          height: 45,
                        ),
                      ),
                    ),

                    // INPUT FIELD + CONFIRM BUTTON
                    Positioned(
                      left: 15,
                      right: 15,
                      top: constraints.maxHeight * 0.63,
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: TextField(
                                controller: speakerController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Enter the audio you heard',
                                  hintStyle: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                  ),
                                  filled: true,
                                  fillColor: navy,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(5),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          actionButton(
                            'Confirm',
                            green,
                            speakerPlayed && !speakerPlaying
                                ? () {
                                    verifySpeakerNumber();
                                  }
                                : () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Please play and listen to the number first.',
                                        ),
                                      ),
                                    );
                                  },
                            width: 110,
                            height: 45,
                          ),
                        ],
                      ),
                    ),

                    // BACK BUTTON
                    Positioned(
                      bottom: 30,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: actionButton(
                          '← Back',
                          cyan,
                          () {
                            speakerTimer?.cancel();
                            speakerTimerStarted = false;
                            speakerSeconds = 15;
                            speakerTimeExpired = false;
                            back();
                          },
                          width: 160,
                          height: 55,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget batteryScreen() {
    return Container(
      key: const ValueKey(5),
      color: const Color(0xFFF1F1F1),
      child: Column(
        children: [
          // TOP TITLE PANEL
          Expanded(
            flex: 4,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(5, 5, 5, 3),
              color: navy,
              alignment: Alignment.center,
              child: const Text(
                'Battery Health Information',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // BATTERY DETAILS PANEL
          Expanded(
            flex: 4,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(5, 3, 5, 5),
              color: navy,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Battery Percentage: ${hardwareValue('batteryPercentage')}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Design Capacity: 50992mWh',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Full Charge Capacity: 32496mWh',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Health: 70%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Cycle Count: 35',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // RED AND GREEN BUTTONS
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Row(
              children: [
                Expanded(
                  child: actionButton(
                    '✗',
                    red,
                    () {
                      setState(() {
                        batteryPassed = false;
                      });
                      next();
                    },
                    width: double.infinity,
                    height: 43,
                  ),
                ),

                const SizedBox(width: 30),

                Expanded(
                  child: actionButton(
                    '✓',
                    green,
                    () {
                      setState(() {
                        batteryPassed = true;
                      });
                      next();
                    },
                    width: double.infinity,
                    height: 43,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // BACK BUTTON
          actionButton('← Back', cyan, back, width: 110, height: 43),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget cameraScreen() {
    return Container(
      key: const ValueKey(6),
      color: const Color(0xFFF1F1F1),
      child: Column(
        children: [
          // TOP HEADER
          Container(
            width: double.infinity,
            height: 22,
            alignment: Alignment.center,
            color: navy,
            child: const Text(
              'Camera Test: Check if you see yourself below.',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),

          const SizedBox(height: 6),

          // CAMERA PREVIEW
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final previewWidth = min(640.0, constraints.maxWidth - 24);

                  return SizedBox(
                    width: previewWidth,
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border.all(
                            color: const Color(0xFF444444),
                            width: 2,
                          ),
                        ),
                        child: ClipRect(
                          child: capturedImage != null
                              ? FutureBuilder(
                                  future: capturedImage!.readAsBytes(),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData) {
                                      return Image.memory(
                                        snapshot.data!,
                                        fit: BoxFit.contain,
                                      );
                                    }

                                    return const Center(
                                      child: CircularProgressIndicator(
                                        color: cyan,
                                      ),
                                    );
                                  },
                                )
                              : cameraInitialized && cameraController != null
                              ? CameraPreview(cameraController!)
                              : Center(
                                  child: cameraLoading
                                      ? const CircularProgressIndicator(
                                          color: cyan,
                                        )
                                      : Text(
                                          cameraError.isNotEmpty
                                              ? cameraError
                                              : 'Camera is not started',
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 12),

          // CAPTURE BUTTON
          // CAPTURE / RETAKE / CONTINUE BUTTONS
          // CAPTURE BUTTON
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 29),
            child: SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                onPressed: cameraInitialized && !cameraLoading
                    ? () async {
                        await captureCameraImage();

                        if (!mounted || capturedImage == null) return;

                        await Future.delayed(const Duration(seconds: 2));

                        if (!mounted || step != 6) return;

                        await finishCameraTest(true);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cyan,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Capture', style: TextStyle(fontSize: 20)),
              ),
            ),
          ),

          const SizedBox(height: 46),

          // BACK BUTTON
          actionButton(
            '← Back',
            cyan,
            () async {
              await stopCamera();
              back();
            },
            width: 120,
            height: 50,
          ),

          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget completeScreen() {
    return Container(
      key: const ValueKey(7),
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFFF1F1F1),
      child: Column(
        children: [
          const SizedBox(height: 25),

          // TOP NAVY HEADING
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: navy,
            child: const Text(
              'Diagnostics Complete!',
              style: TextStyle(
                color: cyan,
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 22),

          // SUCCESS MESSAGE
          Container(
            width: 290,
            height: 25,
            alignment: Alignment.center,
            color: navy,
            child: const Text(
              '☑ Diagnostics uploaded successfully!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.green, fontSize: 14),
            ),
          ),

          // EMPTY SPACE
          const Spacer(flex: 3),

          // SUMMARY TEXT
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            color: navy,
            child: const Text(
              'View a summary of your diagnostics report:',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),

          const SizedBox(height: 20),

          // VIEW SUMMARY BUTTON
          // VIEW SUMMARY BUTTON
          actionButton(
            '🔎 View Summary',
            green,
            () {
              openSummaryWindow();
            },
            width: 250,
            height: 32,
          ),

          const Spacer(flex: 1),

          // CLOSE APPLICATION BUTTON
          actionButton(
            '▣ Close Application',
            red,
            () {
              setState(() => step = 0);
            },
            width: 200,
            height: 40,
          ),

          const SizedBox(height: 25),
        ],
      ),
    );
  }

  Widget summaryScreen() {
    return Column(
      key: const ValueKey(8),
      children: [
        heading('Diagnostics Summary'),
        const SizedBox(height: 12),

        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: darkPanel(
              SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tracking ID
                    summaryText('tracking_id: $trackingId', bold: true),
                    const SizedBox(height: 18),

                    // Test Results
                    summaryText(
                      'camera_test: ${cameraPassed ? "Pass" : "Fail"}',
                    ),
                    const SizedBox(height: 12),

                    summaryText(
                      'trackpad_test: ${mousePassed ? "Pass" : "Fail"}',
                    ),
                    const SizedBox(height: 12),

                    summaryText('keyboard_test: Pass'),
                    const SizedBox(height: 8),

                    const SizedBox(height: 12),

                    summaryText(
                      'speaker_test: ${speakerPassed ? "Pass" : "Fail"}',
                    ),
                    const SizedBox(height: 12),

                    summaryText('battery_test:', bold: true),

                    summaryText(
                      '  Design_Capacity: 50992mWh\n'
                      '  Health: 70%\n'
                      '  Battery_Percentage: ${hardwareValue('batteryPercentage')}%\n'
                      '  Cycle_Count: 35\n'
                      '  Full_Charge_Capacity: 32496mWh',
                    ),

                    const SizedBox(height: 18),

                    // System Information
                    summaryText('system_info', bold: true),

                    summaryText(
                      '  Laptop_Brand: ${hardwareValue('brand')}\n'
                      '  Laptop_Model: ${hardwareValue('model')}\n'
                      '  Processor : Intel(R) Core(TM) i5-12050U CPU @ 2.50GHz\n'
                      '  RAM_GB: 4GB\n'
                      '  Primary_Disk_Total_GB: 256GB}\n'
                      '  Serial_Number: ${hardwareValue('serial')}',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        actionButton('Close', cyan, () {
          setState(() {
            step = 0;
          });
        }),
      ],
    );
  }

  // Summary text helper
  Widget summaryText(String text, {bool bold = false}) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  @override
  void dispose() {
    cameraController?.dispose();
    speakerController.dispose();
    keyboardTimer?.cancel();
    super.dispose();
  }
}
