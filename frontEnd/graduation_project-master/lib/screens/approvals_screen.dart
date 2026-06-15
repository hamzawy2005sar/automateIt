import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ApprovalsScreen extends StatefulWidget {
  final String baseUrl;
  const ApprovalsScreen({super.key, required this.baseUrl});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  List<dynamic> _approvals = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchApprovals();
  }

  Future<void> _fetchApprovals() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('${widget.baseUrl}/api/approvals/pending'));
      if (response.statusCode == 200) {
        setState(() => _approvals = json.decode(response.body));
      }
    } catch (e) {
      debugPrint("Error fetching approvals: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAction(String id, String action) async {
    try {
      final response = await http.post(Uri.parse('${widget.baseUrl}/api/approvals/$id/$action'));
      if (response.statusCode == 200) {
        _fetchApprovals();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(action == 'approve' ? "Email sent!" : "Reply rejected"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _handleBulkAction(String action) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(Uri.parse('${widget.baseUrl}/api/approvals/$action-all'));
      if (response.statusCode == 200) {
        _fetchApprovals();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(action == 'approve' ? "All emails approved!" : "All emails rejected"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text("Pending Approvals", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryColor),
            onPressed: _fetchApprovals,
            tooltip: "Refresh list",
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: RefreshIndicator(
          onRefresh: _fetchApprovals,
          child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _approvals.isEmpty 
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 100), // زيادة البادينغ السفلي لتجنب التداخل
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _approvals.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) return _buildBulkActionsRow();
                        return _buildApprovalCard(_approvals[index - 1]);
                      },
                    ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView( // للسماح بالسحب في الحالة الفارغة
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mark_email_read_outlined, size: 80, color: AppTheme.primaryColor.withOpacity(0.3)),
            const SizedBox(height: 20),
            Text("No pending requests", style: AppTheme.lightTheme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text("You're all caught up!", style: AppTheme.lightTheme.textTheme.bodySmall),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _fetchApprovals,
              icon: const Icon(Icons.refresh),
              label: const Text("Check for updates"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulkActionsRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _handleBulkAction('approve'),
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text("Approve All"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _handleBulkAction('reject'),
              icon: const Icon(Icons.clear_all, size: 18),
              label: const Text("Reject All"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalCard(dynamic item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.person, color: Colors.white)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['senderEmail'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(item['subject'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 30),
              const Text("AI Suggested Reply:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryColor)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
                child: Text(item['proposedReply'], style: GoogleFonts.outfit(fontSize: 14)),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _handleAction(item['id'], 'approve'),
                      icon: const Icon(Icons.send, size: 18),
                      label: const Text("Approve"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _handleAction(item['id'], 'reject'),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text("Reject"),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
