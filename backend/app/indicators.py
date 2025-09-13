# backend/app/indicators.py
import pandas as pd
import numpy as np

def ema(series: pd.Series, span: int) -> pd.Series:
    return series.ewm(span=span, adjust=False).mean()

def macd(df: pd.DataFrame, fast=12, slow=26, signal=9):
    close = df['close'].astype(float)
    ema_fast = ema(close, fast)
    ema_slow = ema(close, slow)
    macd_line = ema_fast - ema_slow
    macd_signal = ema(macd_line, signal)
    macd_hist = macd_line - macd_signal
    return macd_line, macd_signal, macd_hist

def compute_rsi(close: pd.Series, length: int = 14) -> pd.Series:
    if len(close) < length + 1:
        return pd.Series([50.0] * len(close), index=close.index)
    delta = close.diff()
    up = delta.clip(lower=0.0).fillna(0.0)
    down = -1.0 * delta.clip(upper=0.0).fillna(0.0)
    roll_up = up.ewm(alpha=1/length, adjust=False).mean()
    roll_down = down.ewm(alpha=1/length, adjust=False).mean()
    rs = roll_up / roll_down.replace(to_replace=0, value=np.nan)
    rsi = 100 - (100 / (1 + rs))
    rsi = rsi.fillna(50.0)
    return rsi

def compute_vwap(df: pd.DataFrame) -> pd.Series:
    typical = (df['high'] + df['low'] + df['close']) / 3
    tpv = typical * df['volume']
    vwap = tpv.cumsum() / df['volume'].cumsum().replace(0, np.nan)
    return vwap.fillna(method='ffill').fillna(method='bfill')

def compute_all_indicators(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df['RSI'] = compute_rsi(df['close'], 14)
    macd_line, macd_signal, macd_hist = macd(df)
    df['MACD'] = macd_line
    df['MACD_signal'] = macd_signal
    df['MACD_hist'] = macd_hist
    df['EMA_10'] = ema(df['close'], 10)
    df['EMA_100'] = ema(df['close'], 100)
    df['VWAP'] = compute_vwap(df)
    df['OBV'] = ((df['close'].diff().fillna(0) > 0).astype(int) * 2 - 1) * df['volume']
    df['OBV'] = df['OBV'].cumsum()
    df['TR'] = pd.concat([
        df['high'] - df['low'],
        (df['high'] - df['close'].shift()).abs(),
        (df['low'] - df['close'].shift()).abs()
    ], axis=1).max(axis=1)
    df['ATR_14'] = df['TR'].rolling(window=14, min_periods=1).mean()
    df = df.replace([np.inf, -np.inf], np.nan)
    return df
