# mock_backend.py
from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime, timedelta
import random

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

@app.post("/upload-csv")
async def upload_csv(file: UploadFile = File(...)):
    name = file.filename
    return {"rows": 120, "columns": ["open","high","low","close","volume"], "inferred_timeframe": "1h", "filename": name}

@app.post("/compute-indicators")
async def compute_indicators(file: UploadFile = File(...)):
    base = datetime.utcnow() - timedelta(hours=47)
    out = []
    close = 100.0
    for i in range(48):
        ts = base + timedelta(hours=i)
        close += random.uniform(-0.6, 0.8)
        macd = random.uniform(-1.5, 1.5)
        macd_sig = macd - random.uniform(-0.3, 0.3)
        rsi = random.uniform(30, 70)
        signal = 0
        if macd > macd_sig and rsi < 65 and random.random() > 0.8:
            signal = 1
        if macd < macd_sig and rsi > 35 and random.random() > 0.8:
            signal = -1
        out.append({
            "datetime": ts.isoformat(),
            "close": round(close, 2),
            "MACD": round(macd, 3),
            "MACD_signal": round(macd_sig, 3),
            "RSI": round(rsi, 2),
            "signal": signal
        })
    return out

@app.post("/upload-image")
async def upload_image(file: UploadFile = File(...)):
    return {"filename": file.filename, "size": len(await file.read()), "processed": True}

@app.post("/backtest")
async def backtest(file: UploadFile = File(...)):
    return {
        "final_portfolio_value": 123456.78,
        "n_trades": 12,
        "win_rate": 0.5833,
        "trades_sample": [["buy", "2025-01-02T10:00:00Z", 101.2], ["sell", "2025-01-03T12:00:00Z", 105.5]]
    }
