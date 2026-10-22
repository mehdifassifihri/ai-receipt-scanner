import '../theme/app_theme.dart';
import '../data/backend_api.dart';
import 'package:flutter/material.dart';
import '../models/receipt_details.dart';
import '../models/receipt_selection.dart';
import '../state/expense_store.dart';
import '../widgets/receipt_image_preview.dart';

const _ink = AppColors.ink;
const _muted = AppColors.muted;

enum ReceiptReviewResult { saved, retake, gallery }

class ReceiptReviewScreen extends StatefulWidget {
  const ReceiptReviewScreen({
    super.key,
    this.receipt,
    this.editingExpense,
    this.receiptId,
    this.draft,
  }) : assert(receipt != null || editingExpense != null);
  final ReceiptSelection? receipt;
  final SavedReceiptExpense? editingExpense;
  final String? receiptId;
  final Map<String, dynamic>? draft;
  @override
  State<ReceiptReviewScreen> createState() => _ReceiptReviewScreenState();
}

class _ReceiptReviewScreenState extends State<ReceiptReviewScreen> {
  final _form = GlobalKey<FormState>();
  late final _mock =
      widget.editingExpense?.details ??
      (widget.draft == null ? ReceiptDetails.mock() : _draftDetails());
  ReceiptDetails _draftDetails() {
    final fields = widget.draft!['fields'] as Map<String, dynamic>;
    return ReceiptDetails(
      merchant: fields['merchant'] as String? ?? '',
      date:
          DateTime.tryParse(fields['transaction_date'] as String? ?? '') ??
          DateTime.now().toUtc(),
      amountInCents: fields['amount_in_cents'] as int? ?? 0,
      currency: fields['currency'] as String? ?? 'USD',
      category: fields['category'] as String? ?? 'Other',
    );
  }

  late bool _dateKnown =
      widget.draft == null ||
      (widget.draft!['fields'] as Map)['transaction_date'] != null;
  late bool _currencyKnown =
      widget.draft == null ||
      (widget.draft!['fields'] as Map)['currency'] != null;
  late final String _requestKey = BackendApi.newKey();
  String? _attemptBody;
  String? _attemptKey;
  bool get _editing => widget.editingExpense != null;
  ReceiptSelection? get _receipt =>
      widget.receipt ?? widget.editingExpense?.receipt;
  late final _merchant = TextEditingController(text: _mock.merchant);
  late final _amount = TextEditingController(
    text: widget.draft != null && _mock.amountInCents == 0
        ? ''
        : _mock.formattedAmount,
  );
  late final _dateText = TextEditingController(
    text: _dateKnown ? _formatDate(_mock.date) : '',
  );
  late DateTime _date = _mock.date;
  late String _currency = _mock.currency;
  late String _category = _mock.category;
  bool _saving = false;
  bool _allowPop = false;
  bool _asking = false;

  bool get _dirty =>
      _merchant.text != _mock.merchant ||
      _amount.text != _mock.formattedAmount ||
      _date != _mock.date ||
      _currency != _mock.currency ||
      _category != _mock.category;

  @override
  void dispose() {
    _merchant.dispose();
    _amount.dispose();
    _dateText.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) =>
      MaterialLocalizations.of(context).formatMediumDate(date);

  Future<void> _leave([ReceiptReviewResult? result]) async {
    if (_saving || _asking) return;
    _asking = true;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard your edits?'),
          content: const Text(
            'Your unsaved detail changes will be lost. The original receipt will remain unchanged.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard edits'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (discard != true) {
        _asking = false;
        return;
      }
    }
    if (!mounted) return;
    _pop(result);
  }

  void _pop(ReceiptReviewResult? result) {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (mounted && picked != null) {
      setState(() {
        _dateKnown = true;
        _date = picked;
        _dateText.text = _formatDate(picked);
      });
    }
  }

