import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'automation_screen.dart';
import 'approvals_screen.dart'; 

import 'add_workflow_screen.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  String _baseUrl = 'https://untaxed-curtly-raisin.ngrok-free.dev'; 
  final TextEditingController _ipController = TextEditingController();
  final GlobalKey<AutomationScreenState> _automationKey = GlobalKey<AutomationScreenState>();

  @override
  void initState() {
    super.initState();
    _loadIp().then((_) => _registerFcmToken());
  }

  Future<void> _registerFcmToken() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        debugPrint("FCM Token: $token");
        await http.post(
          Uri.parse('$_baseUrl/api/FcmTokens'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            "token": token,
            "deviceInfo": "ALI NX1 (Android 15)"
          }),
        );
        debugPrint("✅ FCM Token registered with backend");
      }
    } catch (e) {
      debugPrint("❌ Error registering FCM token: $e");
    }
  }

  Future<void> _loadIp() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _baseUrl = prefs.getString('server_url') ?? 'https://untaxed-curtly-raisin.ngrok-free.dev';
      _ipController.text = _baseUrl.replaceAll('http://', '').replaceAll(':5161', '');
    });
  }

  Future<void> _saveIp(String input) async {
    String sanitized = input.trim();
    if (sanitized.isEmpty) return;

    String newUrl;
    if (sanitized.startsWith('http://') || sanitized.startsWith('https://')) {
      newUrl = sanitized;
    } else {
      newUrl = 'http://$sanitized:5161';
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', newUrl);
    setState(() {
      _baseUrl = newUrl;
    });
  }

  void _showSettings() {
    bool isTesting = false;
    String testResult = "";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Server Settings"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _ipController,
                decoration: const InputDecoration(labelText: "Server IP Address", hintText: "e.g. 192.168.1.101"),
              ),
              const SizedBox(height: 10),
              if (isTesting) const CircularProgressIndicator(),
              if (testResult.isNotEmpty) 
                Text(testResult, style: TextStyle(color: testResult.contains("Success") ? Colors.green : Colors.red, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                String input = _ipController.text.trim();
                if (input.isEmpty) return;
                
                String testUrl;
                if (input.startsWith('http://') || input.startsWith('https://')) {
                  testUrl = input;
                } else {
                  testUrl = 'http://$input:5161';
                }
                
                // Ensure no double slash at the end
                if (testUrl.endsWith('/')) testUrl = testUrl.substring(0, testUrl.length - 1);

                setDialogState(() { isTesting = true; testResult = ""; });
                try {
                  final response = await http.get(Uri.parse('$testUrl/api/automations')).timeout(const Duration(seconds: 10));
                  setDialogState(() { testResult = "Success! Status: ${response.statusCode}"; });
                } catch (e) {
                  setDialogState(() { testResult = "Failed: ${e.toString()}"; });
                } finally {
                  setDialogState(() { isTesting = false; });
                }
              }, 
              child: const Text("Test Connection")
            ),
            TextButton(
              onPressed: () async {
                String input = _ipController.text.trim();
                if (input.isEmpty) return;
                
                String testUrl;
                if (input.startsWith('http://') || input.startsWith('https://')) {
                  testUrl = input;
                } else {
                  testUrl = 'http://$input:5161';
                }
                
                // Ensure no double slash at the end
                if (testUrl.endsWith('/')) testUrl = testUrl.substring(0, testUrl.length - 1);

                setDialogState(() { isTesting = true; testResult = ""; });
                try {
                  final response = await http.get(Uri.parse('$testUrl/api/FcmTokens/test')).timeout(const Duration(seconds: 10));
                  setDialogState(() { testResult = "Test sent! Response: ${response.statusCode}"; });
                } catch (e) {
                  setDialogState(() { testResult = "Test failed: ${e.toString()}"; });
                } finally {
                  setDialogState(() { isTesting = false; });
                }
              }, 
              child: const Text("Test Notification", style: TextStyle(color: Colors.orange))
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                _saveIp(_ipController.text);
                _registerFcmToken(); // Register again with new IP
                Navigator.pop(context);
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectedIndex == 0 ? AppBar(
        title: const Text("AutomateIt"),
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: _showSettings),
        ],
      ) : null,
      drawer: _selectedIndex == 0 ? Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: AppTheme.primaryGradient,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "AutomateIt",
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.login_rounded, color: AppTheme.primaryColor),
              title: const Text("Google Login"),
              subtitle: const Text("Required for Gmail automations"),
              onTap: () async {
                Navigator.pop(context); // Close drawer
                final url = Uri.parse('$_baseUrl/api/auth/google/login');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Could not launch login URL")),
                  );
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text("About"),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ) : null,
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 90), // ترك مساحة كافية للناف بار العائم
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                AutomationScreen(key: _automationKey, baseUrl: _baseUrl),
                ApprovalsScreen(baseUrl: _baseUrl),
              ],
            ),
          ),
          _buildBottomNavBar(),
        ],
      ),
      floatingActionButton: _selectedIndex == 0 ? _buildFAB() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildFAB() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 90), // ارفعه فوق الناف بار
      child: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => AddWorkflowScreen(baseUrl: _baseUrl)),
            );
            
            if (result == true) {
              _automationKey.currentState?.refresh();
            }
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text("New Workflow", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(24),
        height: 70,
        decoration: BoxDecoration(
          color: AppTheme.secondaryColor,
          borderRadius: BorderRadius.circular(35),
          boxShadow: [
            BoxShadow(
              color: AppTheme.secondaryColor.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(0, Icons.auto_awesome_rounded, "Workflows"),
            _buildNavItem(1, Icons.mark_email_unread_rounded, "Approvals"),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    bool isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
              size: 24,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
