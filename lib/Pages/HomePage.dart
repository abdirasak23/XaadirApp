// lib/home_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../Auth/AuthService.dart';
import '../Services/BiometrricService.dart';
import '../Services/DataService.dart';
import '../Services/ScanService.dart';
import 'FingrPrintPage.dart';
import 'ScanPage.dart';

const String _logoAsset = 'assets/images/xaadirlogo.png';

// ════════════════════════════════════════════════════════════════════
//  DESIGN TOKENS
// ════════════════════════════════════════════════════════════════════
class XColors {
  static const Color bg = Colors.white;
  static const Color card = Color(0xFFF1F3F7);
  static const Color border = Color(0xFFE2E5EB);
  static const Color ink = Color(0xFF0F172A);
  static const Color text = Color(0xFF0F172A);
  static const Color textDim = Color(0xFF6B7280);
  static const Color green = Color(0xFF1DB580);
  static const Color orange = Color(0xFFE09112);
  static const Color red = Color(0xFFF04438);
  static const Color blue = Color(0xFF3B82F6);
  static const Color purple = Color(0xFF8B5CF6);
}

class XText {
  static const String f = 'Poppins';
  static const TextStyle heading = TextStyle(
      fontFamily: f, fontSize: 28, fontWeight: FontWeight.w700, color: XColors.text, height: 1.2);
  static const TextStyle title = TextStyle(
      fontFamily: f, fontSize: 22, fontWeight: FontWeight.w700, color: XColors.text, height: 1.25);
  static const TextStyle number = TextStyle(
      fontFamily: f, fontSize: 32, fontWeight: FontWeight.w700, color: XColors.text, height: 1.2);
  static const TextStyle body = TextStyle(
      fontFamily: f, fontSize: 14, fontWeight: FontWeight.w400, color: XColors.text, height: 1.4);
  static const TextStyle bodyStrong = TextStyle(
      fontFamily: f, fontSize: 14, fontWeight: FontWeight.w600, color: XColors.text, height: 1.4);
  static const TextStyle caption = TextStyle(
      fontFamily: f, fontSize: 12, fontWeight: FontWeight.w400, color: XColors.textDim, height: 1.4);
}

class XRadius {
  static const double card = 20;
  static const double sheet = 28;
  static const double chip = 999;
}

/// All icons live here. If a Hugeicons name does not exist in your
/// package version, change it in this one place.
class XIcons {
  static const logout = HugeIcons.strokeRoundedLogout01;
  static const qr = HugeIcons.strokeRoundedQrCode;
  static const wifiOff = HugeIcons.strokeRoundedWifiDisconnected01;
  static const alert = HugeIcons.strokeRoundedAlertCircle;
  static const refresh = HugeIcons.strokeRoundedRefresh;
  static const close = HugeIcons.strokeRoundedCancel01;
  static const prev = HugeIcons.strokeRoundedArrowLeft01;
  static const next = HugeIcons.strokeRoundedArrowRight01;
  static const chart = HugeIcons.strokeRoundedChartLineData01;
  static const calendar = HugeIcons.strokeRoundedCalendar01;
  static const mail = HugeIcons.strokeRoundedMail01;
  static const branch = HugeIcons.strokeRoundedLocation01;
  static const clock = HugeIcons.strokeRoundedClock01;
  static const user = HugeIcons.strokeRoundedUser;
  static const info = HugeIcons.strokeRoundedInformationCircle;
  static const selfCheck = HugeIcons.strokeRoundedQrCode;
  static const hr = HugeIcons.strokeRoundedUserGroup;
}

class _Hi extends StatelessWidget {
  const _Hi(this.icon, {this.size = 22, this.color = XColors.ink});
  final dynamic icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => HugeIcon(icon: icon, color: color, size: size);
}

Color _tint(Color c, double opacity) => c.withAlpha((opacity * 255).round());

// ════════════════════════════════════════════════════════════════════
//  FORMAT HELPERS
// ════════════════════════════════════════════════════════════════════
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsFull = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

String fmtMin(int m) {
  final h24 = (m ~/ 60) % 24;
  final mm = m % 60;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  final ap = h24 >= 12 ? 'PM' : 'AM';
  return '$h12:${mm.toString().padLeft(2, '0')} $ap';
}

String fmtRange(int a, int b) => '${fmtMin(a)} – ${fmtMin(b)}';

/// "8:02 AM" or "–" when missing.
String _t(int? m) => m == null ? '–' : fmtMin(m);

String fmtDate(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day} ${_monthsShort[d.month - 1]}';

String fmtMoney(double v, String currency) {
  final neg = v < -0.004;
  final fixed = v.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final dec = parts[1] == '00' ? '' : '.${parts[1]}';
  final prefix = currency == 'USD' ? '\$' : '$currency\u00A0';
  return '${neg ? '-' : ''}$prefix$intPart$dec';
}

/// "−$12.50" for deductions.
String _minus(double v, String currency) => '−${fmtMoney(v.abs(), currency)}';

