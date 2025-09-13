# backend/app/ingest.py
import pandas as pd
import io
from dateutil import parser as dateparser
from fastapi import HTTPException, UploadFile
import chardet

def ensure_small_file(upload: UploadFile, max_bytes: int):
    upload.file.seek(0, io.SEEK_END)
    size = upload.file.tell()
    upload.file.seek(0)
    if size > max_bytes:
        raise HTTPException(status_code=413, detail=f"File too large: {size} bytes")
    return size

def detect_encoding(b: bytes) -> str:
    res = chardet.detect(b)
    return res.get('encoding') or 'utf-8'

def robust_read_csv_bytes(b: bytes) -> pd.DataFrame:
    enc = detect_encoding(b)
    s = b.decode(enc, errors='replace')
    for sep in [',', ';', '\t', '|']:
        try:
            df = pd.read_csv(io.StringIO(s), sep=sep)
            if df.shape[1] >= 4:
                return df
        except Exception:
            continue
    try:
        return pd.read_csv(io.StringIO(s), engine='python')
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to parse CSV: {e}")

def parse_date_safe(x):
    try:
        return dateparser.parse(str(x))
    except Exception:
        return pd.NaT

def infer_and_normalize(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    cols = [c.lower().strip() for c in df.columns]
    colmap = {c.lower().strip(): c for c in df.columns}
    mapping_candidates = {
        'open': ['open','o','open price'],
        'high': ['high','h','high price'],
        'low':  ['low','l','low price'],
        'close':['close','c','last','close price'],
        'volume':['volume','vol','total traded qty','totaltradedqty','trdqty','qty']
    }
    mapping = {}
    for key, variants in mapping_candidates.items():
        for v in variants:
            if v in colmap:
                mapping[key] = colmap[v]
                break
    if 'volume' not in mapping:
        for c in df.columns:
            if 'traded' in c.lower() and 'qty' in c.lower():
                mapping['volume'] = c
                break
    missing = [k for k in ['open','high','low','close','volume'] if k not in mapping]
    if missing:
        raise HTTPException(status_code=422, detail=f"CSV missing required columns: {missing}. Found: {list(df.columns)}")
    df2 = pd.DataFrame()
    df2['open']  = pd.to_numeric(df[mapping['open']], errors='coerce')
    df2['high']  = pd.to_numeric(df[mapping['high']], errors='coerce')
    df2['low']   = pd.to_numeric(df[mapping['low']], errors='coerce')
    df2['close'] = pd.to_numeric(df[mapping['close']], errors='coerce')
    df2['volume']= pd.to_numeric(df[mapping['volume']], errors='coerce')
    date_col = None
    for c in df.columns:
        if 'date' in c.lower() or 'time' in c.lower() or 'timestamp' in c.lower():
            date_col = c
            break
    if date_col is None:
        if df.index.dtype == object or ('datetime' in (df.index.name or '').lower()):
            df2.index = pd.to_datetime(df.index)
        else:
            raise HTTPException(status_code=422, detail="No date/time column found in CSV.")
    else:
        df2['datetime'] = df[date_col].apply(parse_date_safe)
        if df2['datetime'].isna().any():
            bad = df.loc[df2['datetime'].isna()].iloc[:5].to_dict(orient='records')
            raise HTTPException(status_code=422, detail=f"Some dates could not be parsed. Examples: {bad}")
        df2 = df2.set_index('datetime')
    df2 = df2.dropna(subset=['open','high','low','close'])
    df2 = df2.sort_index()
    df2 = df2[~df2.index.duplicated(keep='last')]
    MIN_BARS = 60
    if len(df2) < MIN_BARS:
        raise HTTPException(status_code=422, detail=f"Not enough data: {len(df2)} rows. Need >= {MIN_BARS}")
    return df2
