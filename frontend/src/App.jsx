import React, { useState } from "react";
import {
  ResponsiveContainer,
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid
} from "recharts";

export default function App() {
  const [csvFile, setCsvFile] = useState(null);
  const [imgFile, setImgFile] = useState(null);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [backtest, setBacktest] = useState(null);
  const [explanation, setExplanation] = useState(null);

  const API_BASE = process.env.REACT_APP_API_BASE || "http://localhost:8000";

  function resetState() {
    setData(null);
    setBacktest(null);
    setExplanation(null);
    setError(null);
  }

  async function postFile(endpoint, file) {
    const fd = new FormData();
    fd.append("file", file, file.name);
    const res = await fetch(`${API_BASE}${endpoint}`, { method: "POST", body: fd });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.detail || `HTTP error ${res.status}`);
    }
    return res.json();
  }

  const handleCsvSubmit = async (ev) => {
    ev.preventDefault();
    if (!csvFile) return setError("Select a CSV file first.");
    setLoading(true);
    setError(null);
    try {
      resetState();
      await postFile("/upload-csv", csvFile);
      const indicators = await postFile("/compute-indicators", csvFile);
      const parsed = indicators.map((r) => ({
        ...r,
        datetime: new Date(r.datetime).toISOString(),
        signal_long_close: r.signal === 1 ? r.close : null,
        signal_short_close: r.signal === -1 ? r.close : null,
      }));
      setData(parsed);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  };

  const handleImgSubmit = async (ev) => {
    ev.preventDefault();
    if (!imgFile) return setError("Select an image file first.");
    setLoading(true);
    setError(null);
    try {
      const resp = await postFile("/upload-image", imgFile);
      setExplanation({ image: resp });
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  };

  const handleBacktest = async (ev) => {
    ev.preventDefault();
    if (!csvFile) return setError("Upload CSV first for backtest.");
    setLoading(true);
    setError(null);
    try {
      const res = await postFile("/backtest", csvFile);
      setBacktest(res);
      if (res.explanations) setExplanation(res.explanations);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{padding:20, fontFamily:'Inter, sans-serif', background:'#f1f5f9', minHeight:'100vh'}}>
      <div style={{maxWidth:1100, margin:'auto', background:'#fff', borderRadius:12, padding:20}}>
        <h1 style={{fontSize:22, marginBottom:12}}>Signal Integrity Simulation Platform — MVP</h1>
        <div style={{display:'flex', gap:16, marginBottom:16}}>
          <form onSubmit={handleCsvSubmit} style={{flex:1}}>
            <label>Upload historical CSV (BSE or NSE)</label>
            <input type="file" accept=".csv,text/csv,application/vnd.ms-excel" onChange={(e)=>setCsvFile(e.target.files?.[0]??null)} />
            <div style={{marginTop:8}}>
              <button type="submit" disabled={loading} style={{marginRight:8}}>Upload & Compute Indicators</button>
              <button type="button" onClick={handleBacktest} disabled={loading}>Run Backtest</button>
            </div>
          </form>
          <form onSubmit={handleImgSubmit} style={{flex:1}}>
            <label>Upload chart image (PNG)</label>
            <input type="file" accept="image/png" onChange={(e)=>setImgFile(e.target.files?.[0]??null)} />
            <div style={{marginTop:8}}>
              <button type="submit" disabled={loading}>Annotate Image</button>
            </div>
          </form>
        </div>

        {error && <div style={{padding:8, background:'#fee2e2', color:'#b91c1c'}}>{error}</div>}

        <div style={{marginTop:12}}>
          <h3>Price Chart (Close)</h3>
          <div style={{height:220, background:'#fff', padding:12, borderRadius:8}}>
            {data ? (
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={data} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="datetime" tickFormatter={(s)=>new Date(s).toLocaleString()} />
                  <YAxis domain={["dataMin","dataMax"]}/>
                  <Tooltip labelFormatter={(label)=>new Date(label).toLocaleString()} />
                  <Line type="monotone" dataKey="close" stroke="#1f8ef1" dot={false}/>
                  <Line type="monotone" dataKey="signal_long_close" stroke="#16a34a" dot={{r:4}} isAnimationActive={false}/>
                </LineChart>
              </ResponsiveContainer>
            ) : <div style={{height:'100%', display:'flex', alignItems:'center', justifyContent:'center', color:'#64748b'}}>Upload CSV and compute indicators to preview chart</div>}
          </div>
        </div>

        <div style={{display:'flex', gap:16, marginTop:12}}>
          <div style={{flex:1, background:'#fff', padding:12, borderRadius:8}}>
            <h4>MACD (stub)</h4>
            {data ? (
              <div style={{height:140}}>
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart data={data}>
                    <XAxis dataKey="datetime" hide />
                    <YAxis hide />
                    <Tooltip />
                    <Line type="monotone" dataKey="MACD" stroke="#ef4444" dot={false}/>
                    <Line type="monotone" dataKey="MACD_signal" stroke="#6366f1" dot={false}/>
                  </LineChart>
                </ResponsiveContainer>
              </div>
            ) : <div style={{color:'#64748b'}}>MACD will appear after computing indicators</div>}
          </div>

          <div style={{flex:1, background:'#fff', padding:12, borderRadius:8}}>
            <h4>RSI (stub)</h4>
            {data ? (
              <div style={{height:140}}>
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart data={data}>
                    <XAxis dataKey="datetime" hide />
                    <YAxis domain={[0,100]} />
                    <Tooltip />
                    <Line type="monotone" dataKey="RSI" stroke="#a855f7" dot={false}/>
                  </LineChart>
                </ResponsiveContainer>
              </div>
            ) : <div style={{color:'#64748b'}}>RSI will appear after computing indicators</div>}
          </div>
        </div>

        <div style={{marginTop:12, background:'#fff', padding:12, borderRadius:8}}>
          <h4>Backtest Summary</h4>
          {backtest ? (
            <div style={{display:'flex', gap:16}}>
              <div><div style={{fontSize:12,color:'#94a3b8'}}>Final Value</div><div style={{fontWeight:600}}>{Number(backtest.final_portfolio_value).toFixed(2)}</div></div>
              <div><div style={{fontSize:12,color:'#94a3b8'}}>Trades</div><div style={{fontWeight:600}}>{backtest.n_trades}</div></div>
              <div><div style={{fontSize:12,color:'#94a3b8'}}>Win Rate</div><div style={{fontWeight:600}}>{(backtest.win_rate*100).toFixed(1)}%</div></div>
            </div>
          ) : <div style={{color:'#64748b'}}>Run a backtest to see results</div>}
        </div>

        <div style={{marginTop:12, background:'#fff', padding:12, borderRadius:8}}>
          <h4>XAI Explanation (per-signal)</h4>
          {explanation ? <pre style={{fontSize:12, whiteSpace:'pre-wrap'}}>{JSON.stringify(explanation, null,2)}</pre> : <div style={{color:'#64748b'}}>Run compute or backtest to view explanations</div>}
        </div>
      </div>
    </div>
  );
}
