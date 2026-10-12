import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() => runApp(const PassNowApp());

class PassNowApp extends StatefulWidget {
  const PassNowApp({super.key});

  @override
  State<PassNowApp> createState() => _PassNowAppState();
}

class _PassNowAppState extends State<PassNowApp> {
  final _localNotifications = FlutterLocalNotificationsPlugin();
  final _ttsEngine = FlutterTts();
  bool _loggedIn = true;
  bool _largeText = false;
  bool _highContrast = false;
  bool _tts = true;
  bool _vibration = true;
  int _tab = 0;
  WaitingTicket? _ticket = WaitingTicket.initial();
  final List<HistoryItem> _history = List.of(initialHistory);
  Timer? _callTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeAndroidAlerts());
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _ttsEngine.stop();
    super.dispose();
  }

  void _notice(String text) {
    unawaited(_showAndroidAlert(text));
  }

  Future<void> _initializeAndroidAlerts() async {
    if (!Platform.isAndroid) return;
    try {
      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _ttsEngine.setLanguage('ko-KR');
      await _ttsEngine.setSpeechRate(0.45);
      await _ttsEngine.awaitSpeakCompletion(true);
    } on MissingPluginException catch (error) {
      debugPrint('Android alerts are unavailable: $error');
    }
  }

  Future<void> _showAndroidAlert(String message) async {
    if (!Platform.isAndroid) return;
    try {
      await _localNotifications.show(
        DateTime.now().microsecondsSinceEpoch.remainder(1 << 31),
        'PASS NOW',
        message,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'waiting_status',
            '대기 상태 알림',
            channelDescription: '대기 등록과 입장 상태를 안내합니다.',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
      if (_tts) {
        await _ttsEngine.stop();
        await _ttsEngine.speak(message);
      }
    } on MissingPluginException catch (error) {
      debugPrint('Android alert delivery is unavailable: $error');
    }
  }

  void _setTicket(WaitingTicket? ticket) {
    _callTimer?.cancel();
    setState(() => _ticket = ticket);
    if (ticket?.called == true) {
      _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final current = _ticket;
        if (current == null || !current.called) {
          timer.cancel();
          return;
        }
        if (current.countdown <= 1) {
          _finishWaiting('자동 취소됨', '미응답 초과');
          _notice('입장 취소 알림: 응답 시간이 지나 대기가 자동으로 취소되었습니다.');
        } else {
          setState(
            () => _ticket = current.copyWith(countdown: current.countdown - 1),
          );
        }
      });
    }
  }

  void _advanceQueue() {
    final ticket = _ticket;
    if (ticket == null) {
      _notice('현재 대기 중인 매장이 없습니다.');
      return;
    }
    if (ticket.called) {
      _notice('이미 호출되었습니다. 입장 완료를 선택해 주세요.');
      return;
    }
    final currentNumber = (ticket.currentNumber + 1).clamp(0, ticket.myNumber);
    final teamsLeft = ticket.myNumber - currentNumber;
    final next = ticket.copyWith(
      currentNumber: currentNumber,
      imminent: teamsLeft <= 3,
      called: teamsLeft <= 0,
      estimatedMinutes: (teamsLeft * 3).clamp(0, 999),
      countdown: 30,
    );
    _setTicket(next);
    _notice(
      next.called
          ? '입장 안내 알림: ${ticket.storeName}, 지금 입장해 주세요.'
          : teamsLeft == 3
          ? '입장 3팀 전 알림: ${ticket.storeName} 앞에 3팀 남았습니다.'
          : '대기 순번이 갱신되었습니다. 앞에 $teamsLeft팀 남았습니다.',
    );
  }

  void _finishWaiting(String status, String wait) {
    final ticket = _ticket;
    if (ticket == null) return;
    _history.insert(
      0,
      HistoryItem(
        storeName: ticket.storeName,
        date: '2026-10-12',
        time: _currentTime(),
        partySize: ticket.partySize,
        number: ticket.myNumber,
        waitTime: wait,
        status: status,
      ),
    );
    _setTicket(null);
  }

  String _currentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _register(Store store, int partySize) {
    if (_ticket?.storeId == store.id) {
      _notice('이미 해당 매장에 대기 등록되어 있습니다.');
      setState(() => _tab = 0);
      return;
    }
    _setTicket(
      WaitingTicket(
        storeId: store.id,
        storeName: store.name,
        myNumber: store.waiting + 14,
        currentNumber: store.waiting + 6,
        partySize: partySize,
        estimatedMinutes: store.minutes * 8,
      ),
    );
    setState(() => _tab = 0);
    _notice('등록 알림: 대기 등록이 완료되었습니다. 번호표 ${store.waiting + 14}번입니다.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xff020617),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff6366f1),
        brightness: Brightness.dark,
      ),
    );
    return MaterialApp(
      title: 'PASS NOW',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(_largeText ? 1.18 : 1)),
        child: _loggedIn
            ? _AppShell(
                tab: _tab,
                ticket: _ticket,
                history: _history,
                highContrast: _highContrast,
                tts: _tts,
                vibration: _vibration,
                largeText: _largeText,
                onTab: (value) => setState(() => _tab = value),
                onAdvance: _advanceQueue,
                onRegister: _register,
                onSnooze: () {
                  final ticket = _ticket;
                  if (ticket == null) return;
                  _setTicket(
                    ticket.copyWith(
                      myNumber: ticket.myNumber + 3,
                      imminent: false,
                      estimatedMinutes:
                          (ticket.myNumber + 3 - ticket.currentNumber) * 4,
                    ),
                  );
                  _notice('대기 순번이 3팀 뒤로 미뤄졌습니다.');
                },
                onCancel: () {
                  _finishWaiting('취소됨', '사용자 취소');
                  _notice('입장 취소 알림: 대기 신청이 취소되었습니다.');
                },
                onComplete: () {
                  _finishWaiting('입장 완료', '약 24분');
                  _notice('입장 완료 알림: 입장이 완료되었습니다. 맛있는 시간 되세요.');
                },
                onTts: (value) => setState(() => _tts = value),
                onContrast: (value) => setState(() => _highContrast = value),
                onVibration: (value) => setState(() => _vibration = value),
                onLargeText: (value) => setState(() => _largeText = value),
                onLogout: () => setState(() => _loggedIn = false),
              )
            : _LoginScreen(onLogin: () => setState(() => _loggedIn = true)),
      ),
    );
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.onLogin});
  final VoidCallback onLogin;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  AuthMode _mode = AuthMode.login;

  @override
  Widget build(BuildContext context) {
    final title = switch (_mode) {
      AuthMode.login => '로그인',
      AuthMode.signUp => '신규 회원가입',
      AuthMode.find => '계정 정보 찾기',
    };
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const CircleAvatar(
                radius: 36,
                backgroundColor: Color(0xff6366f1),
                child: Icon(Icons.bolt, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 16),
              const Text(
                'PASS NOW',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Color(0xffa5b4fc),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '기다림의 미학을 경험으로 바꾸다',
                style: TextStyle(color: Color(0xff94a3b8)),
              ),
              const Spacer(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_mode == AuthMode.signUp) ...[
                const _Input(label: '이름', hint: '홍길동'),
                const SizedBox(height: 12),
              ],
              const _Input(
                label: '아이디 (이메일)',
                hint: 'user@passnow.kr',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              if (_mode != AuthMode.find)
                const _Input(label: '비밀번호', hint: '8자리 이상 입력', obscure: true),
              if (_mode == AuthMode.find)
                const _Input(
                  label: '휴대폰 번호',
                  hint: '010-0000-0000',
                  keyboardType: TextInputType.phone,
                ),
              const SizedBox(height: 12),
              if (_mode == AuthMode.login)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _mode = AuthMode.find),
                      child: const Text('아이디/비밀번호 찾기'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _mode = AuthMode.signUp),
                      child: const Text('회원가입'),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _mode == AuthMode.login
                    ? widget.onLogin
                    : () => setState(() => _mode = AuthMode.login),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(
                  _mode == AuthMode.find
                      ? '인증번호 받기'
                      : _mode == AuthMode.signUp
                      ? '가입완료'
                      : '로그인하기',
                ),
              ),
              if (_mode != AuthMode.login)
                TextButton(
                  onPressed: () => setState(() => _mode = AuthMode.login),
                  child: const Text('로그인 화면으로'),
                ),
              const Spacer(),
              const Text(
                '© 2026 PASS NOW Inc.',
                style: TextStyle(fontSize: 12, color: Color(0xff475569)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell({
    required this.tab,
    required this.ticket,
    required this.history,
    required this.highContrast,
    required this.tts,
    required this.vibration,
    required this.largeText,
    required this.onTab,
    required this.onAdvance,
    required this.onRegister,
    required this.onSnooze,
    required this.onCancel,
    required this.onComplete,
    required this.onTts,
    required this.onContrast,
    required this.onVibration,
    required this.onLargeText,
    required this.onLogout,
  });
  final int tab;
  final WaitingTicket? ticket;
  final List<HistoryItem> history;
  final bool highContrast, tts, vibration, largeText;
  final ValueChanged<int> onTab;
  final VoidCallback onAdvance, onSnooze, onCancel, onComplete, onLogout;
  final void Function(Store, int) onRegister;
  final ValueChanged<bool> onTts, onContrast, onVibration, onLargeText;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Home(
        ticket: ticket,
        onRegister: () => onTab(2),
        onSnooze: onSnooze,
        onCancel: onCancel,
        onComplete: onComplete,
      ),
      _Recommended(onRegister: () => onTab(2)),
      _Register(onRegister: onRegister),
      _History(
        ticket: ticket,
        history: history,
        onHome: () => onTab(0),
        onRegister: () => onTab(2),
      ),
      _MyPage(
        tts: tts,
        contrast: highContrast,
        vibration: vibration,
        largeText: largeText,
        onTts: onTts,
        onContrast: onContrast,
        onVibration: onVibration,
        onLargeText: onLargeText,
        onLogout: onLogout,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: Color(0xff6366f1),
              child: Text('P', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            SizedBox(width: 8),
            Text('PASS NOW', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '음성 안내',
            onPressed: () => onTts(!tts),
            icon: Icon(
              tts ? Icons.volume_up : Icons.volume_off,
              color: tts ? const Color(0xffa5b4fc) : null,
            ),
          ),
          IconButton(
            tooltip: '고대비 모드',
            onPressed: () => onContrast(!highContrast),
            icon: Icon(
              Icons.visibility,
              color: highContrast ? const Color(0xffa5b4fc) : null,
            ),
          ),
          TextButton(
            onPressed: () => onLargeText(!largeText),
            child: const Text('가+'),
          ),
        ],
      ),
      body: ColoredBox(
        color: highContrast ? Colors.black : const Color(0xff020617),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _Card(
                child: Row(
                  children: [
                    const Icon(Icons.skip_next, color: Color(0xffa5b4fc)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '대기열 진행 시뮬레이터',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: onAdvance,
                      child: const Text('1팀 줄이기'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(index: tab, children: pages),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: onTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.access_time), label: '메인대기'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: '추천가게'),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            label: '대기등록',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: '히스토리'),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: '마이페이지',
          ),
        ],
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home({
    required this.ticket,
    required this.onRegister,
    required this.onSnooze,
    required this.onCancel,
    required this.onComplete,
  });
  final WaitingTicket? ticket;
  final VoidCallback onRegister, onSnooze, onCancel, onComplete;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (ticket == null)
          _Card(
            child: Column(
              children: [
                const Icon(
                  Icons.access_time,
                  size: 48,
                  color: Color(0xff818cf8),
                ),
                const SizedBox(height: 12),
                const Text(
                  '현재 대기 중인 매장이 없습니다',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'QR 코드를 스캔하거나 등록 메뉴를 선택하세요.',
                  style: TextStyle(color: Color(0xff94a3b8)),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRegister,
                  child: const Text('대기열 등록하러 가기'),
                ),
              ],
            ),
          )
        else
          _TicketCard(
            ticket: ticket!,
            onSnooze: onSnooze,
            onCancel: onCancel,
            onComplete: onComplete,
          ),
        const SizedBox(height: 24),
        const Text(
          '✦ 실시간 인기 웨이팅 매장',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...stores.map(
          (store) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _StoreCard(store: store, onRegister: onRegister),
          ),
        ),
      ],
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.ticket,
    required this.onSnooze,
    required this.onCancel,
    required this.onComplete,
  });
  final WaitingTicket ticket;
  final VoidCallback onSnooze, onCancel, onComplete;

  @override
  Widget build(BuildContext context) {
    final color = ticket.called ? Colors.amber : const Color(0xff818cf8);
    return _Card(
      borderColor: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Chip(
                label: Text(
                  ticket.called
                      ? '지금 입장해 주세요'
                      : ticket.imminent
                      ? '입장 임박'
                      : '실시간 대기 중',
                ),
              ),
              const Spacer(),
              const Icon(Icons.refresh, size: 15, color: Color(0xff94a3b8)),
              const SizedBox(width: 4),
              const Text(
                '방금 갱신',
                style: TextStyle(fontSize: 12, color: Color(0xff94a3b8)),
              ),
            ],
          ),
          Text(
            ticket.storeName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            '등록 18:15 · ${ticket.partySize}명',
            style: const TextStyle(color: Color(0xff94a3b8)),
          ),
          if (ticket.called)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: Column(
                  children: [
                    const Text(
                      '응답 대기 카운트다운',
                      style: TextStyle(color: Colors.amber),
                    ),
                    Text(
                      '${ticket.countdown}초',
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: Colors.amber,
                      ),
                    ),
                    const Text(
                      '시간 내 미응답 시 대기가 자동으로 취소됩니다.',
                      style: TextStyle(fontSize: 12, color: Color(0xffcbd5e1)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TicketNumber(
                  label: '내 번호표',
                  value: ticket.myNumber,
                  color: const Color(0xff818cf8),
                ),
              ),
              Container(height: 44, width: 1, color: const Color(0xff334155)),
              Expanded(
                child: _TicketNumber(
                  label: '현재 호출 번호',
                  value: ticket.currentNumber,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  'AI 예상 ${ticket.estimatedMinutes}분',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '내 앞 ${ticket.teamsLeft}팀',
                style: const TextStyle(color: Color(0xffa5b4fc)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (ticket.called)
            FilledButton.icon(
              onPressed: () => _confirm(
                context,
                title: '입장 완료 확인',
                content: '매장 직원의 확인 후에 입장 완료로 처리해 주세요.',
                actionLabel: '입장 완료',
                action: onComplete,
              ),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('직원 확인 후 입장 완료'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: Colors.green,
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onSnooze,
                    child: const Text('순서 미루기'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _confirm(
                      context,
                      title: '대기 취소 확인',
                      content: '대기 신청을 취소하면 번호표를 되돌릴 수 없습니다.',
                      actionLabel: '취소하기',
                      action: onCancel,
                    ),
                    child: const Text('대기 취소'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String content,
    required String actionLabel,
    required VoidCallback action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('돌아가기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (confirmed == true) action();
  }
}

class _Recommended extends StatelessWidget {
  const _Recommended({required this.onRegister});
  final VoidCallback onRegister;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        '✦ 추천 가게',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      const Text(
        '현재 대기 현황과 예상 대기 시간을 바탕으로 추천해 드립니다.',
        style: TextStyle(color: Color(0xff94a3b8)),
      ),
      const SizedBox(height: 16),
      ...stores.asMap().entries.map(
        (entry) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _StoreCard(
            store: entry.value,
            rank: entry.key + 1,
            onRegister: onRegister,
          ),
        ),
      ),
    ],
  );
}

class _Register extends StatefulWidget {
  const _Register({required this.onRegister});
  final void Function(Store, int) onRegister;
  @override
  State<_Register> createState() => _RegisterState();
}

class _RegisterState extends State<_Register> {
  Store _selected = stores.first;
  int _partySize = 2;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        '▣ 대기열 등록하기',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      const Text(
        'QR 코드를 인식하거나 매장 코드를 입력하여 등록합니다.',
        style: TextStyle(color: Color(0xff94a3b8)),
      ),
      const SizedBox(height: 20),
      _Card(
        child: Column(
          children: [
            const Icon(
              Icons.qr_code_scanner,
              size: 100,
              color: Color(0xffa5b4fc),
            ),
            const SizedBox(height: 8),
            const Text('매장 표지판의 QR 코드를 스캔하세요'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => widget.onRegister(stores.first, _partySize),
              child: const Text('모의 QR 스캔 실행'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '매장 선택 및 수기 등록',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Store>(
              value: _selected,
              decoration: const InputDecoration(labelText: '매장 선택'),
              items: stores
                  .map(
                    (store) => DropdownMenuItem(
                      value: store,
                      child: Text('${store.name} · 현재 ${store.waiting}팀'),
                    ),
                  )
                  .toList(),
              onChanged: (store) => setState(() => _selected = store!),
            ),
            const SizedBox(height: 16),
            const _Input(
              label: '알림 수신 휴대폰 번호',
              hint: '010-9876-5432',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            const Text('방문 인원수'),
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(
                    () => _partySize = (_partySize - 1).clamp(1, 20),
                  ),
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: '인원 줄이기',
                ),
                Text(
                  '$_partySize명',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => setState(
                    () => _partySize = (_partySize + 1).clamp(1, 20),
                  ),
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: '인원 늘리기',
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => widget.onRegister(_selected, _partySize),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('대기 번호표 즉시 발급받기'),
            ),
          ],
        ),
      ),
    ],
  );
}

class _History extends StatelessWidget {
  const _History({
    required this.ticket,
    required this.history,
    required this.onHome,
    required this.onRegister,
  });
  final WaitingTicket? ticket;
  final List<HistoryItem> history;
  final VoidCallback onHome, onRegister;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        '◷ 대기 히스토리',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      const Text(
        '현재 대기와 지난 방문 이력을 확인하세요.',
        style: TextStyle(color: Color(0xff94a3b8)),
      ),
      const SizedBox(height: 20),
      const Text(
        '현재 등록 매장',
        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xff94a3b8)),
      ),
      const SizedBox(height: 8),
      _Card(
        child: ticket == null
            ? const Center(child: Text('현재 등록된 대기 건이 없습니다.'))
            : Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Chip(label: Text('진행 중')),
                        Text(
                          ticket!.storeName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('번호표 No.${ticket!.myNumber}'),
                      ],
                    ),
                  ),
                  FilledButton(onPressed: onHome, child: const Text('현황 확인')),
                ],
              ),
      ),
      const SizedBox(height: 20),
      const Text(
        '이전 등록 매장 목록',
        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xff94a3b8)),
      ),
      const SizedBox(height: 8),
      ...history.map(
        (item) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _Card(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.storeName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${item.date} ${item.time} · ${item.partySize}명 · ${item.waitTime}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xff94a3b8),
                        ),
                      ),
                      Text(
                        item.status,
                        style: TextStyle(
                          fontSize: 12,
                          color: item.status == '입장 완료'
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(onPressed: onRegister, child: const Text('재대기')),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _MyPage extends StatelessWidget {
  const _MyPage({
    required this.tts,
    required this.contrast,
    required this.vibration,
    required this.largeText,
    required this.onTts,
    required this.onContrast,
    required this.onVibration,
    required this.onLargeText,
    required this.onLogout,
  });
  final bool tts, contrast, vibration, largeText;
  final ValueChanged<bool> onTts, onContrast, onVibration, onLargeText;
  final VoidCallback onLogout;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _Card(
        child: const Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Color(0xff6366f1),
              child: Text(
                '김',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '김패스 님',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '010-9876-5432',
                  style: TextStyle(color: Color(0xff94a3b8)),
                ),
                Text(
                  'user@passnow.kr',
                  style: TextStyle(color: Color(0xff94a3b8)),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _Card(
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '▣ 배리어프리 접근성 설정',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            _Setting(
              title: '음성 안내 (TTS)',
              detail: '대기 순번 및 상태를 음성으로 안내합니다.',
              value: tts,
              onChanged: onTts,
            ),
            _Setting(
              title: '고대비 모드',
              detail: '화면 명암 대비를 높여 가독성을 개선합니다.',
              value: contrast,
              onChanged: onContrast,
            ),
            _Setting(
              title: '진동 피드백 알림',
              detail: '호출 및 알림 발생 시 진동을 실행합니다.',
              value: vibration,
              onChanged: onVibration,
            ),
            _Setting(
              title: '큰 글씨 모드',
              detail: '앱 전체의 기본 글씨 크기를 확대합니다.',
              value: largeText,
              onChanged: onLargeText,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: onLogout,
        icon: const Icon(Icons.logout, color: Colors.redAccent),
        label: const Text('로그아웃', style: TextStyle(color: Colors.redAccent)),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
      ),
    ],
  );
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store, required this.onRegister, this.rank});
  final Store store;
  final VoidCallback onRegister;
  final int? rank;
  @override
  Widget build(BuildContext context) => _Card(
    child: Row(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xff312e81),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.restaurant,
            size: 34,
            color: Color(0xffc7d2fe),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rank != null)
                Text(
                  '추천 $rank',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xffa5b4fc),
                  ),
                ),
              Text(
                store.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                store.location,
                style: const TextStyle(fontSize: 12, color: Color(0xff94a3b8)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '대기 ${store.waiting}팀 · 팀당 약 ${store.minutes}분',
                style: const TextStyle(fontSize: 12, color: Color(0xffcbd5e1)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(onPressed: onRegister, child: const Text('등록')),
      ],
    ),
  );
}

