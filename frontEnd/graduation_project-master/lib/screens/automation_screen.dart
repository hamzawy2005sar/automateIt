import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../models/workflow_model.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'add_workflow_screen.dart';

class AutomationScreen extends StatefulWidget {
  final String baseUrl;
  final String? userEmail;

  const AutomationScreen({super.key, required this.baseUrl, this.userEmail});

  @override
  State<AutomationScreen> createState() => AutomationScreenState();
}

class AutomationScreenState extends State<AutomationScreen> {
  bool _isLoading = false;
  List<Workflow> _workflows = [];

  @override
  void initState() {
    super.initState();
    _fetchWorkflows();
  }

  void refresh() {
    _fetchWorkflows();
  }

  @override
  void didUpdateWidget(AutomationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseUrl != widget.baseUrl) {
      _fetchWorkflows();
    }
  }

  Future<void> _fetchWorkflows() async {
    setState(() => _isLoading = true);
    try {
      final url = widget.userEmail != null 
          ? '${widget.baseUrl}/api/automations?email=${widget.userEmail}' 
          : '${widget.baseUrl}/api/automations';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _workflows = data.map((w) => Workflow.fromJson(w)).toList();
        });
      }
    } catch (e) {
      debugPrint("Error fetching workflows: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Connection Error: ${e.toString()}"),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteWorkflow(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Workflow"),
        content: const Text("Are you sure you want to delete this automation? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final response = await http.delete(Uri.parse('${widget.baseUrl}/api/automations/$id'));
        if (response.statusCode == 204 || response.statusCode == 200) {
          _fetchWorkflows();
        }
      } catch (e) {
        debugPrint("Error deleting: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildHeader()),
          _isLoading 
            ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            : _workflows.isEmpty 
              ? const SliverFillRemaining(child: Center(child: Text("No workflows yet. Start building!")))
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildWorkflowCard(_workflows[index]),
                      childCount: _workflows.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      floating: true,
      pinned: true,
      expandedHeight: 120,
      backgroundColor: AppTheme.backgroundColor,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          "AutomateIt",
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none_rounded),
          onPressed: () {},
        ),
        const SizedBox(width: 10),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Smart Workflows",
            style: AppTheme.lightTheme.textTheme.displayLarge,
          ),
          const SizedBox(height: 8),
          Text(
            "Manage your automated routines easily.",
            style: AppTheme.lightTheme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowCard(Workflow workflow) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: GlassCard(
        color: Colors.white,
        opacity: 0.9,
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildIconBox(workflow.triggerType),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            workflow.name,
                            style: AppTheme.lightTheme.textTheme.titleLarge,
                          ),
                          Text(
                            "Trigger: ${workflow.triggerType}",
                            style: AppTheme.lightTheme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: workflow.isActive,
                      onChanged: (val) {},
                      activeColor: AppTheme.primaryColor,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                      onPressed: () => _deleteWorkflow(workflow.id),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0),
                  child: Divider(height: 1, color: Colors.black12),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: workflow.actions.map((a) => _buildActionBadge(a.actionType)).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconBox(String type) {
    IconData icon;
    Color color;
    switch (type) {
      case 'EMAIL_RECEIVED':
        icon = Icons.email_rounded;
        color = Colors.blue;
        break;
      case 'TIME':
        icon = Icons.access_time_filled_rounded;
        color = Colors.orange;
        break;
      case 'BATTERY_LOW':
        icon = Icons.battery_alert_rounded;
        color = Colors.red;
        break;
      default:
        icon = Icons.bolt_rounded;
        color = AppTheme.primaryColor;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 28),
    );
  }

  Widget _buildActionBadge(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_circle_outline, size: 14, color: AppTheme.primaryColor),
          const SizedBox(width: 4),
          Text(
            type.replaceAll('_', ' '),
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
