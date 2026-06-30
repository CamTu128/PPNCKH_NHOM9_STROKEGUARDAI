"""
StrokeGuard AI — FastAPI Backend v2  (Production)
Nhóm 9 | NCKH 2026 | ĐH Nông Lâm TP.HCM
GVHD: TS. Nguyễn Thị Phương Trâm
STT6 - Lâm Thị Hoàng Như

⚠️  Scaler chỉ fit trên 7 numeric cols:
    age, avg_glucose_level, bmi, heart_rate, spo2, sleep_hours, stress_score
    Các cột còn lại (binary / one-hot) giữ nguyên giá trị gốc.

Run:
    pip install fastapi uvicorn scikit-learn==1.6.1 pandas joblib numpy
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import numpy as np
import pandas as pd
import joblib, os, logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="StrokeGuard AI API v2",
    description="Dự báo nguy cơ đột quỵ — Nhóm 9 NCKH 2026",
    version="2.0.0",
)
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# ── Load artifacts ─────────────────────────────────────────────────
BASE = os.path.dirname(__file__)

def _load(fname):
    p = os.path.join(BASE, "models", fname)
    if os.path.exists(p):
        return joblib.load(p)
    logger.warning(f"Not found: {fname}")
    return None

lr_model        = _load("logistic_regression.pkl")
dt_model        = _load("decision_tree.pkl")
rf_model        = _load("random_forest.pkl")
scaler          = _load("scaler.pkl")
feature_columns = _load("feature_columns.pkl")
lr_threshold    = _load("lr_threshold.pkl") or 0.3
dt_threshold    = _load("dt_threshold.pkl") or 0.3
rf_threshold    = _load("rf_threshold.pkl") or 0.3
model_metrics   = _load("model_metrics.pkl")

MODELS_READY = all([lr_model, dt_model, rf_model, scaler, feature_columns])
logger.info(f"Models ready: {MODELS_READY}")

# Scaler chỉ transform 7 numeric cols này
NUMERIC_COLS = list(scaler.feature_names_in_) if scaler is not None else [
    "age", "avg_glucose_level", "bmi", "heart_rate", "spo2", "sleep_hours", "stress_score"
]

WORK_TYPES    = ["Govt_job", "Never_worked", "Private", "Self-employed", "children"]
SMOKING_TYPES = ["Unknown", "formerly smoked", "never smoked", "smokes"]

# ── Schema ─────────────────────────────────────────────────────────
class PredictionRequest(BaseModel):
    gender:            int   = Field(..., ge=0, le=1,   description="0=Nam, 1=Nữ")
    age:               int   = Field(..., ge=1, le=120)
    hypertension:      int   = Field(..., ge=0, le=1)
    heart_disease:     int   = Field(..., ge=0, le=1)
    ever_married:      int   = Field(..., ge=0, le=1)
    Residence_type:    int   = Field(..., ge=0, le=1)
    work_type:         str
    smoking_status:    str
    avg_glucose_level: float = Field(..., ge=50, le=300)
    bmi:               float = Field(..., ge=10, le=60)
    heart_rate:        float = Field(..., ge=30, le=220)
    spo2:              float = Field(..., ge=80, le=100)
    sleep_hours:       float = Field(..., ge=0,  le=24)
    stress_score:      float = Field(..., ge=0,  le=100)

    class Config:
        json_schema_extra = {"example": {
            "gender": 1, "age": 55, "hypertension": 1, "heart_disease": 0,
            "ever_married": 1, "Residence_type": 1, "work_type": "Private",
            "smoking_status": "formerly smoked", "avg_glucose_level": 180.5,
            "bmi": 28.3, "heart_rate": 85, "spo2": 96.5,
            "sleep_hours": 5.5, "stress_score": 72.0
        }}

# ── Feature engineering ────────────────────────────────────────────
def build_feature_vector(req: PredictionRequest) -> pd.DataFrame:
    """Tạo feature vector 21 cột khớp đúng schema notebook."""

    # ⚠️ Clip các cột numeric về đúng phạm vi đã quan sát lúc train
    # (scaler.data_max_) để tránh model ngoại suy ra ngoài vùng dữ liệu
    # đã học — đặc biệt quan trọng với age (dataset gốc tối đa ~82 tuổi),
    # nơi tree-based model (RF) có thể cho kết quả không ổn định.
    age_clip = min(req.age, float(scaler.data_max_[NUMERIC_COLS.index("age")]))
    bmi_clip = min(req.bmi, float(scaler.data_max_[NUMERIC_COLS.index("bmi")]))
    glu_clip = min(req.avg_glucose_level, float(scaler.data_max_[NUMERIC_COLS.index("avg_glucose_level")]))

    row = {c: 0 for c in feature_columns}
    row.update({
        "gender":            req.gender,
        "age":               age_clip,
        "hypertension":      req.hypertension,
        "heart_disease":     req.heart_disease,
        "ever_married":      req.ever_married,
        "Residence_type":    req.Residence_type,
        "avg_glucose_level": glu_clip,
        "bmi":               bmi_clip,
        "heart_rate":        req.heart_rate,
        "spo2":              req.spo2,
        "sleep_hours":       req.sleep_hours,
        "stress_score":      req.stress_score,
    })
    for wt in WORK_TYPES:
        row[f"work_type_{wt}"] = 1 if req.work_type == wt else 0
    for ss in SMOKING_TYPES:
        row[f"smoking_status_{ss}"] = 1 if req.smoking_status == ss else 0

    df = pd.DataFrame([row])[feature_columns]

    # ⚠️ Chỉ scale 7 numeric cols, binary/one-hot giữ nguyên
    df[NUMERIC_COLS] = scaler.transform(df[NUMERIC_COLS])
    return df

# ── Helpers ────────────────────────────────────────────────────────
def _risk(prob: float):
    if prob < 0.35: return "THẤP",       "#4CAF50"
    if prob < 0.65: return "TRUNG BÌNH", "#FF9800"
    return "CAO", "#F44336"

def _recommend(prob: float) -> str:
    if prob < 0.35:
        return "Nguy cơ thấp. Duy trì lối sống lành mạnh, tập thể dục đều đặn và kiểm tra sức khỏe định kỳ."
    if prob < 0.65:
        return "Nguy cơ trung bình. Hãy tham khảo ý kiến bác sĩ và theo dõi các chỉ số sức khỏe thường xuyên hơn."
    return "⚠️ Nguy cơ CAO! Hãy đến cơ sở y tế ngay để được tư vấn. Không tự ý điều trị tại nhà."

def _risk_factors(req: PredictionRequest) -> list:
    factors = []
    if req.age >= 60:                   factors.append({"factor":"Tuổi cao (≥60)","value":str(req.age),"impact":"cao"})
    if req.hypertension:                factors.append({"factor":"Cao huyết áp","value":"Có","impact":"cao"})
    if req.heart_disease:               factors.append({"factor":"Bệnh tim mạch","value":"Có","impact":"cao"})
    if req.avg_glucose_level > 150:     factors.append({"factor":"Đường huyết cao","value":f"{req.avg_glucose_level} mg/dL","impact":"trung bình"})
    if req.bmi > 30:                    factors.append({"factor":"Béo phì (BMI>30)","value":str(req.bmi),"impact":"trung bình"})
    if req.spo2 < 95:                   factors.append({"factor":"SpO₂ thấp","value":f"{req.spo2}%","impact":"cao"})
    if req.sleep_hours < 6:             factors.append({"factor":"Ngủ không đủ giấc","value":f"{req.sleep_hours}h","impact":"trung bình"})
    if req.stress_score > 70:           factors.append({"factor":"Stress cao","value":f"{req.stress_score}/100","impact":"trung bình"})
    if req.heart_rate > 100:            factors.append({"factor":"Nhịp tim cao","value":f"{req.heart_rate} bpm","impact":"trung bình"})
    if req.smoking_status == "smokes":  factors.append({"factor":"Đang hút thuốc","value":"Có","impact":"cao"})
    return factors[:5]

def _simulate(req: PredictionRequest):
    age=req.age/100; glu=req.avg_glucose_level/300; bmi=(req.bmi-10)/50
    hr=max(0,(req.heart_rate-70)/100); spo2=max(0,(98-req.spo2)/10)
    slp=max(0,(7-req.sleep_hours)/7); stress=req.stress_score/100
    base=(age*0.28+glu*0.22+bmi*0.12+req.hypertension*0.10+req.heart_disease*0.09
          +hr*0.07+spo2*0.06+slp*0.04+stress*0.02)
    n=np.random.normal(0,0.02,3)
    return (float(np.clip(base*0.90+n[0],0,1)),
            float(np.clip(base*1.05+n[1],0,1)),
            float(np.clip(base*0.98+n[2],0,1)))

# ── Routes ─────────────────────────────────────────────────────────
@app.get("/")
def root():
    return {"app":"StrokeGuard AI","version":"2.0.0",
            "group":"Nhóm 9 NCKH 2026","docs":"/docs"}

@app.get("/health")
def health():
    return {
        "status": "online",
        "models_loaded": {
            "logistic_regression": lr_model is not None,
            "decision_tree":       dt_model is not None,
            "random_forest":       rf_model is not None,
            "scaler":              scaler is not None,
        },
        "simulation_mode":  not MODELS_READY,
        "feature_count":    len(feature_columns) if feature_columns else 0,
        "numeric_cols_scaled": NUMERIC_COLS,
        "thresholds": {
            "lr": float(lr_threshold),
            "dt": float(dt_threshold),
            "rf": float(rf_threshold),
        }
    }

@app.post("/predict")
def predict(req: PredictionRequest):
    try:
        logger.info(f"Predict — age={req.age} HR={req.heart_rate} SpO2={req.spo2}")

        if MODELS_READY:
            df   = build_feature_vector(req)
            lr_p = float(lr_model.predict_proba(df)[0][1])
            dt_p = float(dt_model.predict_proba(df)[0][1])
            rf_p = float(rf_model.predict_proba(df)[0][1])
            lr_pred = int(lr_p >= lr_threshold)
            dt_pred = int(dt_p >= dt_threshold)
            rf_pred = int(rf_p >= rf_threshold)

            # ── DT Display Fix ────────────────────────────────────────
            # Decision Tree (SMOTE-trained) chỉ cho ra 2 giá trị leaf:
            # 0.0 (không có nguy cơ) hoặc ~0.9963 (có nguy cơ cao).
            # Để hiển thị trực quan hơn trên app, ta blend DT raw prob
            # với trung bình LR+RF (70% DT + 30% blend), giữ nguyên
            # giá trị classification (dt_pred) theo threshold gốc.
            dt_display = dt_p * 0.70 + ((lr_p + rf_p) / 2) * 0.30

        else:
            logger.warning("Simulation mode")
            lr_p, dt_p, rf_p = _simulate(req)
            lr_pred = int(lr_p >= 0.3)
            dt_pred = int(dt_p >= 0.3)
            rf_pred = int(rf_p >= 0.3)
            dt_display = dt_p

        # Ensemble dùng trọng số — giảm ảnh hưởng RF vì kém ổn định
        # khi ngoại suy ngoài phạm vi tuổi/bệnh nền hiếm gặp trong dữ liệu train
        ens = lr_p * 0.45 + dt_p * 0.35 + rf_p * 0.20
        level, color = _risk(ens)

        return {
            "timestamp":           datetime.now().isoformat(),
            "logistic_regression": round(lr_p, 4),
            "decision_tree":       round(dt_display, 4),  # blended for display
            "decision_tree_raw":   round(dt_p, 4),         # raw: 0.0 or 0.9963
            "random_forest":       round(rf_p, 4),
            "ensemble":            round(ens, 4),
            "predictions": {
                "logistic_regression": lr_pred,
                "decision_tree":       dt_pred,
                "random_forest":       rf_pred,
                "ensemble":            int(ens >= 0.35),
            },
            "thresholds": {
                "logistic_regression": round(float(lr_threshold), 2),
                "decision_tree":       round(float(dt_threshold), 2),
                "random_forest":       round(float(rf_threshold), 2),
            },
            "risk_level":        level,
            "risk_color":        color,
            "recommendation":    _recommend(ens),
            "top_risk_factors":  _risk_factors(req),
            "fit3_features_used": {
                "heart_rate":   req.heart_rate,
                "spo2":         req.spo2,
                "sleep_hours":  req.sleep_hours,
                "stress_score": req.stress_score,
            },
            "simulation_mode": not MODELS_READY,
        }

    except Exception as e:
        logger.error(f"Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/model-performance")
def model_performance():
    if model_metrics:
        # Reformat metrics dict từ notebook
        m = model_metrics
        names = m.get("Model", {0:"Logistic Regression",1:"Decision Tree",2:"Random Forest"})
        return {
            "source": "trained",
            "models": {
                names[0]: {
                    "accuracy":  m.get("Accuracy",{}).get(0, 0),
                    "recall":    m.get("Recall",{}).get(0, 0),
                    "precision": m.get("Precision",{}).get(0, 0),
                    "f1":        m.get("F1-Score",{}).get(0, 0),
                    "auc_roc":   m.get("AUC-ROC",{}).get(0, 0),
                    "threshold": m.get("Threshold",{}).get(0, 0),
                },
                names[1]: {
                    "accuracy":  m.get("Accuracy",{}).get(1, 0),
                    "recall":    m.get("Recall",{}).get(1, 0),
                    "precision": m.get("Precision",{}).get(1, 0),
                    "f1":        m.get("F1-Score",{}).get(1, 0),
                    "auc_roc":   m.get("AUC-ROC",{}).get(1, 0),
                    "threshold": m.get("Threshold",{}).get(1, 0),
                },
                names[2]: {
                    "accuracy":  m.get("Accuracy",{}).get(2, 0),
                    "recall":    m.get("Recall",{}).get(2, 0),
                    "precision": m.get("Precision",{}).get(2, 0),
                    "f1":        m.get("F1-Score",{}).get(2, 0),
                    "auc_roc":   m.get("AUC-ROC",{}).get(2, 0),
                    "threshold": m.get("Threshold",{}).get(2, 0),
                },
            }
        }
    return {"source": "no metrics file", "models": {}}

@app.get("/features")
def features():
    return {
        "total":         len(feature_columns) if feature_columns else 0,
        "all_columns":   feature_columns or [],
        "numeric_scaled": NUMERIC_COLS,
        "kaggle_cols":   ["gender","age","hypertension","heart_disease",
                          "ever_married","Residence_type","avg_glucose_level","bmi",
                          "work_type_*","smoking_status_*"],
        "fit3_cols":     ["heart_rate","spo2","sleep_hours","stress_score"],
    }