class _TicketNumber extends StatelessWidget {
  const _TicketNumber({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xff94a3b8)),
      ),
      Text(
        'No.$value',
        style: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.borderColor});
  final Widget child;
  final Color? borderColor;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xff0f172a),
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor ?? const Color(0xff1e293b),
          width: borderColor == null ? 1 : 1.5,
        ),
      ),
      child: child,
    ),
  );
}

class _Input extends StatelessWidget {
  const _Input({
    required this.label,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
  });
  final String label, hint;
  final bool obscure;
  final TextInputType? keyboardType;
  @override
  Widget build(BuildContext context) => TextFormField(
    obscureText: obscure,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
  );
}

class _Setting extends StatelessWidget {
  const _Setting({
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
  });
  final String title, detail;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(detail, style: const TextStyle(fontSize: 12)),
    value: value,
    onChanged: onChanged,
  );
}

enum AuthMode { login, signUp, find }

class Store {
  const Store(this.id, this.name, this.location, this.waiting, this.minutes);
  final String id, name, location;
  final int waiting, minutes;
}

const stores = [
  Store('STORE-101', '맛있는 녀석들 삼겹살 본점', '서울 마포구 독막로 12', 12, 6),
  Store('STORE-102', '스시 오마카세 겐지', '서울 강남구 테헤란로 45', 5, 10),
  Store('STORE-103', '성수 피자 루프탑', '서울 성동구 성수이로 88', 18, 4),
];

