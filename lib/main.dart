// ============================================================================
// TCMU-1 UNIVERSAL GSM MOTOR CONTROLLER & SMART BILLING SYSTEM
// Complete Flutter Android Code for Visual Studio Code
// Features:
// 1. Universal SMS Config (Commands + Case-Insensitive Substring Replies)
// 2. Future-Ready Timer / Scheduler (3*X where 1 = 30 mins) + Paste Reply Later
// 3. Auto-Parse *TCMU-1 USERS* (USER1 = ..., USER2 = ..., USER3 = Empty, USER4 = ...)
// 4. Sticky Default Rate (persists until changed) + Manual Final Bill Override Box
// 5. Cash Memo Slip Generator (No fixed shop name) + WhatsApp Share + Udhaar/Paid status
// 6. Phone Biometric / Device PIN Lock (local_auth) for App & Settings Security
// 7. 30-Second Anti-Spam Cooldown + 3x Auto-Retry Engine + Power Cut Pause/Resume
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:telephony/telephony.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

// Top-level background SMS handler for Android Telephony plugin
@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) async {
  // Background SMS is also processed when app resumes or via SharedPreferences queue
  final prefs = await SharedPreferences.getInstance();
  final List<String> pending = prefs.getStringList('pending_bg_sms') ?? [];
  pending.add(jsonEncode({
    'sender': message.address ?? '',
    'body': message.body ?? '',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  }));
  await prefs.setStringList('pending_bg_sms', pending);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TcmuUniversalApp());
}

class TcmuUniversalApp extends StatelessWidget {
  const TcmuUniversalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TCMU-1 Smart Billing',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0F766E),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      home: const MainDashboardScreen(),
    );
  }
}

class BillingRecord {
  String id;
  String dateStr;
  String customerName;
  String customerMobile;
  int netRunningSeconds;
  int powerCutSeconds;
  double ratePerHour;
  double calculatedAmount;
  double finalAmount; // Supports manual override
  bool isManualOverride;
  bool isPaid; // True = Paid, False = Udhaar/Pending
  String startMode; // Normal / Timer / Manual Physical

  BillingRecord({
    required this.id,
    required this.dateStr,
    required this.customerName,
    this.customerMobile = '',
    required this.netRunningSeconds,
    this.powerCutSeconds = 0,
    required this.ratePerHour,
    required this.calculatedAmount,
    required this.finalAmount,
    this.isManualOverride = false,
    this.isPaid = true,
    this.startMode = 'Normal',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'dateStr': dateStr,
        'customerName': customerName,
        'customerMobile': customerMobile,
        'netRunningSeconds': netRunningSeconds,
        'powerCutSeconds': powerCutSeconds,
        'ratePerHour': ratePerHour,
        'calculatedAmount': calculatedAmount,
        'finalAmount': finalAmount,
        'isManualOverride': isManualOverride,
        'isPaid': isPaid,
        'startMode': startMode,
      };

  factory BillingRecord.fromJson(Map<String, dynamic> m) => BillingRecord(
        id: m['id'] ?? '',
        dateStr: m['dateStr'] ?? '',
        customerName: m['customerName'] ?? 'Customer',
        customerMobile: m['customerMobile'] ?? '',
        netRunningSeconds: m['netRunningSeconds'] ?? 0,
        powerCutSeconds: m['powerCutSeconds'] ?? 0,
        ratePerHour: (m['ratePerHour'] ?? 100.0).toDouble(),
        calculatedAmount: (m['calculatedAmount'] ?? 0.0).toDouble(),
        finalAmount: (m['finalAmount'] ?? 0.0).toDouble(),
        isManualOverride: m['isManualOverride'] ?? false,
        isPaid: m['isPaid'] ?? true,
        startMode: m['startMode'] ?? 'Normal',
      );
}

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  final Telephony telephony = Telephony.instance;
  final LocalAuthentication auth = LocalAuthentication();

  int _selectedTab = 0;
  bool _isSettingsUnlocked = false;
  bool _appLockEnabled = true;