  int? _parseAmount(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(normalized)) return null;
    final parts = normalized.split('.');
    return int.parse(parts[0]) * 100 +
        (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final store = ExpenseScope.of(context);
    final details = ReceiptDetails(
      merchant: _merchant.text.trim(),
      date: DateUtils.dateOnly(_date),
      amountInCents: _parseAmount(_amount.text)!,
      currency: _currency,
      category: _category,
    );
    setState(() => _saving = true);
    final expense = SavedReceiptExpense(
      details: details,
      receipt: _receipt,
      receiptId: widget.receiptId ?? widget.editingExpense?.receiptId,
    );
    // Reuse the same key after an ambiguous network failure for identical fields.
    final body =
        '${details.merchant}|${details.date}|${details.amountInCents}|${details.currency}|${details.category}';
    if (_attemptBody != body) {
      _attemptKey = _attemptBody == null ? _requestKey : BackendApi.newKey();
      _attemptBody = body;
    }
    try {
      await store.persist(
        expense,
        id: widget.editingExpense?.id,
        key: _attemptKey!,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!mounted) return;
    _pop(ReceiptReviewResult.saved);
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20, color: _muted),
    filled: true,
    fillColor: const Color(0xFFF7F8F5),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: Color(0xFFE7EAE1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: Color(0xFF75945D), width: 1.5),
    ),
    errorMaxLines: 3,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
  );

  void _zoom() {
    if (_receipt != null) showReceiptImagePreview(context, _receipt!);
  }

  @override
  Widget build(BuildContext context) => PopScope<ReceiptReviewResult>(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave(result);
    },
    child: Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Text(
          _editing ? 'Edit Expense' : 'Review Receipt',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          tooltip: _editing ? 'Back to expense' : 'Back to Scanner',
          onPressed: _saving ? null : _leave,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            14 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: _ink,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _ink.withValues(alpha: .65),
                        disabledForegroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 20),
                      label: Text(
                        _saving
                            ? 'Saving…'
                            : _editing
                            ? 'Save Changes'
                            : 'Save Expense',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Review every detail before saving',
                    style: TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _form,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'One last look.',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Verify your receipt details before saving.',
                      style: TextStyle(color: _muted, fontSize: 13),
                    ),
                    const SizedBox(height: 22),
                    if (_receipt != null)
                      Material(
                        color: const Color(0xFFECEFE7),
                        borderRadius: BorderRadius.circular(25),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _zoom,
                          child: Column(
                            children: [
                              SizedBox(
                                height: 225,
                                width: double.infinity,
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Image.memory(
                                    _receipt!.bytes,
                                    fit: BoxFit.contain,
                                    cacheWidth: 1200,
                                    semanticLabel:
                                        'Selected receipt. Tap to enlarge',
                                    errorBuilder: (_, _, _) => const Center(
                                      child: Text(
                                        'Image unavailable. Change your receipt.',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.zoom_in_rounded, size: 17),
                                    SizedBox(width: 7),
                                    Text(
                                      'Tap to view full receipt',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!_editing)
                      Wrap(
                        alignment: WrapAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _leave(ReceiptReviewResult.retake),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Retake Photo'),
                          ),
                          TextButton(
                            onPressed: _saving
                                ? null
                                : () => _leave(ReceiptReviewResult.gallery),
                            child: const Text('Change Receipt'),
                          ),
                        ],
                      ),
                    if (!_editing)
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDDEEBA),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 20,
                              color: Color(0xFF526840),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.draft == null
                                        ? 'Demo details ready for review'
                                        : 'Receipt details ready for review',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    widget.draft == null
                                        ? 'Mock data — not extracted from your receipt. Please edit every detail to match.'
                                        : [
                                            'AI suggestions can contain mistakes. Verify all fields.',
                                            ...(widget.draft!['warnings']
                                                    as List)
                                                .cast<String>(),
                                          ].join('\n'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF526840),
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                    const Text(
                      'Receipt details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          TextFormField(
                            key: const ValueKey('merchant'),
                            controller: _merchant,
                            enabled: !_saving,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 120,
                            textInputAction: TextInputAction.next,
                            decoration: _decoration(
                              'Merchant Name',
                              Icons.storefront_outlined,
                            ).copyWith(counterText: ''),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Enter a merchant name.'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _dateText,
                            readOnly: true,
                            enabled: !_saving,
                            onTap: _pickDate,
                            decoration:
                                _decoration(
                                  'Transaction Date',
                                  Icons.calendar_today_outlined,
                                ).copyWith(
                                  suffixIcon: const Icon(
                                    Icons.expand_more_rounded,
                                  ),
                                ),
                            validator: (_) => !_dateKnown
                                ? 'Choose the transaction date.'
                                : DateUtils.dateOnly(
                                    _date,
                                  ).isAfter(DateUtils.dateOnly(DateTime.now()))
                                ? 'Choose today or an earlier date.'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const ValueKey('amount'),
                            controller: _amount,
                            enabled: !_saving,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.done,
                            decoration: _decoration(
                              'Total Amount',
                              Icons.payments_outlined,
                            ),
                            validator: (value) {
                              final amount = _parseAmount(value ?? '');
                              return amount == null || amount <= 0
                                  ? 'Enter an amount above zero, with up to 2 decimals.'
                                  : null;
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            key: ValueKey('currency-$_currencyKnown'),
                            initialValue: _currencyKnown ? _currency : null,
                            validator: (v) => v == null
                                ? 'Choose the receipt currency.'
                                : null,
                            isExpanded: true,
                            decoration: _decoration(
                              'Currency',
                              Icons.currency_exchange_rounded,
                            ),
                            items: [
                              for (final currency in receiptCurrencies)
                                DropdownMenuItem(
                                  value: currency,
                                  child: Text(currency),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) => setState(() {
                                    _currency = value!;
                                    _currencyKnown = true;
                                  }),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _category,
                            isExpanded: true,
                            decoration: _decoration(
                              'Expense Category',
                              Icons.grid_view_rounded,
                            ),
                            items: [
                              for (final category in receiptCategories)
                                DropdownMenuItem(
                                  value: category,
                                  child: Text(
                                    category,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) => setState(() => _category = value!),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
