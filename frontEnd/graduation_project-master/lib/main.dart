import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ─── Global Notifications Plugin ─────────────────────────────────────────────
final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
final FlutterTts _flutterTts = FlutterTts();

// ─── App Entry Point ──────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize local notifications for foreground messages
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

  await _localNotificationsPlugin.initialize(
    settings: initSettings,
    onDidReceiveNotificationResponse: (response) {
      // Handle notification tap
    },
  );

  // Request notification permissions
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );

  print('User granted permission: ${settings.authorizationStatus}');

  // Get FCM token and send to backend
  String? token = await messaging.getToken();
  if (token != null) {
    print('FCM Token: $token');
    await _sendTokenToBackend(token);
  }

  // Listen for token refresh
  messaging.onTokenRefresh.listen((newToken) {
    print('FCM Token refreshed: $newToken');
    _sendTokenToBackend(newToken);
  });

  // Handle foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('Got a message whilst in the foreground!');
    print('Message data: ${message.data}');

    if (message.notification != null) {
      _localNotificationsPlugin.show(
        id: message.hashCode,
        title: message.notification!.title,
        body: message.notification!.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'automations',
            'Automations',
            channelDescription: 'Automation trigger notifications',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
          ),
        ),
      );
    }

    // Check for Calendar Reminder action in data
    if (message.data['type'] == 'calendar_reminder') {
      final text = message.data['message'] ?? "لديك تذكير جديد بالمهام اليومية";
      // We already show the notification via notification property, 
      // but we can also handle specific logic here if needed.
      print("Calendar Reminder: $text");
    }
  });

  // Handle background/terminated messages
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('Message clicked!');
  });

  // Set foreground notification presentation options
  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  runApp(const AutomationApp());
}

// ─── Send FCM Token to Backend ────────────────────────────────────────────────
Future<void> _sendTokenToBackend(String token) async {
  try {
    await http
        .post(
          Uri.parse('$_baseUrl/api/fcmtokens'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'token': token,
            'deviceInfo': 'Flutter App',
          }),
        )
        .timeout(const Duration(seconds: 10));
    print('Token registered with backend');
  } catch (e) {
    print('Failed to register token: $e');
  }
}

// ─── Base URL ─────────────────────────────────────────────────────────────────
const String _baseUrl = 'https://gentle-oranges-rescue.loca.lt';

// ─── App Widget ────────────────────────────────────────────────────────────────
class AutomationApp extends StatelessWidget {
  const AutomationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Workflow Automation',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

// ─── Main Screen with Bottom Navigation ───────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  int _pendingCount = 0;
  Timer? _pollingTimer;
  final Battery _battery = Battery();
  bool _hasTriggeredBatteryLow = false;

  final String _baseUrl = 'https://massive-sheep-94.loca.lt';

  @override
  void initState() {
    super.initState();
    _startPolling();
    _monitorBattery();
  }

  void _monitorBattery() {
    _battery.onBatteryStateChanged.listen((BatteryState state) async {
      final level = await _battery.batteryLevel;
      if (level < 20 && !_hasTriggeredBatteryLow) {
        _hasTriggeredBatteryLow = true;
        _sendExternalTrigger('BATTERY_LOW');
      } else if (level >= 20) {
        _hasTriggeredBatteryLow = false;
      }
    });
  }

  Future<void> _sendExternalTrigger(String type) async {
    try {
      await http.post(Uri.parse('$_baseUrl/api/automations/trigger/$type'));
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _checkPendingApprovals();
    _pollingTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkPendingApprovals();
    });
  }

  Future<void> _checkPendingApprovals() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/approvals/pending'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> pending = json.decode(response.body);
        final int newCount = pending.length;

        if (newCount > _pendingCount && newCount > 0) {
          await _showNotification(newCount);
        }

        if (mounted) {
          setState(() => _pendingCount = newCount);
        }
      }
    } catch (_) {}
  }

  Future<void> _showNotification(int count) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'approvals_channel',
      'Email Approvals',
      channelDescription: 'Notifications for pending email replies',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await _localNotificationsPlugin.show(
      id: 0,
      title: '📧 رد جاهز للمراجعة',
      body: 'يوجد $count رد(ود) من الذكاء الاصطناعي ينتظر موافقتك',
      notificationDetails: details,
      payload: 'approvals',
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      WorkflowBuilderScreen(baseUrl: _baseUrl),
      ApprovalsScreen(
          baseUrl: _baseUrl, onApprovalChanged: _checkPendingApprovals),
    ];

    return Scaffold(
      body: screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
          if (index == 1) _checkPendingApprovals();
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome),
            label: 'الأتمتة',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _pendingCount > 0,
              label: Text('$_pendingCount'),
              child: const Icon(Icons.mark_email_unread),
            ),
            label: 'الموافقات',
          ),
        ],
      ),
    );
  }
}

