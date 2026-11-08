// lib/home_data_service.dart
import 'dart:async';
import 'dart:convert';

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
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt();
  return null;
}

double? _d(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

bool? _b(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    if (s == 'true') return true;
    if (s == 'false') return false;
  }
  return null;
}

Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// List parser that also accepts a JSON string (jsonb sometimes arrives as text).
List<dynamic> _l(dynamic v) {
  if (v is List) return v;
  if (v is String && v.trim().startsWith('[')) {
    try {
      final d = jsonDecode(v);
      if (d is List) return d;
    } catch (_) {}
  }
  return const [];
}

String? _s(dynamic v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// "11:10" or "11:10:00" → minutes since midnight.
int? _timeMin(dynamic v) {
  final s = v?.toString().trim();
  if (s == null || s.isEmpty) return null;
  final p = s.split(':');
  if (p.length < 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// First non-null value among several possible key names.
dynamic _first(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v != null) return v;
  }
  return null;
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

/// Database weekday: 0 = Sunday … 6 = Saturday (same as staff.scheduled_shifts.day).
int dbDay(DateTime d) => d.weekday % 7;

/// Weekday parser. Accepts 0–6 (Sun = 0), 7 (ISO Sunday), numeric strings
/// ("4") and names ("Thu", "Thursday"). Returns null when it is not a day.
int? _dayOf(dynamic v) {
  if (v == null) return null;
  int? fromNum(num n) {
    final x = n.toInt();
    if (x >= 0 && x <= 6) return x;
    if (x == 7) return 0;
    return null;
  }

  if (v is num) return fromNum(v);
  final s = v.toString().trim().toLowerCase();
  if (s.isEmpty) return null;
  final n = num.tryParse(s);
  if (n != null) return fromNum(n);
  const names = {'sun': 0, 'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6};
  return names[s.length >= 3 ? s.substring(0, 3) : s];
}

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

/// Makes the state agree with the data: a person who checked in with
/// late minutes is LATE, and a person with times is never "not checked in".
TodayState _fixState(TodayState s, {int? inMin, int? outMin, required int lateMin}) {
  if (s == TodayState.notCheckedIn && inMin != null) {
    if (outMin != null) return TodayState.checkedOut;
    return lateMin > 0 ? TodayState.late : TodayState.checkedIn;
  }
  if (s == TodayState.checkedIn && lateMin > 0) return TodayState.late;
  return s;
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
/// One scheduled shift. [day] is the DB weekday (0 = Sun … 6 = Sat) when the
/// entry comes from staff.scheduled_shifts; null when the server already
/// filtered the list for today.
class ShiftDef {
  const ShiftDef({required this.number, required this.startMin, required this.endMin, this.day});

  final int number;
  final int startMin;
  final int endMin;
  final int? day;

  ShiftDef withNumber(int n) => ShiftDef(number: n, startMin: startMin, endMin: endMin, day: day);

  factory ShiftDef.fromJson(Map<String, dynamic> j, int fallbackNumber) => ShiftDef(
    number: _i(j['number']) ?? _i(j['shift_number']) ?? fallbackNumber,
    startMin: _i(j['start_min']) ?? _timeMin(j['start']) ?? _timeMin(j['shift_start']) ?? 8 * 60,
    endMin: _i(j['end_min']) ?? _timeMin(j['end']) ?? _timeMin(j['shift_end']) ?? 17 * 60,
    day: _dayOf(_first(j, ['day', 'weekday', 'day_of_week', 'dow'])),
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
        if (outMin != null) return lateMin > 0 ? ShiftPhase.completedLate : ShiftPhase.completed;
        return lateMin > 0 ? ShiftPhase.onShiftLate : ShiftPhase.onShift;
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
    final inMin = _i(j['in_min']);
    final outMin = _i(j['out_min']);
    final lateMin = _i(j['late_min']) ?? 0;
    final state = _fixState(_todayStateOf(j['state']), inMin: inMin, outMin: outMin, lateMin: lateMin);
    final note = _s(j['note']);

    final byNumber = {for (final s in schedule) s.number: s};
    final raw = _l(j['shifts']);
    final shifts = <TodayShift>[];

    if (raw.isNotEmpty) {
      for (int k = 0; k < raw.length; k++) {
        final r = _m(raw[k]);
        final n = _i(r['shift_number']) ?? _i(r['number']) ?? (k + 1);
        final def = byNumber[n];
        final rIn = _i(r['in_min']);
        final rOut = _i(r['out_min']);
        final rLate = _i(r['late_min']) ?? 0;
        shifts.add(TodayShift(
          number: n,
          startMin: _i(r['start_min']) ?? def?.startMin ?? 8 * 60,
          endMin: _i(r['end_min']) ?? def?.endMin ?? 17 * 60,
          state: _fixState(_todayStateOf(r['state']), inMin: rIn, outMin: rOut, lateMin: rLate),
          inMin: rIn,
          outMin: rOut,
          lateMin: rLate,
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
  final int shiftTotal; // how many shifts that staff has on THAT day

  bool get isMultiShift => shiftTotal > 1;

  /// Leave, sick or holiday: the person was not expected to work.
  bool get isTimeOff =>
      status == AttStatus.leave || status == AttStatus.sick || status == AttStatus.holiday;

  factory AttRecord.fromJson(Map<String, dynamic> j) {
    final lateMin = _i(j['late_min']) ?? 0;
    var status = _statusOf(j['status']);
    // Backend says "present" but the person arrived late → show Late.
    if (status == AttStatus.present && lateMin > 0) status = AttStatus.late;
    return AttRecord(
      date: _date(j['date']),
      inMin: _i(j['in_min']),
      outMin: _i(j['out_min']),
      lateMin: lateMin,
      status: status,
      source: j['source'] == 'manual' ? AttSource.manual : AttSource.qr,
      note: _s(j['note']),
      shiftNumber: _i(j['shift_number']) ?? 1,
      shiftTotal: _i(j['shift_total']) ?? 1,
    );
  }
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
    final records = [for (final r in _l(j['records'])) AttRecord.fromJson(_m(r))];

    // If the summary has no late count, count it from the records.
    final lateFromSummary = _i(_first(s, ['late', 'late_count', 'late_days']));
    final lateCount = lateFromSummary ?? records.where((r) => r.status == AttStatus.late).length;

    return MonthData(
      year: key.length == 2 ? int.tryParse(key[0]) ?? now.year : now.year,
      month: key.length == 2 ? int.tryParse(key[1]) ?? now.month : now.month,
      present: _i(s['present']) ?? 0,
      late: lateCount,
      absent: _i(s['absent']) ?? 0,
      attended: _i(s['attended']) ?? 0,
      workingDays: _i(s['working_days']) ?? 0,
      pct: _i(s['attendance_pct']) ?? 0,
      partialDays: _i(s['partial_days']) ?? 0,
      missedShifts: _i(s['missed_shifts']) ?? 0,
      records: records,
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

  factory PayShift.fromJson(Map<String, dynamic> j, int fallbackNumber, bool monthIsEstimate) {
    final late = _i(j['late_min']) ?? 0;
    var kind = _payKindOf(_first(j, ['kind', 'status']));
    // A shift with late minutes is a late shift even if the backend said on-time.
    if (kind == PayKind.onTime && late > 0) kind = PayKind.late;

    return PayShift(
      number: _i(j['shift_number']) ?? _i(j['number']) ?? fallbackNumber,
      schedStartMin: _i(j['start_min']) ?? 8 * 60,
      schedEndMin: _i(j['end_min']) ?? 17 * 60,
      kind: kind,
      inMin: _i(j['in_min']),
      outMin: _i(j['out_min']),
      lateMin: late,
      countedLateMin: _i(_first(j, ['counted_late_min', 'counted_late'])) ?? 0,
      deduction: _d(j['deduction']) ?? 0,
      isEstimate: _b(j['is_estimate']) ?? monthIsEstimate,
      note: _s(j['note']),
    );
  }
}

class PayDay {
  const PayDay({required this.date, required this.shifts, this.holidayName});

  final DateTime date;
  final List<PayShift> shifts;
  final String? holidayName; // set when the company marked this date as a holiday

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
    this.periodStart,
    this.periodEnd,
    this.workingDays,
    this.elapsedWorkingDays,
    this.earnedSoFar,
    this.dailySalary,
    this.payableDays,
    this.expectedDays,
    this.attendanceDays,
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

  // Optional extras from the server (period + progress through the month).
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final int? workingDays;
  final double? elapsedWorkingDays;
  final double? earnedSoFar;
  final double? dailySalary;
  final int? payableDays; // working days that are paid (holidays excluded)
  final int? expectedDays; // past working days the person was expected to attend
  final int? attendanceDays; // of those, days with a check-in

  DateTime get start => periodStart ?? DateTime(year, month, 1);
  DateTime get end => periodEnd ?? DateTime(year, month + 1, 0);

  /// 0..1 — how far through the pay period we are.
  double get progress {
    if (!isEstimate) return 1;
    final w = workingDays;
    final e = elapsedWorkingDays;
    if (w != null && w > 0 && e != null) return (e / w).clamp(0.0, 1.0).toDouble();
    final dim = DateTime(year, month + 1, 0).day;
    return (DateTime.now().day / dim).clamp(0.0, 1.0).toDouble();
  }

  /// What the person has earned so far this month (after deductions).
  double get earnedNow {
    final v = earnedSoFar ?? (monthlySalary * progress - totalDeduction);
    return v < 0 ? 0 : v;
  }

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

    // Summary can live under "summary" or directly on the payroll object.
    var s = _m(j['summary']);
    if (s.isEmpty) s = j;

    final salary = _d(_first(s, ['monthly_salary', 'salary', 'base_salary', 'gross_salary'])) ??
        _d(_first(j, ['monthly_salary', 'salary', 'base_salary', 'gross_salary'])) ??
        0;
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
      if (shifts.isNotEmpty) days.add(PayDay(date: date, shifts: shifts, holidayName: _s(dj['holiday'])));
    }
    days.sort((a, b) => b.date.compareTo(a.date));

    // Fallbacks computed from the day list when the summary is missing a field.
    int sumLateMin = 0;
    double sumLateDed = 0;
    double sumAbsDed = 0;
    int absentDays = 0;
    for (final d in days) {
      bool hadUnexcused = false;
      for (final sh in d.shifts) {
        if (sh.kind == PayKind.late) {
          sumLateMin += sh.lateMin;
          sumLateDed += sh.deduction;
        } else if (sh.kind == PayKind.unexcused) {
          sumAbsDed += sh.deduction;
          hadUnexcused = true;
        }
      }
      if (hadUnexcused) absentDays++;
    }

    final lateDed = _d(s['lateness_deduction']) ?? sumLateDed;
    final absDed = _d(s['absence_deduction']) ?? sumAbsDed;

    final pStart = _dateOrNull(s['period_start']);
    final pEnd = _dateOrNull(s['period_end']);

    return PayrollInfo(
      year: key.length == 2 ? int.tryParse(key[0]) ?? now.year : now.year,
      month: key.length == 2 ? int.tryParse(key[1]) ?? now.month : now.month,
      currency: _s(s['currency']) ?? _s(j['currency']) ?? 'USD',
      monthlySalary: salary,
      graceMinutes: _i(s['grace_minutes']) ?? 5,
      lateMinutes: _i(_first(s, ['late_minutes', 'total_late_minutes'])) ?? sumLateMin,
      latenessDeduction: lateDed,
      unexcusedAbsentDays: _i(s['unexcused_absent_days']) ?? absentDays,
      absenceDeduction: absDed,
      estimatedNet: _d(s['estimated_net']) ?? (salary - lateDed - absDed),
      isEstimate: estimate,
      days: days,
      periodStart: pStart,
      periodEnd: pEnd,
      workingDays: _i(s['working_days']),
      elapsedWorkingDays: _d(s['elapsed_working_days']),
      earnedSoFar: _d(s['earned_so_far']),
      dailySalary: _d(s['daily_salary']),
      payableDays: _i(s['payable_days']),
      expectedDays: _i(s['expected_days']),
      attendanceDays: _i(s['attendance_days']),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  MODELS · HOME
// ════════════════════════════════════════════════════════════════════

/// Parses every entry, skipping days marked off. An entry that carries a
/// `days: [..]` list is expanded into one ShiftDef per weekday.
List<ShiftDef> _parseSchedule(List<dynamic> raw) {
  final out = <ShiftDef>[];
  for (int k = 0; k < raw.length; k++) {
    final r = _m(raw[k]);
    if (r.isEmpty) continue;
    final off = _b(_first(r, ['off', 'is_off', 'day_off'])) ?? false;
    final enabled = _b(r['enabled']) ?? true;
    if (off || !enabled) continue;

    final dayList = _l(r['days']);
    if (dayList.isNotEmpty) {
      for (final d in dayList) {
        out.add(ShiftDef.fromJson({...r, 'day': d}, k + 1));
      }
    } else {
      out.add(ShiftDef.fromJson(r, k + 1));
    }
  }
  return out;
}

/// Weekly schedule entries (staff.scheduled_shifts) from whichever place the
/// server put them. The RAW weekly lists come first because they carry the
/// weekday; `shifts` comes last because a server that "pre-filters" it often
/// drops the `day` field, which would make every day look like today.
/// The first source that actually carries day info wins; otherwise the first
/// non-empty source is used as-is.
List<ShiftDef> _scheduleOf(Map<String, dynamic> j) {
  final candidates = <List<dynamic>>[
    _l(j['scheduled_shifts']),
    _l(_m(j['staff'])['scheduled_shifts']),
    _l(_m(j['schedule'])['scheduled_shifts']),
    _l(_m(j['schedule'])['shifts']),
    _l(j['shifts']),
  ];

  List<ShiftDef>? firstNonEmpty;
  for (final raw in candidates) {
    if (raw.isEmpty) continue;
    final parsed = _parseSchedule(raw);
    if (parsed.isEmpty) continue;
    if (parsed.any((s) => s.day != null)) return parsed;
    firstNonEmpty ??= parsed;
  }
  return firstNonEmpty ?? <ShiftDef>[];
}

/// Only the shifts that belong to [today]'s weekday, sorted by start time and
/// numbered 1, 2… (a double shift = two entries with the same day).
/// Entries without a `day` were already filtered by the server and are kept.
List<ShiftDef> _shiftsForDay(List<ShiftDef> all, DateTime today) {
  final weekly = all.any((s) => s.day != null);
  if (!weekly) {
    final copy = [...all]..sort((a, b) => a.number.compareTo(b.number));
    return copy;
  }
  final wd = dbDay(today);
  final todays = all.where((s) => s.day == wd).toList()
    ..sort((a, b) => a.startMin.compareTo(b.startMin));
  return [for (int k = 0; k < todays.length; k++) todays[k].withNumber(k + 1)];
}

/// Shifts of today read from the pay statement (one pay row per scheduled shift).
/// Falls back to the latest row with the same weekday. Never mixes different days.
/// Only used when the server sent NO weekly schedule at all.
List<ShiftDef> _scheduleFromPayroll(PayrollInfo? p, DateTime serverDate) {
  if (p == null || p.days.isEmpty) return const [];
  final today = dayOnly(serverDate);

  PayDay? pick;
  for (final d in p.days) {
    if (dayOnly(d.date) == today) {
      pick = d;
      break;
    }
  }
  if (pick == null) {
    final wd = dbDay(today);
    for (final d in p.days) {
      // days are newest first → first match is the latest same-weekday row
      if (dbDay(d.date) == wd && d.shifts.isNotEmpty) {
        pick = d;
        break;
      }
    }
  }
  if (pick == null) return const [];
  return [
    for (final s in pick.shifts)
      ShiftDef(number: s.number, startMin: s.schedStartMin, endMin: s.schedEndMin),
  ];
}

TodayState _stateOfPayShift(PayShift s) {
  switch (s.kind) {
    case PayKind.onTime:
      if (s.inMin == null) return TodayState.notCheckedIn;
      return s.outMin != null ? TodayState.checkedOut : TodayState.checkedIn;
    case PayKind.late:
      return s.outMin != null ? TodayState.checkedOut : TodayState.late;
    case PayKind.unexcused:
      return TodayState.absent;
    case PayKind.leave:
      return TodayState.leave;
    case PayKind.sick:
      return TodayState.sick;
    case PayKind.holiday:
      return TodayState.holiday;
    case PayKind.future:
      return TodayState.notCheckedIn;
  }
}

/// Today per shift (multi-shift staff) and leave / sick / holiday days, read from
/// today's row of the pay statement. Single-shift staff keep the server's own view.
/// Only the pay rows that match today's SCHEDULED shifts are used, so a pay
/// statement that lists every weekday's shifts can never leak into today.
TodayInfo _todayFromPayroll(
    TodayInfo base,
    PayrollInfo? pay,
    DateTime serverDate,
    List<ShiftDef> schedule,
    ) {
  if (pay == null || schedule.isEmpty) return base;
  final today = dayOnly(serverDate);
  PayDay? day;
  for (final d in pay.days) {
    if (dayOnly(d.date) == today) {
      day = d;
      break;
    }
  }
  if (day == null || day.shifts.isEmpty) return base;

  final rows = day.shifts
      .where((s) => schedule.any((x) => x.startMin == s.schedStartMin && x.endMin == s.schedEndMin))
      .toList();
  if (rows.isEmpty) return base;

  final shifts = [
    for (final s in rows)
      TodayShift(
        number: s.number,
        startMin: s.schedStartMin,
        endMin: s.schedEndMin,
        state: _stateOfPayShift(s),
        inMin: s.inMin,
        outMin: s.outMin,
        lateMin: s.lateMin,
        note: s.note,
      ),
  ];

  bool allAre(TodayState t) => shifts.every((x) => x.state == t);

  // A full day off always wins (blocks check-in + shows the banner).
  for (final t in const [TodayState.holiday, TodayState.leave, TodayState.sick]) {
    if (allAre(t)) {
      return TodayInfo(
        state: t,
        inMin: null,
        outMin: null,
        lateMin: 0,
        note: shifts.first.note ?? base.note,
        shifts: shifts,
      );
    }
  }

  if (shifts.length == 1) return base;

  final attended = shifts
      .where((x) =>
  x.state == TodayState.checkedIn || x.state == TodayState.late || x.state == TodayState.checkedOut)
      .toList();

  final TodayState state;
  if (attended.isNotEmpty) {
    if (attended.any((x) => x.lateMin > 0)) {
      state = TodayState.late;
    } else if (attended.every((x) => x.state == TodayState.checkedOut)) {
      state = TodayState.checkedOut;
    } else {
      state = TodayState.checkedIn;
    }
  } else if (allAre(TodayState.absent)) {
    state = TodayState.absent;
  } else {
    state = TodayState.notCheckedIn;
  }

  return TodayInfo(
    state: state,
    inMin: attended.isEmpty ? null : attended.first.inMin,
    outMin: attended.isEmpty ? null : attended.last.outMin,
    lateMin: attended.fold<int>(0, (a, x) => x.lateMin > a ? x.lateMin : a),
    note: base.note,
    shifts: shifts,
  );
}

/// Upcoming holidays and the current / next approved leave, from the pay statement.
TimeOffInfo _timeOffFromPayroll(PayrollInfo? pay, DateTime serverDate) {
  if (pay == null) return TimeOffInfo.empty;
  final today = dayOnly(serverDate);
  final asc = [...pay.days]..sort((a, b) => a.date.compareTo(b.date));

  final holidays = <Holiday>[
    for (final d in asc)
      if (d.holidayName != null && !dayOnly(d.date).isBefore(today))
        Holiday(date: dayOnly(d.date), name: d.holidayName!),
  ];

  // Runs of consecutive leave / sick days.
  final runs = <List<PayDay>>[];
  var cur = <PayDay>[];
  for (final d in asc) {
    final off = d.shifts.isNotEmpty &&
        d.shifts.every((x) => x.kind == PayKind.leave || x.kind == PayKind.sick);
    if (off) {
      cur.add(d);
    } else if (cur.isNotEmpty) {
      runs.add(cur);
      cur = <PayDay>[];
    }
  }
  if (cur.isNotEmpty) runs.add(cur);

  LeaveSpan? leave;
  for (final r in runs) {
    final end = dayOnly(r.last.date);
    if (end.isBefore(today)) continue;
    leave = LeaveSpan(
      type: r.first.shifts.first.kind == PayKind.sick ? 'sick' : 'other',
      start: dayOnly(r.first.date),
      end: end,
    );
    break;
  }
  return TimeOffInfo(holidays: holidays, leave: leave);
}

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
    this.weekSchedule = const [],
    this.payroll,
  });

  final String firstName;
  final String fullName;
  final String jobTitle;
  final String branchName;
  final DateTime serverDate;

  /// ONLY today's shifts (0 = day off, 1 = single, 2+ = double/multi).
  final List<ShiftDef> shifts;

  /// The whole weekly schedule (every day), for screens that want to show it.
  final List<ShiftDef> weekSchedule;

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

  HomeData withPayroll(PayrollInfo? p) => HomeData(
    firstName: firstName,
    fullName: fullName,
    jobTitle: jobTitle,
    branchName: branchName,
    serverDate: serverDate,
    shifts: shifts,
    weekSchedule: weekSchedule,
    today: today,
    month: month,
    chart: chart,
    recent: recent,
    timeOff: timeOff,
    payroll: p,
  );

  factory HomeData.fromJson(Map<String, dynamic> j) {
    final g = _m(j['greeting']);
    final chart = _m(j['chart']);
    final payroll = j['payroll'] is Map ? PayrollInfo.fromJson(_m(j['payroll'])) : null;
    final serverDate = _date(j['server_date']);
    final timeOff = j['time_off'] is Map
        ? TimeOffInfo.fromJson(_m(j['time_off']))
        : _timeOffFromPayroll(payroll, serverDate);

    // ── Schedule: keep ONLY the shifts of today's weekday ──────────
    final all = _scheduleOf(j);
    final weekly = all.any((s) => s.day != null);
    final week = weekly
        ? ([...all]..sort((a, b) {
      final c = (a.day ?? 0).compareTo(b.day ?? 0);
      return c != 0 ? c : a.startMin.compareTo(b.startMin);
    }))
        : <ShiftDef>[];

    var schedule = _shiftsForDay(all, serverDate);

    // The pay statement is only a fallback when the server sent NO weekly
    // schedule. With a weekly schedule, an empty day really is a day off.
    if (schedule.isEmpty && !weekly) schedule = _scheduleFromPayroll(payroll, serverDate);

    // Old backend with a single `shift` object (never for a known day off).
    if (schedule.isEmpty && !weekly && j['shift'] is Map) {
      final shift = _m(j['shift']);
      schedule = [
        ShiftDef(
          number: 1,
          startMin: _i(shift['start_min']) ?? 8 * 60,
          endMin: _i(shift['end_min']) ?? 17 * 60,
        ),
      ];
    }
    schedule.sort((a, b) => a.number.compareTo(b.number));

    debugPrint('📅 Schedule · entries=${all.length} · withDay=${all.where((s) => s.day != null).length} · '
        'serverDate=${serverDate.toIso8601String().substring(0, 10)} · todayDb=${dbDay(serverDate)} · '
        'todayShifts=${schedule.length}');

    final todayJson = _m(j['today']);
    var today = TodayInfo.fromJson(todayJson, schedule);
    if (_l(todayJson['shifts']).isEmpty) {
      today = _todayFromPayroll(today, payroll, serverDate, schedule);
    }

    return HomeData(
      firstName: _s(g['first_name']) ?? '',
      fullName: _s(g['full_name']) ?? '',
      jobTitle: _s(g['job_title']) ?? '',
      branchName: _s(g['branch_name']) ?? '',
      serverDate: serverDate,
      shifts: schedule,
      weekSchedule: week,
      today: today,
      month: MonthData.fromJson(_m(j['month'])),
      chart: [
        for (final d in _l(chart['days']))
          ChartPoint(
            date: _date(_m(d)['date']),
            inMin: _i(_m(d)['check_in_min']),
            late: (_b(_m(d)['late']) ?? false) || (_i(_m(d)['late_min']) ?? 0) > 0,
          ),
      ],
      recent: [for (final r in _l(j['recent'])) AttRecord.fromJson(_m(r))],
      timeOff: timeOff,
      payroll: payroll,
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
        debugPrint('📨 Home keys: ${json.keys.toList()} · payroll=${json['payroll'] is Map ? 'present' : 'MISSING'}');
        var data = HomeData.fromJson(json);

        // The server could not calculate pay on the home call → ask the payroll scope once.
        if (data.payroll == null) {
          debugPrint('💰 Home response had no payroll, asking the payroll scope…');
          try {
            final pay = await loadPayroll(data.month.year, data.month.month, forceRefresh: true);
            data = data.withPayroll(pay);
          } catch (e) {
            debugPrint('⚠️ Payroll fallback failed: $e');
          }
        }

        // Seed the caches so the first open of each sheet is instant.
        _monthCache[_key(data.month.year, data.month.month)] =
            _CachedMonth(data.month, DateTime.now());
        final pay = data.payroll;
        if (pay != null) {
          _payrollCache[_key(pay.year, pay.month)] = _CachedPayroll(pay, DateTime.now());
        }

        debugPrint('✅ Home loaded in ${sw.elapsedMilliseconds}ms · '
            'today=${data.today.state.name} · todayShifts=${data.shifts.length} · '
            'weekEntries=${data.weekSchedule.length} · '
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
            '${data.days.length} days · salary=${data.monthlySalary} · deductions=${data.totalDeduction}');
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