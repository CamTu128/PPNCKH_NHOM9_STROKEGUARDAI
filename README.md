# StrokeGuard AI - Hướng dẫn cài đặt

Hệ thống dự báo sớm nguy cơ đột quỵ, kết hợp dữ liệu lâm sàng và dữ liệu sinh học thu thập từ Samsung Galaxy Fit 3 qua Android Health Connect API. Hệ thống gồm hai phần: backend FastAPI (chạy mô hình Machine Learning) và ứng dụng di động Flutter.

## Mục lục

1. [Tổng quan kiến trúc](#tổng-quan-kiến-trúc)
2. [Yêu cầu phần cứng và phần mềm](#yêu-cầu-phần-cứng-và-phần-mềm)
3. [Cài đặt FastAPI Backend](#cài-đặt-fastapi-backend)
4. [Cài đặt Flutter App](#cài-đặt-flutter-app)
5. [Kiểm tra sau triển khai](#kiểm-tra-sau-triển-khai)
6. [Xử lý sự cố thường gặp](#xử-lý-sự-cố-thường-gặp)

## Tổng quan kiến trúc

Hệ thống hoạt động theo mô hình mạng LAN cục bộ: máy tính chạy FastAPI backend và điện thoại chạy Flutter app phải cùng kết nối một mạng WiFi.

```
Samsung Galaxy Fit 3 → Health Connect → Flutter App → FastAPI Backend → Mô hình ML
                                              ↓
                                          Firebase
                                    (Auth + Firestore)
```

## Yêu cầu phần cứng và phần mềm

| Thành phần | Yêu cầu tối thiểu | Cấu hình đã kiểm thử thực tế |
|---|---|---|
| Máy chủ (FastAPI) | RAM 4GB, Python 3.10+, port 8000 mở | Laptop Windows 11, Intel Core i5-1235U, RAM 8GB, Python 3.11.5, Anaconda 23.7 |
| Thiết bị di động | Android 10+, Health Connect 1.0+ | Samsung Galaxy A36 5G, Android 15, Health Connect v1.0.0-alpha11 |
| Thiết bị đeo | Samsung Galaxy Fit 3 hoặc thiết bị tương thích Health Connect | Samsung Galaxy Fit 3 (SM-R390), firmware 2.0.0.50, đồng bộ qua Samsung Health 6.x |
| Mạng | WiFi LAN cùng subnet | WiFi 802.11ac |
| Firebase | Dự án Firebase với Firestore + Auth bật | Region: asia-southeast1 (Singapore) |

## Cài đặt FastAPI Backend

### Bước 1: Cài đặt Python dependencies

```bash
# Tạo môi trường ảo (khuyến nghị)
conda create -n strokeguard python=3.11
conda activate strokeguard

# Cài đặt các thư viện cần thiết
pip install fastapi uvicorn scikit-learn==1.6.1 pandas joblib numpy

# Kiểm tra phiên bản scikit-learn (quan trọng: model.pkl cần khớp phiên bản)
python -c "import sklearn; print(sklearn.__version__)"
# Output mong đợi: 1.6.1
```

### Bước 2: Chuẩn bị file mô hình (.pkl)

Cấu trúc thư mục backend cần có dạng:

```
strokeguard-backend/
├── main.py                      # File FastAPI chính
└── models/                      # Thư mục chứa các file mô hình
    ├── logistic_regression.pkl
    ├── decision_tree.pkl
    ├── random_forest.pkl
    ├── scaler.pkl
    ├── feature_columns.pkl
    ├── model_metrics.pkl
    ├── lr_threshold.pkl
    ├── dt_threshold.pkl
    └── rf_threshold.pkl
```

### Bước 3: Chạy FastAPI server

```bash
cd strokeguard-backend/

# Chạy server, lắng nghe trên tất cả interface (quan trọng để điện thoại kết nối được)
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Output mong đợi khi khởi động thành công:

```
INFO:    Started server process [XXXXX]
INFO:    Waiting for application startup.
INFO:    Models ready: True
INFO:    Application startup complete.
INFO:    Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

Kiểm tra qua trình duyệt trên máy chủ:
- `http://localhost:8000/health`
- `http://localhost:8000/docs` (Swagger UI tự động)

Lấy IP LAN của máy chủ để cấu hình trong Flutter app:

```bash
ipconfig    # Windows
ifconfig    # Linux/Mac -> tìm IPv4 Address của WiFi adapter
```

## Cài đặt Flutter App

### Bước 1: Cài đặt Flutter SDK và chuẩn bị dự án

```bash
# Cài Flutter SDK (xem flutter.dev/install)
flutter --version
# Kiểm tra: Flutter 3.x.x, Dart 3.x.x
```

Clone hoặc giải nén source code dự án. Cấu trúc thư mục Flutter app:

```
strokeguard-app/
├── lib/
│   ├── main.dart
│   ├── models/models.dart
│   ├── screens/
│   │   ├── register_screen.dart
│   │   ├── home_screen.dart
│   │   ├── prediction_screen.dart
│   │   ├── profile_screen.dart
│   │   └── history_screen.dart
│   ├── services/
│   │   ├── health_service.dart
│   │   └── api_service.dart
│   └── theme/app_theme.dart
├── android/
│   └── app/src/main/AndroidManifest.xml   # khai báo quyền Health Connect
├── pubspec.yaml
└── google-services.json                    # tải từ Firebase Console
```

### Bước 2: Cấu hình IP backend và Firebase

Sửa file `lib/services/api_service.dart`, thay IP bằng địa chỉ LAN thực tế của máy chủ FastAPI:

```dart
// File: lib/services/api_service.dart
static const String baseUrl = 'http://<IP-MAY-CHU>:8000';
// Ví dụ: 'http://192.168.1.105:8000'
```

Tải file `google-services.json` từ Firebase Console > Project Settings > Android app, đặt vào `android/app/google-services.json`. Đảm bảo `applicationId` khớp với cấu hình Firebase.

### Bước 3: Khai báo quyền Health Connect trong AndroidManifest.xml

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application ...>
    <!-- Khai báo intent filter để Health Connect nhận ra app này -->
    <activity android:name=".MainActivity" ...>
      <intent-filter>
        <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"/>
      </intent-filter>
    </activity>
  </application>

  <!-- Các quyền cần thiết -->
  <uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>
  <uses-permission android:name="android.permission.BODY_SENSORS"/>
  <uses-permission android:name="android.permission.health.READ_HEART_RATE"/>
  <uses-permission android:name="android.permission.health.READ_BLOOD_OXYGEN"/>
  <uses-permission android:name="android.permission.health.READ_SLEEP"/>
  <uses-permission android:name="android.permission.health.READ_STEPS"/>
  <uses-permission android:name="android.permission.health.READ_ACTIVE_CALORIES_BURNED"/>
  <uses-permission android:name="android.permission.health.READ_BODY_MASS_INDEX"/>
</manifest>
```

### Bước 4: Build và chạy app trên thiết bị thực

```bash
# Cài đặt dependencies
flutter pub get

# Kết nối điện thoại Android qua USB (bật Developer Options + USB Debugging)
flutter devices
# Xác nhận thiết bị hiện trong danh sách

# Build và chạy (chế độ debug)
flutter run

# Build APK phát hành (production)
flutter build apk --release
# APK ở: build/app/outputs/flutter-apk/app-release.apk
```

## Kiểm tra sau triển khai

| # | Bước kiểm tra | Cách kiểm tra | Kết quả mong đợi |
|---|---|---|---|
| 1 | FastAPI đang chạy | Truy cập `http://[IP]:8000/health` từ trình duyệt máy chủ | `{"status": "online", "models_loaded": {"logistic_regression": true, ...}}` |
| 2 | Kết nối mạng LAN | Truy cập `http://[IP]:8000` từ trình duyệt điện thoại (cùng WiFi) | `{"app": "StrokeGuard AI", "version": "2.0.0"}` |
| 3 | Firebase kết nối | Đăng ký tài khoản mới trong app | Document xuất hiện trong Firestore Console > users |
| 4 | Health Connect hoạt động | Mở tab Home, chấp nhận quyền khi được hỏi | Badge "Đã kết nối" trong tab Hồ Sơ, giá trị thực từ Fit 3 (không có banner mô phỏng) |
| 5 | Dự báo hoạt động end-to-end | Nhấn "Phân tích nguy cơ đột quỵ" trong tab Phân tích | Gauge chart hiển thị kết quả, kết quả xuất hiện trong Lịch sử |

## Xử lý sự cố thường gặp

Nếu dự báo thất bại với lỗi **"connection refused"**, kiểm tra lần lượt:

1. FastAPI đang chạy với `--host 0.0.0.0` (không phải `127.0.0.1`).
2. Tường lửa Windows đã cho phép port 8000.
3. Điện thoại và máy chủ cùng mạng WiFi.
4. IP cấu hình trong `api_service.dart` đúng với IP LAN hiện tại của máy chủ (IP có thể đổi mỗi lần kết nối lại WiFi).

---

*Tài liệu này được tổng hợp từ báo cáo đồ án "Ứng dụng Machine Learning trong phát hiện sớm nguy cơ đột quỵ dựa trên dữ liệu sinh học từ đồng hồ thông minh Samsung Galaxy Fit 3", mục 3.13 - Môi trường triển khai và hướng dẫn cài đặt.*
