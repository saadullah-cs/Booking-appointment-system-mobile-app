import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import 'staff_login_screen.dart';

class StaffAppointmentsScreen extends StatefulWidget {
  final String staffEmail;

  const StaffAppointmentsScreen({
    super.key,
    required this.staffEmail,
  });

  @override
  State<StaffAppointmentsScreen> createState() => _StaffAppointmentsScreenState();
}

class _StaffAppointmentsScreenState extends State<StaffAppointmentsScreen> {
  bool _allowStaffView = true;
  bool _isLoading = true;
  List<Map<String, dynamic>> _appointments = [];
  StreamSubscription? _configSubscription;
  StreamSubscription? _appointmentsSubscription;
  StreamSubscription? _staffUserSubscription;

  @override
  void initState() {
    super.initState();
    _loadCachedAppointments().then((_) {
      if (mounted) {
        _listenToData();
      }
    });
  }

  Future<void> _loadCachedAppointments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString('cached_appointments');
      if (cachedStr != null && cachedStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(cachedStr);
        final list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        setState(() {
          _appointments = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load cached appointments: $e');
    }
  }

  @override
  void dispose() {
    _configSubscription?.cancel();
    _appointmentsSubscription?.cancel();
    _staffUserSubscription?.cancel();
    super.dispose();
  }

  void _listenToData() {
    // 1. Listen to doctor's global access toggle
    _configSubscription = FirebaseFirestore.instance
        .collection('settings')
        .doc('clinic_config')
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      if (doc.exists && doc.data() != null) {
        setState(() {
          _allowStaffView = doc.data()?['allowStaffView'] != false; // defaults to true
        });
      } else {
        setState(() {
          _allowStaffView = true;
        });
      }
    }, onError: (err) {
      debugPrint('Error listening to clinic config: $err');
      // If error (e.g. permission/offline), fallback to true so staff can work offline if needed
    });

    // 2. Listen to appointments list
    _appointmentsSubscription = FirebaseFirestore.instance
        .collection('appointments')
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;
      
      final list = snapshot.docs.map((d) {
        final data = d.data();
        return {
          ...data,
          'id': d.id,
        };
      }).toList();

      // Sort in-memory descending by scheduledAt
      list.sort((a, b) {
        final aStr = a['scheduledAt']?.toString() ?? '';
        final bStr = b['scheduledAt']?.toString() ?? '';
        return bStr.compareTo(aStr);
      });

      setState(() {
        _appointments = list;
        _isLoading = false;
      });

      // Save to cache
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_appointments', jsonEncode(list));
      } catch (e) {
        debugPrint('Failed to save appointments cache: $e');
      }
    }, onError: (err) {
      debugPrint('Error listening to appointments: $err');
      setState(() => _isLoading = false);
    });

    // 3. Listen to staff user document for real-time security check (force-logout)
    _staffUserSubscription = FirebaseFirestore.instance
        .collection('staff')
        .doc(widget.staffEmail)
        .snapshots()
        .listen((doc) async {
      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final localPassword = prefs.getString('offline_password_${widget.staffEmail}');
      
      bool mustLogout = false;
      String logoutReason = '';

      if (!doc.exists || doc.data() == null) {
        mustLogout = true;
        logoutReason = 'Your staff account has been deleted by the administrator.';
      } else {
        final dbPassword = doc.data()?['password']?.toString() ?? '';
        if (localPassword != null && dbPassword != localPassword) {
          mustLogout = true;
          logoutReason = 'Your password has been changed by the administrator. Please log in again.';
        }
      }

      if (mustLogout) {
        // Clear session
        await prefs.remove('is_staff_logged_in');
        await prefs.remove('logged_in_staff_email');
        if (localPassword != null) {
          await prefs.remove('offline_password_${widget.staffEmail}');
        }

        // Cancel subscriptions
        _configSubscription?.cancel();
        _appointmentsSubscription?.cancel();
        _staffUserSubscription?.cancel();

        if (!mounted) return;

        // Show SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              logoutReason,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Force navigate to Login Screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const StaffLoginScreen()),
        );
      }
    }, onError: (err) {
      debugPrint('Error listening to staff user document: $err');
    });
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign Out', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to sign out from the Staff Portal?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sign Out', style: GoogleFonts.poppins(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_staff_logged_in');
    await prefs.remove('logged_in_staff_email');

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const StaffLoginScreen()),
    );
  }

  String _formatDateTime(String? isoStr) {
    if (isoStr == null || isoStr.isEmpty) return 'Date & Time Pending';
    try {
      final dt = DateTime.parse(isoStr);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} - $hour:$minute $ampm';
    } catch (_) {
      return isoStr;
    }
  }

  Color _statusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'confirmed': return const Color(0xFF00A86B);
      case 'cancelled': return const Color(0xFFEF4444);
      case 'completed': return const Color(0xFF3B82F6);
      default: return const Color(0xFFF59E0B);
    }
  }

  Color _statusBgColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'confirmed': return const Color(0xFFE6F7F1);
      case 'cancelled': return const Color(0xFFFEE2E2);
      case 'completed': return const Color(0xFFEFF6FF);
      default: return const Color(0xFFFFFBEB);
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF0E7490);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Booked Appointments',
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF0D1B35)),
            ),
            Text(
              'Staff: ${widget.staffEmail}',
              style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'Sign Out',
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(brandColor)))
          : !_allowStaffView
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Container(
                      padding: const EdgeInsets.all(28.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.block_flipped, size: 40, color: Colors.redAccent),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Access Suspended',
                            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0D1B35)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'The clinic Administrator has disabled real-time booking access for staff portals. Please check with the doctor.',
                            style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : _appointments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            'No Bookings Scheduled',
                            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF0D1B35)),
                          ),
                          Text(
                            'New appointments will appear here automatically.',
                            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        // Simply triggers another read operation, which updates the stream
                        await Future.delayed(const Duration(milliseconds: 600));
                      },
                      color: brandColor,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16.0),
                        itemCount: _appointments.length,
                        itemBuilder: (ctx, index) {
                          final apt = _appointments[index];
                          final name = apt['patientName']?.toString() ?? 'Unknown Patient';
                          final timeStr = _formatDateTime(apt['scheduledAt']?.toString());
                          final status = apt['status']?.toString() ?? 'Pending';
                          final type = apt['type']?.toString() ?? 'General Appointment';
                          final phone = apt['phoneNumber']?.toString() ?? '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF0D1B35),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _statusBgColor(status),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: _statusColor(status),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  type,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: brandColor,
                                  ),
                                ),
                                const Divider(height: 20),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time_rounded, size: 16, color: Colors.grey),
                                    const SizedBox(width: 8),
                                    Text(
                                      timeStr,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                if (phone.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.phone_iphone_rounded, size: 16, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Text(
                                        phone,
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