/// Countdown text: "12:05" under one hour, "2:12:05" from one hour up.
String _clock(int secs) {
  final s = secs < 0 ? 0 : secs;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final r = s % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = r.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String _untilText(int mins) {
  if (mins < 60) return '$mins min';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '·';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _shortDay(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';

/// "1 Nov – 30 Nov 2026"
String _periodText(PayrollInfo p) => '${_shortDay(p.start)} – ${_shortDay(p.end)} ${p.end.year}';

/// 0 → today, 1 → tomorrow, n → in n days
String _rel(int days) => days <= 0 ? 'today' : (days == 1 ? 'tomorrow' : 'in $days days');

String _leaveLabel(String type) {
  switch (type) {
    case 'annual':
      return 'Annual leave';
    case 'sick':
      return 'Sick leave';
    case 'emergency':
      return 'Emergency leave';
    case 'unpaid':
      return 'Unpaid leave';
    case 'maternity':
      return 'Maternity leave';
    default:
      return 'Leave';
  }
}

String _range(DateTime a, DateTime b) =>
    dayOnly(a) == dayOnly(b) ? fmtDate(a) : '${fmtDate(a)} – ${fmtDate(b)}';

// ════════════════════════════════════════════════════════════════════
//  TIME-OFF BANNER MODEL (holiday / leave / sick / upcoming)
// ════════════════════════════════════════════════════════════════════
class _BannerData {
  const _BannerData({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.trail,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? trail;
}

/// Decides what the banner says. Returns null when there is nothing to show.
_BannerData? _bannerFor(HomeData d) {
  final today = dayOnly(d.serverDate);
  final t = d.timeOff;
  final state = d.today.state;

  Holiday? holidayToday;
  Holiday? nextHoliday;
  for (final h in t.holidays) {
    final hd = dayOnly(h.date);
    if (hd == today) {
      holidayToday ??= h;
    } else if (hd.isAfter(today)) {
      nextHoliday ??= h;
    }
  }
  final int? daysToHoliday = nextHoliday == null ? null : dayOnly(nextHoliday.date).difference(today).inDays;

  final leave = t.leave;
  final leaveActive =
      leave != null && !today.isBefore(dayOnly(leave.start)) && !today.isAfter(dayOnly(leave.end));
  final LeaveSpan? leaveNext = (leave != null && dayOnly(leave.start).isAfter(today)) ? leave : null;
  final int? daysToLeave = leaveNext == null ? null : dayOnly(leaveNext.start).difference(today).inDays;

  // 1 ─ Holiday today
  if (state == TodayState.holiday || holidayToday != null) {
    return _BannerData(
      icon: Icons.celebration_rounded,
      color: XColors.purple,
      title: 'Today is a holiday',
      subtitle: holidayToday?.name ?? d.today.note ?? 'Enjoy your day off',
      trail: daysToHoliday == null ? null : 'Next ${_rel(daysToHoliday)}',
    );
  }

  // 2 ─ Sick / leave today
  if (state == TodayState.sick || state == TodayState.leave || leaveActive) {
    final sick = state == TodayState.sick || (state != TodayState.leave && leave?.type == 'sick');
    String sub;
    if (leave != null) {
      final lastDay = dayOnly(leave.end) == today;
      sub = lastDay ? 'Last day · back tomorrow' : 'Until ${fmtDate(leave.end)}';
    } else {
      sub = d.today.note ?? 'Rest well';
    }
    return _BannerData(
      icon: sick ? Icons.local_hospital_rounded : Icons.beach_access_rounded,
      color: sick ? XColors.orange : XColors.blue,
      title: sick ? 'You are on sick leave today' : 'You are on leave today',
      subtitle: sub,
      trail: (!sick && leave != null) ? _leaveLabel(leave.type) : null,
    );
  }

  // 3 ─ Upcoming (whichever comes first; leave wins a tie)
  final leaveFirst = daysToLeave != null && (daysToHoliday == null || daysToLeave <= daysToHoliday);
  if (leaveFirst) {
    final l = leaveNext!;
    return _BannerData(
      icon: Icons.event_available_rounded,
      color: XColors.blue,
      title: '${_leaveLabel(l.type)} starts ${_rel(daysToLeave)}',
      subtitle: _range(l.start, l.end),
      trail: l.days == 1 ? '1 day' : '${l.days} days',
    );
  }
  if (nextHoliday != null && daysToHoliday != null) {
    return _BannerData(
      icon: Icons.event_rounded,
      color: XColors.purple,
      title: nextHoliday.name,
      subtitle: 'Holiday · ${fmtDate(nextHoliday.date)}',
      trail: _cap(_rel(daysToHoliday)),
    );
  }
  return null;
}

String? _blockMessage(TodayState s) {
  switch (s) {
    case TodayState.holiday:
      return 'Today is a holiday. Check-in is not needed.';
    case TodayState.sick:
      return 'You are on sick leave today. Check-in is blocked.';
    case TodayState.leave:
      return 'You are on leave today. Check-in is blocked.';
    default:
      return null;
  }
}

// ════════════════════════════════════════════════════════════════════
//  SNAPSHOT (lets the profile sheet follow Home's loading state)
// ════════════════════════════════════════════════════════════════════
class _Snap {
  const _Snap({this.data, this.loading = true, this.error});
  final HomeData? data;
  final bool loading;
  final String? error;
}

// ════════════════════════════════════════════════════════════════════
//  HOME SCREEN
// ════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final HomeDataService _service = HomeDataService.instance;
  final ValueNotifier<_Snap> _snap = ValueNotifier<_Snap>(const _Snap());

  HomeData? _data;
  bool _loading = true;
  bool _offline = false;
  String? _error;
  int _seq = 0;

  BioGate _bio = BioGate.unknown;
  bool _autoPrompted = false;
  CheckInMethod? _method;

  // Month picker: null → the current month (default).
  static const int _maxMonthsBack = 6;
  DateTime? _picked;
  MonthData? _pickedMonth;
  PayrollInfo? _pickedPayroll;
  String? _pickedError;
  int _pickSeq = 0;

  late final AnimationController _fabCtrl =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  late final Animation<Offset> _fabSlide = Tween<Offset>(
    begin: const Offset(0, 0.4),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _fabCtrl, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fabCtrl.forward();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fabCtrl.dispose();
    _snap.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(silent: true);
  }

  /// setState + publish to the profile sheet.
  void _set(VoidCallback fn) {
    setState(fn);
    _snap.value = _Snap(data: _data, loading: _loading, error: _error);
  }

  // ───────────── check-in method + biometrics ─────────────
  Future<CheckInMethod?> _resolveMethod() async {
    try {
      final m = await ScanService.instance.fetchMethod();
      if (mounted) _method = m;
      return m;
    } catch (e) {
      debugPrint('❌ Method fetch error: $e');
      return null;
    }
  }

  Future<void> _refreshBio() async {
    try {
      final method = await _resolveMethod();
      if (!mounted) return;
      if (method == CheckInMethod.selfie) {
        // Selfie staff: no fingerprint banner, no enrollment prompt, ever.
        setState(() => _bio = BioGate.unknown);
        return;
      }
      final g = await BiometricService.instance.gate();
      if (!mounted) return;
      setState(() => _bio = g);
      if (g == BioGate.needsEnroll && !_autoPrompted) {
        _autoPrompted = true;
        await _enrollFlow();
      }
    } catch (e) {
      debugPrint('❌ Bio refresh error: $e');
    }
  }

  Future<bool> _enrollFlow() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const EnrollFingerprintPage()),
    );
    if (ok == true && mounted) await _refreshBio();
    return ok == true;
  }

  // ───────────── data ─────────────
  Future<void> _load({bool silent = false}) async {
    final id = ++_seq;
    if (!silent && _data == null) {
      _set(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final d = await _service.load();
      if (!mounted || id != _seq) return;
      debugPrint('✅ Home loaded · today=${d.today.state.name} · shifts=${d.shifts.length}');
      _set(() {
        _data = d;
        _loading = false;
        _error = null;
        _offline = false;
      });
      unawaited(_refreshBio());
    } on AuthFailure catch (e) {
      if (!mounted || id != _seq) return;
      if (await HomeDataService.handleSessionFailure(e)) return;
      if (!mounted) return;
      _set(() {
        _loading = false;
        if (_data == null) {
          _error = e.message;
        } else {
          _offline = e.isNetwork;
          if (!e.isNetwork && !silent) _toast(e.message);
        }
      });
    } catch (e) {
      if (!mounted || id != _seq) return;
      debugPrint('❌ Home load error: $e');
      _set(() {
        _loading = false;
        if (_data == null) _error = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _onRefresh() async {
    await _load(silent: true);
    final d = _data;
    if (d != null && !_isCurrent(d)) await _loadPicked(force: true);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontFamily: XText.f))));
  }

  Future<void> _onScan() async {
    // Leave / sick / holiday: check-in is blocked, tell the user up front.
    final blocked = _data == null ? null : _blockMessage(_data!.today.state);
    if (blocked != null) {
      debugPrint('⛔ Scan blocked · ${_data!.today.state.name}');
      _toast(blocked);
      return;
    }

    final method = _method ?? await _resolveMethod();
    if (!mounted) return;
    if (method != CheckInMethod.selfie && _bio != BioGate.active) {
      _autoPrompted = true;
      await _refreshBio();
      if (!mounted) return;
      switch (_bio) {
        case BioGate.needsEnroll:
          if (!await _enrollFlow()) return;
          break;
        case BioGate.changed:
          _toast('Your fingerprints changed. Ask HR to approve re-enrollment.');
          return;
        case BioGate.noSensor:
          _toast('Add a fingerprint in your phone settings to check in.');
          return;
        default:
          break;
      }
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const ScanPage()),
    );
    if (!mounted) return;
    if (changed == true) _load(silent: true);
  }

  void _openProfile() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => ProfileSheet(
        source: _snap,
        email: AuthService.instance.currentEmail,
        onRetry: () => _load(),
        onLogout: () {
          Navigator.of(sheetCtx).pop();
          AuthService.instance.signOut();
        },
      ),
    );
  }

  void _openRecords(MonthData month) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, controller) => _RecordsSheet(
          scrollController: controller,
          initial: month,
        ),
      ),
    );
  }

  bool _payrollBusy = false;

  /// Reloads the pay card (used by the "tap to retry" state).
  Future<void> _retryPayroll() async {
    final d = _data;
    if (d == null || _payrollBusy) return;
    if (!_isCurrent(d)) {
      await _loadPicked(force: true);
      return;
    }
    setState(() => _payrollBusy = true);
    try {
      final p = await _service.loadPayroll(d.month.year, d.month.month, forceRefresh: true);
      if (!mounted) return;
      _set(() => _data = _data?.withPayroll(p));
    } on AuthFailure catch (e) {
      if (await HomeDataService.handleSessionFailure(e)) return;
      if (mounted) _toast(e.message);
    } catch (e) {
      debugPrint('❌ Payroll retry error: $e');
      if (mounted) _toast('Could not load your pay. Please try again.');
    } finally {
      if (mounted) setState(() => _payrollBusy = false);
    }
  }

  void _openPayroll(PayrollInfo pay) {
    debugPrint('💰 Opening payroll sheet · ${pay.year}-${pay.month}');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, controller) => _PayrollSheet(
          scrollController: controller,
          initial: pay,
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // ───────────── build ─────────────
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: XColors.bg,
      floatingActionButton: FadeTransition(
        opacity: _fabCtrl,
        child: SlideTransition(position: _fabSlide, child: _ScanFab(onTap: _onScan)),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _OfflineBanner(visible: _offline),
            const _TopLogo(),
            Expanded(
              child: RefreshIndicator(
                color: XColors.ink,
                backgroundColor: Colors.white,
                strokeWidth: 2.4,
                onRefresh: _onRefresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 96 + bottomInset),
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: KeyedSubtree(
                        key: ValueKey<bool>(_data == null && _error == null),
                        child: (_data == null && _error == null)
                            ? _buildHeaderSkeleton()
                            : _buildHeader(),
                      ),
                    ),
                    if (_bio == BioGate.needsEnroll ||
                        _bio == BioGate.changed ||
                        _bio == BioGate.noSensor) ...[
                      const SizedBox(height: 16),
                      _BioBanner(gate: _bio, onRegister: _enrollFlow),
                    ],
                    const SizedBox(height: 24),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: KeyedSubtree(
                        key: ValueKey<String>(_data == null ? (_error != null ? 'error' : 'loading') : 'data'),
                        child: _data != null
                            ? _buildContent(_data!)
                            : (_error != null ? _buildError() : _buildSkeleton()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────── header (big greeting, tap name → profile) ─────────────
  Widget _buildHeader() {
    final d = _data;
    final first = d?.firstName ?? '';
    final dateText = fmtDate(d?.serverDate ?? DateTime.now());
    final dateLine = (d != null && d.branchName.isNotEmpty) ? '$dateText · ${d.branchName}' : dateText;
    final heading = first.isEmpty ? _greeting() : '${_greeting()},\n$first';

    return Semantics(
      button: true,
      label: 'Open profile',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _openProfile,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading, maxLines: 2, overflow: TextOverflow.ellipsis, style: XText.heading),
                  const SizedBox(height: 6),
                  Text(dateLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: XText.caption),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSkeleton() {
    return const _Shimmer(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Bone(width: 200, height: 30, radius: 10),
            SizedBox(height: 10),
            _Bone(width: 120, height: 30, radius: 10),
            SizedBox(height: 12),
            _Bone(width: 170, height: 14, radius: 7),
          ],
        ),
      ),
    );
  }

  // ───────────── skeleton / error ─────────────
  Widget _buildSkeleton() {
    return const _Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Bone(height: 72, radius: 20),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _Bone(height: 128, radius: 20)),
              SizedBox(width: 12),
              Expanded(child: _Bone(height: 128, radius: 20)),
              SizedBox(width: 12),
              Expanded(child: _Bone(height: 128, radius: 20)),
            ],
          ),
          SizedBox(height: 16),
          _Bone(height: 88, radius: 20),
          SizedBox(height: 16),
          _Bone(height: 240, radius: 20),
          SizedBox(height: 16),
          _Bone(height: 340, radius: 20),
        ],
      ),
    );
  }

  Widget _buildError() {
    return _XCard(
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: _tint(XColors.red, 0.14), shape: BoxShape.circle),
            child: const Center(child: _Hi(XIcons.alert, size: 24, color: XColors.red)),
          ),
          const SizedBox(height: 16),
          const Text('Could not load your data', style: XText.bodyStrong),
          const SizedBox(height: 4),
          Text(_error ?? '', textAlign: TextAlign.center, style: XText.caption.copyWith(fontSize: 13)),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: XColors.ink,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              icon: const _Hi(XIcons.refresh, size: 20, color: Colors.white),
              label: const Text('Retry',
                  style: TextStyle(fontFamily: XText.f, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ───────────── month picker ─────────────
  DateTime _currentMonthOf(HomeData d) => DateTime(d.month.year, d.month.month);

  bool _isCurrent(HomeData d) {
    final p = _picked;
    return p == null || (p.year == d.month.year && p.month == d.month.month);
  }

  Future<void> _openMonthPicker(HomeData d) async {
    final cur = _currentMonthOf(d);
    final shown = _isCurrent(d) ? cur : _picked!;
    final res = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MonthSheet(current: cur, selected: shown, maxBack: _maxMonthsBack),
    );
    if (res == null || !mounted) return;
    _selectMonth(res, d);
  }

  void _selectMonth(DateTime m, HomeData d) {
    final cur = _currentMonthOf(d);
    if (m.year == cur.year && m.month == cur.month) {
      _pickSeq++;
      setState(() {
        _picked = null;
        _pickedMonth = null;
        _pickedPayroll = null;
        _pickedError = null;
      });
      return;
    }
    if (_picked != null && _picked!.year == m.year && _picked!.month == m.month) return;
    setState(() {
      _picked = DateTime(m.year, m.month);
      _pickedMonth = null;
      _pickedPayroll = null;
      _pickedError = null;
    });
    _loadPicked();
  }

  Future<void> _loadPicked({bool force = false}) async {
    final p = _picked;
    if (p == null) return;
    final id = ++_pickSeq;
    if (force && _pickedMonth == null) setState(() => _pickedError = null);
    try {
      final results = await Future.wait<Object?>([
        _service.loadMonth(p.year, p.month, forceRefresh: force),
        _service
            .loadPayroll(p.year, p.month, forceRefresh: force)
            .then<PayrollInfo?>((v) => v)
            .catchError((Object _) => null),
      ]);
      if (!mounted || id != _pickSeq) return;
      setState(() {
        _pickedMonth = results[0] as MonthData;
        _pickedPayroll = results[1] as PayrollInfo?;
        _pickedError = null;
      });
    } on AuthFailure catch (e) {
      if (!mounted || id != _pickSeq) return;
      if (await HomeDataService.handleSessionFailure(e)) return;
      if (!mounted) return;
      setState(() {
        if (_pickedMonth == null) _pickedError = e.message;
      });
    } catch (e) {
      if (!mounted || id != _pickSeq) return;
      debugPrint('❌ Picked month load error: $e');
      setState(() {
        if (_pickedMonth == null) _pickedError = 'Something went wrong. Please try again.';
      });
    }
  }

  /// One point per day (earliest check-in) built from a month's records.
  List<ChartPoint> _chartFromRecords(List<AttRecord> recs) {
    final byDay = <DateTime, AttRecord>{};
    for (final r in recs) {
      if (r.inMin == null) continue;
      final k = dayOnly(r.date);
      final ex = byDay[k];
      if (ex == null || r.inMin! < ex.inMin!) byDay[k] = r;
    }
    final days = byDay.keys.toList()..sort();
    return [
      for (final k in days)
        ChartPoint(
          date: k,
          inMin: byDay[k]!.inMin,
          late: byDay[k]!.status == AttStatus.late || byDay[k]!.lateMin > 0,
        ),
    ];
  }

  // ───────────── content ─────────────
  Widget _buildContent(HomeData d) {
    final current = _isCurrent(d);
    final MonthData m = current ? d.month : (_pickedMonth ?? d.month);
    final PayrollInfo? pay = current ? d.payroll : _pickedPayroll;
    final hasPay = pay != null && pay.monthlySalary > 0;
    final selecting = !current && _pickedMonth == null;
    final sel = current ? _currentMonthOf(d) : _picked!;
    final monthLabel = '${_monthsFull[sel.month - 1]} ${sel.year}';
    final periodLabel = current ? 'Last 14 days' : '${_monthsShort[sel.month - 1]} ${sel.year}';

    final banner = current ? _bannerFor(d) : null;

    final List<Widget> monthBody;
    if (selecting && _pickedError != null) {
      monthBody = [_buildPickedError()];
    } else if (selecting) {
      monthBody = [_buildMonthSkeleton()];
    } else {
      monthBody = _buildMonthSections(d, current, m, pay, hasPay, periodLabel);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (banner != null) ...[
          _TimeOffBanner(data: banner),
          const SizedBox(height: 16),
        ],
        // Leave / sick / holiday today → the banner already says it, hide this.
        if (current && !d.today.blocksCheckIn) ...[
          _TodaySection(data: d),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            _MonthPill(label: monthLabel, isCurrent: current, onTap: () => _openMonthPicker(d)),
            const Spacer(),
            if (!current)
              TextButton(
                onPressed: () => _selectMonth(_currentMonthOf(d), d),
                style: TextButton.styleFrom(
                  foregroundColor: XColors.ink,
                  minimumSize: const Size(48, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Current month',
                    style: TextStyle(fontFamily: XText.f, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        ...monthBody,
      ],
    );
  }

  List<Widget> _buildMonthSections(
      HomeData d,
      bool current,
      MonthData m,
      PayrollInfo? pay,
      bool hasPay,
      String periodLabel,
      ) {
    final chart = current ? d.chart : _chartFromRecords(m.records);
    final chartHasData = current ? chart.any((p) => p.inMin != null) : chart.length >= 2;
    final recent = current ? d.recent : m.records.take(5).toList();

    final presentCaption = m.partialDays > 0 ? '${m.pct}% · ${m.partialDays} part.' : '${m.pct}%';

    final String lateCaption;
    if (pay != null && pay.lateMinutes > 0) {
      lateCaption = '${pay.lateMinutes} min';
    } else {
      lateCaption = m.late > 0 ? 'this month' : 'none';
    }

    final absentCaption =
    m.missedShifts > 0 && d.shifts.length > 1 ? '${m.missedShifts} missed' : 'this month';

    return [
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _StatCard(
                color: XColors.green,
                value: m.attended,
                label: 'Present',
                caption: presentCaption,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                color: XColors.orange,
                value: m.late,
                label: 'Late',
                caption: lateCaption,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                color: XColors.red,
                value: m.absent,
                label: 'Absent',
                caption: absentCaption,
              ),
            ),
          ],
        ),
      ),
      if (current || pay != null) ...[
        const SizedBox(height: 16),
        _PayrollCard(
          payroll: pay,
          busy: _payrollBusy,
          onTap: pay == null
              ? _retryPayroll
              : (pay.monthlySalary > 0 ? () => _openPayroll(pay) : null),
        ),
      ],
      const SizedBox(height: 16),
      _XCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Check-in times', style: XText.bodyStrong)),
                Text(periodLabel, style: XText.caption),
              ],
            ),
            const SizedBox(height: 12),
            if (chartHasData)
              _CheckInChart(
                key: ValueKey<String>('chart-$periodLabel'),
                points: chart,
                shiftStartMin: d.shiftStartMin,
              )
            else
              _EmptyNote(
                icon: XIcons.chart,
                title: current ? 'No check-ins yet' : 'Not enough check-ins',
                subtitle: current
                    ? 'Your arrival times will show up here after your first scan.'
                    : 'Check-in times appear here when the month has at least two.',
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _XCard(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(current ? 'Last 5 days' : 'Latest records', style: XText.bodyStrong)),
                TextButton(
                  onPressed: () => _openRecords(m),
                  style: TextButton.styleFrom(
                    foregroundColor: XColors.ink,
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text(
                    'View all',
                    style: TextStyle(fontFamily: XText.f, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (recent.isEmpty)
              _EmptyNote(
                icon: XIcons.calendar,
                title: current ? 'No records yet' : 'No records this month',
                subtitle: current
                    ? 'Scan the QR code to check in for the first time.'
                    : 'Nothing was recorded for this month.',
              )
            else ...[
              const _TableHeader(),
              for (int i = 0; i < recent.length; i++) ...[
                if (i > 0) const _HDivider(),
                _TableRow(record: recent[i]),
              ],
            ],
          ],
        ),
      ),
    ];
  }

  Widget _buildMonthSkeleton() {
    return const _Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _Bone(height: 128, radius: 20)),
              SizedBox(width: 12),
              Expanded(child: _Bone(height: 128, radius: 20)),
              SizedBox(width: 12),
              Expanded(child: _Bone(height: 128, radius: 20)),
            ],
          ),
          SizedBox(height: 16),
          _Bone(height: 88, radius: 20),
          SizedBox(height: 16),
          _Bone(height: 240, radius: 20),
          SizedBox(height: 16),
          _Bone(height: 340, radius: 20),
        ],
      ),
    );
  }

  Widget _buildPickedError() {
    return _XCard(
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: _tint(XColors.red, 0.14), shape: BoxShape.circle),
            child: const Center(child: _Hi(XIcons.alert, size: 24, color: XColors.red)),
          ),
          const SizedBox(height: 16),
          const Text('Could not load this month', style: XText.bodyStrong),
          const SizedBox(height: 4),
          Text(_pickedError ?? '', textAlign: TextAlign.center, style: XText.caption.copyWith(fontSize: 13)),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _loadPicked(force: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: XColors.ink,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              icon: const _Hi(XIcons.refresh, size: 20, color: Colors.white),
              label: const Text('Retry', style: TextStyle(fontFamily: XText.f, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  MONTH PICKER (pill + bottom sheet)
// ════════════════════════════════════════════════════════════════════
class _MonthPill extends StatelessWidget {
  const _MonthPill({required this.label, required this.isCurrent, required this.onTap});
  final String label;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Change month. Showing $label',
      child: Material(
        color: XColors.card,
        borderRadius: BorderRadius.circular(XRadius.chip),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Hi(XIcons.calendar, size: 18),
                const SizedBox(width: 8),
                Text(label, style: XText.bodyStrong),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: XColors.ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthSheet extends StatelessWidget {
  const _MonthSheet({required this.current, required this.selected, required this.maxBack});
  final DateTime current;
  final DateTime selected;
  final int maxBack;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final months = [for (int i = 0; i <= maxBack; i++) DateTime(current.year, current.month - i)];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(XRadius.sheet)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: const Color(0xFFD1D5DB), borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
            child: Row(
              children: [
                const Expanded(child: Text('Select month', style: XText.title)),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const _Hi(XIcons.close, size: 22),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(12, 4, 12, 16 + bottomInset),
              children: [
                for (int i = 0; i < months.length; i++)
                  _MonthRow(
                    month: months[i],
                    isCurrent: i == 0,
                    isSelected: months[i].year == selected.year && months[i].month == selected.month,
                    onTap: () => Navigator.of(context).pop(months[i]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.month,
    required this.isCurrent,
    required this.isSelected,
    required this.onTap,
  });
  final DateTime month;
  final bool isCurrent;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected ? XColors.card : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_monthsFull[month.month - 1]} ${month.year}',
                    style: isSelected ? XText.bodyStrong : XText.body,
                  ),
                ),
                if (isCurrent) ...[
                  const _Tag('Current', XColors.green),
                  const SizedBox(width: 8),
                ],
                if (isSelected) const Icon(Icons.check_rounded, size: 22, color: XColors.ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  TODAY SECTION  (upcoming-shift badge + pill / multi-shift timeline)
// ════════════════════════════════════════════════════════════════════
class _BadgeInfo {
  const _BadgeInfo(this.shift, this.secsToStart);
  final TodayShift shift;

  /// null → the shift already started and is waiting for check-in.
  final int? secsToStart;
}

class _TodaySection extends StatefulWidget {
  const _TodaySection({required this.data});
  final HomeData data;

  @override
  State<_TodaySection> createState() => _TodaySectionState();
}

class _TodaySectionState extends State<_TodaySection> {
  static const Duration _slow = Duration(seconds: 15);
  static const Duration _fast = Duration(seconds: 1);

  Timer? _timer;
  Duration _period = _slow;

  @override
  void initState() {
    super.initState();
    _start(_slow);
  }

  void _start(Duration p) {
    _timer?.cancel();
    _period = p;
    _timer = Timer.periodic(p, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Picks the shift to announce: a started shift waiting for check-in wins,
  /// otherwise the next upcoming shift of the day (no 1-hour limit anymore).
  _BadgeInfo? _badgeFor(List<TodayShift> shifts, int nowMin, int nowSec) {
    TodayShift? next;
    for (final s in shifts) {
      final p = s.phaseAt(nowMin);
      if (p == ShiftPhase.ready) return _BadgeInfo(s, null);
      if (p == ShiftPhase.upcoming) {
        final secs = s.startMin * 60 - nowSec;
        if (secs > 0 && (next == null || s.startMin < next.startMin)) next = s;
      }
    }
    return next == null ? null : _BadgeInfo(next, next.startMin * 60 - nowSec);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final info = d.today;

    // Always use the device clock so the countdown never disappears
    // because of a server/device date mismatch.
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final nowSec = now.hour * 3600 + now.minute * 60 + now.second;

    final badge = _badgeFor(info.shifts, nowMin, nowSec);

    // Tick every second only while a countdown is on screen.
    final want = (badge?.secsToStart != null) ? _fast : _slow;
    if (want != _period) _start(want);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (badge != null) ...[
          _UpcomingBadge(info: badge, multi: info.isMultiShift),
          const SizedBox(height: 12),
        ],
        if (info.isMultiShift)
          _TodayShiftsCard(shifts: info.shifts, nowMin: nowMin)
        else
          _TodayPill(info: info),
      ],
    );
  }
}

class _UpcomingBadge extends StatelessWidget {
  const _UpcomingBadge({required this.info, required this.multi});
  final _BadgeInfo info;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    final s = info.shift;
    final started = info.secsToStart == null;
    final soon = !started && info.secsToStart! <= 3600;
    final c = started ? XColors.orange : XColors.blue;
    final name = multi ? 'Shift ${s.number}' : 'Your shift';
    final title = started
        ? '$name has started'
        : (soon ? '$name starts soon' : '$name starts at ${fmtMin(s.startMin)}');
    final sub = started ? 'Scan to check in · ${fmtRange(s.startMin, s.endMin)}' : fmtRange(s.startMin, s.endMin);

    return Semantics(
      container: true,
      liveRegion: false,
      label: started ? '$title. Scan to check in.' : '$title. Starts in ${_clock(info.secsToStart!)}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _tint(c, 0.12),
          borderRadius: BorderRadius.circular(XRadius.card),
          border: Border.all(color: _tint(c, 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: _tint(c, 0.2), shape: BoxShape.circle),
              child: Icon(started ? Icons.qr_code_scanner_rounded : Icons.timer_rounded, color: c, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: XText.bodyStrong.copyWith(color: XColors.ink)),
                  const SizedBox(height: 2),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: XText.caption.copyWith(fontSize: 13)),
                ],
              ),
            ),
            if (!started) ...[
              const SizedBox(width: 8),
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(XRadius.chip)),
                child: Text(
                  _clock(info.secsToStart!),
                  style: TextStyle(
                    fontFamily: XText.f,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ───────────── multi-shift "today" card ─────────────
class _PhaseUi {
  const _PhaseUi(this.color, this.label, this.detail);
  final Color color;
  final String label;
  final String detail;
}

_PhaseUi _phaseUi(TodayShift s, ShiftPhase p, int nowMin) {
  switch (p) {
    case ShiftPhase.upcoming:
      final until = s.startMin - nowMin;
      return _PhaseUi(
        XColors.textDim,
        'Upcoming',
        nowMin < 0 ? 'Starts ${fmtMin(s.startMin)}' : 'Starts in ${_untilText(until < 1 ? 1 : until)}',
      );
    case ShiftPhase.ready:
      return const _PhaseUi(XColors.orange, 'Check in', 'Started · scan to check in');
    case ShiftPhase.onShift:
      return _PhaseUi(XColors.green, 'In progress', 'Checked in ${_t(s.inMin)}');
    case ShiftPhase.onShiftLate:
      return _PhaseUi(XColors.orange, 'Late', 'In ${_t(s.inMin)} · ${s.lateMin} min late');
    case ShiftPhase.completed:
      return _PhaseUi(XColors.green, 'Complete', 'In ${_t(s.inMin)} · Out ${_t(s.outMin)}');
    case ShiftPhase.completedLate:
      return _PhaseUi(XColors.orange, 'Late', 'In ${_t(s.inMin)} · Out ${_t(s.outMin)} · ${s.lateMin} min late');
    case ShiftPhase.missed:
      return const _PhaseUi(XColors.red, 'Missed', 'No check-in recorded');
    case ShiftPhase.excused:
      return _PhaseUi(XColors.blue, 'Off', s.note ?? 'Not expected to work');
  }
}

class _TodayShiftsCard extends StatelessWidget {
  const _TodayShiftsCard({required this.shifts, required this.nowMin});
  final List<TodayShift> shifts;
  final int nowMin;

  @override
  Widget build(BuildContext context) {
    final phases = [for (final s in shifts) s.phaseAt(nowMin)];
    final total = shifts.length;
    final attended = phases.where((p) => p.attended).length;
    final completed = phases.where((p) => p.completedOk).length;
    final missed = phases.where((p) => p == ShiftPhase.missed).length;
    final anyLate = phases.any((p) => p == ShiftPhase.onShiftLate || p == ShiftPhase.completedLate);

    // Present for the day when at least one shift was attended,
    // but the missed ones are called out so it never reads as a full day.
    final String chipLabel;
    final Color chipColor;
    if (attended >= 1 && missed == 0) {
      chipLabel = anyLate ? 'Present · late' : 'Present';
      chipColor = anyLate ? XColors.orange : XColors.green;
    } else if (attended >= 1) {
      chipLabel = 'Present · $missed missed';
      chipColor = XColors.orange;
    } else if (missed > 0) {
      chipLabel = 'Absent';
      chipColor = XColors.red;
    } else {
      chipLabel = 'Not started';
      chipColor = XColors.textDim;
    }

    return _XCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Today', style: XText.caption),
                    const SizedBox(height: 2),
                    Text('$completed of $total shifts complete',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: XText.bodyStrong.copyWith(fontSize: 16)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Tag(chipLabel, chipColor),
            ],
          ),
          const SizedBox(height: 4),
          // progress dots, one per shift
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                for (int i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: _barColor(phases[i]),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (int i = 0; i < total; i++)
            _ShiftTimelineRow(
              shift: shifts[i],
              phase: phases[i],
              nowMin: nowMin,
              isLast: i == total - 1,
            ),
        ],
      ),
    );
  }

  Color _barColor(ShiftPhase p) {
    switch (p) {
      case ShiftPhase.completed:
      case ShiftPhase.onShift:
        return XColors.green;
      case ShiftPhase.completedLate:
      case ShiftPhase.onShiftLate:
      case ShiftPhase.ready:
        return XColors.orange;
      case ShiftPhase.missed:
        return XColors.red;
      case ShiftPhase.excused:
        return XColors.blue;
      case ShiftPhase.upcoming:
        return XColors.border;
    }
  }
}

class _ShiftTimelineRow extends StatelessWidget {
  const _ShiftTimelineRow({
    required this.shift,
    required this.phase,
    required this.nowMin,
    required this.isLast,
  });
  final TodayShift shift;
  final ShiftPhase phase;
  final int nowMin;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final ui = _phaseUi(shift, phase, nowMin);
    final done = phase.completedOk;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 3),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: done ? ui.color : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: ui.color, width: 2),
                  ),
                  child: done ? const Icon(Icons.check_rounded, size: 11, color: Colors.white) : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Center(child: Container(width: 2, color: XColors.border)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Shift ${shift.number} · ${fmtRange(shift.startMin, shift.endMin)}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: XText.bodyStrong.copyWith(fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(ui.detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: XText.caption.copyWith(
                              fontSize: 12.5,
                              color: phase == ShiftPhase.missed ||
                                  phase == ShiftPhase.ready ||
                                  phase == ShiftPhase.onShiftLate ||
                                  phase == ShiftPhase.completedLate
                                  ? ui.color
                                  : XColors.textDim,
                              fontWeight: phase == ShiftPhase.missed ||
                                  phase == ShiftPhase.ready ||
                                  phase == ShiftPhase.onShiftLate ||
                                  phase == ShiftPhase.completedLate
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Tag(ui.label, ui.color),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  PAYROLL CARD (home)
// ════════════════════════════════════════════════════════════════════
class _PayrollCard extends StatelessWidget {
  const _PayrollCard({required this.payroll, required this.onTap, this.busy = false});
  final PayrollInfo? payroll;
  final VoidCallback? onTap;
  final bool busy;

  Widget _shell(Widget child, String label) {
    return Semantics(
      button: onTap != null,
      label: label,
      child: Material(
        color: XColors.card,
        borderRadius: BorderRadius.circular(XRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }

  Widget _notice(dynamic icon, String title, String sub) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Center(
            child: busy
                ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: XColors.ink))
                : _Hi(icon, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: XText.bodyStrong),
              const SizedBox(height: 2),
              Text(sub, style: XText.caption.copyWith(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = payroll;

    // 1 ─ the server did not send any pay data
    if (p == null) {
      return _shell(
        _notice(XIcons.refresh, 'Your pay is not available', busy ? 'Loading…' : 'Tap to try again'),
        'Pay not available. Tap to try again.',
      );
    }

    // 2 ─ HR has not set a salary yet
    if (p.monthlySalary <= 0) {
      return _shell(
        _notice(XIcons.info, 'Salary not set', 'HR has not set your monthly salary yet.'),
        'Salary not set.',
      );
    }

    final cur = p.currency;
    final live = p.isEstimate;
    final title = live ? "This month's pay" : '${_monthsFull[p.month - 1]} pay';
    final big = live ? p.earnedNow : p.estimatedNet;
    final pct = (p.progress * 100).round();
    final lateCount = p.lateEvents.length;
    final hasLate = lateCount > 0 || p.lateMinutes > 0;

    return _shell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: XColors.blue, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: XText.body.copyWith(color: XColors.textDim))),
              _Tag(live ? 'Estimate' : 'Final', live ? XColors.blue : XColors.green),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Center(child: _Hi(XIcons.next, size: 18)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(live ? 'Earned so far' : 'Net pay', style: XText.caption),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(fmtMoney(big, cur), maxLines: 1, style: XText.number.copyWith(fontSize: 36)),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: p.progress,
              minHeight: 6,
              backgroundColor: XColors.border,
              valueColor: const AlwaysStoppedAnimation<Color>(XColors.green),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(_periodText(p),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: XText.caption.copyWith(fontSize: 11.5)),
              ),
              Text(live ? '$pct% of the month' : 'Month closed', style: XText.caption.copyWith(fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                _PayStat('Base salary', fmtMoney(p.monthlySalary, cur), XColors.text),
                Container(width: 1, height: 28, color: XColors.border),
                _PayStat(
                  'Deductions',
                  p.hasDeductions ? _minus(p.totalDeduction, cur) : fmtMoney(0, cur),
                  p.hasDeductions ? XColors.orange : XColors.text,
                ),
                Container(width: 1, height: 28, color: XColors.border),
                _PayStat(live ? 'Est. net' : 'Net', fmtMoney(p.estimatedNet, cur), XColors.text),
              ],
            ),
          ),
          if (hasLate) ...[
            const SizedBox(height: 10),
            Text(
              'Late ${lateCount > 0 ? '$lateCount ${lateCount == 1 ? 'time' : 'times'} · ' : ''}${p.lateMinutes} min'
                  '${p.latenessDeduction > 0 ? ' · ${_minus(p.latenessDeduction, cur)}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: XText.caption.copyWith(color: XColors.orange, fontWeight: FontWeight.w600),
            ),
          ],
          if (p.unexcusedAbsentDays > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Absent ${p.unexcusedAbsentDays} ${p.unexcusedAbsentDays == 1 ? 'day' : 'days'}'
                  '${p.absenceDeduction > 0 ? ' · ${_minus(p.absenceDeduction, cur)}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: XText.caption.copyWith(color: XColors.red, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
      'This month pay ${fmtMoney(big, cur)}. Open payroll details.',
    );
  }
}

class _PayStat extends StatelessWidget {
  const _PayStat(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: XText.caption.copyWith(fontSize: 11.5)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, maxLines: 1, style: XText.bodyStrong.copyWith(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  PAYROLL BOTTOM SHEET
// ════════════════════════════════════════════════════════════════════
class _PayrollSheet extends StatefulWidget {
  const _PayrollSheet({required this.scrollController, required this.initial});
  final ScrollController scrollController;
  final PayrollInfo initial;

  @override
  State<_PayrollSheet> createState() => _PayrollSheetState();
}

class _PayrollSheetState extends State<_PayrollSheet> {
  static const int _maxBack = 6;

  int _monthOffset = 0;
  _SheetState _state = _SheetState.data;
  PayrollInfo? _payroll;
  String _error = '';
  int _seq = 0;
  late final DateTime _base;

  DateTime get _shown => DateTime(_base.year, _base.month + _monthOffset);

  @override
  void initState() {
    super.initState();
    _base = DateTime(widget.initial.year, widget.initial.month);
    _payroll = widget.initial;
  }

  Future<void> _load({bool force = false}) async {
    final id = ++_seq;
    final shown = _shown;
    setState(() => _state = _SheetState.loading);
    try {
      final p = await HomeDataService.instance.loadPayroll(shown.year, shown.month, forceRefresh: force);
      if (!mounted || id != _seq) return;
      setState(() {
        _payroll = p;
        _state = _SheetState.data;
      });
    } on AuthFailure catch (e) {
      if (!mounted || id != _seq) return;
      if (await HomeDataService.handleSessionFailure(e)) return;
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _state = _SheetState.error;
      });
    } catch (e) {
      if (!mounted || id != _seq) return;
      debugPrint('❌ Payroll load error: $e');
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _state = _SheetState.error;
      });
    }
  }

  void _changeMonth(int delta) {
    final next = _monthOffset + delta;
    if (next > 0 || next < -_maxBack) return;
    _monthOffset = next;
    _load();
  }

  void _openStatement(PayrollInfo p) {
    debugPrint('🧾 Opening payroll statement · ${p.year}-${p.month}');
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _PayrollStatementPage(payroll: p)));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final m = _shown;
    const disabled = Color(0xFFD1D5DB);
    final canPrev = _monthOffset > -_maxBack;
    final canNext = _monthOffset < 0;

    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(XRadius.sheet)),
      ),
      child: CustomScrollView(
        controller: widget.scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFD1D5DB), borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Payroll', style: XText.title)),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        icon: const _Hi(XIcons.close, size: 22),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedHeader(
              height: 61,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: canPrev ? () => _changeMonth(-1) : null,
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          icon: _Hi(XIcons.prev, size: 22, color: canPrev ? XColors.ink : disabled),
                        ),
                        Expanded(
                          child: Text(
                            '${_monthsFull[m.month - 1]} ${m.year}',
                            textAlign: TextAlign.center,
                            style: XText.bodyStrong.copyWith(fontSize: 16),
                          ),
                        ),
                        IconButton(
                          onPressed: canNext ? () => _changeMonth(1) : null,
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          icon: _Hi(XIcons.next, size: 22, color: canNext ? XColors.ink : disabled),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const _HDivider(),
                ],
              ),
            ),
          ),
          ..._buildBody(bottomInset),
        ],
      ),
    );
  }

  List<Widget> _buildBody(double bottomInset) {
    switch (_state) {
      case _SheetState.loading:
        return [
          SliverToBoxAdapter(
            child: _Shimmer(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
                child: const Column(
                  children: [
                    _Bone(height: 120, radius: 20),
                    SizedBox(height: 16),
                    _Bone(height: 230, radius: 20),
                    SizedBox(height: 16),
                    _Bone(height: 72, radius: 14),
                    SizedBox(height: 12),
                    _Bone(height: 72, radius: 14),
                  ],
                ),
              ),
            ),
          ),
        ];

      case _SheetState.error:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: _tint(XColors.red, 0.14), shape: BoxShape.circle),
                    child: const Center(child: _Hi(XIcons.alert, size: 24, color: XColors.red)),
                  ),
                  const SizedBox(height: 16),
                  const Text('Could not load payroll', style: XText.bodyStrong),
                  const SizedBox(height: 4),
                  Text(_error, textAlign: TextAlign.center, style: XText.caption.copyWith(fontSize: 13)),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => _load(force: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: XColors.ink,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      icon: const _Hi(XIcons.refresh, size: 20, color: Colors.white),
                      label: const Text('Retry', style: TextStyle(fontFamily: XText.f, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ];

      case _SheetState.empty:
      case _SheetState.data:
        final p = _payroll;
        if (p == null) return const [SliverToBoxAdapter(child: SizedBox.shrink())];
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 28 + bottomInset),
              child: _PayrollBody(payroll: p, onStatement: () => _openStatement(p)),
            ),
          ),
        ];
    }
  }
}