class WaitingTicket {
  WaitingTicket({
    required this.storeId,
    required this.storeName,
    required this.myNumber,
    required this.currentNumber,
    required this.partySize,
    required this.estimatedMinutes,
    this.imminent = false,
    this.called = false,
    this.countdown = 30,
  });
  factory WaitingTicket.initial() => WaitingTicket(
    storeId: 'STORE-101',
    storeName: '맛있는 녀석들 삼겹살 본점',
    myNumber: 38,
    currentNumber: 32,
    partySize: 2,
    estimatedMinutes: 18,
  );
  final String storeId, storeName;
  final int myNumber, currentNumber, partySize, estimatedMinutes, countdown;
  final bool imminent, called;
  int get teamsLeft => (myNumber - currentNumber).clamp(0, 999);
  WaitingTicket copyWith({
    int? myNumber,
    int? currentNumber,
    int? estimatedMinutes,
    int? countdown,
    bool? imminent,
    bool? called,
  }) => WaitingTicket(
    storeId: storeId,
    storeName: storeName,
    myNumber: myNumber ?? this.myNumber,
    currentNumber: currentNumber ?? this.currentNumber,
    partySize: partySize,
    estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
    countdown: countdown ?? this.countdown,
    imminent: imminent ?? this.imminent,
    called: called ?? this.called,
  );
}

class HistoryItem {
  const HistoryItem({
    required this.storeName,
    required this.date,
    required this.time,
    required this.partySize,
    required this.number,
    required this.waitTime,
    required this.status,
  });
  final String storeName, date, time, waitTime, status;
  final int partySize, number;
}

const initialHistory = [
  HistoryItem(
    storeName: '성수 피자 루프탑',
    date: '2026-09-22',
    time: '18:30',
    partySize: 2,
    number: 42,
    waitTime: '24분',
    status: '입장 완료',
  ),
  HistoryItem(
    storeName: '강남 미쉐린 멘야',
    date: '2026-09-18',
    time: '12:15',
    partySize: 3,
    number: 15,
    waitTime: '35분',
    status: '입장 완료',
  ),
  HistoryItem(
    storeName: '한남 카페 아틀리에',
    date: '2026-09-05',
    time: '15:10',
    partySize: 2,
    number: 8,
    waitTime: '0분',
    status: '자동 취소됨',
  ),
];
