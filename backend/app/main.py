# backend/app/main.py
from fastapi import FastAPI, UploadFile, File, BackgroundTasks, HTTPException, Request
from fastapi.responses import JSONResponse
from starlette.middleware.cors import CORSMiddleware
import logging
from .ingest import robust_read_csv_bytes, infer_and_normalize, ensure_small_file
from .indicators import compute_all_indicators
from .backtest import safe_backtest
from .schemas import UploadSummary

logger = logging.getLogger("sisp")
logging.basicConfig(level=logging.INFO)

app = FastAPI(title="Signal Integrity Simulation Platform API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

MAX_UPLOAD_BYTES = 20 * 1024 * 1024  # 20MB

@app.exception_handler(Exception)
async def all_exception_handler(request: Request, exc: Exception):
    logger.exception("Unhandled error: %s", exc)
    return JSONResponse(status_code=500, content={"error": "Internal server error"})

@app.post("/upload-csv", response_model=UploadSummary)
async def upload_csv(file: UploadFile = File(...)):
    size = ensure_small_file(file, MAX_UPLOAD_BYTES)
    contents = await file.read()
    try:
        df_raw = robust_read_csv_bytes(contents)
        df = infer_and_normalize(df_raw)
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("CSV parsing failed")
        raise HTTPException(status_code=400, detail=str(e))
    indicators_df = compute_all_indicators(df)
    return {"rows": len(indicators_df), "columns": list(indicators_df.columns), "inferred_timeframe": "unknown"}

@app.post("/compute-indicators")
async def compute_indicators(file: UploadFile = File(...)):
    contents = await file.read()
    df = robust_read_csv_bytes(contents)
    df = infer_and_normalize(df)
    out = compute_all_indicators(df)
    out = out.reset_index().rename(columns={"index":"datetime"})
    out['datetime'] = out['datetime'].astype(str)
    return out.to_dict(orient="records")

@app.post("/backtest")
async def backtest_endpoint(file: UploadFile = File(...)):
    contents = await file.read()
    df_raw = robust_read_csv_bytes(contents)
    df = infer_and_normalize(df_raw)
    df = compute_all_indicators(df)
    result = safe_backtest(df)
    return result