class _PayrollBody extends StatelessWidget {
  const _PayrollBody({required this.payroll, required this.onStatement});
  final PayrollInfo payroll;
  final VoidCallback onStatement;

  @override
  Widget build(BuildContext context) {
    final p = payroll;
    final cur = p.currency;
    final lates = p.lateEvents;

    // Show the summary when anything happened: deduction, late minutes or absences.
    final showSummary = p.monthlySalary > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NetPayHero(payroll: p),
        const SizedBox(height: 16),

        if (showSummary) ...[
          _XCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                _KV('Monthly salary', fmtMoney(p.monthlySalary, cur)),
                if (p.dailySalary != null) ...[
                  const _HDivider(),
                  _KV('Daily salary', fmtMoney(p.dailySalary!, cur)),
                ],
                if (p.expectedDays != null && p.expectedDays! > 0) ...[
                  const _HDivider(),
                  _KV('Attendance', '${p.attendanceDays ?? 0} of ${p.expectedDays} days'),
                ],
                const _HDivider(),
                _KV('Late minutes', '${p.lateMinutes} min',
                    valueColor: p.lateMinutes > 0 ? XColors.orange : XColors.text),
                const _HDivider(),
                _KV('Lateness deductions',
                    p.latenessDeduction > 0 ? _minus(p.latenessDeduction, cur) : fmtMoney(0, cur),
                    valueColor: p.latenessDeduction > 0 ? XColors.orange : XColors.text),
                const _HDivider(),
                _KV('Unexcused absent days', '${p.unexcusedAbsentDays}'),
                const _HDivider(),
                _KV('Absence deductions',
                    p.absenceDeduction > 0 ? _minus(p.absenceDeduction, cur) : fmtMoney(0, cur),
                    valueColor: p.absenceDeduction > 0 ? XColors.red : XColors.text),
                const _HDivider(),
                _KV(p.isEstimate ? 'Estimated net pay' : 'Net pay', fmtMoney(p.estimatedNet, cur), strong: true),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: _Hi(XIcons.info, size: 16, color: XColors.textDim),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Lateness is counted only after ${p.graceMinutes} minutes.'
                      '${p.isEstimate ? ' Figures are estimates until the month closes.' : ''}',
                  style: XText.caption.copyWith(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ] else ...[
          const _XCard(
            child: _EmptyNote(
              icon: XIcons.calendar,
              title: 'No deductions',
              subtitle: 'Nothing has been deducted from your salary this month.',
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Lateness history with dates and times.
        if (lates.isNotEmpty) ...[
          Row(
            children: [
              const Expanded(child: Text('Lateness history', style: XText.bodyStrong)),
              Text('${lates.length} ${lates.length == 1 ? 'time' : 'times'}', style: XText.caption),
            ],
          ),
          const SizedBox(height: 8),
          _XCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (int i = 0; i < lates.length; i++) ...[
                  if (i > 0) const _HDivider(),
                  _LateRow(event: lates[i], currency: cur),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        _StatementLink(onTap: onStatement),
      ],
    );
  }
}

class _NetPayHero extends StatelessWidget {
  const _NetPayHero({required this.payroll});
  final PayrollInfo payroll;

  @override
  Widget build(BuildContext context) {
    final p = payroll;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: XColors.ink, borderRadius: BorderRadius.circular(XRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.isEstimate ? 'Estimated net pay' : 'Net pay',
                  style: XText.body.copyWith(color: Colors.white70),
                ),
              ),
              if (p.isEstimate)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(30),
                    borderRadius: BorderRadius.circular(XRadius.chip),
                  ),
                  child: const Text('Estimate',
                      style: TextStyle(fontFamily: XText.f, fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              fmtMoney(p.estimatedNet, p.currency),
              maxLines: 1,
              style: XText.number.copyWith(color: Colors.white, fontSize: 36),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Monthly salary ${fmtMoney(p.monthlySalary, p.currency)}',
            style: XText.caption.copyWith(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            'Period ${_periodText(p)} · ${p.currency}',
            style: XText.caption.copyWith(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _KV extends StatelessWidget {
  const _KV(this.label, this.value, {this.valueColor = XColors.text, this.strong = false});
  final String label;
  final String value;
  final Color valueColor;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (strong ? XText.bodyStrong : XText.body).copyWith(color: strong ? XColors.ink : XColors.textDim)),
          ),
          const SizedBox(width: 12),
          Text(value, style: XText.bodyStrong.copyWith(color: valueColor, fontSize: strong ? 16 : 14)),
        ],
      ),
    );
  }
}

class _LateRow extends StatelessWidget {
  const _LateRow({required this.event, required this.currency});
  final PayLate event;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final s = event.shift;
    final shiftLabel = event.multi ? 'Shift ${s.number} · ' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fmtDate(event.date), style: XText.bodyStrong),
                const SizedBox(height: 2),
                Text('${shiftLabel}Due ${fmtMin(s.schedStartMin)} · In ${_t(s.inMin)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: XText.caption.copyWith(fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  '${s.lateMin} min late'
                      '${s.countedLateMin > 0 && s.countedLateMin != s.lateMin ? ' · ${s.countedLateMin} counted' : ''}',
                  style: XText.caption.copyWith(color: XColors.orange, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                s.deduction > 0 ? _minus(s.deduction, currency) : 'No charge',
                style: XText.bodyStrong.copyWith(color: s.deduction > 0 ? XColors.orange : XColors.textDim),
              ),
              if (s.isEstimate && s.deduction > 0) ...[
                const SizedBox(height: 2),
                const Text('Est.', style: XText.caption),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatementLink extends StatelessWidget {
  const _StatementLink({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: XColors.card,
      borderRadius: BorderRadius.circular(XRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.receipt_long_rounded, size: 18, color: XColors.ink),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Detailed payroll statement', style: XText.bodyStrong),
                    SizedBox(height: 2),
                    Text('Every day and shift, with times and deductions', style: XText.caption),
                  ],
                ),
              ),
              const _Hi(XIcons.next, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  PAYROLL STATEMENT (full day-by-day, shift-by-shift history)
// ════════════════════════════════════════════════════════════════════
class _KindUi {
  const _KindUi(this.color, this.label);
  final Color color;
  final String label;
}

_KindUi _kindUi(PayKind k) {
  switch (k) {
    case PayKind.onTime:
      return const _KindUi(XColors.green, 'On time');
    case PayKind.late:
      return const _KindUi(XColors.orange, 'Late');
    case PayKind.unexcused:
      return const _KindUi(XColors.red, 'Unexcused absence');
    case PayKind.leave:
      return const _KindUi(XColors.blue, 'Approved leave');
    case PayKind.sick:
      return const _KindUi(XColors.orange, 'Sick leave');
    case PayKind.holiday:
      return const _KindUi(XColors.purple, 'Holiday');
    case PayKind.future:
      return const _KindUi(XColors.textDim, 'Upcoming');
  }
}

class _PayrollStatementPage extends StatelessWidget {
  const _PayrollStatementPage({required this.payroll});
  final PayrollInfo payroll;

  @override
  Widget build(BuildContext context) {
    final p = payroll;
    final cur = p.currency;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: XColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const _Hi(XIcons.prev, size: 22),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Payroll statement',
                            style: TextStyle(
                                fontFamily: XText.f, fontSize: 18, fontWeight: FontWeight.w700, color: XColors.ink)),
                        Text('${_monthsFull[p.month - 1]} ${p.year}', style: XText.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const _HDivider(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
                children: [
                  if (p.isEstimate) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _tint(XColors.orange, 0.12),
                        borderRadius: BorderRadius.circular(XRadius.card),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Hi(XIcons.info, size: 18, color: XColors.orange),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Figures marked Est. are estimates and can change until the month closes. '
                                  'Upcoming shifts and approved leave are not deducted. '
                                  'Lateness is counted only after ${p.graceMinutes} minutes.',
                              style: XText.caption.copyWith(fontSize: 13, color: XColors.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _XCard(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Column(
                      children: [
                        _KV('Total deductions', p.hasDeductions ? _minus(p.totalDeduction, cur) : fmtMoney(0, cur),
                            valueColor: p.hasDeductions ? XColors.orange : XColors.text),
                        const _HDivider(),
                        _KV(p.isEstimate ? 'Estimated net pay' : 'Net pay', fmtMoney(p.estimatedNet, cur), strong: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (p.days.isEmpty)
                    const _XCard(
                      child: _EmptyNote(
                        icon: XIcons.calendar,
                        title: 'No shifts to show',
                        subtitle: 'Scheduled shifts for this month will appear here.',
                      ),
                    )
                  else
                    for (final day in p.days) ...[
                      _StatementDay(day: day, currency: cur),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatementDay extends StatelessWidget {
  const _StatementDay({required this.day, required this.currency});
  final PayDay day;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final ded = day.deduction;
    return _XCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(fmtDate(day.date), style: XText.bodyStrong)),
              if (day.isFuture)
                const Text('Upcoming', style: XText.caption)
              else if (ded > 0)
                Text(_minus(ded, currency),
                    style: XText.bodyStrong.copyWith(color: XColors.orange)),
            ],
          ),
          const SizedBox(height: 4),
          for (int i = 0; i < day.shifts.length; i++) ...[
            if (i > 0) const _HDivider(),
            _StatementShiftRow(shift: day.shifts[i], multi: day.isMulti, currency: currency),
          ],
        ],
      ),
    );
  }
}

class _StatementShiftRow extends StatelessWidget {
  const _StatementShiftRow({required this.shift, required this.multi, required this.currency});
  final PayShift shift;
  final bool multi;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final s = shift;
    final ui = _kindUi(s.kind);
    final sched = fmtRange(s.schedStartMin, s.schedEndMin);

    final String actual;
    switch (s.kind) {
      case PayKind.future:
        actual = 'Not counted yet';
        break;
      case PayKind.unexcused:
        actual = 'No check-in recorded';
        break;
      case PayKind.leave:
      case PayKind.sick:
      case PayKind.holiday:
        actual = s.note ?? 'Not expected to work';
        break;
      default:
        actual = 'In ${_t(s.inMin)} · Out ${_t(s.outMin)}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(multi ? 'Shift ${s.number} · $sched' : sched,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: XText.bodyStrong.copyWith(fontSize: 13)),
                const SizedBox(height: 2),
                Text(actual,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: XText.caption.copyWith(fontSize: 12.5)),
                if (s.kind == PayKind.late) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${s.lateMin} min late'
                        '${s.countedLateMin > 0 && s.countedLateMin != s.lateMin ? ' · ${s.countedLateMin} counted' : ''}',
                    style: XText.caption.copyWith(color: XColors.orange, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Tag(ui.label, ui.color),
              if (s.deduction > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '${_minus(s.deduction, currency)}${s.isEstimate ? ' (Est.)' : ''}',
                  style: XText.caption.copyWith(
                    color: s.kind == PayKind.unexcused ? XColors.red : XColors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  TIME-OFF BANNER (long horizontal card)
// ════════════════════════════════════════════════════════════════════
class _TimeOffBanner extends StatelessWidget {
  const _TimeOffBanner({required this.data});
  final _BannerData data;

  @override
  Widget build(BuildContext context) {
    final c = data.color;
    return Semantics(
      container: true,
      label: '${data.title}. ${data.subtitle}',
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _tint(c, 0.12),
          borderRadius: BorderRadius.circular(XRadius.card),
          border: Border.all(color: _tint(c, 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: _tint(c, 0.2), shape: BoxShape.circle),
              child: Icon(data.icon, color: c, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    data.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: XText.bodyStrong.copyWith(color: XColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: XText.caption.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),
            if (data.trail != null) ...[
              const SizedBox(width: 8),
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(XRadius.chip),
                ),
                child: Text(
                  data.trail!,
                  maxLines: 1,
                  style: TextStyle(fontFamily: XText.f, fontSize: 12, fontWeight: FontWeight.w600, color: c),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  BIOMETRIC BANNER
// ════════════════════════════════════════════════════════════════════
class _BioBanner extends StatelessWidget {
  const _BioBanner({required this.gate, required this.onRegister});
  final BioGate gate;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final bool register = gate == BioGate.needsEnroll;
    final Color c = register ? XColors.blue : XColors.orange;
    final String title = register
        ? 'Register your fingerprint'
        : gate == BioGate.changed
        ? 'Fingerprint changed'
        : 'No fingerprint on this phone';
    final String sub = register
        ? 'Required before you can check in.'
        : gate == BioGate.changed
        ? 'Ask HR to approve re-enrollment.'
        : 'Add one in your phone settings.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _tint(c, 0.12), borderRadius: BorderRadius.circular(XRadius.card)),
      child: Row(
        children: [
          Icon(Icons.fingerprint, color: c, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: XText.bodyStrong.copyWith(color: c)),
                const SizedBox(height: 2),
                Text(sub, style: XText.caption),
              ],
            ),
          ),
          if (register)
            TextButton(
              onPressed: onRegister,
              style: TextButton.styleFrom(foregroundColor: c, minimumSize: const Size(48, 48)),
              child: const Text('Register', style: TextStyle(fontFamily: XText.f, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  TOP CENTER LOGO
// ════════════════════════════════════════════════════════════════════
class _TopLogo extends StatelessWidget {
  const _TopLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Center(
          child: Image.asset(
            _logoAsset,
            height: 40,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  PROFILE BOTTOM SHEET (view only + logout)
// ════════════════════════════════════════════════════════════════════
class ProfileSheet extends StatelessWidget {
  const ProfileSheet({
    super.key,
    required this.source,
    required this.email,
    required this.onRetry,
    required this.onLogout,
  });

  final ValueListenable<_Snap> source;
  final String? email;
  final VoidCallback onRetry;
  final VoidCallback onLogout;

  /// Add more read-only rows here if HomeData has more fields
  /// (phone, role, staff ID...). One line each.
  List<_InfoRowData> _rows(HomeData d) => [
    _InfoRowData(XIcons.user, 'Full name', d.fullName),
    if (email != null && email!.isNotEmpty) _InfoRowData(XIcons.mail, 'Email', email!),
    if (d.branchName.isNotEmpty) _InfoRowData(XIcons.branch, 'Branch', d.branchName),
    _InfoRowData(
      XIcons.clock,
      d.shifts.length > 1 ? 'Shifts' : 'Shift',
      d.shifts.map((s) => fmtRange(s.startMin, s.endMin)).join('\n'),
    ),
  ];

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Log out?',
            style: TextStyle(
                fontFamily: XText.f, fontSize: 18, fontWeight: FontWeight.w700, color: XColors.ink)),
        content: const Text('You will need to sign in again to use the app.', style: XText.body),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: XColors.ink,
              minimumSize: const Size(48, 48),
            ),
            child: const Text('Cancel',
                style: TextStyle(fontFamily: XText.f, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: XColors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size(96, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: const Text('Log out',
                style: TextStyle(fontFamily: XText.f, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok == true) onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(XRadius.sheet)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<_Snap>(
              valueListenable: source,
              builder: (context, snap, _) {
                final Widget body;
                final String key;
                if (snap.data != null) {
                  key = 'data';
                  body = _buildData(snap.data!);
                } else if (snap.error != null) {
                  key = 'error';
                  body = _buildError(snap.error!);
                } else {
                  key = 'loading';
                  body = const _ProfileSkeleton();
                }
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(key: ValueKey<String>(key), child: body),
                );
              },
            ),
            const SizedBox(height: 28),
            Tooltip(
              message: 'Log out',
              child: Semantics(
                button: true,
                label: 'Log out',
                child: Material(
                  color: XColors.red,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _confirmLogout(context),
                    child: const SizedBox(
                      width: 68,
                      height: 68,
                      child: Center(child: _Hi(XIcons.logout, size: 28, color: Colors.white)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildData(HomeData d) {
    final m = d.month;
    final rows = _rows(d);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: XColors.ink),
            child: Text(
              _initialsOf(d.fullName),
              style: const TextStyle(
                fontFamily: XText.f,
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(d.fullName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: XText.title),
        if (d.branchName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(d.branchName, textAlign: TextAlign.center, style: XText.caption.copyWith(fontSize: 13)),
        ],
        const SizedBox(height: 24),
        const Text('This month', style: XText.caption),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _MiniStat(color: XColors.green, label: 'Present', value: '${m.present}')),
            const SizedBox(width: 12),
            Expanded(child: _MiniStat(color: XColors.orange, label: 'Late', value: '${m.late}')),
            const SizedBox(width: 12),
            Expanded(child: _MiniStat(color: XColors.red, label: 'Absent', value: '${m.absent}')),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: XColors.card,
            borderRadius: BorderRadius.circular(XRadius.card),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 52),
                    child: Container(height: 1, color: XColors.border),
                  ),
                _InfoRow(data: rows[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Hi(XIcons.info, size: 16, color: XColors.textDim),
            SizedBox(width: 6),
            Text('These details are view only.', style: XText.caption),
          ],
        ),
      ],
    );
  }

  Widget _buildError(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: _tint(XColors.red, 0.14), shape: BoxShape.circle),
            child: const Center(child: _Hi(XIcons.alert, size: 24, color: XColors.red)),
          ),
          const SizedBox(height: 16),
          const Text('Could not load your profile', style: XText.bodyStrong),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center, style: XText.caption.copyWith(fontSize: 13)),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: XColors.ink,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              icon: const _Hi(XIcons.refresh, size: 20, color: Colors.white),
              label: const Text('Retry',
                  style: TextStyle(fontFamily: XText.f, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRowData {
  const _InfoRowData(this.icon, this.label, this.value);
  final dynamic icon;
  final String label;
  final String value;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.data});
  final _InfoRowData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Center(child: _Hi(data.icon, size: 18)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.label, style: XText.caption),
                const SizedBox(height: 2),
                Text(data.value, maxLines: 4, overflow: TextOverflow.ellipsis, style: XText.bodyStrong),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.color, required this.label, required this.value});
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: XColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: XText.caption),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontFamily: XText.f, fontSize: 22, fontWeight: FontWeight.w700, color: XColors.ink, height: 1.2)),
        ],
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const _Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _Bone(width: 88, height: 88, radius: 44)),
          SizedBox(height: 16),
          Center(child: _Bone(width: 180, height: 22, radius: 8)),
          SizedBox(height: 8),
          Center(child: _Bone(width: 110, height: 14, radius: 7)),
          SizedBox(height: 24),
          _Bone(width: 80, height: 12, radius: 6),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _Bone(height: 72, radius: 16)),
              SizedBox(width: 12),
              Expanded(child: _Bone(height: 72, radius: 16)),
              SizedBox(width: 12),
              Expanded(child: _Bone(height: 72, radius: 16)),
            ],
          ),
          SizedBox(height: 20),
          _Bone(height: 232, radius: 20),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  SMALL WIDGETS
// ════════════════════════════════════════════════════════════════════
class _XCard extends StatelessWidget {
  const _XCard({required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: XColors.card,
        borderRadius: BorderRadius.circular(XRadius.card),
      ),
      child: child,
    );
  }
}

class _HDivider extends StatelessWidget {
  const _HDivider();
  @override
  Widget build(BuildContext context) => Container(height: 1, color: XColors.border);
}

/// Small rounded label used for shift phases and payroll kinds.
class _Tag extends StatelessWidget {
  const _Tag(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _tint(color, 0.14),
        borderRadius: BorderRadius.circular(XRadius.chip),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(fontFamily: XText.f, fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: visible
          ? Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: _tint(XColors.orange, 0.16),
        child: Row(
          children: [
            const _Hi(XIcons.wifiOff, size: 18, color: XColors.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No connection · showing last saved data',
                style: XText.bodyStrong.copyWith(color: XColors.orange, fontSize: 13),
              ),
            ),
          ],
        ),
      )
          : const SizedBox(width: double.infinity),
    );
  }
}

/// Single-shift staff keep the simple pill.
class _TodayPill extends StatelessWidget {
  const _TodayPill({required this.info});
  final TodayInfo info;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;

    switch (info.state) {
      case TodayState.checkedOut:
        label = info.lateMin > 0
            ? 'Out ${fmtMin(info.outMin ?? 0)} · was ${info.lateMin} min late'
            : 'Checked out ${fmtMin(info.outMin ?? 0)}';
        color = info.lateMin > 0 ? XColors.orange : XColors.ink;
        break;
      case TodayState.late:
        label = info.inMin != null
            ? 'Late ${info.lateMin} min · in ${fmtMin(info.inMin!)}'
            : 'Late ${info.lateMin} min';
        color = XColors.orange;
        break;
      case TodayState.checkedIn:
        label = 'Checked in ${fmtMin(info.inMin ?? 0)}';
        color = XColors.green;
        break;
      case TodayState.absent:
        label = 'Marked absent';
        color = XColors.red;
        break;
      case TodayState.leave:
        label = 'On leave';
        color = XColors.blue;
        break;
      case TodayState.sick:
        label = 'On sick leave';
        color = XColors.orange;
        break;
      case TodayState.holiday:
        label = 'Holiday';
        color = XColors.purple;
        break;
      case TodayState.notCheckedIn:
        label = 'Not checked in';
        color = XColors.textDim;
        break;
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: _tint(color, 0.12),
          borderRadius: BorderRadius.circular(XRadius.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: XText.bodyStrong.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.color,
    required this.value,
    required this.label,
    required this.caption,
  });
  final Color color;
  final int value;
  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return _XCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: XText.body.copyWith(color: XColors.textDim, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('$value', style: XText.number),
          ),
          const SizedBox(height: 4),
          Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: XText.caption),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final AttStatus status;

  @override
  Widget build(BuildContext context) {
    late final Color c;
    late final String t;
    switch (status) {
      case AttStatus.present:
        c = XColors.green;
        t = 'Present';
        break;
      case AttStatus.late:
        c = XColors.orange;
        t = 'Late';
        break;
      case AttStatus.absent:
        c = XColors.red;
        t = 'Absent';
        break;
      case AttStatus.leave:
        c = XColors.blue;
        t = 'Leave';
        break;
      case AttStatus.sick:
        c = XColors.orange;
        t = 'Sick';
        break;
      case AttStatus.holiday:
        c = XColors.purple;
        t = 'Holiday';
        break;
    }
    return _Tag(t, c);
  }
}

/// Source badge: "Self check-in" (QR) or "HR-attendee" (manual).
class _SourceTag extends StatelessWidget {
  const _SourceTag(this.source);
  final AttSource source;

  @override
  Widget build(BuildContext context) {
    final byHr = source == AttSource.manual;
    final c = byHr ? XColors.blue : XColors.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: byHr ? _tint(XColors.blue, 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: byHr ? _tint(XColors.blue, 0.4) : XColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Hi(byHr ? XIcons.hr : XIcons.selfCheck, size: 12, color: c),
          const SizedBox(width: 4),
          Text(
            byHr ? 'HR-attendee' : 'Self check-in',
            style: TextStyle(fontFamily: XText.f, fontSize: 11, fontWeight: FontWeight.w500, color: c),
          ),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.icon, required this.title, required this.subtitle});
  final dynamic icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Center(child: _Hi(icon, size: 24)),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: XText.bodyStrong),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: XText.caption.copyWith(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ───────────── table ─────────────
class _TableHeader extends StatelessWidget {
  const _TableHeader();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('Date', style: XText.caption)),
          Expanded(flex: 3, child: Text('In', style: XText.caption)),
          Expanded(flex: 3, child: Text('Out', style: XText.caption)),
          SizedBox(width: 76, child: Text('Status', textAlign: TextAlign.right, style: XText.caption)),
        ],
      ),
    );
  }
}

class _FitText extends StatelessWidget {
  const _FitText(this.text, {this.color = XColors.text});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(text, maxLines: 1, style: XText.body.copyWith(fontSize: 13, color: color)),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.record});
  final AttRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FitText(fmtDate(r.date)),
                if (r.isMultiShift) Text('Shift ${r.shiftNumber} of ${r.shiftTotal}', style: XText.caption.copyWith(fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: _FitText(
              r.inMin == null ? '–' : fmtMin(r.inMin!).replaceAll(' ', '\u00A0'),
              color: r.status == AttStatus.late ? XColors.orange : XColors.text,
            ),
          ),
          Expanded(
            flex: 3,
            child: _FitText(r.outMin == null ? '–' : fmtMin(r.outMin!).replaceAll(' ', '\u00A0')),
          ),
          SizedBox(width: 76, child: Align(alignment: Alignment.centerRight, child: _StatusChip(r.status))),
        ],
      ),
    );
  }
}

// ───────────── FAB ─────────────
class _ScanFab extends StatelessWidget {
  const _ScanFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: XColors.ink,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: const SizedBox(
          height: 56,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Hi(XIcons.qr, size: 24, color: Colors.white),
                SizedBox(width: 10),
                Text(
                  'Scan',
                  style: TextStyle(
                    fontFamily: XText.f,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────── shimmer ─────────────
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});
  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final center = -1.5 + 3 * _c.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (Rect rect) => LinearGradient(
            begin: Alignment(center - 1, 0),
            end: Alignment(center + 1, 0),
            colors: const [Color(0xFFEBEEF3), Color(0xFFF8F9FB), Color(0xFFEBEEF3)],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}

class _Bone extends StatelessWidget {
  const _Bone({this.width = double.infinity, required this.height, this.radius = 8});
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEBEEF3),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  CHECK-IN CHART (custom painter, no packages)
// ════════════════════════════════════════════════════════════════════
class _CheckInChart extends StatefulWidget {
  const _CheckInChart({super.key, required this.points, required this.shiftStartMin});
  final List<ChartPoint> points;
  final int shiftStartMin;

  @override
  State<_CheckInChart> createState() => _CheckInChartState();
}

class _CheckInChartState extends State<_CheckInChart> {
  static const double _height = 190;
  int? _selected;

  int? _hit(double dx, double width) {
    final n = widget.points.length;
    int? best;
    double bestDist = double.infinity;
    for (int i = 0; i < n; i++) {
      if (widget.points[i].inMin == null) continue;
      final d = (_ChartPainter.xAt(i, n, width) - dx).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return bestDist <= 22 ? best : null;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, c) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              final i = _hit(d.localPosition.dx, c.maxWidth);
              setState(() => _selected = (i == _selected) ? null : i);
            },
            child: CustomPaint(
              size: Size(c.maxWidth, _height),
              painter: _ChartPainter(
                points: widget.points,
                shiftStartMin: widget.shiftStartMin,
                selected: _selected,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.points, required this.shiftStartMin, required this.selected});

  final List<ChartPoint> points;
  final int shiftStartMin;
  final int? selected;

  static const double padX = 14;
  static const double padTop = 40;
  static const double padBottom = 26;

  static double xAt(int i, int n, double w) => padX + i * (w - 2 * padX) / (n - 1);

  TextPainter _tp(String s, TextStyle st) =>
      TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr)..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    final vals = [for (final p in points) if (p.inMin != null) p.inMin!];
    if (vals.isEmpty || n < 2) return;

    final lo = (math.min(vals.reduce(math.min), shiftStartMin) - 10).toDouble();
    final hi = (math.max(vals.reduce(math.max), shiftStartMin) + 10).toDouble();
    final plotH = size.height - padTop - padBottom;
    double yAt(num v) => padTop + (1 - (v - lo) / (hi - lo)) * plotH;

    // dashed shift-start line
    final yShift = yAt(shiftStartMin);
    final dashPaint = Paint()
      ..color = _tint(XColors.textDim, 0.7)
      ..strokeWidth = 1;
    double dx = padX;
    while (dx < size.width - padX) {
      canvas.drawLine(
        Offset(dx, yShift),
        Offset(math.min(dx + 5, size.width - padX), yShift),
        dashPaint,
      );
      dx += 10;
    }
    final shiftLabel = _tp(
      'Shift start ${fmtMin(shiftStartMin)}',
      const TextStyle(fontFamily: XText.f, fontSize: 11, color: XColors.textDim),
    );
    shiftLabel.paint(canvas, Offset(padX, yShift - shiftLabel.height - 4));

    // points + smooth line
    final pts = <int, Offset>{};
    for (int i = 0; i < n; i++) {
      final m = points[i].inMin;
      if (m != null) pts[i] = Offset(xAt(i, n, size.width), yAt(m));
    }
    final entries = pts.entries.toList();

    if (entries.length > 1) {
      final path = Path()..moveTo(entries.first.value.dx, entries.first.value.dy);
      for (int k = 1; k < entries.length; k++) {
        final p = entries[k - 1].value;
        final c = entries[k].value;
        final mx = (p.dx + c.dx) / 2;
        path.cubicTo(mx, p.dy, mx, c.dy, c.dx, c.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = XColors.ink,
      );
    }

    for (final e in entries) {
      final color = points[e.key].late ? XColors.orange : XColors.green;
      if (e.key == selected) {
        canvas.drawCircle(e.value, 11, Paint()..color = _tint(color, 0.22));
      }
      canvas.drawCircle(e.value, 6.5, Paint()..color = XColors.card);
      canvas.drawCircle(e.value, 4.5, Paint()..color = color);
    }

    // bottom labels (first / middle / last)
    const labelStyle = TextStyle(fontFamily: XText.f, fontSize: 11, color: XColors.textDim);
    for (final i in {0, n ~/ 2, n - 1}) {
      final d = points[i].date;
      final tp = _tp('${d.day} ${_monthsShort[d.month - 1]}', labelStyle);
      final x = (xAt(i, n, size.width) - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(x, size.height - tp.height));
    }

    // tooltip
    final s = selected;
    if (s != null && pts.containsKey(s)) {
      final p = pts[s]!;
      final d = points[s].date;
      final tp = _tp(
        '${d.day} ${_monthsShort[d.month - 1]} · ${fmtMin(points[s].inMin!)}${points[s].late ? ' · late' : ''}',
        const TextStyle(fontFamily: XText.f, fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
      );
      const padH = 10.0, padV = 6.0;
      final w = tp.width + padH * 2;
      final h = tp.height + padV * 2;
      final left = (p.dx - w / 2).clamp(0.0, size.width - w);
      double top = p.dy - 14 - h;
      if (top < 0) top = p.dy + 14;
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), const Radius.circular(8));
      canvas.drawRRect(rect, Paint()..color = XColors.ink);
      tp.paint(canvas, Offset(left + padH, top + padV));
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.points != points || old.selected != selected || old.shiftStartMin != shiftStartMin;
}

// ════════════════════════════════════════════════════════════════════
//  ALL RECORDS BOTTOM SHEET
// ════════════════════════════════════════════════════════════════════
enum _SheetState { loading, data, empty, error }

class _RecordsSheet extends StatefulWidget {
  const _RecordsSheet({required this.scrollController, required this.initial});
  final ScrollController scrollController;
  final MonthData initial;

  @override
  State<_RecordsSheet> createState() => _RecordsSheetState();
}

class _RecordsSheetState extends State<_RecordsSheet> {
  static const int _maxBack = 6;

  int _monthOffset = 0;
  _SheetState _state = _SheetState.data;
  MonthData? _month;
  String _error = '';
  int _seq = 0;
  late final DateTime _base;

  DateTime get _shown => DateTime(_base.year, _base.month + _monthOffset);

  @override
  void initState() {
    super.initState();
    _base = DateTime(widget.initial.year, widget.initial.month);
    _month = widget.initial;
    _state = widget.initial.records.isEmpty ? _SheetState.empty : _SheetState.data;
  }

  Future<void> _load() async {
    final id = ++_seq;
    final shown = _shown;
    setState(() => _state = _SheetState.loading);
    try {
      final m = await HomeDataService.instance.loadMonth(shown.year, shown.month);
      if (!mounted || id != _seq) return;
      setState(() {
        _month = m;
        _state = m.records.isEmpty ? _SheetState.empty : _SheetState.data;
      });
    } on AuthFailure catch (e) {
      if (!mounted || id != _seq) return;
      if (await HomeDataService.handleSessionFailure(e)) return;
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _state = _SheetState.error;
      });
    } catch (e) {
      if (!mounted || id != _seq) return;
      debugPrint('❌ Month load error: $e');
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _state = _SheetState.error;
      });
    }
  }

  void _changeMonth(int delta) {
    final next = _monthOffset + delta;
    if (next > 0 || next < -_maxBack) return;
    _monthOffset = next;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final m = _shown;
    final data = _month;
    final hasData = _state == _SheetState.data && data != null;
    const disabled = Color(0xFFD1D5DB);
    final canPrev = _monthOffset > -_maxBack;
    final canNext = _monthOffset < 0;

    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(XRadius.sheet)),
      ),
      child: CustomScrollView(
        controller: widget.scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                  child: Row(
                    children: [
                      const Expanded(child: Text('All records', style: XText.title)),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        icon: const _Hi(XIcons.close, size: 22),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedHeader(
              height: 112,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: canPrev ? () => _changeMonth(-1) : null,
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          icon: _Hi(XIcons.prev, size: 22, color: canPrev ? XColors.ink : disabled),
                        ),
                        Expanded(
                          child: Text(
                            '${_monthsFull[m.month - 1]} ${m.year}',
                            textAlign: TextAlign.center,
                            style: XText.bodyStrong.copyWith(fontSize: 16),
                          ),
                        ),
                        IconButton(
                          onPressed: canNext ? () => _changeMonth(1) : null,
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          icon: _Hi(XIcons.next, size: 22, color: canNext ? XColors.ink : disabled),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          children: [
                            _SummaryItem(
                                color: XColors.green,
                                label: 'Present',
                                value: hasData ? '${data.present}' : '–'),
                            const SizedBox(width: 20),
                            _SummaryItem(
                                color: XColors.orange,
                                label: 'Late',
                                value: hasData ? '${data.late}' : '–'),
                            const SizedBox(width: 20),
                            _SummaryItem(
                                color: XColors.red,
                                label: 'Absent',
                                value: hasData ? '${data.absent}' : '–'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  const _HDivider(),
                ],
              ),
            ),
          ),
          ..._buildBody(bottomInset),
        ],
      ),
    );
  }

  List<Widget> _buildBody(double bottomInset) {
    switch (_state) {
      case _SheetState.loading:
        return [
          SliverToBoxAdapter(
            child: _Shimmer(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
                child: Column(
                  children: List.generate(
                    7,
                        (_) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: _Bone(height: 72, radius: 14),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ];

      case _SheetState.empty:
        return [
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyNote(
              icon: XIcons.calendar,
              title: 'No records this month',
              subtitle: 'Nothing here yet. Try another month.',
            ),
          ),
        ];

      case _SheetState.error:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: _tint(XColors.red, 0.14), shape: BoxShape.circle),
                    child: const Center(child: _Hi(XIcons.alert, size: 24, color: XColors.red)),
                  ),
                  const SizedBox(height: 16),
                  const Text('Could not load records', style: XText.bodyStrong),
                  const SizedBox(height: 4),
                  Text(_error, textAlign: TextAlign.center, style: XText.caption.copyWith(fontSize: 13)),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _load,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: XColors.ink,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      icon: const _Hi(XIcons.refresh, size: 20, color: Colors.white),
                      label: const Text('Retry',
                          style: TextStyle(fontFamily: XText.f, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ];

      case _SheetState.data:
        final records = _month?.records ?? const <AttRecord>[];
        return [
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, i) => Column(
                children: [
                  if (i > 0) const _HDivider(),
                  _RecordTile(record: records[i]),
                ],
              ),
              childCount: records.length,
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 24 + bottomInset)),
        ];
    }
  }
}

