import 'package:flutter/material.dart';
import '../data/backend_api.dart';
import '../models/receipt_selection.dart';
import 'receipt_review_screen.dart';

class ReceiptExtractionScreen extends StatefulWidget {
  const ReceiptExtractionScreen({
    super.key,
    required this.receipt,
    required this.api,
  });
  final ReceiptSelection receipt;
  final BackendApi api;
  @override
  State<ReceiptExtractionScreen> createState() =>
      _ReceiptExtractionScreenState();
}

class _ReceiptExtractionScreenState extends State<ReceiptExtractionScreen> {
  String? _receiptId, _error;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _extract();
  }

  Future<void> _extract() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _receiptId ??= await widget.api.upload(widget.receipt);
      if (!mounted) return;
      final draft = await widget.api.extract(_receiptId!);
      if (!mounted) return;
      _review(draft);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = apiErrorMessage(e);
          _busy = false;
        });
      }
    }
  }

  void _review(Map<String, dynamic> draft) {
    Navigator.of(
      context,
    ).pushReplacement<ReceiptReviewResult, ReceiptReviewResult>(
      MaterialPageRoute(
        builder: (_) => ReceiptReviewScreen(
          receipt: widget.receipt,
          receiptId: _receiptId,
          draft: draft,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reading your receipt')),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.memory(
                    widget.receipt.bytes,
                    height: 210,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 32),
                if (_busy) ...[
                  const CircularProgressIndicator(color: Color(0xFF75945D)),
                  const SizedBox(height: 24),
                  Text(
                    _receiptId == null
                        ? 'Uploading your receipt…'
                        : 'Finding the details…',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'You’ll review every detail before it is saved.',
                    textAlign: TextAlign.center,
                  ),
                ] else ...[
                  const Icon(Icons.receipt_long_outlined, size: 32),
                  const SizedBox(height: 16),
                  Text(
                    _error ?? 'Could not read this receipt.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _extract,
                    child: const Text('Try again'),
                  ),
                  if (_receiptId != null)
                    TextButton(
                      onPressed: () => _review({
                        'fields': <String, dynamic>{},
                        'warnings': [
                          'Extraction was unavailable. Enter and verify all fields manually.',
                        ],
                      }),
                      child: const Text('Enter details manually'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