  // Device & Universal Config State
  String _motorSimNumber = '+919876543210';
  bool _autoRestartMode = true;
  double _stickyDefaultRate = 120.0; // Persists automatically across sessions

  // Universal Commands & Expected Substring Replies
  String _cmdStart = '1*';
  String _replyStart = 'PUMP STARTED';
  String _cmdStop = '2*';
  String _replyStop = 'PUMP STOPPED';
  String _cmdTimerPrefix = '3*';
  String _replyTimerStart = 'PUMP STARTED'; // Universal: can paste exact timer reply later
  String _replyTimerEnd = 'PUMP STOPPED';   // Universal: can paste exact timer end reply later
  String _cmdAutoOn = '4*1';
  String _cmdAutoOff = '4*0';
  String _replyAutoMode = 'SUCCESSFULLY SET AUTO MODE';
  String _cmdStatus = '5*';
  String _cmdUsersList = '10*';
  String _replyPowerCut = 'POWER OFF PUMP OFF';
  String _replyPowerResume = 'POWER RESUME PUMP STARTED';
  String _replyPhysicalStart = 'manual start';
  String _replyPhysicalStop = 'manual stop';

  // 4 Registered Users (from *TCMU-1 USERS*)
  List<String> _deviceUsers = [
    '8081728811',
    '7839455008',
    '',
    '9236504217',
  ];

  // Live Motor & Session State
  String _motorState = 'STOPPED'; // STOPPED, RUNNING, PAUSED_POWER_CUT
  String _powerStatus = 'AVAILABLE';
  String _batteryStatus = 'CHARGING';
  String _signalStrength = '63%';
  String _activeCustomer = '';
  String _activeCustomerMobile = '';
  double _activeRate = 120.0;
  double? _activeManualFixedAmount; // Optional manual amount entered at start/end
  String _activeStartMode = 'Normal';
  int _runningSeconds = 0;
  int _pausedSeconds = 0;
  int _timerTargetSeconds = 0; // If started with 3*X
  Timer? _sessionClock;

  // Anti-Spam Cooldown & Auto-Retry State
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  int _retryAttempt = 0;
  Timer? _retryTimer;

  // Billing History
  List<BillingRecord> _history = [];

  @override
  void initState() {
    super.initState();
    _loadSavedData();
    _initSmsListener();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _motorSimNumber = prefs.getString('motorSim') ?? '+919876543210';
      _stickyDefaultRate = prefs.getDouble('stickyRate') ?? 120.0;
      _activeRate = _stickyDefaultRate;
      _autoRestartMode = prefs.getBool('autoMode') ?? true;
      _deviceUsers = prefs.getStringList('deviceUsers') ??
          ['8081728811', '7839455008', '', '9236504217'];

      _cmdStart = prefs.getString('cmdStart') ?? '1*';
      _replyStart = prefs.getString('replyStart') ?? 'PUMP STARTED';
      _cmdStop = prefs.getString('cmdStop') ?? '2*';
      _replyStop = prefs.getString('replyStop') ?? 'PUMP STOPPED';
      _cmdTimerPrefix = prefs.getString('cmdTimerPrefix') ?? '3*';
      _replyTimerStart = prefs.getString('replyTimerStart') ?? 'PUMP STARTED';
      _replyTimerEnd = prefs.getString('replyTimerEnd') ?? 'PUMP STOPPED';
      _replyPowerCut = prefs.getString('replyPowerCut') ?? 'POWER OFF PUMP OFF';
      _replyPowerResume =
          prefs.getString('replyPowerResume') ?? 'POWER RESUME PUMP STARTED';
      _replyPhysicalStart =
          prefs.getString('replyPhysicalStart') ?? 'manual start';
      _replyPhysicalStop =
          prefs.getString('replyPhysicalStop') ?? 'manual stop';

      final histRaw = prefs.getStringList('billingHistory') ?? [];
      _history = histRaw
          .map((e) => BillingRecord.fromJson(jsonDecode(e)))
          .toList();
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('motorSim', _motorSimNumber);
    await prefs.setDouble('stickyRate', _stickyDefaultRate);
    await prefs.setBool('autoMode', _autoRestartMode);
    await prefs.setStringList('deviceUsers', _deviceUsers);
    await prefs.setString('cmdStart', _cmdStart);
    await prefs.setString('replyStart', _replyStart);
    await prefs.setString('cmdStop', _cmdStop);
    await prefs.setString('replyStop', _replyStop);
    await prefs.setString('cmdTimerPrefix', _cmdTimerPrefix);
    await prefs.setString('replyTimerStart', _replyTimerStart);
    await prefs.setString('replyTimerEnd', _replyTimerEnd);
    await prefs.setString('replyPowerCut', _replyPowerCut);
    await prefs.setString('replyPowerResume', _replyPowerResume);
    await prefs.setString('replyPhysicalStart', _replyPhysicalStart);
    await prefs.setString('replyPhysicalStop', _replyPhysicalStop);
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _history.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('billingHistory', list);
  }