class _PinnedHeader extends SliverPersistentHeaderDelegate {
  _PinnedHeader({required this.height, required this.child});
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: Colors.white, child: child);

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  bool shouldRebuild(covariant _PinnedHeader old) => true;
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.color, required this.label, required this.value});
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(value, style: XText.bodyStrong),
        const SizedBox(width: 6),
        Text(label, style: XText.body.copyWith(color: XColors.textDim)),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});
  final AttRecord record;

  String _noCheckInText(AttRecord r) {
    switch (r.status) {
      case AttStatus.leave:
        return r.note ?? 'On leave';
      case AttStatus.sick:
        return r.note ?? 'On sick leave';
      case AttStatus.holiday:
        return r.note ?? 'Public holiday';
      default:
        return 'No check-in';
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = record;
    final times = r.inMin == null
        ? _noCheckInText(r)
        : 'In ${fmtMin(r.inMin!)}  ·  Out ${r.outMin == null ? '–' : fmtMin(r.outMin!)}';
    final showNote = r.inMin != null && r.note != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.isMultiShift ? '${fmtDate(r.date)} · Shift ${r.shiftNumber} of ${r.shiftTotal}' : fmtDate(r.date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: XText.bodyStrong,
                ),
                const SizedBox(height: 2),
                Text(times,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: XText.body.copyWith(color: XColors.textDim, fontSize: 13)),
                if (r.lateMin > 0) ...[
                  const SizedBox(height: 2),
                  Text('${r.lateMin} min late',
                      style: XText.caption.copyWith(color: XColors.orange, fontWeight: FontWeight.w600)),
                ],
                if (showNote) ...[
                  const SizedBox(height: 2),
                  Text(r.note!, maxLines: 2, overflow: TextOverflow.ellipsis, style: XText.caption),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatusChip(r.status),
              if (r.inMin != null) ...[
                const SizedBox(height: 6),
                _SourceTag(r.source),
              ],
            ],
          ),
        ],
      ),
    );
  }
}