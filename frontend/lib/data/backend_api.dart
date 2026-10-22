import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:uuid/uuid.dart';
import '../models/receipt_details.dart';
import '../models/ask_snap_reply.dart';
import '../services/analytics_report.dart';
import '../models/receipt_selection.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Ne montre jamais une exception technique brute (réponse, chemin ou détail SDK).
String apiErrorMessage(
  Object? error, {
  String fallback = 'Something went wrong. Please retry.',
}) => error is ApiException ? error.message : fallback;

class BackendApi {
  BackendApi({
    required this.baseUrl,
    required this.accessToken,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final String baseUrl;
  final Future<String> Function() accessToken;
  final http.Client _client;
  bool _closed = false;
  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }

  void _ensureOpen() {
    if (_closed) throw const ApiException('Please sign in again.', status: 401);
  }

  Uri uri(String path) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/v1$path');

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    _ensureOpen();
    final request = http.Request(method, uri(path));
    request.headers['Authorization'] = 'Bearer ${await accessToken()}';
    if (idempotencyKey != null) {
      request.headers['Idempotency-Key'] = idempotencyKey;
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return _send(request);
  }

  Future<Map<String, dynamic>> _send(http.BaseRequest request) async {
    _ensureOpen();
    try {
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(const Duration(seconds: 100));
      // Ignore même une réponse terminée si le compte a été déconnecté entre-temps.
      _ensureOpen();
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          decoded is Map && decoded['error'] is Map
              ? ((decoded['error'] as Map)['message'] is String
                    ? (decoded['error'] as Map)['message'] as String
                    : 'Request failed. Please retry.')
              : 'Request failed.',
          status: response.statusCode,
        );
      }
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object');
      }
      return decoded;
    } on TimeoutException {
      throw const ApiException('The server took too long. Please retry.');
    } on http.ClientException {
      throw const ApiException(
        'Cannot reach the server. Check your connection and try again.',
      );
    } on FormatException {
      throw const ApiException('The server returned an unexpected response.');
    }
  }

  Future<String> upload(ReceiptSelection receipt) async {
    final bytes = receipt.bytes;
    if (bytes.length > 6291456) {
      throw const ApiException('Choose a receipt smaller than 6 MiB.');
    }
    final png =
        bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71;
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    if (!png && !jpeg) {
      throw const ApiException(
        'Please choose a JPEG or PNG receipt. HEIC and PDF are not supported yet.',
      );
    }
    final request = http.MultipartRequest('POST', uri('/receipts'));
    request.headers['Authorization'] = 'Bearer ${await accessToken()}';
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: png ? 'receipt.png' : 'receipt.jpg',
        contentType: MediaType('image', png ? 'png' : 'jpeg'),
      ),
    );
    return (await _send(request))['id'] as String;
  }

  Future<Map<String, dynamic>> extract(String id) async {
    final response = await request('POST', '/receipts/$id/extract');
    final job = response['job'] as Map<String, dynamic>;
    if (job['status'] != 'completed' || job['result'] == null) {
      throw const ApiException('Extraction is not ready. Please retry.');
    }
    return Map<String, dynamic>.from(job['result'] as Map);
  }

  Future<List<SavedReceiptExpense>> expenses() async {
    final all = <SavedReceiptExpense>[];
    var offset = 0;
    int? expectedTotal;
    final seen = <String>{};
    while (true) {
      final page = await request('GET', '/expenses?limit=100&offset=$offset');
      final total = page['total'];
      if (total is! int || total < 0 || page['items'] is! List) {
        throw const ApiException(
          'The server returned an unexpected expense list.',
        );
      }
      if (expectedTotal != null && expectedTotal != total) {
        throw _changedExpenses;
      }
      expectedTotal = total;
      final items = (page['items'] as List).cast<Map<String, dynamic>>();
      for (final item in items) {
        final expense = decodeExpense(item);
        if (!seen.add(expense.id)) throw _changedExpenses;
        all.add(expense);
      }
      if (all.length > total) throw _changedExpenses;
      offset += items.length;
      if (offset >= total) break;
      if (items.isEmpty) {
        throw const ApiException(
          'Expense list changed while loading. Please refresh.',
        );
      }
    }
    return all;
  }

  static const _changedExpenses = ApiException(
    'Expense list changed while loading. Please refresh.',
  );

  static SavedReceiptExpense decodeExpense(
    Map<String, dynamic> json, {
    ReceiptSelection? receipt,
  }) => SavedReceiptExpense(
    id: json['id'] as String,
    receiptId: json['receipt_id'] as String?,
    receipt: receipt,
    details: ReceiptDetails(
      merchant: json['merchant'] as String,
      date: DateTime.parse(json['transaction_date'] as String),
      amountInCents: json['amount_in_cents'] as int,
      currency: json['currency'] as String,
      category: json['category'] as String,
    ),
  );

  Future<SavedReceiptExpense> save(
    SavedReceiptExpense expense, {
    String? id,
    required String key,
  }) async {
    final d = expense.details;
    final body = <String, dynamic>{
      'merchant': d.merchant,
      'transaction_date':
          '${d.date.year.toString().padLeft(4, '0')}-${d.date.month.toString().padLeft(2, '0')}-${d.date.day.toString().padLeft(2, '0')}',
      'amount_in_cents': d.amountInCents,
      'currency': d.currency,
      'category': d.category,
    };
    if (id == null) body['receipt_id'] = expense.receiptId;
    return decodeExpense(
      await request(
        id == null ? 'POST' : 'PUT',
        id == null ? '/expenses' : '/expenses/$id',
        body: body,
        idempotencyKey: id == null ? key : null,
      ),
      receipt: expense.receipt,
    );
  }

  Future<ReceiptSelection> image(String id) async {
    _ensureOpen();
    final result = await request('GET', '/receipts/$id/image-url');
    try {
      final response = await _client
          .get(Uri.parse(result['url'] as String))
          .timeout(const Duration(seconds: 30));
      _ensureOpen();
      if (response.statusCode != 200) {
        throw const ApiException(
          'Receipt image could not be loaded. Please retry.',
        );
      }
      return ReceiptSelection.fromBytes(response.bodyBytes);
    } on TimeoutException {
      throw const ApiException('Receipt image took too long to load.');
    } on http.ClientException {
      throw const ApiException(
        'Cannot load the receipt image. Check your connection.',
      );
    }
  }

  Future<AnalyticsReport> analytics(
    AnalyticsPeriod period,
    String currency,
  ) async {
    final name = switch (period) {
      AnalyticsPeriod.thisMonth => 'this_month',
      AnalyticsPeriod.lastMonth => 'last_month',
      AnalyticsPeriod.lastThreeMonths => 'last_three_months',
      AnalyticsPeriod.thisYear => 'this_year',
    };
    final json = await request(
      'GET',
      '/analytics?period=$name&currency=$currency',
    );
    final range = json['date_range'] as Map;
    return AnalyticsReport(
      period: period,
      currency: currency,
      range: AnalyticsRange(
        DateTime.parse(range['start'] as String).toUtc(),
        DateTime.parse(range['end_exclusive'] as String).toUtc(),
      ),
      totalInCents: json['total_in_cents'] as int,
      previousTotalInCents: json['previous_total_in_cents'] as int,
      transactionCount: json['transaction_count'] as int,
      categories: [
        for (final item in json['categories'] as List)
          CategorySpending(
            item['category'] as String,
            item['amount_in_cents'] as int,
            (item['percentage'] as num).toDouble() / 100,
          ),
      ],
      buckets: [
        for (final item in json['buckets'] as List)
          TrendBucket(
            DateTime.parse(item['start'] as String).toUtc(),
            DateTime.parse(item['end_exclusive'] as String).toUtc(),
            item['amount_in_cents'] as int,
          ),
      ],
    );
  }

  // Passe par le client HTTP authentifié existant. Flutter envoie la question,
  // pas une clé OpenAI ; le backend interprète et calcule la réponse.
  Future<AskSnapReply> askSnap(
    String message, {
    String? currency,
    List<Map<String, dynamic>> history = const [],
  }) async => AskSnapReply.fromJson(
    await request(
      'POST',
      '/ask-snap',
      body: {'message': message, 'currency': currency, 'history': history},
    ),
  );

  Future<SavedReceiptExpense> expense(String id) async =>
      decodeExpense(await request('GET', '/expenses/$id'));

  static String newKey() => const Uuid().v4();
}
