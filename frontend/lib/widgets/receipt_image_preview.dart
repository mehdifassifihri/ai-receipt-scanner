import 'package:flutter/material.dart';
import '../models/receipt_selection.dart';

Future<void> showReceiptImagePreview(
  BuildContext context,
  ReceiptSelection receipt,
) => showDialog<void>(
  context: context,
  useSafeArea: false,
  builder: (context) => Dialog.fullscreen(
    backgroundColor: const Color(0xFF171C18),
    child: SafeArea(
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 20),
              const Expanded(
                child: Text(
                  'Receipt preview',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close preview',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ],
          ),
          Expanded(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              child: Center(
                child: Image.memory(
                  receipt.bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Text(
                    'Image unavailable',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'Pinch to zoom · Drag to explore',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  ),
);