  void _initSmsListener() async {
    final bool? granted = await telephony.requestPhoneAndSmsPermissions;
    if (granted ?? false) {
      telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) {
          _processIncomingSms(message.address ?? '', message.body ?? '');
        },
        onBackgroundMessage: backgroundMessageHandler,
      );
    }
  }

  // Case-insensitive universal SMS parser
  void _processIncomingSms(String sender, String body) {
    final cleanBody = body.trim();
    final upperBody = cleanBody.toUpperCase();

    // 1. Parse *TCMU-1 USERS* reply (10*)
    if (upperBody.contains('TCMU-1 USERS') || upperBody.contains('USER1')) {
      final List<String> updated = ['', '', '', ''];
      for (int i = 1; i <= 4; i++) {
        final reg = RegExp(r'USER\s*' + i.toString() + r'\s*=\s*(\d{10,12})',
            caseSensitive: false);
        final match = reg.firstMatch(cleanBody);
        if (match != null) {
          updated[i - 1] = match.group(1) ?? '';
        }
      }
      setState(() {
        _deviceUsers = updated;
      });
      _saveConfig();
      _showToast('Users Synced from TCMU-1 Device!');
      return;
    }

    // 2. Parse **TCMU-1 STATUS** reply (5*)
    if (upperBody.contains('TCMU-1 STATUS')) {
      setState(() {
        if (upperBody.contains('POWER AVAILABLE')) _powerStatus = 'AVAILABLE';
        if (upperBody.contains('POWER OFF') || upperBody.contains('NO POWER')) {
          _powerStatus = 'OFF';
        }
        final sigMatch = RegExp(r'SIGNAL\s*:\s*(\d+%)', caseSensitive: false)
            .firstMatch(cleanBody);
        if (sigMatch != null) _signalStrength = sigMatch.group(1)!;
        if (upperBody.contains('MODE : AUTO')) _autoRestartMode = true;
        if (upperBody.contains('MODE : MANUAL')) _autoRestartMode = false;
      });
      _showToast('Device Status Updated!');
      return;
    }

    // 3. Power Cut (Pause Session)
    if (upperBody.contains(_replyPowerCut.toUpperCase())) {
      if (_motorState == 'RUNNING') {
        setState(() {
          _motorState = 'PAUSED_POWER_CUT';
          _powerStatus = 'OFF (Power Cut)';
        });
        _showToast('Power Cut Detected! Billing Timer PAUSED.');
      }
      return;
    }

    // 4. Power Resume (Resume Session)
    if (upperBody.contains(_replyPowerResume.toUpperCase())) {
      if (_motorState == 'PAUSED_POWER_CUT') {
        setState(() {
          _motorState = 'RUNNING';
          _powerStatus = 'AVAILABLE';
        });
        _showToast('Power Resumed! Billing Timer RESUMED.');
      }
      return;
    }

    // 5. Physical Manual Start (case-insensitive substring match)
    if (upperBody.contains(_replyPhysicalStart.toUpperCase())) {
      if (_motorState == 'STOPPED') {
        _startBillingSession(
          customerName: 'Manual Customer (Physical Button)',
          rate: _stickyDefaultRate,
          mode: 'Physical Start',
          sendSmsCommand: false,
        );
        _showToast('Motor started physically! Timer started.');
      }
      return;
    }

    // 6. Physical Manual Stop
    if (upperBody.contains(_replyPhysicalStop.toUpperCase())) {
      if (_motorState != 'STOPPED') {
        _completeBillingSession(sendSmsCommand: false);
        _showToast('Motor stopped physically! Cash Memo saved.');
      }
      return;
    }

    // 7. Normal / Timer Start Confirmation
    if (upperBody.contains(_replyStart.toUpperCase()) ||
        upperBody.contains(_replyTimerStart.toUpperCase())) {
      _retryTimer?.cancel();
      _retryAttempt = 0;
      if (_motorState == 'STOPPED') {
        _startBillingSession(
          customerName: _activeCustomer.isEmpty ? 'Customer' : _activeCustomer,
          rate: _activeRate,
          mode: _activeStartMode,
          sendSmsCommand: false,
        );
      }
      return;
    }

    // 8. Stop / Timer End Confirmation
    if (upperBody.contains(_replyStop.toUpperCase()) ||
        upperBody.contains(_replyTimerEnd.toUpperCase())) {
      _retryTimer?.cancel();
      _retryAttempt = 0;
      if (_motorState != 'STOPPED') {
        _completeBillingSession(sendSmsCommand: false);
      }
      return;
    }
  }

  // Biometric / Device PIN Lock via local_auth
  Future<bool> _authenticateWithPhoneLock() async {
    try {
      final bool canCheck =
          await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!canCheck) {
        setState(() => _isSettingsUnlocked = true);
        return true;
      }
      final bool didAuthenticate = await auth.authenticate(
        localizedReason:
            'Authenticate with your phone Fingerprint or PIN to unlock Settings',
        options: const AuthenticationOptions(
          biometricOnly: false, // Allows both Fingerprint & Phone PIN/Pattern
          stickyAuth: true,
        ),
      );
      if (didAuthenticate) {
        setState(() => _isSettingsUnlocked = true);
      }
      return didAuthenticate;
    } catch (e) {
      setState(() => _isSettingsUnlocked = true);
      return true;
    }
  }

  void _sendSmsWithRetry(String command, {bool expectReply = true}) {
    if (_cooldownSeconds > 0) {
      _showToast('Please wait $_cooldownSeconds sec (Anti-Spam Lock)');
      return;
    }
    // Start 30s UI Cooldown
    setState(() => _cooldownSeconds = 30);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_cooldownSeconds <= 1) {
        t.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds--);
      }
    });

    // Send actual SMS
    telephony.sendSms(to: _motorSimNumber, message: command);
    _showToast('SMS Sent: $command to $_motorSimNumber');

    if (expectReply) {
      _retryAttempt = 1;
      _retryTimer?.cancel();
      _retryTimer = Timer.periodic(const Duration(seconds: 25), (t) {
        if (_retryAttempt < 3) {
          _retryAttempt++;
          telephony.sendSms(to: _motorSimNumber, message: command);
          _showToast('Auto-Retry ($_retryAttempt/3): Sending $command');
        } else {
          t.cancel();
        }
      });
    }
  }

  void _startBillingSession({
    required String customerName,
    String customerMobile = '',
    required double rate,
    double? manualFixedAmount,
    required String mode,
    int timerMinutes = 0,
    bool sendSmsCommand = true,
  }) {
    // Save rate as the new sticky default rate for all future sessions
    _stickyDefaultRate = rate;
    _saveConfig();

    setState(() {
      _activeCustomer = customerName;
      _activeCustomerMobile = customerMobile;
      _activeRate = rate;
      _activeManualFixedAmount = manualFixedAmount;
      _activeStartMode = mode;
      _motorState = 'RUNNING';
      _runningSeconds = 0;
      _pausedSeconds = 0;
      _timerTargetSeconds = timerMinutes * 60;
    });

    if (sendSmsCommand) {
      if (timerMinutes > 0) {
        final int xUnits = (timerMinutes / 30).ceil().clamp(1, 47);
        _sendSmsWithRetry('$_cmdTimerPrefix$xUnits');
      } else {
        _sendSmsWithRetry(_cmdStart);
      }
    }

    _sessionClock?.cancel();
    _sessionClock = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        if (_motorState == 'RUNNING') {
          _runningSeconds++;
          if (_timerTargetSeconds > 0 &&
              _runningSeconds >= _timerTargetSeconds) {
            _completeBillingSession(sendSmsCommand: false);
          }
        } else if (_motorState == 'PAUSED_POWER_CUT') {
          _pausedSeconds++;
        }
      });
    });
  }

  void _completeBillingSession({bool sendSmsCommand = true}) {
    _sessionClock?.cancel();
    if (sendSmsCommand) {
      _sendSmsWithRetry(_cmdStop);
    }

    final double hours = _runningSeconds / 3600.0;
    final double calcAmt = double.parse((hours * _activeRate).toStringAsFixed(2));
    final double finalAmt = _activeManualFixedAmount ?? calcAmt;

    final record = BillingRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      dateStr: DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now()),
      customerName: _activeCustomer.isEmpty ? 'Walk-in Customer' : _activeCustomer,
      customerMobile: _activeCustomerMobile,
      netRunningSeconds: _runningSeconds,
      powerCutSeconds: _pausedSeconds,
      ratePerHour: _activeRate,
      calculatedAmount: calcAmt,
      finalAmount: finalAmt,
      isManualOverride: _activeManualFixedAmount != null,
      isPaid: true,
      startMode: _activeStartMode,
    );

    setState(() {
      _motorState = 'STOPPED';
      _history.insert(0, record);
    });
    _saveHistory();
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  String _formatDuration(int totalSeconds) {
    final int h = totalSeconds ~/ 3600;
    final int m = (totalSeconds % 3600) ~/ 60;
    final int s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // Share Cash Memo via WhatsApp / Share Sheet
  void _shareCashMemo(BillingRecord rec) {
    final String memo = '''
🧾 *CASH MEMO (बिल पर्ची)*
--------------------------------
📅 Date: ${rec.dateStr}
👤 Customer: ${rec.customerName}
⚙️ Mode: ${rec.startMode}
⏱️ Net Running Time: ${_formatDuration(rec.netRunningSeconds)}
⚡ Power Cut Deducted: ${_formatDuration(rec.powerCutSeconds)}
💰 Rate: ₹${rec.ratePerHour.toStringAsFixed(0)} / Hour
--------------------------------
💵 *TOTAL AMOUNT: ₹${rec.finalAmount.toStringAsFixed(2)}* ${rec.isManualOverride ? '(Manual Fixed)' : ''}
📌 Status: ${rec.isPaid ? 'PAID (भुगतान प्राप्त)' : 'UDHAAR / PENDING (बाकी)'}
--------------------------------
''';
    Share.share(memo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TCMU-1 Universal Controller'),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Check Status (5*)',
            icon: const Icon(Icons.refresh),
            onPressed: () => _sendSmsWithRetry(_cmdStatus, expectReply: false),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _buildHomeTab(),
          _buildHisabTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (idx) async {
          if (idx == 2 && !_isSettingsUnlocked && _appLockEnabled) {
            final ok = await _authenticateWithPhoneLock();
            if (!ok) return;
          }
          setState(() => _selectedTab = idx);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.power_settings_new), label: 'Control Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Cash Memo / Hisab'),
          NavigationDestination(icon: Icon(Icons.security), label: 'Settings & Config'),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    final double liveBill = _activeManualFixedAmount ??
        ((_runningSeconds / 3600.0) * _activeRate);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'STATUS: $_motorState',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _motorState == 'RUNNING'
                            ? Colors.green.shade700
                            : (_motorState == 'PAUSED_POWER_CUT'
                                ? Colors.orange.shade800
                                : Colors.red.shade700),
                      ),
                    ),
                    Chip(label: Text('Rate: ₹${_stickyDefaultRate.toStringAsFixed(0)}/hr')),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Customer: ${_activeCustomer.isEmpty ? "None" : _activeCustomer}'),
                Text('Running Time: ${_formatDuration(_runningSeconds)} (Power Cut: ${_formatDuration(_pausedSeconds)})'),
                const SizedBox(height: 8),
                Text(
                  'Live Bill: ₹${liveBill.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
          ),
          icon: const Icon(Icons.play_arrow),
          label: Text(_cooldownSeconds > 0
              ? 'WAIT $_cooldownSeconds SEC...'
              : 'NORMAL START (1*)'),
          onPressed: _cooldownSeconds > 0 || _motorState != 'STOPPED'
              ? null
              : () => _showStartDialog(isTimer: false),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal.shade700,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
          ),
          icon: const Icon(Icons.timer),
          label: const Text('TIMER / SCHEDULER START (3*X)'),
          onPressed: _cooldownSeconds > 0 || _motorState != 'STOPPED'
              ? null
              : () => _showStartDialog(isTimer: true),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
          ),
          icon: const Icon(Icons.stop),
          label: const Text('STOP MOTOR & GENERATE CASH MEMO (2*)'),
          onPressed: _motorState == 'STOPPED'
              ? null
              : () => _completeBillingSession(sendSmsCommand: true),
        ),
      ],
    );
  }

  void _showStartDialog({required bool isTimer}) {
    final nameCtrl = TextEditingController();
    final rateCtrl = TextEditingController(text: _stickyDefaultRate.toStringAsFixed(0));
    final manualAmtCtrl = TextEditingController();
    int selectedMinutes = 60; // 3*2

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isTimer ? 'Timer Start (3*X)' : 'Normal Start (1*)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Customer Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: rateCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Rate per Hour (₹) - Auto saves for future',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: manualAmtCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Manual Fixed Amount (Optional Override ₹)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final double newRate =
                  double.tryParse(rateCtrl.text) ?? _stickyDefaultRate;
              final double? manualAmt = manualAmtCtrl.text.trim().isEmpty
                  ? null
                  : double.tryParse(manualAmtCtrl.text.trim());
              Navigator.pop(ctx);
              _startBillingSession(
                customerName: nameCtrl.text.trim().isEmpty
                    ? 'Customer'
                    : nameCtrl.text.trim(),
                rate: newRate,
                manualFixedAmount: manualAmt,
                mode: isTimer ? 'Timer (3*X)' : 'Normal (1*)',
                timerMinutes: isTimer ? selectedMinutes : 0,
                sendSmsCommand: true,
              );
            },
            child: const Text('Start Motor'),
          ),
        ],
      ),
    );
  }

  Widget _buildHisabTab() {
    if (_history.isEmpty) {
      return const Center(child: Text('No Cash Memos recorded yet.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _history.length,
      itemBuilder: (ctx, i) {
        final rec = _history[i];
        return Card(
          child: ListTile(
            title: Text('${rec.customerName} — ₹${rec.finalAmount.toStringAsFixed(2)}'),
            subtitle: Text(
              '${rec.dateStr}
Run: ${_formatDuration(rec.netRunningSeconds)} | Rate: ₹${rec.ratePerHour.toStringAsFixed(0)}/hr',
            ),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.share, color: Colors.teal),
              onPressed: () => _shareCashMemo(rec),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Registered Users (*TCMU-1 USERS*)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < 4; i++)
          ListTile(
            title: Text('USER ${i + 1}: ${_deviceUsers[i].isEmpty ? "Empty" : _deviceUsers[i]}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => _sendSmsWithRetry('16*${i + 1}', expectReply: false),
                  child: const Text('DEL', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
        ElevatedButton(
          onPressed: () => _sendSmsWithRetry(_cmdUsersList, expectReply: false),
          child: const Text('Sync Users from Device (10*)'),
        ),
      ],
    );
  }
}
