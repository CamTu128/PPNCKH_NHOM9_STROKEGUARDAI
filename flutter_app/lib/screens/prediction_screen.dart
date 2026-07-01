// Gauge chart xác suất, ensemble verdict, risk badge, so sánh 3 mô hình
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/health_service.dart';
import '../theme/app_theme.dart';
 
class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});
  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}
 
class _PredictionScreenState extends State<PredictionScreen> {
  UserModel?         _user;
  BiometricSnapshot? _bio;
  PredictionResult?  _result;
  bool _loadingInit = true;
  bool _predicting  = false;
  String _predictStep = ''; // Mô tả bước đang thực hiện
 
  @override
  void initState() { super.initState(); _init(); }
 
  // Khởi tạo: load user và bio để hiển thị preview trước khi dự báo
  Future<void> _init() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users').doc(uid).get();
        if (doc.exists && mounted)
          setState(() => _user = UserModel.fromJson(doc.data()!));
      }
    } catch (e) { debugPrint('_init Firestore error: $e'); }
    try {
      final granted = await HealthService.requestPermissions()
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
      final bio = granted
          ? await HealthService.fetchLatestData()
              .timeout(const Duration(seconds: 15),
                onTimeout: () => BiometricSnapshot.defaultValues())
          : BiometricSnapshot.defaultValues();
      if (mounted) setState(() => _bio = bio);
    } catch (e) {
      if (mounted) setState(() => _bio = BiometricSnapshot.defaultValues());
    }
    if (mounted) setState(() => _loadingInit = false);
  }
 
  // Luồng dự báo 3 bước với step indicator
  Future<void> _predict() async {
    setState(() { _predicting = true; _predictStep = 'Dang dong bo ho so...'; });
 
    // Bước 1: Reload UserModel mới nhất từ Firestore
    UserModel? freshUser;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users').doc(uid).get();
        if (doc.exists) freshUser = UserModel.fromJson(doc.data()!);
      }
    } catch (e) { debugPrint('_predict reload error: $e'); }
    freshUser ??= _user;
 
    // Bước 2: Fetch dữ liệu sức khoẻ mới nhất
    if (mounted) setState(() => _predictStep = 'Dang lay du lieu suc khoe...');
    BiometricSnapshot freshBio;
    try {
      final granted = await HealthService.requestPermissions()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      freshBio = granted
          ? await HealthService.fetchLatestData()
              .timeout(const Duration(seconds: 15),
                onTimeout: () => _bio ?? BiometricSnapshot.defaultValues())
          : (_bio ?? BiometricSnapshot.defaultValues());
    } catch (e) {
      freshBio = _bio ?? BiometricSnapshot.defaultValues();
    }
 
    // Bước 3: Gọi FastAPI và nhận kết quả
    if (mounted) setState(() => _predictStep = 'Dang phan tich AI...');
    try {
      final r = await ApiService.predict(user: freshUser!, bio: freshBio);
      if (mounted) {
        setState(() { _result = r; _predicting = false; _predictStep = ''; });
        _saveFirestore(r);
      }
    } catch (e) {
      if (mounted) setState(() { _predicting = false; _predictStep = ''; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Loi ket noi backend: $e'),
          backgroundColor: SGColor.riskHigh));
    }
  }
 
  // Lưu kết quả dự báo vào Firestore sub-collection
  Future<void> _saveFirestore(PredictionResult r) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users').doc(uid).collection('predictions')
        .add(r.toFirestore());
  }
 
  Color _probColor(double p) =>
      p < 0.35 ? SGColor.riskLow : p < 0.65 ? SGColor.riskMid : SGColor.riskHigh;
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SGColor.bg,
      appBar: AppBar(title: const Text('Phan tich nguy co dot quy')),
      body: SingleChildScrollView(
        child: Column(children: [
          // Card: dữ liệu sinh học preview
          if (_bio != null) _BioPreviewCard(bio: _bio!),
          // Card: Gauge Chart + Risk Badge
          SGCard(child: Column(children: [
            const Text('Xac suat nguy co (Ensemble)', style: SGText.h2),
            if (_result != null) ...[
              SizedBox(height: 160, child: CustomPaint(
                painter: _GaugePainter(
                    probability: _result!.ensemble,
                    color: _probColor(_result!.ensemble)),
                child: const SizedBox.expand(),
              )),
              Text('${(_result!.ensemble * 100).toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold,
                      color: _probColor(_result!.ensemble))),
              RiskBadge(riskLevel: _result!.riskLevel),
            ],
          ])),
          // Card: So sánh 3 mô hình ML
          if (_result != null) ...[
            SGCard(child: Column(children: [
              const Text('So sanh 3 mo hinh ML', style: SGText.h3),
              _modelBar('Logistic Regression',
                  _result!.logisticRegression, Colors.blue),
              _modelBar('Decision Tree',
                  _result!.decisionTree, Colors.orange),
              _modelBar('Random Forest',
                  _result!.randomForest, Colors.green),
            ])),
            // Card: Bar chart fl_chart
            SGCard(child: SizedBox(height: 200, child: BarChart(
              BarChartData(barGroups: [
                _bar(0, _result!.logisticRegression, Colors.blue),
                _bar(1, _result!.decisionTree, Colors.orange),
                _bar(2, _result!.randomForest, Colors.green),
                _bar(3, _result!.ensemble, SGColor.primary),
              ]),
            ))),
            // Card: Recommendation
            SGCard(
              color: _probColor(_result!.ensemble).withOpacity(0.07),
              child: Text(_result!.recommendation)),
            // Card: Top-5 Risk Factors
            SGCard(child: Column(
              children: _result!.topRiskFactors.map((f) =>
                _RiskFactorTile(factor: f)).toList())),
          ],
          // Nút Phân tích
          _PredictButton(predicting: _predicting,
              step: _predictStep, onTap: _predict),
        ]),
      ),
    );
  }
}
 
// CustomPainter vẽ Gauge Chart bán nguyệt
class _GaugePainter extends CustomPainter {
  final double probability;
  final Color color;
  const _GaugePainter({required this.probability, required this.color});
 
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.78;
    final r  = size.width * 0.36;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    const sw = 16.0;
    // Arc nền màu xám
    canvas.drawArc(rect, 3.14, 3.14, false,
        Paint()..color = Colors.grey.shade200..strokeWidth = sw
          ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    // Arc màu theo xác suất (0 → 180 độ)
    canvas.drawArc(rect, 3.14, 3.14 * probability.clamp(0, 1), false,
        Paint()..color = color..strokeWidth = sw
          ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
  }
 
  @override
  bool shouldRepaint(_GaugePainter o) => o.probability != probability;
}
