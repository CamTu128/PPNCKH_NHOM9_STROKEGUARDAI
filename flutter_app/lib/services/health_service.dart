import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/models.dart';
 
class HealthService {
  static final Health _health = Health();
 
  static const List<HealthDataType> _types = [
    HealthDataType.HEART_RATE,       // Nhip tim (bpm)
    HealthDataType.BLOOD_OXYGEN,     // SpO2 (%)
    HealthDataType.SLEEP_ASLEEP,     // Thoi gian ngu sau
    HealthDataType.SLEEP_SESSION,    // Fallback cho giac ngu
    HealthDataType.STEPS,            // Buoc chan
    HealthDataType.ACTIVE_ENERGY_BURNED, // Calo hoat dong
    HealthDataType.BODY_MASS_INDEX,  // Chi so BMI
  ];
 
  static Future<bool> requestPermissions() async {
    try {
      await Permission.activityRecognition.request();
      await Permission.sensors.request();
      return await _health.requestAuthorization(
        _types,
        permissions: _types.map((e) => HealthDataAccess.READ).toList(),
      );
    } catch (e) { return false; }
  }
 
  static Future<BiometricSnapshot> fetchLatestData() async {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 7));
    final midnightToday = DateTime(now.year, now.month, now.day);
 
    List<HealthDataPoint> pts = [];
    try {
      pts = await _health.getHealthDataFromTypes(
          startTime: start, endTime: now, types: _types);
      pts = _health.removeDuplicates(pts); // Loai bo ban sao trung
    } catch (e) { return BiometricSnapshot.defaultValues(); }
 
    if (pts.isEmpty) return BiometricSnapshot.defaultValues();
 
    // Helper: lay gia tri cuoi cung cua mot kieu data
    double last(HealthDataType type, double fallback) {
      final list = pts.where((p) => p.type == type).toList();
      if (list.isEmpty) return fallback;
      return (list.last.value as NumericHealthValue).numericValue.toDouble();
    }
 
    // Heart Rate
    final hr = last(HealthDataType.HEART_RATE, 72);
 
    // SpO2: mot so thiet bi tra ve 0-1 thay vi 0-100, can nhan 100
    double spo2 = last(HealthDataType.BLOOD_OXYGEN, 98);
    if (spo2 <= 1) spo2 *= 100;
 
    // Sleep: uu tien SLEEP_ASLEEP, fallback sang SLEEP_SESSION
    final sleepWindow = now.subtract(const Duration(days: 2));
    List<HealthDataPoint> sleepPts = pts.where((p) =>
      p.type == HealthDataType.SLEEP_ASLEEP &&
      p.dateTo.isBefore(now) && p.dateTo.isAfter(sleepWindow)).toList();
    if (sleepPts.isEmpty)
      sleepPts = pts.where((p) =>
        p.type == HealthDataType.SLEEP_SESSION &&
        p.dateTo.isBefore(now) && p.dateTo.isAfter(sleepWindow)).toList();
    double sleepHours = 0;
    if (sleepPts.isNotEmpty) {
      int totalMin = 0;
      for (final s in sleepPts) {
        final min = s.dateTo.difference(s.dateFrom).inMinutes;
        if (min > 0 && min < 720) totalMin += min; // Loai segment bat thuong
      }
      if (totalMin > 0) sleepHours = totalMin / 60;
    }
 
    // Steps: su dung API tich hop de tinh chinh xac hon
    int steps = 0;
    try {
      final total = await _health.getTotalStepsInInterval(midnightToday, now);
      if (total != null) steps = total;
    } catch (e) {
      // Fallback: tong hop thu cong
      for (final p in pts.where((p) => p.type == HealthDataType.STEPS))
        steps += (p.value as NumericHealthValue).numericValue.toInt();
    }
 
    // Calories
    double calories = 0;
    for (final p in pts.where(
        (p) => p.type == HealthDataType.ACTIVE_ENERGY_BURNED))
      calories += (p.value as NumericHealthValue).numericValue.toDouble();
    final caloriesFinal = calories > 0 ? calories : steps * 0.04;
 
    final bmi = last(HealthDataType.BODY_MASS_INDEX, 22);
 
    return BiometricSnapshot(
      heartRate:   hr.clamp(30, 220),
      spo2:        spo2.clamp(80, 100),
      sleepHours:  sleepHours.clamp(0, 24),
      stressScore: _estimateStress(hr: hr, spo2: spo2, sleepHours: sleepHours).clamp(0, 100),
      bmi:         bmi.clamp(10, 60),
      steps:       steps,
      calories:    caloriesFinal,
      fetchedAt:   now,
      isSimulated: false,
    );
  }
 
  // Cong thuc uoc tinh stress tu 3 chi so: HR + SpO2 + Sleep
  static double _estimateStress({
    required double hr, required double spo2, required double sleepHours}) {
    final hrN   = ((hr - 60) / 60).clamp(0.0, 1.0);   // Chuan hoa nhip tim
    final spo2N = ((98 - spo2) / 10).clamp(0.0, 1.0); // SpO2 thap = stress cao
    final slpN  = ((7 - sleepHours) / 7).clamp(0.0, 1.0); // Thieu ngu = stress cao
    return (0.45 * hrN + 0.35 * spo2N + 0.20 * slpN) * 100;
  }
}
