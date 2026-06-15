import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../models/workflow_model.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AddWorkflowScreen extends StatefulWidget {
  final String baseUrl;
  final String? userEmail;

  const AddWorkflowScreen({super.key, required this.baseUrl, this.userEmail});

  @override
  State<AddWorkflowScreen> createState() => _AddWorkflowScreenState();
}

class _AddWorkflowScreenState extends State<AddWorkflowScreen> {
  String _name = "New Automation";
  String _selectedTrigger = "EMAIL_RECEIVED";
  List<WorkflowActionModel> _actions = [WorkflowActionModel(actionType: "SEND_EMAIL", order: 0, actionConfig: "{}")];
  bool _isSaving = false;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final body = {
        "name": _name,
        "isActive": true,
        "userEmail": widget.userEmail,
        "triggerType": _selectedTrigger,
        "triggerConfig": _selectedTrigger == "TIME" 
            ? json.encode({"hour": _selectedTime.hour, "minute": _selectedTime.minute})
            : "{}",
        "actions": _actions.map((a) => a.toJson()).toList(),
      };

      final response = await http.post(
        Uri.parse('${widget.baseUrl}/api/automations'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Error saving: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString()}"),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text("Create Workflow", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle("1. Basic Info"),
            _buildNameField(),
            const SizedBox(height: 30),
            _buildSectionTitle("2. Choose Trigger"),
            _buildTriggerSelector(),
            const SizedBox(height: 30),
            _buildSectionTitle("3. Actions Sequence"),
            ..._actions.asMap().entries.map((e) => _buildActionItem(e.key, e.value)),
            _buildAddActionButton(),
            const SizedBox(height: 40),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: AppTheme.lightTheme.textTheme.titleLarge),
    );
  }

  Widget _buildNameField() {
    return GlassCard(
      opacity: 0.9,
      child: TextField(
        decoration: InputDecoration(
          hintText: "Enter workflow name...",
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(20),
          hintStyle: GoogleFonts.outfit(color: AppTheme.textSecondary),
        ),
        onChanged: (val) => _name = val,
      ),
    );
  }

  Widget _buildTriggerSelector() {
    final triggers = [
      {'val': 'EMAIL_RECEIVED', 'label': 'Gmail Email Received', 'icon': Icons.email_rounded},
      {'val': 'TIME', 'label': 'Specific Time', 'icon': Icons.access_time_filled_rounded},
      {'val': 'BATTERY_LOW', 'label': 'Battery Below 20%', 'icon': Icons.battery_alert_rounded},
    ];

    return Column(
      children: [
        ...triggers.map((t) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            color: _selectedTrigger == t['val'] ? AppTheme.primaryColor.withOpacity(0.1) : Colors.white,
            border: _selectedTrigger == t['val'] ? Border.all(color: AppTheme.primaryColor, width: 2) : null,
            child: ListTile(
              leading: Icon(t['icon'] as IconData, color: _selectedTrigger == t['val'] ? AppTheme.primaryColor : AppTheme.textSecondary),
              title: Text(t['label'] as String, style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              onTap: () => setState(() => _selectedTrigger = t['val'] as String),
              trailing: _selectedTrigger == t['val'] ? const Icon(Icons.check_circle, color: AppTheme.primaryColor) : null,
            ),
          ),
        )).toList(),
        if (_selectedTrigger == "TIME") 
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: GlassCard(
              color: AppTheme.primaryColor.withOpacity(0.05),
              child: ListTile(
                leading: const Icon(Icons.timer_outlined, color: AppTheme.primaryColor),
                title: Text("Select Execution Time", style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                subtitle: Text("Currently set to: ${_selectedTime.format(context)}", style: GoogleFonts.outfit(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.edit_calendar_rounded),
                onTap: () async {
                  final picked = await showTimePicker(context: context, initialTime: _selectedTime);
                  if (picked != null) setState(() => _selectedTime = picked);
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActionItem(int index, WorkflowActionModel action) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.primaryColor,
            radius: 15,
            child: Text("${index + 1}", style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GlassCard(
              child: ListTile(
                title: Text(action.actionType.replaceAll('_', ' ')),
                subtitle: Text("Configure settings...", style: AppTheme.lightTheme.textTheme.bodySmall),
                trailing: const Icon(Icons.edit_note_rounded, color: AppTheme.primaryColor),
                onTap: () => _showActionSelector(index),
              ),
            ),
          ),
          if (_actions.length > 1)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
              onPressed: () => setState(() => _actions.removeAt(index)),
            ),
        ],
      ),
    );
  }

  void _showActionSelector(int index) {
    final availableActions = [
      {'val': 'SEND_NOTIFICATION', 'label': 'Push Notification', 'icon': Icons.notifications_active},
      {'val': 'SEND_EMAIL', 'label': 'Send Gmail Email', 'icon': Icons.email_rounded},
      {'val': 'CALENDAR_REMINDER', 'label': "Get Today's Schedule", 'icon': Icons.calendar_month_rounded},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassCard(
        borderRadius: 30,
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Select Action Type", style: AppTheme.lightTheme.textTheme.titleLarge),
              const SizedBox(height: 20),
              ...availableActions.map((a) => ListTile(
                leading: Icon(a['icon'] as IconData, color: AppTheme.primaryColor),
                title: Text(a['label'] as String),
                onTap: () {
                  setState(() {
                    _actions[index] = WorkflowActionModel(
                      actionType: a['val'] as String,
                      order: index,
                      actionConfig: "{}",
                    );
                  });
                  Navigator.pop(context);
                },
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddActionButton() {
    return TextButton.icon(
      onPressed: () => setState(() => _actions.add(WorkflowActionModel(actionType: "SEND_NOTIFICATION", order: _actions.length, actionConfig: "{}"))),
      icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryColor),
      label: Text("Add Another Action", style: GoogleFonts.outfit(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        onPressed: _isSaving ? null : _save,
        child: _isSaving 
          ? const CircularProgressIndicator(color: Colors.white) 
          : Text("Activate Workflow", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
