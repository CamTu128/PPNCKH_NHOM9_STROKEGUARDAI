// lib/services/health_service.dart
// Reads Samsung Fit 3 data via Android Health Connect

import 'package:health/health.dart';
import '../models/models.dart';

class HealthService {
  static final _health = Health();

  static const _types = [
    HealthDataType.HEART_RATE,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.SLEEP_ASLEEP,
<<<<<<< HEAD
    HealthDataType.SLEEP_SESSION,
=======
    HealthDataType.WEIGHT,
    HealthDataType.HEIGHT,
>>>>>>> 1a09eba3f05d295fe063cec17c6a2739a79fa358
    HealthDataType.STEPS,
  ];

  /// Request read permissions from Health Connect.
  /// Returns true if granted, false if denied.
  static Future<bool> requestPermissions() async {
    try {
<<<<<<< HEAD
      await Permission.activityRecognition.request();
      await Permission.sensors.request();
      return await _health.requestAuthorization(
        _types,
        permissions: _types.map((e) => HealthDataAccess.READ).toList(),
      );
    } catch (e, stack) {
      debugPrint('PERMISSION ERROR $e');
      debugPrint(stack.toString());
=======
      final perms = _types.map((_) => HealthDataAccess.READ).toList();
      return await _health.requestAuthorization(_types, permissions: perms);
    } catch (e) {
>>>>>>> 1a09eba3f05d295fe063cec17c6a2739a79fa358
      return false;
    }
  }

<<<<<<< HEAD
  static Future<BiometricSnapshot> fetchLatestData() async {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 7));
    
    // Mốc thời gian 00:00:00 ngày hôm nay để lấy dữ liệu đồng bộ
    final midnightToday = DateTime(now.year, now.month, now.day);

    List<HealthDataPoint> pts = [];
    try {
      pts = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: now,
        types: _types,
      );
      
      pts = _health.removeDuplicates(pts);
      
      debugPrint('HEALTH POINTS (CLEANED): ${pts.length}');
      for (final t in _types) {
        final cnt = pts.where((p) => p.type == t).length;
        debugPrint('  TYPE $t -> $cnt records');
      }
    } catch (e, stack) {
      debugPrint('FETCH ERROR $e');
      debugPrint(stack.toString());
      return BiometricSnapshot.defaultValues();
    }

    if (pts.isEmpty) {
      debugPrint('NO HEALTH DATA -> defaultValues');
      return BiometricSnapshot.defaultValues();
    }

    double last(HealthDataType type, double fallback) {
      final list = pts.where((p) => p.type == type).toList();
      if (list.isEmpty) return fallback;
      return (list.last.value as NumericHealthValue).numericValue.toDouble();
    }

    // ================= HEART RATE =================
    final hr = last(HealthDataType.HEART_RATE, 72);
    debugPrint('HR: $hr');

    // ================= SPO2 =================
    double spo2 = last(HealthDataType.BLOOD_OXYGEN, 98);
    if (spo2 <= 1) spo2 *= 100; 
    debugPrint('SPO2: $spo2');

    // ================= GIỮ NGUYÊN LOGIC NGỦ CỦA BẠN =================
    final sleepWindow = now.subtract(const Duration(days: 2));

    List<HealthDataPoint> sleepPts = pts.where((p) {
      return p.type == HealthDataType.SLEEP_ASLEEP &&
          p.dateTo.isBefore(now) &&
          p.dateTo.isAfter(sleepWindow);
    }).toList();

    if (sleepPts.isEmpty) {
      sleepPts = pts.where((p) {
        return p.type == HealthDataType.SLEEP_SESSION &&
            p.dateTo.isBefore(now) &&
            p.dateTo.isAfter(sleepWindow);
      }).toList();
      debugPrint('Using SLEEP_SESSION fallback: ${sleepPts.length} records');
    }

    double sleepHours = 0;

    if (sleepPts.isNotEmpty) {
      debugPrint('SLEEP RECORDS: ${sleepPts.length}');
      int totalMinutes = 0;
      for (final s in sleepPts) {
        final minutes = s.dateTo.difference(s.dateFrom).inMinutes;
        debugPrint('  SEG: ${s.dateFrom} -> ${s.dateTo} = $minutes min');
        if (minutes > 0 && minutes < 720) {
          totalMinutes += minutes;
        }
      }
      debugPrint('TOTAL SLEEP MINUTES: $totalMinutes');
      if (totalMinutes > 0) {
        sleepHours = double.parse((totalMinutes / 60).toStringAsFixed(1));
      }
    }
    debugPrint('FINAL SLEEP: $sleepHours h');

    // ================= SỬA BƯỚC CHÂN: SỬ DỤNG API TÍNH TỔNG HỆ THỐNG =================
    int steps = 0;
    try {
      final totalSteps = await _health.getTotalStepsInInterval(midnightToday, now);
      if (totalSteps != null) {
        steps = totalSteps;
      }
    } catch (e) {
      debugPrint('Lỗi hàm tính tổng hệ thống, dùng fallback: $e');
      final stepPts = pts.where((p) => p.type == HealthDataType.STEPS).toList();
      for (final p in stepPts) {
        if (p.value is NumericHealthValue) {
          steps += (p.value as NumericHealthValue).numericValue.toInt();
        }
      }
    }
    debugPrint('TOTAL STEPS: $steps');

    // ================= SỬA CALORIES: ĐỌC DỮ LIỆU TỪ SAMSUNG SYNC =================
    double calories = 0;
    final calPts = pts.where((p) => p.type == HealthDataType.ACTIVE_ENERGY_BURNED).toList();

    for (final p in calPts) {
      if (p.value is NumericHealthValue) {
        calories += (p.value as NumericHealthValue).numericValue.toDouble();
      }
    }

    final caloriesFinal = calories > 0
        ? double.parse(calories.toStringAsFixed(0))
        : double.parse((steps * 0.04).toStringAsFixed(0)); 

    debugPrint('CALORIES FROM HEALTH CONNECT: $calories -> FINAL CALORIES: $caloriesFinal');

    // ================= BMI =================
    final bmi = last(HealthDataType.BODY_MASS_INDEX, 22);
    debugPrint('BMI: $bmi');

    final stress = _estimateStress(
      hr: hr,
      spo2: spo2,
      sleepHours: sleepHours,
    );

    return BiometricSnapshot(
      heartRate: hr.clamp(30, 220),
      spo2: spo2.clamp(80, 100),
      sleepHours: sleepHours.clamp(0, 24),
      stressScore: stress.clamp(0, 100),
      bmi: bmi.clamp(10, 60),
      steps: steps,
      calories: caloriesFinal,
      fetchedAt: now,
      isSimulated: false,
=======
  /// Fetch the last 24 hours of biometrics from Health Connect.
  /// Falls back to null for any data type that isn't available yet.
  static Future<BiometricSnapshot> fetchSnapshot() async {
    final now   = DateTime.now();
    final since = now.subtract(const Duration(hours: 24));

    // Generic average helper
    Future<double?> avg(HealthDataType type) async {
      try {
        final data = await _health.getHealthDataFromTypes(
          startTime: since, endTime: now, types: [type]);
        if (data.isEmpty) return null;
        final sum = data.fold<double>(
          0.0,
          (acc, pt) => acc + (pt.value as NumericHealthValue).numericValue.toDouble(),
        );
        return sum / data.length;
      } catch (_) {
        return null;
      }
    }

    final heartRate = await avg(HealthDataType.HEART_RATE);
    final spo2      = await avg(HealthDataType.BLOOD_OXYGEN);
    final weight    = await avg(HealthDataType.WEIGHT);   // kg
    final heightM   = await avg(HealthDataType.HEIGHT);   // metres

    // Sleep: sum all SLEEP_ASLEEP segments from last 10 hours → convert to hrs
    double? sleepHours;
    try {
      final sleepData = await _health.getHealthDataFromTypes(
        startTime: now.subtract(const Duration(hours: 12)),
        endTime: now,
        types: [HealthDataType.SLEEP_ASLEEP],
      );
      if (sleepData.isNotEmpty) {
        final totalMins = sleepData.fold<double>(
          0.0,
          (acc, pt) => acc + (pt.value as NumericHealthValue).numericValue.toDouble(),
        );
        sleepHours = totalMins / 60.0;
      }
    } catch (_) {}

    // BMI derived from weight and height
    double? bmi;
    if (weight != null && heightM != null && heightM > 0) {
      bmi = weight / (heightM * heightM);
    }

    // Stress score: derived from HR and SpO2 using Samsung Health methodology
    // Higher HR + lower SpO2 → higher stress
    double? stressScore;
    if (heartRate != null && spo2 != null) {
      final hrContrib   = ((heartRate - 60) / 80.0 * 50).clamp(0.0, 50.0);
      final spo2Contrib = ((100.0 - spo2) / 5.0 * 30).clamp(0.0, 45.0);
      final sleepPenalty = sleepHours != null
        ? ((7.0 - sleepHours) / 7.0 * 10).clamp(0.0, 10.0)
        : 5.0;
      stressScore = (hrContrib + spo2Contrib + sleepPenalty).clamp(5.0, 95.0);
    }

    return BiometricSnapshot(
      heartRate:   heartRate,
      spo2:        spo2,
      sleepHours:  sleepHours,
      stressScore: stressScore,
      bmi:         bmi,
>>>>>>> 1a09eba3f05d295fe063cec17c6a2739a79fa358
    );
  }
}
