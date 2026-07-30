import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/app_preferences.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();

  String _currentEmail = '';
  String _currentName = '';
  bool _isStaff = false;
  bool _isLoading = true;
  bool _isSending = false;
  bool _showScrollBtn = false;
  int _unreadCount = 0;
  Timestamp? _lastSeen;
  List<QueryDocumentSnapshot>? _prevDocs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollCtrl.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _msgCtrl.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _markSeen();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _markSeen();
  }

  void _onScroll() {
    final far = _scrollCtrl.hasClients && _scrollCtrl.position.pixels > 250;
    if (far != _showScrollBtn) setState(() => _showScrollBtn = far);
  }

  Future<void> _init() async {
    final prefs = await AppPreferences.instance.prefs;
    final isStaff = prefs.getBool('is_staff_logged_in') ?? false;
    if (isStaff) {
      final email = prefs.getString('logged_in_staff_email') ?? 'staff@gct.com';
      setState(() {
        _isStaff = true;
        _currentEmail = email;
        _currentName = 'Staff (${email.split('@').first})';
        _isLoading = false;
      });
    } else {
      final user = FirebaseAuth.instance.currentUser;
      setState(() {
        _isStaff = false;
        _currentEmail = user?.email ?? 'doctor@gct.com';
        _currentName = 'Doctor';
        _isLoading = false;
      });
    }
    await _loadLastSeen();
    await _markSeen();
  }

  Future<void> _loadLastSeen() async {
    if (_currentEmail.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('chats')
          .doc('group_chat')
          .collection('user_meta')
          .doc(_currentEmail)
          .get();
      if (doc.exists) {
        setState(() => _lastSeen = doc.data()?['lastSeenAt'] as Timestamp?);
      }
    } catch (_) {}
  }

  Future<void> _markSeen() async {
    if (_currentEmail.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc('group_chat')
          .collection('user_meta')
          .doc(_currentEmail)
          .set({
            'lastSeenAt': FieldValue.serverTimestamp(),
            'userEmail': _currentEmail,
            'userName': _currentName,
          }, SetOptions(merge: true));
      if (mounted) {
        setState(() {
          _lastSeen = Timestamp.now();
          _unreadCount = 0;
        });
      }
    } catch (_) {}
  }

  void _handleNewDocs(List<QueryDocumentSnapshot> docs) {
    if (_prevDocs == null) {
      _prevDocs = docs;
      return;
    }
    final prevIds = _prevDocs!.map((d) => d.id).toSet();
    for (final doc in docs.where((d) => !prevIds.contains(d.id))) {
      final data = doc.data() as Map<String, dynamic>;
      final sender = data['senderEmail'] as String? ?? '';
      if (sender != _currentEmail) {
        final name = data['senderName'] as String? ?? 'Someone';
        final text = data['text'] as String? ?? '📎';
        final isStaff = data['isStaff'] as bool? ?? false;
        NotificationService().showChatNotification(
          senderName: name,
          message: text,
          isStaff: isStaff,
        );
        if (_showScrollBtn) setState(() => _unreadCount++);
      }
    }
    _prevDocs = docs;
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    _msgCtrl.clear();
    try {
      final ref = await FirebaseFirestore.instance
          .collection('chats')
          .doc('group_chat')
          .collection('messages')
          .add({
            'senderEmail': _currentEmail,
            'senderName': _currentName,
            'text': text,
            'timestamp': FieldValue.serverTimestamp(),
            'isStaff': _isStaff,
            'messageType': 'text',
            'status': 'sent',
          });
      unawaited(_updateStatus(ref.id, 'delivered', ms: 800));
      await Future.delayed(const Duration(milliseconds: 120));
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      _snack('Failed to send: $e', err: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _updateStatus(String id, String status, {int ms = 0}) async {
    if (ms > 0) await Future.delayed(Duration(milliseconds: ms));
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc('group_chat')
          .collection('messages')
          .doc(id)
          .update({'status': status});
    } catch (_) {}
  }

  Future<void> _delete(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc('group_chat')
          .collection('messages')
          .doc(docId)
          .delete();
    } catch (e) {
      _snack('Failed to delete: $e', err: true);
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear All Chat',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Delete all messages? This cannot be undone.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Clear',
              style: GoogleFonts.poppins(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('chats')
          .doc('group_chat')
          .collection('messages')
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      _snack('Chat cleared.');
    } catch (e) {
      _snack('Failed: $e', err: true);
    }
  }

  void _showOptions(String docId, String text, bool isMe, bool canDelete) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: AppColors.primary),
              title: Text(
                'Copy message',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(context);
                _snack('Copied to clipboard');
              },
            ),
            if (canDelete)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: Text(
                  'Delete message',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: Colors.redAccent,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _delete(docId);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        ),
        backgroundColor: err ? Colors.redAccent : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(d.year, d.month, d.day);
    if (msgDay == today) return 'Today';
    if (msgDay == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('MMMM d, y').format(d);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5FB);

    return Scaffold(
      backgroundColor: bg,
      appBar: _buildAppBar(isDark),
      body: Column(
        children: [
          _buildBanner(),
          Expanded(child: _buildList(isDark, bg)),
          _buildInput(isDark),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 0,

      // 1. Leading back button
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
          size: 20,
        ),
        onPressed: () {
          // 2. Pop if it can, otherwise hard-route to dashboard
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/dashboard');
          }
        },
      ),

      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.forum_rounded,
              color: Colors.white,
              size: 17,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Clinic Chat',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    'Active · Clinic Team',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (!_isStaff)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (v) {
              if (v == 'clear') _clearAll();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    const Icon(
                      Icons.delete_sweep_rounded,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Clear All Chat',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.07),
            AppColors.accent.withValues(alpha: 0.03),
          ],
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 12, color: AppColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Private clinic team chat · End-to-end secured',
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            'You: $_currentName',
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(bool isDark, Color bg) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc('group_chat')
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (snap.connectionState == ConnectionState.active) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _handleNewDocs(docs),
          );
        }
        if (docs.isEmpty) return _emptyState();

        // Calculate first unread index
        int firstUnreadIdx = -1;
        if (_lastSeen != null) {
          for (int i = 0; i < docs.length; i++) {
            final d = docs[i].data() as Map<String, dynamic>;
            final ts = d['timestamp'] as Timestamp?;
            final se = d['senderEmail'] as String? ?? '';
            if (ts != null &&
                ts.compareTo(_lastSeen!) > 0 &&
                se != _currentEmail) {
              firstUnreadIdx = i;
            }
          }
        }
        final unreadTotal = firstUnreadIdx + 1;

        return Stack(
          children: [
            ListView.builder(
              controller: _scrollCtrl,
              reverse: true,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final data = docs[i].data() as Map<String, dynamic>;
                final id = docs[i].id;
                final senderEmail = data['senderEmail'] as String? ?? '';
                final senderName = data['senderName'] as String? ?? '';
                final text = data['text'] as String? ?? '';
                final ts = data['timestamp'] as Timestamp?;
                final isMsgStaff = data['isStaff'] as bool? ?? false;
                final status = data['status'] as String? ?? 'sent';
                final isMe = senderEmail == _currentEmail;
                final canDelete = isMe || (!_isStaff && isMsgStaff);

                // Date separator
                Widget? dateSep;
                if (ts != null) {
                  final d = ts.toDate().toLocal();
                  bool showDate = i == docs.length - 1;
                  if (!showDate && i < docs.length - 1) {
                    final nd = docs[i + 1].data() as Map<String, dynamic>;
                    final nts = (nd['timestamp'] as Timestamp?)
                        ?.toDate()
                        .toLocal();
                    if (nts != null) {
                      final a = DateTime(d.year, d.month, d.day);
                      final b = DateTime(nts.year, nts.month, nts.day);
                      showDate = a != b;
                      if (showDate) dateSep = _dateSep(_dateLabel(nts));
                    }
                  }
                  if (i == docs.length - 1) dateSep = _dateSep(_dateLabel(d));
                }

                return Column(
                  children: [
                    if (i == firstUnreadIdx && unreadTotal > 0)
                      _unreadDivider(unreadTotal),
                    ?dateSep,
                    _bubble(
                      docId: id,
                      isMe: isMe,
                      senderName: senderName,
                      text: text,
                      ts: ts,
                      isMsgStaff: isMsgStaff,
                      status: status,
                      canDelete: canDelete,
                      isDark: isDark,
                    ),
                  ],
                );
              },
            ),
            if (_showScrollBtn)
              Positioned(
                bottom: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () {
                    _scrollCtrl.animateTo(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                    _markSeen();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        if (_unreadCount > 0)
                          Positioned(
                            top: -8,
                            right: -8,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                _unreadCount > 9 ? '9+' : '$_unreadCount',
                                style: GoogleFonts.poppins(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 52,
              color: AppColors.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Be the first to say something!',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _dateSep(String label) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: Colors.grey[600],
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _unreadDivider(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.primary.withValues(alpha: 0.4))),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count unread message${count > 1 ? 's' : ''}',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Divider(color: AppColors.primary.withValues(alpha: 0.4))),
        ],
      ),
    );
  }

  Widget _bubble({
    required String docId,
    required bool isMe,
    required String senderName,
    required String text,
    required Timestamp? ts,
    required bool isMsgStaff,
    required String status,
    required bool canDelete,
    required bool isDark,
  }) {
    final timeStr = ts != null
        ? DateFormat('hh:mm a').format(ts.toDate().toLocal())
        : '';
    final bubbleBg = isDark ? const Color(0xFF1E293B) : Colors.grey[200]!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onLongPress: () => _showOptions(docId, text, isMe, canDelete),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) ...[
              CircleAvatar(
                radius: 15,
                backgroundColor: isMsgStaff
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.accent.withValues(alpha: 0.15),
                child: Icon(
                  isMsgStaff
                      ? Icons.badge_rounded
                      : Icons.local_hospital_rounded,
                  size: 14,
                  color: isMsgStaff ? AppColors.primary : AppColors.accent,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 3),
                      child: Text(
                        senderName,
                        style: GoogleFonts.poppins(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isMsgStaff
                              ? AppColors.primary
                              : AppColors.accent,
                        ),
                      ),
                    ),
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: isMe
                          ? const LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primaryDark,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isMe ? null : bubbleBg,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: isMe
                            ? const Radius.circular(18)
                            : const Radius.circular(4),
                        bottomRight: isMe
                            ? const Radius.circular(4)
                            : const Radius.circular(18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          text,
                          style: GoogleFonts.poppins(
                            color: isMe
                                ? Colors.white
                                : (isDark
                                      ? Colors.white.withValues(alpha: 0.9)
                                      : Colors.black87),
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeStr,
                              style: GoogleFonts.poppins(
                                color: isMe ? Colors.white60 : Colors.grey[500],
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              Icon(
                                status == 'seen'
                                    ? Icons.done_all_rounded
                                    : status == 'delivered'
                                    ? Icons.done_all_rounded
                                    : Icons.done_rounded,
                                size: 13,
                                color: status == 'seen'
                                    ? Colors.lightBlueAccent
                                    : Colors.white70,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isMe) ...[
              const SizedBox(width: 6),
              CircleAvatar(
                radius: 15,
                backgroundColor: _isStaff
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.accent.withValues(alpha: 0.15),
                child: Icon(
                  _isStaff ? Icons.badge_rounded : Icons.local_hospital_rounded,
                  size: 14,
                  color: _isStaff ? AppColors.primary : AppColors.accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInput(bool isDark) {
    final inputBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: inputBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF1F5FB),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.15),
                  ),
                ),
                child: TextField(
                  controller: _msgCtrl,
                  focusNode: _focusNode,
                  style: GoogleFonts.poppins(fontSize: 14),
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 5,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'Type a message…',
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 13.5,
                      color: Colors.grey[400],
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _isSending ? null : _send,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
