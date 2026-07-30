import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import '../utils/import_export_service.dart';
import '../../services/app_preferences.dart';

import '../../models/payment.dart';
import '../shared/widgets/app_shell_scaffold.dart';
import '../shared/widgets/premium_card.dart';
import 'payment_repository.dart';
import '../../theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/repository_providers.dart';
import '../../services/notification_service.dart';
import 'package:printing/printing.dart';
import '../appointments/pdf_generator.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen>
    with SingleTickerProviderStateMixin {
  PaymentRepository get _repository => ref.read(paymentRepositoryProvider);
  final _patientController = TextEditingController();
  final _amountController = TextEditingController();
  final _paidAmountController = TextEditingController();
  final _noteController = TextEditingController();
  final _searchController = TextEditingController();
  final _patientFocusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();
  DateTime? _reminderDate;

  Future<void> _exportPayments() async {
    try {
      final header = [
        'Payment ID',
        'Patient Name',
        'Amount (PKR)',
        'Payment Method',
        'Status',
        'Note/Details',
        'Payment Date',
      ];
      final rows = <List<dynamic>>[header];
      for (final payment in _payments) {
        rows.add([
          payment.id,
          payment.patientName,
          payment.amount,
          payment.method,
          payment.status,
          payment.note,
          DateFormat('yyyy-MM-dd HH:mm').format(payment.paidAt),
        ]);
      }

      final success = await ImportExportService.exportExcel(
        context: context,
        defaultFileName: 'gct_payments.xlsx',
        sheets: {'Payments': rows},
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payments exported to Excel successfully! 💾'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _importPayments() async {
    try {
      final excel = await ImportExportService.importExcel(context: context);
      if (excel == null) return;

      final rows = ImportExportService.parseSheet(
        excel: excel,
        sheetName: 'Payments',
      );
      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No payments sheet found or sheet is empty.'),
            ),
          );
        }
        return;
      }

      final List<Payment> imported = [];
      for (final row in rows) {
        final id = row['Payment ID']?.toString() ?? _uuid.v4();
        final patientName = row['Patient Name']?.toString() ?? '';
        final amount =
            double.tryParse(row['Amount (PKR)']?.toString() ?? '0') ?? 0.0;
        final method = row['Payment Method']?.toString() ?? 'Cash';
        final status = row['Status']?.toString() ?? 'Paid';
        final note = row['Note/Details']?.toString() ?? '';

        DateTime paidAt;
        final rawDate = row['Payment Date'];
        if (rawDate != null) {
          paidAt = DateTime.tryParse(rawDate.toString()) ?? DateTime.now();
        } else {
          paidAt = DateTime.now();
        }

        if (patientName.isNotEmpty) {
          final double pAmt = status.toLowerCase() == 'paid' ? amount : 0.0;
          imported.add(
            Payment(
              id: id,
              patientName: patientName,
              amount: amount,
              paidAmount: pAmt,
              paidAt: paidAt,
              method: method,
              status: status,
              note: note,
            ),
          );
        }
      }

      final prefs = await AppPreferences.instance.prefs;
      await prefs.setString(
        'clinic_patient_payments',
        jsonEncode(imported.map((item) => item.toJson()).toList()),
      );

      await _loadPayments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payments imported successfully! 🔄')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: ${e.toString()}')),
        );
      }
    }
  }

  final Uuid _uuid = const Uuid();
  late TabController _tabController;

  List<Payment> _payments = [];
  bool _isLoading = false;
  String _method = 'Cash';
  String _status = 'Paid';
  String _filterStatus = 'All';
  String _selectedDuration = 'All';
  String _selectedMethodFilter = 'All';
  String _searchQuery = '';
  DateTimeRange? _customDateRange;
  List<String> _patientSuggestions = [];
  bool _showFilters = false;

  static const _methods = [
    'Cash',
    'Card',
    'Bank Transfer',
    'JazzCash',
    'EasyPaisa',
  ];
  static const _statuses = ['Paid', 'Partial', 'Pending'];
  static const _filterOptions = ['All', 'Paid', 'Partial', 'Pending'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPayments();
  }

  @override
  void dispose() {
    _patientController.dispose();
    _amountController.dispose();
    _paidAmountController.dispose();
    _noteController.dispose();
    _searchController.dispose();
    _patientFocusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPayments() async {
    final data = await _repository.loadPayments();
    List<String> suggestions = [];
    try {
      final appointments = await ref
          .read(appointmentRepositoryProvider)
          .loadAppointments();
      suggestions = appointments.map((a) => a.patientName).toSet().toList();
      suggestions.sort();
    } catch (e) {
      debugPrint('Error loading suggestions: $e');
    }
    if (!mounted) return;
    setState(() {
      _payments = data;
      _patientSuggestions = suggestions;
      _isLoading = false;
    });
  }

  Future<void> _selectCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange:
          _customDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
    );
    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _selectedDuration = 'Custom';
      });
    }
  }

  Future<void> _selectReminderDate(
    BuildContext context, {
    void Function(DateTime)? onSelected,
  }) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate != null && context.mounted) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 9, minute: 0),
      );
      if (pickedTime != null) {
        final reminder = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        if (onSelected != null) {
          onSelected(reminder);
        } else {
          setState(() {
            _reminderDate = reminder;
          });
        }
      }
    }
  }

  Future<void> _savePayment() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final paidAmount = double.tryParse(_paidAmountController.text.trim()) ?? 0;

    String finalStatus = _status;
    if (paidAmount >= amount) {
      finalStatus = 'Paid';
    } else if (paidAmount == 0) {
      finalStatus = 'Pending';
    } else {
      finalStatus = 'Partial';
    }

    final pId = _uuid.v4();
    final patientName = _patientController.text.trim();

    await _repository.savePayment(
      Payment(
        id: pId,
        patientName: patientName,
        amount: amount,
        paidAmount: paidAmount,
        paidAt: DateTime.now(),
        method: _method,
        status: finalStatus,
        note: _noteController.text.trim(),
        reminderDate: _reminderDate,
      ),
    );

    // Handle payment notifications
    try {
      // 1. Immediate payment success notification
      await NotificationService().showLocalNotification(
        'Payment Recorded 💳',
        'Received PKR ${paidAmount.toStringAsFixed(0)} of PKR ${amount.toStringAsFixed(0)} from $patientName.',
        payload: '/payments',
      );

      // 2. Schedule balance collection reminder if there is outstanding amount and a reminder date is set
      if (_reminderDate != null && paidAmount < amount) {
        final remaining = amount - paidAmount;
        await NotificationService().scheduleLocalNotification(
          id: NotificationService.getPaymentReminderId(pId),
          title: 'Collect Outstanding Balance 💰',
          body:
              'Collect outstanding balance of PKR ${remaining.toStringAsFixed(0)} from $patientName.',
          scheduledDate: _reminderDate!,
          payload: '/payments',
        );
      }
    } catch (e) {
      debugPrint('Payment notification failed: $e');
    }

    _patientController.clear();
    _amountController.clear();
    _paidAmountController.clear();
    _noteController.clear();
    setState(() {
      _reminderDate = null;
      _method = 'Cash';
      _status = 'Paid';
    });
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Payment saved ✅')));
    final width = MediaQuery.of(context).size.width;
    if (width <= 750) {
      _tabController.animateTo(1);
    }
    _loadPayments();
  }

  Future<void> _printReceipt(Payment p) async {
    try {
      final bytes = await generatePaymentReceiptPdf(p);
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: 'Receipt_${p.patientName.replaceAll(' ', '_')}',
      );
    } catch (e) {
      debugPrint('Error printing receipt: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to print receipt: $e')));
      }
    }
  }

  void _viewPaymentDetails(Payment p) {
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: 'PKR ');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.payment_rounded, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Payment Details',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow(cs, 'Patient', p.patientName),
            _detailRow(cs, 'Total Bill', fmt.format(p.amount)),
            _detailRow(cs, 'Amount Paid', fmt.format(p.paidAmount)),
            _detailRow(cs, 'Remaining', fmt.format(p.amount - p.paidAmount)),
            _detailRow(cs, 'Method', p.method),
            _detailRow(cs, 'Status', p.status),
            _detailRow(
              cs,
              'Date Recorded',
              DateFormat('d MMM y, hh:mm a').format(p.paidAt),
            ),
            if (p.reminderDate != null)
              _detailRow(
                cs,
                'Reminder Date',
                DateFormat('d MMM y, hh:mm a').format(p.reminderDate!),
              ),
            if (p.note.isNotEmpty) _detailRow(cs, 'Notes', p.note),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _printReceipt(p);
            },
            child: const Text(
              'Print Receipt',
              style: TextStyle(color: Colors.teal),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.poppins(color: cs.onSurface, fontSize: 13),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  void _editPaymentDialog(Payment p) {
    final cs = Theme.of(context).colorScheme;
    final nameCtrl = TextEditingController(text: p.patientName);
    final amtCtrl = TextEditingController(text: p.amount.toStringAsFixed(0));
    final paidAmtCtrl = TextEditingController(
      text: p.paidAmount.toStringAsFixed(0),
    );
    final noteCtrl = TextEditingController(text: p.note);
    String method = p.method;
    String status = p.status;
    DateTime? reminderDate = p.reminderDate;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Text(
            'Edit Payment',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Patient Name',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: amtCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Total Bill (PKR)',
                    ),
                    validator: (v) {
                      final a = double.tryParse((v ?? '').trim());
                      return (a == null || a <= 0)
                          ? 'Enter valid amount'
                          : null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: paidAmtCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount Paid (PKR)',
                    ),
                    validator: (v) {
                      final pa = double.tryParse((v ?? '').trim());
                      final ta = double.tryParse(amtCtrl.text.trim()) ?? 0;
                      if (pa == null || pa < 0) return 'Enter valid amount';
                      if (pa > ta) return 'Cannot exceed total amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: method,
                    decoration: const InputDecoration(labelText: 'Method'),
                    items: _methods
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setDlgState(() => method = v ?? method),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: _statuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setDlgState(() => status = v ?? status),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _selectReminderDate(
                            context,
                            onSelected: (dt) {
                              setDlgState(() {
                                reminderDate = dt;
                              });
                            },
                          ),
                          icon: const Icon(Icons.alarm_add_rounded, size: 16),
                          label: Text(
                            reminderDate == null
                                ? 'Set Payment Reminder'
                                : 'Remind: ${DateFormat('d MMM, h:mm a').format(reminderDate!)}',
                            style: GoogleFonts.poppins(fontSize: 12),
                          ),
                        ),
                      ),
                      if (reminderDate != null)
                        IconButton(
                          icon: const Icon(
                            Icons.clear_rounded,
                            color: Colors.red,
                          ),
                          onPressed: () {
                            setDlgState(() {
                              reminderDate = null;
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final amount = double.tryParse(amtCtrl.text.trim()) ?? p.amount;
                final paidAmount =
                    double.tryParse(paidAmtCtrl.text.trim()) ?? 0;

                String finalStatus = status;
                if (paidAmount >= amount) {
                  finalStatus = 'Paid';
                } else if (paidAmount == 0) {
                  finalStatus = 'Pending';
                } else {
                  finalStatus = 'Partial';
                }

                final updated = Payment(
                  id: p.id,
                  patientName: nameCtrl.text.trim(),
                  amount: amount,
                  paidAmount: paidAmount,
                  paidAt: p.paidAt,
                  method: method,
                  status: finalStatus,
                  note: noteCtrl.text.trim(),
                  reminderDate: reminderDate,
                );
                await _repository.savePayment(updated);

                // Cancel old payment reminder notification
                try {
                  await NotificationService().cancelNotification(
                    NotificationService.getPaymentReminderId(p.id),
                  );
                } catch (e) {
                  debugPrint(
                    'Failed to cancel payment reminder notification: $e',
                  );
                }

                // Schedule new balance collection reminder if there is outstanding amount and a reminder date is set
                if (reminderDate != null && paidAmount < amount) {
                  final remaining = amount - paidAmount;
                  try {
                    await NotificationService().scheduleLocalNotification(
                      id: NotificationService.getPaymentReminderId(p.id),
                      title: 'Collect Outstanding Balance 💰',
                      body:
                          'Collect outstanding balance of PKR ${remaining.toStringAsFixed(0)} from ${nameCtrl.text.trim()}.',
                      scheduledDate: reminderDate!,
                      payload: '/payments',
                    );
                  } catch (e) {
                    debugPrint('Payment notification failed: $e');
                  }
                }

                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Payment updated successfully ✅'),
                    ),
                  );
                  _loadPayments();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeletePayment(Payment p) {
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: 'PKR ');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete Payment',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to delete the payment of ${fmt.format(p.amount)} for ${p.patientName}?',
          style: GoogleFonts.poppins(color: cs.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _deletePayment(p.id);
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Payment deleted successfully 🗑️'),
                  ),
                );
              }
            },
            child: Text('Delete', style: TextStyle(color: cs.error)),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePayment(String id) async {
    await _repository.deletePayment(id);
    try {
      await NotificationService().cancelNotification(
        NotificationService.getPaymentReminderId(id),
      );
    } catch (e) {
      debugPrint('Failed to cancel payment reminder notification: $e');
    }
    _loadPayments();
  }

  bool _matchesDuration(DateTime date) {
    if (_selectedDuration == 'All') return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(date.year, date.month, date.day);

    if (_selectedDuration == 'Today') {
      return itemDate.isAtSameMomentAs(today);
    }
    if (_selectedDuration == 'Yesterday') {
      final yesterday = today.subtract(const Duration(days: 1));
      return itemDate.isAtSameMomentAs(yesterday);
    }
    if (_selectedDuration == '7 Days') {
      return today.difference(itemDate).inDays <= 7;
    }
    if (_selectedDuration == '30 Days') {
      return today.difference(itemDate).inDays <= 30;
    }
    if (_selectedDuration == '6 Months') {
      return today.difference(itemDate).inDays <= 180;
    }
    if (_selectedDuration == '1 Year') {
      return today.difference(itemDate).inDays <= 365;
    }
    if (_selectedDuration == 'Custom' && _customDateRange != null) {
      final start = DateTime(
        _customDateRange!.start.year,
        _customDateRange!.start.month,
        _customDateRange!.start.day,
      );
      final end = DateTime(
        _customDateRange!.end.year,
        _customDateRange!.end.month,
        _customDateRange!.end.day,
      ).add(const Duration(days: 1));
      return date.isAfter(start) && date.isBefore(end);
    }
    return true;
  }

  List<Payment> get _filteredPayments {
    var result = _payments;

    // Duration Filter
    result = result.where((p) => _matchesDuration(p.paidAt)).toList();

    // Status Filter
    if (_filterStatus != 'All') {
      result = result.where((p) => p.status == _filterStatus).toList();
    }

    // Method Filter
    if (_selectedMethodFilter != 'All') {
      result = result.where((p) => p.method == _selectedMethodFilter).toList();
    }

    // Search Query Filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result
          .where(
            (p) =>
                p.patientName.toLowerCase().contains(query) ||
                p.note.toLowerCase().contains(query),
          )
          .toList();
    }

    return result;
  }

  List<Payment> get _dueReminders {
    return _payments
        .where((p) => p.status != 'Paid' && p.reminderDate != null)
        .toList()
      ..sort((a, b) => a.reminderDate!.compareTo(b.reminderDate!));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: 'PKR ');
    final totalPaid = _payments.fold<double>(0, (s, p) => s + p.paidAmount);
    final totalPending = _payments.fold<double>(
      0,
      (s, p) => s + (p.amount - p.paidAmount),
    );
    final totalAll = _payments.fold<double>(0, (s, p) => s + p.amount);

    final width = MediaQuery.of(context).size.width;
    final isWide = width > 750;

    Widget formSection() {
      return Form(
        key: _formKey,
        child: PremiumCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Record New Payment',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              RawAutocomplete<String>(
                textEditingController: _patientController,
                focusNode: _patientFocusNode,
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return const Iterable<String>.empty();
                  }
                  return _patientSuggestions.where((String option) {
                    return option.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    );
                  });
                },
                optionsViewBuilder:
                    (
                      BuildContext context,
                      AutocompleteOnSelected<String> onSelected,
                      Iterable<String> options,
                    ) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4.0,
                          borderRadius: BorderRadius.circular(12),
                          color: cs.surface,
                          child: Container(
                            width: 320,
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (BuildContext context, int index) {
                                final String option = options.elementAt(index);
                                return InkWell(
                                  onTap: () => onSelected(option),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: Text(
                                      option,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        onFieldSubmitted: (v) => onFieldSubmitted(),
                        decoration: const InputDecoration(
                          labelText: 'Patient name',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      );
                    },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Total Bill (PKR)',
                  prefixIcon: Icon(Icons.monetization_on_outlined),
                ),
                validator: (v) {
                  final a = double.tryParse((v ?? '').trim());
                  return (a == null || a <= 0) ? 'Enter valid amount' : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _paidAmountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount Paid so far (PKR)',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                validator: (v) {
                  final pa = double.tryParse((v ?? '').trim());
                  final ta =
                      double.tryParse(_amountController.text.trim()) ?? 0;
                  if (pa == null || pa < 0) return 'Enter valid amount';
                  if (pa > ta) return 'Cannot exceed total amount';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              isWide
                  ? Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _method,
                            decoration: const InputDecoration(
                              labelText: 'Method',
                            ),
                            items: _methods
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(
                                      m,
                                      style: GoogleFonts.poppins(),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _method = v ?? _method),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _status,
                            decoration: const InputDecoration(
                              labelText: 'Status (Auto-classified)',
                            ),
                            items: _statuses
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                      s,
                                      style: GoogleFonts.poppins(),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _status = v ?? _status),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _method,
                          decoration: const InputDecoration(
                            labelText: 'Method',
                          ),
                          items: _methods
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m, style: GoogleFonts.poppins()),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _method = v ?? _method),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _status,
                          decoration: const InputDecoration(
                            labelText: 'Status (Auto-classified)',
                          ),
                          items: _statuses
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s, style: GoogleFonts.poppins()),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _status = v ?? _status),
                        ),
                      ],
                    ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selectReminderDate(context),
                      icon: const Icon(Icons.alarm_rounded, size: 16),
                      label: Text(
                        _reminderDate == null
                            ? 'Set Payment Reminder Date'
                            : 'Remind: ${DateFormat('d MMM y, h:mm a').format(_reminderDate!)}',
                        style: GoogleFonts.poppins(fontSize: 12),
                      ),
                    ),
                  ),
                  if (_reminderDate != null)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Colors.red),
                      onPressed: () => setState(() => _reminderDate = null),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _savePayment,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Save Payment'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget historySection({bool useFullHeight = false}) {
      final due = _dueReminders;
      final Widget listContent = _filteredPayments.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 24.0),
                child: Text(
                  'No ${_filterStatus == 'All' ? '' : _filterStatus} payments yet.',
                  style: GoogleFonts.poppins(
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            )
          : ListView.builder(
              shrinkWrap: !useFullHeight,
              physics: useFullHeight
                  ? const AlwaysScrollableScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemCount: _filteredPayments.length,
              itemBuilder: (_, i) {
                final p = _filteredPayments[i];
                final sc = statusColor(
                  p.status == 'Paid'
                      ? 'confirmed'
                      : p.status == 'Pending'
                      ? 'pending'
                      : 'completed',
                );
                final sb = statusBgColor(
                  p.status == 'Paid'
                      ? 'confirmed'
                      : p.status == 'Pending'
                      ? 'pending'
                      : 'completed',
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PremiumCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 360;
                        final details = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.patientName,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              p.status == 'Paid'
                                  ? '${fmt.format(p.amount)} paid via ${p.method}'
                                  : 'Paid: ${fmt.format(p.paidAmount)} / ${fmt.format(p.amount)} (Owed: ${fmt.format(p.amount - p.paidAmount)})',
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                fontWeight: p.status == 'Paid'
                                    ? FontWeight.normal
                                    : FontWeight.w600,
                                color: p.status == 'Paid'
                                    ? cs.onSurface.withValues(alpha: 0.6)
                                    : (p.status == 'Pending'
                                          ? Colors.red
                                          : Colors.orange),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  '${DateFormat('d MMM y').format(p.paidAt)} • ${p.method}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: cs.onSurface.withValues(alpha: 0.45),
                                  ),
                                ),
                                if (p.reminderDate != null)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.alarm_rounded,
                                        size: 10,
                                        color: cs.primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Remind: ${DateFormat('d MMM, h:mm a').format(p.reminderDate!)}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          color: cs.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        );

                        final actionButtons = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.print_rounded,
                                size: 16,
                                color: Colors.teal.shade700,
                              ),
                              onPressed: () => _printReceipt(p),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Print Receipt',
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: Icon(
                                Icons.history_rounded,
                                size: 16,
                                color: cs.primary.withValues(alpha: 0.85),
                              ),
                              onPressed: () {
                                context.push(
                                  '/patient-history?name=${Uri.encodeComponent(p.patientName)}',
                                );
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Patient History',
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: Icon(
                                Icons.visibility_outlined,
                                size: 16,
                                color: cs.primary.withValues(alpha: 0.8),
                              ),
                              onPressed: () => _viewPaymentDetails(p),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'View Details',
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: const Color(0xFF0F766E),
                              ),
                              onPressed: () => _editPaymentDialog(p),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Edit Payment',
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 16,
                                color: cs.error,
                              ),
                              onPressed: () => _confirmDeletePayment(p),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Delete Payment',
                            ),
                          ],
                        );

                        return compact
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: cs.primary.withValues(
                                          alpha: 0.1,
                                        ),
                                        child: Text(
                                          p.patientName.isNotEmpty
                                              ? p.patientName[0].toUpperCase()
                                              : '?',
                                          style: GoogleFonts.poppins(
                                            color: cs.primary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(child: details),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: sb,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      p.status,
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: sc,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  actionButtons,
                                ],
                              )
                            : Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: cs.primary.withValues(
                                      alpha: 0.1,
                                    ),
                                    child: Text(
                                      p.patientName.isNotEmpty
                                          ? p.patientName[0].toUpperCase()
                                          : '?',
                                      style: GoogleFonts.poppins(
                                        color: cs.primary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: details),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: sb,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          p.status,
                                          style: GoogleFonts.poppins(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: sc,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      actionButtons,
                                    ],
                                  ),
                                ],
                              );
                      },
                    ),
                  ),
                );
              },
            );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (due.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.notification_important_rounded,
                        color: Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Upcoming & Overdue Payments',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...due.take(2).map((p) {
                    final isOverdue = p.reminderDate!.isBefore(DateTime.now());
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        '• ${p.patientName}: PKR ${fmt.format(p.amount - p.paidAmount)} remaining (Due: ${DateFormat('d MMM, hh:mm a').format(p.reminderDate!)})',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          color: Colors.red.shade900,
                          fontWeight: isOverdue
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
          // Search Bar
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Search patient or notes...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: _showFilters
                            ? cs.primary.withValues(alpha: 0.12)
                            : cs.surfaceContainerHighest.withValues(alpha: 0.3),
                        padding: const EdgeInsets.all(12),
                      ),
                      icon: Icon(
                        _showFilters
                            ? Icons.filter_alt_rounded
                            : Icons.filter_alt_outlined,
                        color: _showFilters
                            ? cs.primary
                            : cs.onSurface.withValues(alpha: 0.7),
                      ),
                      onPressed: () =>
                          setState(() => _showFilters = !_showFilters),
                      tooltip: 'Filter Options',
                    ),
                    if (_selectedDuration != 'All' ||
                        _selectedMethodFilter != 'All' ||
                        _filterStatus != 'All')
                      Positioned(
                        right: -2,
                        top: -2,
                        child: CircleAvatar(
                          radius: 5,
                          backgroundColor: cs.primary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          if (_showFilters) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ACTIVE FILTERS',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface.withValues(alpha: 0.55),
                          letterSpacing: 1.0,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _filterStatus = 'All';
                            _selectedDuration = 'All';
                            _selectedMethodFilter = 'All';
                            _customDateRange = null;
                          });
                        },
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Clear All',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Status Filters
                  Text(
                    'Status',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: _filterOptions.map((f) {
                        final isSelected = _filterStatus == f;
                        return GestureDetector(
                          onTap: () => setState(() => _filterStatus = f),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected ? cs.primary : cs.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? cs.primary
                                    : cs.outline.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Text(
                              f,
                              style: GoogleFonts.poppins(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : cs.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Duration Filters
                  Text(
                    'Time Duration',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children:
                          [
                            'All',
                            'Today',
                            'Yesterday',
                            '7 Days',
                            '30 Days',
                            '6 Months',
                            '1 Year',
                            'Custom',
                          ].map((opt) {
                            final isSelected = _selectedDuration == opt;
                            String displayLabel = opt;
                            if (opt == 'Custom' && _customDateRange != null) {
                              displayLabel =
                                  '${DateFormat('d MMM').format(_customDateRange!.start)} - ${DateFormat('d MMM').format(_customDateRange!.end)}';
                            }
                            return GestureDetector(
                              onTap: () {
                                if (opt == 'Custom') {
                                  _selectCustomDateRange();
                                } else {
                                  setState(() {
                                    _selectedDuration = opt;
                                    _customDateRange = null;
                                  });
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected ? cs.primary : cs.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? cs.primary
                                        : cs.outline.withValues(alpha: 0.15),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      displayLabel,
                                      style: GoogleFonts.poppins(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? Colors.white
                                            : cs.onSurface.withValues(alpha: 0.7),
                                      ),
                                    ),
                                    if (opt == 'Custom' && isSelected) ...[
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.edit_calendar_rounded,
                                        size: 10,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Method Filters
                  Text(
                    'Payment Method',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: ['All', ..._methods].map((m) {
                        final isSelected = _selectedMethodFilter == m;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedMethodFilter = m),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected ? cs.primary : cs.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? cs.primary
                                    : cs.outline.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Text(
                              m,
                              style: GoogleFonts.poppins(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : cs.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          if (useFullHeight) Expanded(child: listContent) else listContent,
        ],
      );
    }

    final paymentActions = [
      IconButton(
        icon: const Icon(Icons.download_rounded),
        onPressed: _exportPayments,
        tooltip: 'Export Payments',
      ),
      IconButton(
        icon: const Icon(Icons.upload_file_rounded),
        onPressed: _importPayments,
        tooltip: 'Import Payments',
      ),
    ];

    if (isWide) {
      return AppShellScaffold(
        title: 'Payments',
        currentRoute: '/payments',
        actions: paymentActions,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                child: Column(
                  children: [
                    _PaymentsQuickView(
                      total: totalAll,
                      collected: totalPaid,
                      pending: totalPending,
                      activeFilter: _filterStatus,
                      onFilterChanged: (v) => setState(() => _filterStatus = v),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: formSection()),
                        const SizedBox(width: 24),
                        Expanded(flex: 3, child: historySection()),
                      ],
                    ),
                  ],
                ),
              ),
      );
    }

    return AppShellScaffold(
      title: 'Payments',
      currentRoute: '/payments',
      actions: paymentActions,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _PaymentsQuickView(
              total: totalAll,
              collected: totalPaid,
              pending: totalPending,
              activeFilter: _filterStatus,
              onFilterChanged: (v) => setState(() => _filterStatus = v),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
            ),
            child: TabBar(
              controller: _tabController,
              labelStyle: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              unselectedLabelStyle: GoogleFonts.poppins(
                fontWeight: FontWeight.w400,
                fontSize: 13,
              ),
              labelColor: cs.primary,
              unselectedLabelColor: cs.onSurface.withValues(alpha: 0.5),
              indicator: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              tabs: const [
                Tab(text: 'Add Payment'),
                Tab(text: 'History'),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: formSection(),
                      ),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: historySection(useFullHeight: true),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentsQuickView extends StatelessWidget {
  const _PaymentsQuickView({
    required this.total,
    required this.collected,
    required this.pending,
    required this.activeFilter,
    required this.onFilterChanged,
  });
  final double total;
  final double collected;
  final double pending;
  final String activeFilter;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.12),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildStatItem(context, 'Total', total, cs.primary, 'All'),
          _buildDivider(),
          _buildStatItem(
            context,
            'Collected',
            collected,
            AppColors.statusConfirmed,
            'Paid',
          ),
          _buildDivider(),
          _buildStatItem(
            context,
            'Pending',
            pending,
            AppColors.statusPending,
            'Pending',
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 32,
      width: 1,
      color: Colors.grey.withValues(alpha: 0.15),
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    double amount,
    Color color,
    String filterValue,
  ) {
    final isSelected = activeFilter == filterValue;
    final fmt = NumberFormat('PKR #,##0', 'en_US');
    return Expanded(
      child: InkWell(
        onTap: () => onFilterChanged(filterValue),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color.withValues(alpha: 0.24) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? color : color.withValues(alpha: 0.65),
                    ),
                  ),
                  if (isSelected) ...[
                    const Spacer(),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                fmt.format(amount),
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
