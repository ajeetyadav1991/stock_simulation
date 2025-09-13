# backend/app/backtest.py
from typing import Dict, Any
import numpy as np

def safe_backtest(df):
    df = df.copy()
    df['vol_mean20'] = df['volume'].rolling(window=20, min_periods=1).mean()
    df['signal'] = 0
    df.loc[(df['MACD'] > df['MACD_signal']) & (df['close'] > df['EMA_10']) & (df['volume'] > df['vol_mean20']), 'signal'] = 1
    df.loc[(df['MACD'] < df['MACD_signal']) & (df['close'] < df['EMA_10']), 'signal'] = -1

    cash = 100000.0
    position = 0.0
    trades = []
    for i in range(len(df)-1):
        sig = df['signal'].iat[i]
        if sig == 1 and position == 0:
            price = df['open'].iat[i+1]
            if np.isnan(price) or price <= 0:
                continue
            position = cash / price
            cash = 0.0
            trades.append(('buy', df.index[i+1], float(price)))
        elif sig == -1 and position > 0:
            price = df['open'].iat[i+1]
            if np.isnan(price) or price <= 0:
                continue
            cash = position * price
            position = 0.0
            trades.append(('sell', df.index[i+1], float(price)))
    final_value = cash + (position * df['close'].iat[-1] if position else 0.0)
    n_trades = len(trades)
    wins = 0
    for j in range(0, len(trades)-1, 2):
        if trades[j][0] == 'buy' and trades[j+1][0] == 'sell':
            entry = trades[j][2]; exitp = trades[j+1][2]
            if exitp > entry:
                wins += 1
    win_rate = (wins / (n_trades/2)) if n_trades >= 2 else 0.0
    return {
        "final_portfolio_value": final_value,
        "n_trades": n_trades,
        "win_rate": win_rate,
        "trades_sample": trades[:10]
    }
