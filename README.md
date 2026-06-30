# 🫀 StrokeGuard AI — Production Build
**Nhóm 9 | NCKH 2026 | ĐH Nông Lâm TP.HCM**
GVHD: TS. Nguyễn Thị Phương Trâm

---

## 📊 Kết quả mô hình (metrics thật từ notebook)

| Mô hình | Accuracy | Recall | F1-Score | AUC-ROC | Threshold |
|---|---|---|---|---|---|
| Logistic Regression | 98.92% | **86.00%** | 0.8866 | **0.9871** | 0.82 |
| Decision Tree | 85.39% | **86.00%** | 0.3660 | 0.8890 | 0.87 |
| Random Forest | 94.12% | **88.00%** | 0.5946 | 0.9699 | 0.33 |

> Cả 3 mô hình đạt **Recall > 85%** (mục tiêu đề cương). LR có AUC-ROC cao nhất (0.9871).

---

## 📁 Cấu trúc project

```
strokeguard_final/
├── backend/
│   ├── main.py              ← FastAPI (STT6 Lâm Thị Hoàng Như)
│   ├── requirements.txt
│   └── models/              ← ✅ Đã có 9 file .pkl thật
│       ├── logistic_regression.pkl
│       ├── decision_tree.pkl
│       ├── random_forest.pkl
│       ├── scaler.pkl
│       ├── feature_columns.pkl
│       ├── lr_threshold.pkl  (0.82)
│       ├── dt_threshold.pkl  (0.87)
│       ├── rf_threshold.pkl  (0.33)
│       └── model_metrics.pkl
├── flutter_app/
│   ├── lib/
│   │   ├── main.dart               STT8 - Cù Thị Hoài Ngọc
│   │   ├── models/models.dart      STT7 - Lê Thị Kim Ngân
│   │   ├── theme/app_theme.dart    STT7
│   │   ├── services/
│   │   │   ├── api_service.dart    STT6 - Lâm Thị Hoàng Như
│   │   │   └── health_service.dart STT5 - Trần Thị Hiền
│   │   └── screens/
│   │       ├── register_screen.dart   STT2 - Nguyễn Ngọc Thùy Dương
│   │       ├── home_screen.dart       STT3 - Nguyễn Thị Quỳnh Như
│   │       ├── prediction_screen.dart STT1 - Trần Thị Cẩm Tú
│   │       ├── history_screen.dart    STT4 - Phan Thị Yến Ngọc
│   │       └── profile_screen.dart    STT5 - Trần Thị Hiền
│   ├── android/app/src/main/AndroidManifest.xml   STT8
│   └── pubspec.yaml
└── StrokeGuard_Train.ipynb  ← Notebook Colab (train lại nếu cần)
```

---

## ⚡ CHẠY NGAY (Backend đã có .pkl)

### Backend
```bash
cd backend

# ⚠️ Cài đúng version sklearn khớp với pkl
pip install fastapi uvicorn scikit-learn==1.6.1 pandas joblib numpy

uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Mở trình duyệt: **http://localhost:8000/docs** → test /predict ngay

**Verify nhanh:**
```bash
curl http://localhost:8000/health
# Kết quả mong đợi: "simulation_mode": false  ← models đã load
```

### Flutter App
```bash
cd flutter_app

# Bước 1: Setup Firebase (xem hướng dẫn bên dưới)
# Bước 2:
flutter pub get
flutter run
```

---

## 🔥 Setup Firebase (bắt buộc)

### 1. Tạo project
1. Vào https://console.firebase.google.com → **Add project** → đặt tên `strokeguard-nhom9`
2. **Authentication** → Sign-in method → **Email/Password** → Enable
3. **Firestore Database** → Create → **Start in test mode** → region `asia-southeast1`

### 2. Kết nối Flutter (chạy 1 lần)
```bash
# Cài FlutterFire CLI
dart pub global activate flutterfire_cli

# Trong thư mục flutter_app/
cd flutter_app
flutterfire configure --project=strokeguard-nhom9
```
> Tự tạo `lib/firebase_options.dart` + `android/app/google-services.json`

### 3. Cập nhật main.dart
Sau khi có `firebase_options.dart`, sửa `lib/main.dart`:
```dart
import 'firebase_options.dart';   // thêm dòng này

// Trong hàm main():
await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,  // thêm dòng này
);
```

### 4. Firestore Rules
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
      match /predictions/{pid} {
        allow read, write: if request.auth != null && request.auth.uid == uid;
      }
    }
  }
}
```

---

## 📱 Test trên điện thoại thật (Samsung Fit 3)

1. Cài **Health Connect** từ CH Play
2. Kết nối Samsung Galaxy Fit 3 → Galaxy Wearable app
3. Đổi IP trong `lib/services/api_service.dart`:
```dart
static const String baseUrl = 'http://192.168.x.x:8000'; // IP máy tính cùng WiFi
```

---

## 🧪 Test /predict bằng curl
```bash
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{
    "gender": 1, "age": 55, "hypertension": 1, "heart_disease": 0,
    "ever_married": 1, "Residence_type": 1, "work_type": "Private",
    "smoking_status": "formerly smoked", "avg_glucose_level": 180.5,
    "bmi": 28.3, "heart_rate": 85, "spo2": 96.5,
    "sleep_hours": 5.5, "stress_score": 72.0
  }'
```
**Kết quả mong đợi:**
```json
{
  "logistic_regression": 0.9501,
  "decision_tree": 0.9963,
  "random_forest": 0.9822,
  "ensemble": 0.9762,
  "risk_level": "CAO",
  "simulation_mode": false
}
```

---

## ⚠️ Lưu ý về scikit-learn version

Các file .pkl được train với `scikit-learn==1.6.1`.  
Nếu máy đang dùng version khác, chạy:
```bash
pip install scikit-learn==1.6.1
```
Hoặc dùng virtual environment:
```bash
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

---

## ✅ Checklist trước khi demo

- [ ] `cd backend && uvicorn main:app --port 8000` → `/health` trả `simulation_mode: false`
- [ ] Firebase đã setup → có `google-services.json`
- [ ] `flutter pub get` không lỗi
- [ ] `flutter run` chạy được
- [ ] Đăng ký → nhập hồ sơ → Phân tích → thấy kết quả %

---

*StrokeGuard AI — Nhóm 9 NCKH 2026 | Recall > 85% ✅*