// ─── Models ──────────────────────────────────────────────────────────────────
class WorkflowAction {
  String actionType;
  String actionConfig;
  int order;

  WorkflowAction({
    required this.actionType,
    this.actionConfig = '{}',
    this.order = 0,
  });

  Map<String, dynamic> toJson() => {
        'actionType': actionType,
        'actionConfig': actionConfig,
        'order': order,
      };

  factory WorkflowAction.fromJson(Map<String, dynamic> json) => WorkflowAction(
        actionType: json['actionType'] ?? 'SEND_NOTIFICATION',
        actionConfig: json['actionConfig'] ?? '{}',
        order: json['order'] ?? 0,
      );
}

// ─── Workflow Builder Screen ───────────────────────────────────────────────────
class WorkflowBuilderScreen extends StatefulWidget {
  final String baseUrl;
  const WorkflowBuilderScreen({super.key, required this.baseUrl});

  @override
  State<WorkflowBuilderScreen> createState() => _WorkflowBuilderScreenState();
}

class _WorkflowBuilderScreenState extends State<WorkflowBuilderScreen> {
  List<dynamic> _automations = [];
  bool _isLoading = false;
  String _apiStatus = "";
  String? _userEmail;
  bool _isAuthenticated = false;

  String get _apiUrl => '${widget.baseUrl}/api/automations';

  @override
  void initState() {
    super.initState();
    _loadUserAndFetch();
  }

