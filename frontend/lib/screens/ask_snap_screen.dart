import '../widgets/glass_container.dart';
import '../theme/glass_theme.dart';
import '../data/backend_api.dart';
import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../models/ask_snap_reply.dart';
import '../models/receipt_details.dart';
import '../state/expense_store.dart';
import '../state/ask_snap_controller.dart';
import 'expense_details_screen.dart';

const _ink = AppColors.ink;
const _muted = AppColors.muted;
const _starters = [
  'How much did I spend this month?',
  'Find my largest expenses',
  'Compare food spending with last month',
  'Show my all-time spending',
];

class AskSnapScreen extends StatefulWidget {
  const AskSnapScreen({super.key});
  @override
  State<AskSnapScreen> createState() => _AskSnapScreenState();
}

class _AskSnapScreenState extends State<AskSnapScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  AskSnapController? _controller;
  AskSnapController get _chat => _controller!;
  List<AskSnapExchange> get _exchanges => _chat.exchanges;
  bool get _busy => _chat.busy;
  String? get _currency => _chat.currency;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = ExpenseScope.of(context).api;
    if (_controller == null || _controller!.api != api) {
      _controller?.dispose();
      _controller = AskSnapController(api)..addListener(_onChatChanged);
    }
  }

  void _onChatChanged() {
    if (!mounted) return;
    setState(() {});
    _bottom();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _focus.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _bottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  });
  Future<void> _send(String question, {bool retry = false}) async {
    if (_busy || question.trim().isEmpty) return;
    final api = ExpenseScope.of(context).api;
    if (api == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to connect Ask Snap to your saved expenses.'),
        ),
      );
      return;
    }
    if (!retry) _text.clear();
    await _chat.send(question, retry: retry);
  }

  Future<void> _open(AskSnapReference reference) async {
    final store = ExpenseScope.of(context);
    try {
      // Recharge le détail depuis l’API : la référence du chat peut être ancienne.
      // Le serveur vérifie à nouveau que cette dépense appartient au compte.
      final expense = await store.loadExpense(reference.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ExpenseDetailsScreen(store: store, expenseId: expense.id),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseScope.of(context);
    final suggestions = _exchanges.lastOrNull?.reply?.suggestions ?? _starters;
    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? Padding(
                padding: const EdgeInsets.all(5),
                child: GlassGroup(
                  child: GlassContainer(
                    borderRadius: 24,
                    interactive: true,
                    child: BackButton(),
                  ),
                ),
              )
            : null,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Ask Snap',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GlassGroup(
              child: GlassContainer(
                borderRadius: 24,
                interactive: !_busy && _exchanges.isNotEmpty,
                child: IconButton(
                  tooltip: 'Clear conversation',
                  onPressed: _busy || _exchanges.isEmpty ? null : _chat.clear,
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (MediaQuery.viewInsetsOf(context).bottom == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: _muted,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Your saved expenses. Read-only.',
                        style: TextStyle(fontSize: 11, color: _muted),
                      ),
                    ),
                    SizedBox(
                      width: 128,
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _currency ?? 'all',
                        isDense: true,
                        underline: const SizedBox.shrink(),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: _ink,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text(
                              'All currencies',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          for (final code in receiptCurrencies)
                            DropdownMenuItem(value: code, child: Text(code)),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => _chat.selectCurrency(
                                value == 'all' ? null : value,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                children: [
                  if (_exchanges.isEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE6F0D2), Color(0xFFEEE7F6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: Color(0xFF42634B),
                            size: 32,
                          ),
                          SizedBox(height: 22),
                          Text(
                            'A little clarity.\nJust ask.',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.2,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Find a receipt, explore your spending, or understand a monthly total.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF626B5A),
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (!store.connected)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Ask Snap needs a connected account. Sample expenses are never sent as your data.',
                          style: TextStyle(fontSize: 12, color: _muted),
                        ),
                      ),
                    if (store.connected && store.expenses.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                          'New here? Scan and save a receipt to give Snap something to explore.',
                          style: TextStyle(fontSize: 12, color: _muted),
                        ),
                      ),
                    const Text(
                      'TRY ASKING',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                        color: _muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  for (final exchange in _exchanges) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(left: 25, bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _ink,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          exchange.question,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ),
                    if (exchange.reply != null)
                      _ReplyCard(reply: exchange.reply!, onOpen: _open),
                    if (exchange.error != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEDE5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exchange.error!,
                              style: const TextStyle(fontSize: 13),
                            ),
                            if (exchange == _exchanges.last)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () =>
                                          _send(exchange.question, retry: true),
                                child: const Text('Try again'),
                              ),
                          ],
                        ),
                      ),
                  ],
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF75945D),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Looking at your saved expenses…',
                              style: TextStyle(fontSize: 12, color: _muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            _composer(suggestions, store.connected),
          ],
        ),
      ),
    );
  }

  String _suggestionLabel(String question) =>
      const {
        'How much did I spend this month?': 'This month',
        'Find my largest expenses': 'Largest expenses',
        'Compare food spending with last month': 'Compare food',
        'Show my all-time spending': 'All-time spending',
      }[question] ??
      question;

  Widget _composer(List<String> suggestions, bool connected) {
    final glass = GlassTheme.darkPanel;
    final focused =
        _focus.hasFocus || MediaQuery.viewInsetsOf(context).bottom > 0;
    return Theme(
      data: Theme.of(context).copyWith(extensions: [glass]),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: GlassGroup(
          child: GlassContainer(
            borderRadius: focused ? 24 : 30,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : glass.duration,
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.all(focused ? 8 : 10),
              child: AnimatedSize(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : glass.duration,
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_busy && suggestions.isNotEmpty && !focused) ...[
                      SizedBox(
                        height: 46,
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (rect) => const LinearGradient(
                            colors: [
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                            ],
                            stops: [0, .88, 1],
                          ).createShader(rect),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            scrollDirection: Axis.horizontal,
                            itemCount: suggestions.take(4).length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, i) => GlassContainer(
                              blur:
                                  0, // Le parent échantillonne déjà le fond une seule fois.
                              borderRadius: 20,
                              showShadow: false,
                              interactive: connected,
                              child: TextButton(
                                onPressed: connected
                                    ? () => _send(suggestions[i])
                                    : null,
                                style: TextButton.styleFrom(
                                  foregroundColor: glass.foreground,
                                  backgroundColor: glass.textScrim,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: Text(
                                  _suggestionLabel(suggestions[i]),
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            focusNode: _focus,
                            controller: _text,
                            enabled: connected && !_busy,
                            style: TextStyle(
                              color: glass.foreground,
                              fontSize: 14,
                              height: 1.5,
                            ),
                            maxLength: 1000,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: _send,
                            decoration: InputDecoration(
                              constraints: const BoxConstraints(minHeight: 56),
                              hintText: 'Ask about your expenses…',
                              hintStyle: TextStyle(
                                fontSize: 12,
                                color: glass.foreground.withValues(alpha: .75),
                              ),
                              counterText: '',
                              filled: true,
                              fillColor: glass.textScrim,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  focused ? 16 : 20,
                                ),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  focused ? 16 : 20,
                                ),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  focused ? 16 : 20,
                                ),
                                borderSide: const BorderSide(
                                  color: Color(0xFF42634B),
                                ),
                              ),
                              contentPadding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GlassContainer(
                          blur: 0,
                          borderRadius: 28,
                          showShadow: false,
                          interactive: connected && !_busy,
                          child: IconButton.filled(
                            tooltip: 'Send question',
                            onPressed: connected && !_busy
                                ? () => _send(_text.text)
                                : null,
                            style: IconButton.styleFrom(
                              backgroundColor: glass.textScrim,
                              foregroundColor: glass.foreground,
                              padding: const EdgeInsets.all(14),
                              minimumSize: const Size.square(56),
                              maximumSize: const Size.square(56),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.arrow_upward_rounded),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplyCard extends StatelessWidget {
  const _ReplyCard({required this.reply, required this.onOpen});
  final AskSnapReply reply;
  final void Function(AskSnapReference) onOpen;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 16,
              color: Color(0xFF75945D),
            ),
            SizedBox(width: 7),
            Text(
              'SNAP',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SelectableText(
          reply.answer,
          style: const TextStyle(fontSize: 13, height: 1.7, color: _ink),
        ),
        const SizedBox(height: 12),
        Text(reply.scope, style: const TextStyle(fontSize: 10, color: _muted)),
        if (reply.references.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text(
            'RELATED EXPENSES',
            style: TextStyle(fontSize: 9, color: _muted, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          for (final r in reply.references)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: const Color(0xFFF5F7F1),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onOpen(r),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.receipt_long_outlined,
                          size: 19,
                          color: Color(0xFF42634B),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.merchant,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                MaterialLocalizations.of(
                                  context,
                                ).formatShortDate(r.date),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: _muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          r.amount,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 17),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Text(
            'Showing ${reply.references.length} ${reply.references.length == 1 ? 'reference' : 'references'} · ${reply.matchedCount} matching ${reply.matchedCount == 1 ? 'expense' : 'expenses'}',
            style: const TextStyle(fontSize: 9, color: _muted),
          ),
        ],
      ],
    ),
  );
}
