// lib/home_data_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../Auth/AuthService.dart';

// ════════════════════════════════════════════════════════════════════
//  ENUMS
// ════════════════════════════════════════════════════════════════════
enum AttStatus { present, late, absent, leave, sick, holiday }

enum AttSource { qr, manual }

enum TodayState { notCheckedIn, checkedIn, late, checkedOut, absent, leave, sick, holiday }

/// What a single shift looks like RIGHT NOW (depends on the clock).
enum ShiftPhase {
  upcoming, // not started yet
  ready, // started, waiting for check-in
  onShift, // checked in on time, not out yet
  onShiftLate, // checked in late, not out yet
  completed, // checked out on time
  completedLate, // checked out, was late
  missed, // no check-in and the shift is over / marked absent
  excused, // leave / sick / holiday
}

extension ShiftPhaseX on ShiftPhase {
  bool get attended =>
      this == ShiftPhase.onShift ||
          this == ShiftPhase.onShiftLate ||
          this == ShiftPhase.completed ||
          this == ShiftPhase.completedLate;

  bool get completedOk => this == ShiftPhase.completed || this == ShiftPhase.completedLate;
}

/// How a shift counts in payroll.
enum PayKind { onTime, late, unexcused, leave, sick, holiday, future }

// ════════════════════════════════════════════════════════════════════
//  SAFE PARSING HELPERS
// ════════════════════════════════════════════════════════════════════
int? _i(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? _d(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

bool? _b(dynamic v) {
  if (v is bool) return v;
  if (v is String) {
    final s = v.toLowerCase();
    if (s == 'true') return true;
    if (s == 'false') return false;
  }
  return null;
}

Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> _l(dynamic v) => v is List ? v : const [];

String? _s(dynamic v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// Parses a calendar date WITHOUT timezone drift.
/// "2026-10-31" or "2026-10-31T00:00:00Z" both become local Oct 31 (midnight).
DateTime? _dateOrNull(dynamic v) {
  final s = v?.toString() ?? '';
  if (s.length < 10) return null;
  final p = DateTime.tryParse(s.substring(0, 10));
  return p == null ? null : DateTime(p.year, p.month, p.day);
}

DateTime _date(dynamic v) => _dateOrNull(v) ?? dayOnly(DateTime.now());

/// Strips the time part so dates compare cleanly.
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

AttStatus _statusOf(dynamic st) {
  switch (st?.toString().toLowerCase()) {
    case 'absent':
      return AttStatus.absent;
    case 'late':
      return AttStatus.late;
    case 'leave':
      return AttStatus.leave;
    case 'sick':
      return AttStatus.sick;
    case 'holiday':
      return AttStatus.holiday;
    default:
      return AttStatus.present;
  }
}

TodayState _todayStateOf(dynamic st) {
  switch (st?.toString().toUpperCase()) {
    case 'CHECKED_IN':
      return TodayState.checkedIn;
    case 'LATE':
      return TodayState.late;
    case 'CHECKED_OUT':
      return TodayState.checkedOut;
    case 'ABSENT':
      return TodayState.absent;
    case 'LEAVE':
    case 'ON_LEAVE':
      return TodayState.leave;
    case 'SICK':
    case 'ON_SICK':
      return TodayState.sick;
    case 'HOLIDAY':
    case 'ON_HOLIDAY':
      return TodayState.holiday;
    default:
      return TodayState.notCheckedIn;
  }
}

PayKind _payKindOf(dynamic k) {
  switch (k?.toString().toLowerCase()) {
    case 'late':
      return PayKind.late;
    case 'unexcused':
    case 'unexcused_absent':
    case 'absent':
      return PayKind.unexcused;
    case 'leave':
    case 'approved_leave':
      return PayKind.leave;
    case 'sick':
      return PayKind.sick;
    case 'holiday':
      return PayKind.holiday;
    case 'future':
    case 'pending':
    case 'upcoming':
    case 'scheduled':
      return PayKind.future;
    default:
      return PayKind.onTime;
  }
}

// ════════════════════════════════════════════════════════════════════
//  MODELS · SHIFTS
// ════════════════════════════════════════════════════════════════════
/// One scheduled shift from staff.scheduled_shifts (number is 1-based).
class ShiftDef {
  const ShiftDef({required this.number, required this.startMin, required this.endMin});

  final int number;
  final int startMin;
  final int endMin;

  factory ShiftDef.fromJson(Map<String, dynamic> j, int fallbackNumber) => ShiftDef(
    number: _i(j['number']) ?? _i(j['shift_number']) ?? fallbackNumber,
    startMin: _i(j['start_min']) ?? 8 * 60,
    endMin: _i(j['end_min']) ?? 17 * 60,
  );
}

/// Attendance of ONE shift today.
class TodayShift {
  const TodayShift({
    required this.number,
    required this.startMin,
    required this.endMin,
    required this.state,
    this.inMin,
    this.outMin,
    this.lateMin = 0,
    this.note,
  });

  final int number;
  final int startMin;
  final int endMin;
  final TodayState state;
  final int? inMin;
  final int? outMin;
  final int lateMin;
  final String? note;

  /// [nowMin] = minutes since midnight on the device. Pass -1 when the
  /// device day differs from the server day (then nothing is time-derived).
  ShiftPhase phaseAt(int nowMin) {
    switch (state) {
      case TodayState.checkedOut:
        return lateMin > 0 ? ShiftPhase.completedLate : ShiftPhase.completed;
      case TodayState.checkedIn:
        return ShiftPhase.onShift;
      case TodayState.late:
        if (outMin != null) return ShiftPhase.completedLate;
        return ShiftPhase.onShiftLate;
      case TodayState.absent:
        return ShiftPhase.missed;
      case TodayState.leave:
      case TodayState.sick:
      case TodayState.holiday:
        return ShiftPhase.excused;
      case TodayState.notCheckedIn:
        if (nowMin < 0 || nowMin < startMin) return ShiftPhase.upcoming;
        if (nowMin >= endMin) return ShiftPhase.missed;
        return ShiftPhase.ready;
    }
  }
}

class TodayInfo {
  const TodayInfo({
    required this.state,
    required this.inMin,
    required this.outMin,
    required this.lateMin,
    this.note,
    this.shifts = const [],
  });

  final TodayState state;
  final int? inMin;
  final int? outMin;
  final int lateMin;
  final String? note;
  final List<TodayShift> shifts; // ordered by shift number

  bool get isMultiShift => shifts.length > 1;

  /// True when check-in is not allowed today (leave, sick, holiday).
  bool get blocksCheckIn =>
      state == TodayState.leave || state == TodayState.sick || state == TodayState.holiday;

  factory TodayInfo.fromJson(Map<String, dynamic> j, List<ShiftDef> schedule) {
    final state = _todayStateOf(j['state']);
    final inMin = _i(j['in_min']);
    final outMin = _i(j['out_min']);
    final lateMin = _i(j['late_min']) ?? 0;
    final note = _s(j['note']);

    final byNumber = {for (final s in schedule) s.number: s};
    final raw = _l(j['shifts']);
    final shifts = <TodayShift>[];

    if (raw.isNotEmpty) {
      for (int k = 0; k < raw.length; k++) {
        final r = _m(raw[k]);
        final n = _i(r['shift_number']) ?? _i(r['number']) ?? (k + 1);
        final def = byNumber[n];
        shifts.add(TodayShift(
          number: n,
          startMin: _i(r['start_min']) ?? def?.startMin ?? 8 * 60,
          endMin: _i(r['end_min']) ?? def?.endMin ?? 17 * 60,
          state: _todayStateOf(r['state']),
          inMin: _i(r['in_min']),
          outMin: _i(r['out_min']),
          lateMin: _i(r['late_min']) ?? 0,
          note: _s(r['note']),
        ));
      }
    } else {
      // Older backend: build the shifts from the schedule + the day-level state.
      final timeOff = state == TodayState.leave || state == TodayState.sick || state == TodayState.holiday;
      for (int k = 0; k < schedule.length; k++) {
        final def = schedule[k];
        final carriesState = schedule.length == 1 || timeOff;
        shifts.add(TodayShift(
          number: def.number,
          startMin: def.startMin,
          endMin: def.endMin,
          state: carriesState ? state : TodayState.notCheckedIn,
          inMin: carriesState && schedule.length == 1 ? inMin : null,
          outMin: carriesState && schedule.length == 1 ? outMin : null,
          lateMin: carriesState && schedule.length == 1 ? lateMin : 0,
          note: carriesState ? note : null,
        ));
      }
    }
    shifts.sort((a, b) => a.number.compareTo(b.number));

    return TodayInfo(
      state: state,
      inMin: inMin,
      outMin: outMin,
      lateMin: lateMin,
      note: note,
      shifts: shifts,
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  MODELS · ATTENDANCE
// ════════════════════════════════════════════════════════════════════
class AttRecord {
  const AttRecord({
    required this.date,
    required this.inMin,
    required this.outMin,
    required this.lateMin,
    required this.status,
    required this.source,
    this.note,
    this.shiftNumber = 1,
    this.shiftTotal = 1,
  });

  final DateTime date;
  final int? inMin;
  final int? outMin;
  final int lateMin;
  final AttStatus status;
  final AttSource source;
  final String? note;
  final int shiftNumber; // 1-based
  final int shiftTotal; // how many shifts that staff has per day

  bool get isMultiShift => shiftTotal > 1;

  /// Leave, sick or holiday: the person was not expected to work.
  bool get isTimeOff =>
      status == AttStatus.leave || status == AttStatus.sick || status == AttStatus.holiday;

  factory AttRecord.fromJson(Map<String, dynamic> j) => AttRecord(
    date: _date(j['date']),
    inMin: _i(j['in_min']),
    outMin: _i(j['out_min']),
    lateMin: _i(j['late_min']) ?? 0,
    status: _statusOf(j['status']),
    source: j['source'] == 'manual' ? AttSource.manual : AttSource.qr,
    note: _s(j['note']),
    shiftNumber: _i(j['shift_number']) ?? 1,
    shiftTotal: _i(j['shift_total']) ?? 1,
  );
}

class Holiday {
  const Holiday({required this.date, required this.name});

  final DateTime date;
  final String name;

  int daysUntil(DateTime today) => dayOnly(date).difference(dayOnly(today)).inDays;
}

class LeaveSpan {
  const LeaveSpan({required this.type, required this.start, required this.end});

  /// annual | sick | emergency | unpaid | maternity | other
  final String type;
  final DateTime start;
  final DateTime end;

  int get days => dayOnly(end).difference(dayOnly(start)).inDays + 1;

  bool isActiveOn(DateTime day) {
    final d = dayOnly(day);
    return !d.isBefore(dayOnly(start)) && !d.isAfter(dayOnly(end));
  }

  int daysUntilStart(DateTime today) => dayOnly(start).difference(dayOnly(today)).inDays;
}

/// Holidays (today + next 30 days) and the active or next approved leave.
class TimeOffInfo {
  const TimeOffInfo({this.holidays = const [], this.leave});

  final List<Holiday> holidays; // sorted ascending
  final LeaveSpan? leave;

  static const empty = TimeOffInfo();

  bool get isEmpty => holidays.isEmpty && leave == null;

  Holiday? holidayOn(DateTime day) {
    final d = dayOnly(day);
    for (final h in holidays) {
      if (dayOnly(h.date) == d) return h;
    }
    return null;
  }

  Holiday? nextHolidayAfter(DateTime day) {
    final d = dayOnly(day);
    for (final h in holidays) {
      if (dayOnly(h.date).isAfter(d)) return h;
    }
    return null;
  }

  factory TimeOffInfo.fromJson(Map<String, dynamic> j) {
    final hs = <Holiday>[
      for (final h in _l(j['holidays']))
        if (_dateOrNull(_m(h)['date']) != null)
          Holiday(date: _dateOrNull(_m(h)['date'])!, name: _s(_m(h)['name']) ?? 'Holiday'),
    ]..sort((a, b) => a.date.compareTo(b.date));

    final lj = _m(j['leave']);
    final s = _dateOrNull(lj['start_date']);
    final e = _dateOrNull(lj['end_date']);
    final leave = (s != null && e != null && !e.isBefore(s))
        ? LeaveSpan(type: _s(lj['type']) ?? 'other', start: s, end: e)
        : null;

    return TimeOffInfo(holidays: hs, leave: leave);
  }
}

class ChartPoint {
  const ChartPoint({required this.date, required this.inMin, required this.late});

  final DateTime date;
  final int? inMin;
  final bool late;
}

class MonthData {
  const MonthData({
    required this.year,
    required this.month,
    required this.present,
    required this.late,
    required this.absent,
    required this.attended,
    required this.workingDays,
    required this.pct,
    required this.records,
    this.partialDays = 0,
    this.missedShifts = 0,
  });

  final int year;
  final int month;
  final int present; // on time
  final int late;
  final int absent;
  final int attended; // days with at least one attended shift
  final int workingDays;
  final int pct;
  final int partialDays; // attended at least one shift but missed another
  final int missedShifts; // total missed shifts (unexcused)
  final List<AttRecord> records; // newest first

  factory MonthData.fromJson(Map<String, dynamic> j) {
    final now = DateTime.now();
    final key = (j['key']?.toString() ?? '').split('-');
    final s = _m(j['summary']);
    return MonthData(
      year: key.length == 2 ? int.tryParse(key[0]) ?? now.year : now.year,
      month: key.length == 2 ? int.tryParse(key[1]) ?? now.month : now.month,
      present: _i(s['present']) ?? 0,
      late: _i(s['late']) ?? 0,
      absent: _i(s['absent']) ?? 0,
      attended: _i(s['attended']) ?? 0,
      workingDays: _i(s['working_days']) ?? 0,
      pct: _i(s['attendance_pct']) ?? 0,
      partialDays: _i(s['partial_days']) ?? 0,
      missedShifts: _i(s['missed_shifts']) ?? 0,
      records: [for (final r in _l(j['records'])) AttRecord.fromJson(_m(r))],
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  MODELS · PAYROLL
// ════════════════════════════════════════════════════════════════════
class PayShift {
  const PayShift({
    required this.number,
    required this.schedStartMin,
    required this.schedEndMin,
    required this.kind,
    this.inMin,
    this.outMin,
    this.lateMin = 0,
    this.countedLateMin = 0,
    this.deduction = 0,
    this.isEstimate = false,
    this.note,
  });

  final int number;
  final int schedStartMin;
  final int schedEndMin;
  final PayKind kind;
  final int? inMin;
  final int? outMin;
  final int lateMin; // real minutes late
  final int countedLateMin; // minutes that count for payroll (after grace)
  final double deduction;
  final bool isEstimate;
  final String? note;

  factory PayShift.fromJson(Map<String, dynamic> j, int fallbackNumber, bool monthIsEstimate) => PayShift(
    number: _i(j['shift_number']) ?? _i(j['number']) ?? fallbackNumber,
    schedStartMin: _i(j['start_min']) ?? 8 * 60,
    schedEndMin: _i(j['end_min']) ?? 17 * 60,
    kind: _payKindOf(j['kind']),
    inMin: _i(j['in_min']),
    outMin: _i(j['out_min']),
    lateMin: _i(j['late_min']) ?? 0,
    countedLateMin: _i(j['counted_late_min']) ?? 0,
    deduction: _d(j['deduction']) ?? 0,
    isEstimate: _b(j['is_estimate']) ?? monthIsEstimate,
    note: _s(j['note']),
  );
}

class PayDay {
  const PayDay({required this.date, required this.shifts});

  final DateTime date;
  final List<PayShift> shifts;

  bool get isMulti => shifts.length > 1;
  double get deduction => shifts.fold(0.0, (a, s) => a + s.deduction);
  bool get isFuture => shifts.isNotEmpty && shifts.every((s) => s.kind == PayKind.future);
}

class PayLate {
  const PayLate({required this.date, required this.shift, required this.multi});

  final DateTime date;
  final PayShift shift;
  final bool multi;
}

class PayrollInfo {
  const PayrollInfo({
    required this.year,
    required this.month,
    required this.currency,
    required this.monthlySalary,
    required this.graceMinutes,
    required this.lateMinutes,
    required this.latenessDeduction,
    required this.unexcusedAbsentDays,
    required this.absenceDeduction,
    required this.estimatedNet,
    required this.isEstimate,
    required this.days,
  });

  final int year;
  final int month;
  final String currency;
  final double monthlySalary;
  final int graceMinutes;
  final int lateMinutes;
  final double latenessDeduction;
  final int unexcusedAbsentDays;
  final double absenceDeduction;
  final double estimatedNet;
  final bool isEstimate;
  final List<PayDay> days; // newest first

  double get totalDeduction => latenessDeduction + absenceDeduction;

  /// The summary is only shown when there is something deducted.
  bool get hasDeductions => totalDeduction > 0.004;

  /// Every late shift, newest first.
  List<PayLate> get lateEvents => [
    for (final d in days)
      for (final s in d.shifts)
        if (s.kind == PayKind.late) PayLate(date: d.date, shift: s, multi: d.isMulti),
  ];

  factory PayrollInfo.fromJson(Map<String, dynamic> j) {
    final now = DateTime.now();
    final key = (j['key']?.toString() ?? '').split('-');
    final s = _m(j['summary']);
    final salary = _d(s['monthly_salary']) ?? _d(j['monthly_salary']) ?? 0;
    final lateDed = _d(s['lateness_deduction']) ?? 0;
    final absDed = _d(s['absence_deduction']) ?? 0;
    final estimate = _b(s['is_estimate']) ?? true;

    final days = <PayDay>[];
    for (final raw in _l(j['days'])) {
      final dj = _m(raw);
      final date = _dateOrNull(dj['date']);
      if (date == null) continue;
      final shifts = <PayShift>[];
      final rawShifts = _l(dj['shifts']);
      for (int k = 0; k < rawShifts.length; k++) {
        shifts.add(PayShift.fromJson(_m(rawShifts[k]), k + 1, estimate));
      }
      shifts.sort((a, b) => a.number.compareTo(b.number));
      if (shifts.isNotEmpty) days.add(PayDay(date: date, shifts: shifts));
    }
    days.sort((a, b) => b.date.compareTo(a.date));

    return PayrollInfo(
      year: key.length == 2 ? int.tryParse(key[0]) ?? now.year : now.year,
      month: key.length == 2 ? int.tryParse(key[1]) ?? now.month : now.month,
      currency: _s(s['currency']) ?? _s(j['currency']) ?? 'USD',
      monthlySalary: salary,
      graceMinutes: _i(s['grace_minutes']) ?? 5,
      lateMinutes: _i(s['late_minutes']) ?? 0,
      latenessDeduction: lateDed,
      unexcusedAbsentDays: _i(s['unexcused_absent_days']) ?? 0,
      absenceDeduction: absDed,
      estimatedNet: _d(s['estimated_net']) ?? (salary - lateDed - absDed),
      isEstimate: estimate,
      days: days,
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  MODELS · HOME
// ════════════════════════════════════════════════════════════════════
class HomeData {
  const HomeData({
    required this.firstName,
    required this.fullName,
    required this.jobTitle,
    required this.branchName,
    required this.serverDate,
    required this.shifts,
    required this.today,
    required this.month,
    required this.chart,
    required this.recent,
    required this.timeOff,
    this.payroll,
  });

  final String firstName;
  final String fullName;
  final String jobTitle;
  final String branchName;
  final DateTime serverDate;
  final List<ShiftDef> shifts;
  final TodayInfo today;
  final MonthData month;
  final List<ChartPoint> chart;
  final List<AttRecord> recent;
  final TimeOffInfo timeOff;
  final PayrollInfo? payroll;

  int get shiftStartMin => shifts.isEmpty ? 8 * 60 : shifts.first.startMin;
  int get shiftEndMin => shifts.isEmpty ? 17 * 60 : shifts.last.endMin;

  /// The payroll card only exists for staff with a salary.
  bool get hasPayroll => payroll != null && payroll!.monthlySalary > 0;

  factory HomeData.fromJson(Map<String, dynamic> j) {
    final g = _m(j['greeting']);
    final chart = _m(j['chart']);
    final timeOff = j['time_off'] is Map ? TimeOffInfo.fromJson(_m(j['time_off'])) : TimeOffInfo.empty;

    // Schedule: new `shifts` list, or the legacy single `shift` object.
    final schedule = <ShiftDef>[];
    final rawShifts = _l(j['shifts']);
    for (int k = 0; k < rawShifts.length; k++) {
      schedule.add(ShiftDef.fromJson(_m(rawShifts[k]), k + 1));
    }
    if (schedule.isEmpty) {
      final shift = _m(j['shift']);
      schedule.add(ShiftDef(
        number: 1,
        startMin: _i(shift['start_min']) ?? 8 * 60,
        endMin: _i(shift['end_min']) ?? 17 * 60,
      ));
    }
    schedule.sort((a, b) => a.number.compareTo(b.number));

    return HomeData(
      firstName: _s(g['first_name']) ?? '',
      fullName: _s(g['full_name']) ?? '',
      jobTitle: _s(g['job_title']) ?? '',
      branchName: _s(g['branch_name']) ?? '',
      serverDate: _date(j['server_date']),
      shifts: schedule,
      today: TodayInfo.fromJson(_m(j['today']), schedule),
      month: MonthData.fromJson(_m(j['month'])),
      chart: [
        for (final d in _l(chart['days']))
          ChartPoint(
            date: _date(_m(d)['date']),
            inMin: _i(_m(d)['check_in_min']),
            late: _m(d)['late'] == true,
          ),
      ],
      recent: [for (final r in _l(j['recent'])) AttRecord.fromJson(_m(r))],
      timeOff: timeOff,
      payroll: j['payroll'] is Map ? PayrollInfo.fromJson(_m(j['payroll'])) : null,
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  SERVICE (singleton)
// ════════════════════════════════════════════════════════════════════
class HomeDataService {
  HomeDataService._();
  static final HomeDataService instance = HomeDataService._();

  static const String _function = 'home-data';
  static const Duration _monthTtl = Duration(minutes: 2);

  // One in-flight home request is shared by every caller (resume + pull-to-refresh).
  Future<HomeData>? _homeInFlight;

  // Month cache + per-month in-flight de-dupe for the "All records" sheet.
  final Map<String, _CachedMonth> _monthCache = {};
  final Map<String, Future<MonthData>> _monthInFlight = {};

  // Same pattern for payroll months.
  final Map<String, _CachedPayroll> _payrollCache = {};
  final Map<String, Future<PayrollInfo>> _payrollInFlight = {};

  /// Everything the Home screen needs (current month, chart, today incl. every
  /// shift, last 5, holidays + leave, payroll) in ONE call.
  Future<HomeData> load() {
    final running = _homeInFlight;
    if (running != null) {
      debugPrint('♻️ Home load joined in-flight request');
      return running;
    }

    final sw = Stopwatch()..start();
    final future = () async {
      try {
        final json = await AuthService.instance.callFunction(_function, {'scope': 'all'});
        final data = HomeData.fromJson(json);

        // Seed the caches so the first open of each sheet is instant.
        _monthCache[_key(data.month.year, data.month.month)] =
            _CachedMonth(data.month, DateTime.now());
        final pay = data.payroll;
        if (pay != null) {
          _payrollCache[_key(pay.year, pay.month)] = _CachedPayroll(pay, DateTime.now());
        }

        debugPrint('✅ Home loaded in ${sw.elapsedMilliseconds}ms · '
            'today=${data.today.state.name} · shifts=${data.shifts.length} · '
            'holidays=${data.timeOff.holidays.length} · '
            'leave=${data.timeOff.leave?.type ?? 'none'} · '
            'payroll=${data.hasPayroll ? 'yes' : 'no'}');
        return data;
      } catch (e) {
        debugPrint('❌ Home load failed after ${sw.elapsedMilliseconds}ms: $e');
        rethrow;
      }
    }();

    _homeInFlight = future;
    future.whenComplete(() {
      if (identical(_homeInFlight, future)) _homeInFlight = null;
    });
    return future;
  }

  /// One month for the "All records" sheet. Cached briefly; pass
  /// [forceRefresh] from a retry button to bypass the cache.
  Future<MonthData> loadMonth(int year, int month, {bool forceRefresh = false}) {
    final key = _key(year, month);

    if (!forceRefresh) {
      final cached = _monthCache[key];
      if (cached != null && DateTime.now().difference(cached.at) < _monthTtl) {
        debugPrint('📦 Month $key served from cache');
        return Future.value(cached.data);
      }
      final running = _monthInFlight[key];
      if (running != null) {
        debugPrint('♻️ Month $key joined in-flight request');
        return running;
      }
    }

    final sw = Stopwatch()..start();
    final future = () async {
      try {
        final json = await AuthService.instance.callFunction(_function, {'scope': 'month', 'month': key});
        final data = MonthData.fromJson(_m(json['month']));
        _monthCache[key] = _CachedMonth(data, DateTime.now());
        debugPrint('✅ Month $key loaded in ${sw.elapsedMilliseconds}ms · ${data.records.length} records');
        return data;
      } catch (e) {
        debugPrint('❌ Month $key failed: $e');
        rethrow;
      }
    }();

    _monthInFlight[key] = future;
    future.whenComplete(() {
      if (identical(_monthInFlight[key], future)) _monthInFlight.remove(key);
    });
    return future;
  }

  /// One payroll month (summary + day/shift statement) in a single call.
  Future<PayrollInfo> loadPayroll(int year, int month, {bool forceRefresh = false}) {
    final key = _key(year, month);

    if (!forceRefresh) {
      final cached = _payrollCache[key];
      if (cached != null && DateTime.now().difference(cached.at) < _monthTtl) {
        debugPrint('📦 Payroll $key served from cache');
        return Future.value(cached.data);
      }
      final running = _payrollInFlight[key];
      if (running != null) {
        debugPrint('♻️ Payroll $key joined in-flight request');
        return running;
      }
    }

    final sw = Stopwatch()..start();
    final future = () async {
      try {
        final json = await AuthService.instance.callFunction(_function, {'scope': 'payroll', 'month': key});
        final data = PayrollInfo.fromJson(_m(json['payroll']));
        _payrollCache[key] = _CachedPayroll(data, DateTime.now());
        debugPrint('✅ Payroll $key loaded in ${sw.elapsedMilliseconds}ms · '
            '${data.days.length} days · deductions=${data.totalDeduction}');
        return data;
      } catch (e) {
        debugPrint('❌ Payroll $key failed: $e');
        rethrow;
      }
    }();

    _payrollInFlight[key] = future;
    future.whenComplete(() {
      if (identical(_payrollInFlight[key], future)) _payrollInFlight.remove(key);
    });
    return future;
  }

  /// Call on sign-out so the next user never sees stale data.
  void clearCache() {
    _homeInFlight = null;
    _monthCache.clear();
    _monthInFlight.clear();
    _payrollCache.clear();
    _payrollInFlight.clear();
    debugPrint('🧹 HomeDataService cache cleared');
  }

  static String _key(int year, int month) => '$year-${month.toString().padLeft(2, '0')}';

  /// Handles failures that change which screen the user belongs on.
  /// Returns true when the failure was fully handled (caller should stop).
  static Future<bool> handleSessionFailure(AuthFailure e) async {
    if (e.code == 'PASSWORD_CHANGE_REQUIRED') {
      debugPrint('🔐 Password change required');
      AuthService.instance.requestRecheck();
      return true;
    }
    if (e.endsSession) {
      debugPrint('🚪 Session ended: ${e.code}');
      instance.clearCache();
      AuthService.instance.flashNotice = e.message;
      await AuthService.instance.signOut();
      return true;
    }
    return e.code == 'UNAUTHORIZED'; // service already signed out
  }
}

class _CachedMonth {
  const _CachedMonth(this.data, this.at);
  final MonthData data;
  final DateTime at;
}

class _CachedPayroll {
  const _CachedPayroll(this.data, this.at);
  final PayrollInfo data;
  final DateTime at;
}