  Future<void> _loadUserAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    _userEmail = prefs.getString('user_email');
    if (_userEmail != null) {
      await _checkAuthStatus();
    }
    _fetchAutomations();
  }

  Future<void> _checkAuthStatus() async {
    if (_userEmail == null) return;
    try {
      final response = await http.get(Uri.parse('${widget.baseUrl}/api/auth/status/$_userEmail'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() => _isAuthenticated = data['isAuthenticated'] ?? false);
      }
    } catch (_) {}
  }

  Future<void> _connectGoogle() async {
    try {
      final response = await http.get(Uri.parse('${widget.baseUrl}/api/auth/google/login'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final url = Uri.parse(data['url']);
        // Launch directly without check to avoid Android 11+ visibility issues
        await launchUrl(url, mode: LaunchMode.externalApplication);
        _showEmailInputDialog();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Server Error: ${response.statusCode}")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Connection Error: $e")),
        );
      }
    }
  }

  void _showEmailInputDialog() {
    String email = "";
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Enter your Google Email"),
        content: TextField(
          decoration: const InputDecoration(hintText: "example@gmail.com"),
          onChanged: (val) => email = val,
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              if (email.contains("@")) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('user_email', email);
                setState(() => _userEmail = email);
                Navigator.pop(context);
                await _checkAuthStatus();
                _fetchAutomations();
              }
            },
            child: const Text("Confirm"),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchAutomations() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _apiStatus = "Fetching workflows...";
    });

    try {
      // Fetch only for this user
      final url = _userEmail != null ? '$_apiUrl?email=$_userEmail' : _apiUrl;
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (mounted) {
          setState(() {
            _automations = body is List ? body : [];
            _apiStatus = "Found ${_automations.length} workflow(s).";
          });
        }
      } else {
        if (mounted) setState(() => _apiStatus = "Error: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) setState(() => _apiStatus = "Network Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createWorkflow(
      String name, String triggerType, List<WorkflowAction> actions,
      {String? timeString}) async {
    setState(() {
      _isLoading = true;
      _apiStatus = "Creating workflow...";
    });

    final newWorkflow = {
      "name": name,
      "isActive": true,
      "userEmail": _userEmail,
      "triggerType": triggerType,
      "triggerConfig":
          triggerType == 'TIME' ? '{"time": "${timeString ?? '14:30'}"}' : '{}',
      "actions": actions.map((a) => a.toJson()).toList(),
    };

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(newWorkflow),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) setState(() => _apiStatus = "Workflow created!");
        await _fetchAutomations();
      } else {
        if (mounted) setState(() => _apiStatus = "Error: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) setState(() => _apiStatus = "Network Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteWorkflow(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this workflow?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final response = await http.delete(Uri.parse('$_apiUrl/$id'));
      if (response.statusCode == 200 || response.statusCode == 204) {
        if (mounted) setState(() => _apiStatus = "Workflow deleted.");
        await _fetchAutomations();
      } else {
        if (mounted) setState(() => _apiStatus = "Delete Error: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) setState(() => _apiStatus = "Network Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_email');
    setState(() {
      _userEmail = null;
      _isAuthenticated = false;
      _automations = [];
    });
    _fetchAutomations();
  }

  void _showCreateDialog() {
    String name = "My Workflow";
    String selectedTrigger = "EMAIL_RECEIVED";
    TimeOfDay? selectedTime;
    List<WorkflowAction> actions = [WorkflowAction(actionType: "SEND_EMAIL")];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text("Build New Workflow"),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    decoration:
                        const InputDecoration(labelText: "Workflow Name"),
                    onChanged: (val) => name = val,
                  ),
                  const SizedBox(height: 20),
                  const Text("1. Trigger (Starts the flow)",
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  DropdownButton<String>(
                    value: selectedTrigger,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                          value: "EMAIL_RECEIVED",
                          child: Text("When getting Gmail email")),
                      DropdownMenuItem(
                          value: "TIME",
                          child: Text("At a specific Time")),
                      DropdownMenuItem(
                          value: "BATTERY_LOW",
                          child: Text("When Battery < 20%")),
                    ],
                    onChanged: (val) =>
                        setStateDialog(() => selectedTrigger = val!),
                  ),
                  if (selectedTrigger == "TIME") ...[
                    Row(
                      children: [
                        Text(selectedTime == null
                            ? "Time: --:--"
                            : "Time: ${selectedTime!.format(context)}"),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                                context: context, initialTime: TimeOfDay.now());
                            if (t != null) setStateDialog(() => selectedTime = t);
                          },
                          child: const Text("Set Time"),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text("2. Actions (Sequential steps)",
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                  const SizedBox(height: 10),
                  ...actions.asMap().entries.map((entry) {
                    int idx = entry.key;
                    WorkflowAction action = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.deepPurple.shade100),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(radius: 12, child: Text("${idx + 1}")),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButton<String>(
                                  value: action.actionType,
                                  isExpanded: true,
                                  items: const [
                                    DropdownMenuItem(value: "SEND_EMAIL", child: Text("Gemini AI Reply")),
                                    DropdownMenuItem(value: "SEND_NOTIFICATION", child: Text("Send Push Notif")),
                                    DropdownMenuItem(value: "CALENDAR_REMINDER", child: Text("Calendar Reminder")),
                                  ],
                                  onChanged: (val) => setStateDialog(() => action.actionType = val!),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                onPressed: actions.length > 1 ? () => setStateDialog(() => actions.removeAt(idx)) : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                  TextButton.icon(
                    onPressed: () => setStateDialog(() => actions.add(WorkflowAction(actionType: "SEND_NOTIFICATION", order: actions.length))),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text("Add Another Action"),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                String? timeStr;
                if (selectedTime != null) {
                  timeStr = "${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}";
                }
                for (int i = 0; i < actions.length; i++) {
                  actions[i].order = i;
                }
                _createWorkflow(name, selectedTrigger, actions, timeString: timeStr);
              },
              child: const Text("Create Workflow"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(''), // Empty title for more space
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (!_isAuthenticated)
            TextButton.icon(
              onPressed: _connectGoogle,
              icon: const Icon(Icons.login),
              label: const Text("Connect"),
            ),
          if (_isAuthenticated)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Icon(Icons.check_circle, color: Colors.green),
            ),
          if (_userEmail != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.account_circle, size: 30),
              onSelected: (val) {
                if (val == 'logout') _logout();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text("Logged in as: $_userEmail", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: Colors.red),
                      SizedBox(width: 8),
                      Text("Logout"),
                    ],
                  ),
                ),
              ],
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _fetchAutomations())
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 16, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Expanded(child: Text(_apiStatus, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
              ],
            ),
          ),
          Expanded(
            child: _isLoading && _automations.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _automations.isEmpty
                    ? const Center(child: Text("No workflows yet. Start building!"))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _automations.length,
                        itemBuilder: (context, index) {
                          final auto = _automations[index];
                          final List actions = auto['actions'] ?? [];
                          
                          return Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            margin: const EdgeInsets.only(bottom: 20),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.hub, color: Colors.blue),
                                      const SizedBox(width: 10),
                                      Text(auto['name'] ?? 'Unnamed', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                        onPressed: () => _deleteWorkflow(auto['id']),
                                      ),
                                      Switch(value: auto['isActive'] ?? true, onChanged: (_) {}),
                                    ],
                                  ),
                                  const Divider(),
                                  const SizedBox(height: 10),
                                  _buildNode(
                                    title: "Trigger: ${auto['triggerType']}",
                                    color: Colors.green.shade100,
                                    icon: Icons.bolt,
                                    isFirst: true,
                                  ),
                                  ...actions.map((act) => _buildNode(
                                    title: "Action: ${act['actionType']}",
                                    color: Colors.purple.shade50,
                                    icon: Icons.play_arrow,
                                  )),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text("New Workflow"),
      ),
    );
  }

  Widget _buildNode({required String title, required Color color, required IconData icon, bool isFirst = false}) {
    return Column(
      children: [
        if (!isFirst) 
          Container(
            height: 20,
            width: 2,
            color: Colors.grey.shade300,
          ),
        if (!isFirst)
          Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey.shade400),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}


// ─── Approvals Screen ─────────────────────────────────────────────────────────
class ApprovalsScreen extends StatefulWidget {
  final String baseUrl;
  final VoidCallback onApprovalChanged;

  const ApprovalsScreen({
    super.key,
    required this.baseUrl,
    required this.onApprovalChanged,
  });

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  List<dynamic> _pending = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchPending();
  }

  Future<void> _fetchPending() async {
    setState(() => _isLoading = true);
    try {
      final response = await http
          .get(Uri.parse('${widget.baseUrl}/api/approvals/pending'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        setState(() => _pending = json.decode(response.body));
      }
    } catch (_) {} finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _approve(String id) async {
    try {
      final response = await http.post(
          Uri.parse('${widget.baseUrl}/api/approvals/$id/approve'));

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الإرسال بنجاح!'),
              backgroundColor: Colors.green),
        );
      } else {
        final error = json.decode(response.body)['error'] ?? 'فشل الإرسال';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $error'), backgroundColor: Colors.red),
        );
      }
      widget.onApprovalChanged();
      await _fetchPending();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في الاتصال: $e')),
      );
    }
  }

  Future<void> _reject(String id) async {
    try {
      final response = await http.post(
          Uri.parse('${widget.baseUrl}/api/approvals/$id/reject'));

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الرفض بنجاح'),
              backgroundColor: Colors.orange),
        );
      }
      widget.onApprovalChanged();
      await _fetchPending();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في الاتصال: $e')),
      );
    }
  }

  Future<void> _approveAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد قبول الجميع'),
        content: const Text('هل تريد إرسال جميع الردود المنتظرة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إرسال الجميع'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final response = await http
          .post(Uri.parse('${widget.baseUrl}/api/approvals/approve-all'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'اكتملت العملية. المرسل: ${data['sent']}, الفاشل: ${data['failed']}'),
              backgroundColor: Colors.blue),
        );
      }
      widget.onApprovalChanged();
      await _fetchPending();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _rejectAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد رفض الجميع'),
        content: const Text('هل تريد رفض جميع الردود المنتظرة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('رفض الجميع'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await http.post(Uri.parse('${widget.baseUrl}/api/approvals/reject-all'));
      widget.onApprovalChanged();
      await _fetchPending();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الموافقة على الردود'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          TextButton.icon(
            onPressed: _pending.isEmpty ? null : _approveAll,
            icon: const Icon(Icons.done_all, color: Colors.green),
            label: const Text('قبول الكل',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ),
          TextButton.icon(
            onPressed: _pending.isEmpty ? null : _rejectAll,
            icon: const Icon(Icons.close, color: Colors.red),
            label: const Text('رفض الكل',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchPending),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pending.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64, color: Colors.green),
                      SizedBox(height: 12),
                      Text('لا توجد ردود تنتظر موافقتك!',
                          style: TextStyle(fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _pending.length,
                  itemBuilder: (context, index) {
                    final item = _pending[index];
                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.email, color: Colors.deepPurple),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item['senderEmail'] ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item['subject'] ?? '',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                            const Divider(height: 24),
                            const Text('الرد المقترح من الذكاء الاصطناعي:',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(item['proposedReply'] ?? ''),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _reject(item['id']),
                                    icon: const Icon(Icons.close,
                                        color: Colors.red),
                                    label: const Text('رفض',
                                        style: TextStyle(color: Colors.red)),
                                    style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                            color: Colors.red)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _approve(item['id']),
                                    icon: const Icon(Icons.send),
                                    label: const Text('إرسال'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
