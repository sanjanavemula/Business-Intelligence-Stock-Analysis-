<!DOCTYPE html>
<html lang="en" xmlns:th="http://www.thymeleaf.org">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1.0"/>
<title>StockStream AI</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/sockjs-client/1.6.1/sockjs.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/stomp.js/2.3.3/stomp.min.js"></script>
<style>
@import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=Syne:wght@400;600;700&display=swap');
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#0d0f14;--bg1:#13161e;--bg2:#1a1e2a;--bg3:#222736;
  --border:rgba(255,255,255,0.08);--text:#e8eaf0;--muted:#6b7280;
  --accent:#3b82f6;--up:#22c55e;--down:#ef4444;--warn:#f59e0b;--pred:#a855f7;
  --ff:'Syne',sans-serif;--mono:'IBM Plex Mono',monospace;
}
body{background:var(--bg);color:var(--text);font-family:var(--ff);}
header{display:flex;align-items:center;justify-content:space-between;
  padding:14px 24px;border-bottom:1px solid var(--border);
  background:var(--bg1);position:sticky;top:0;z-index:100;}
header h1{font-size:16px;font-weight:700;}
header h1 .blue{color:var(--accent);}
header h1 .purple{color:var(--pred);}
.badge{display:flex;align-items:center;gap:6px;font-family:var(--mono);
  font-size:11px;color:var(--up);background:rgba(34,197,94,0.1);
  border:1px solid rgba(34,197,94,0.2);padding:4px 12px;border-radius:20px;}
.dot{width:6px;height:6px;border-radius:50%;background:var(--up);animation:blink 1.2s infinite;}
@keyframes blink{0%,100%{opacity:1}50%{opacity:.2}}
#clock{font-family:var(--mono);font-size:12px;color:var(--muted);}
.pipeline{display:flex;align-items:center;gap:6px;overflow-x:auto;
  padding:10px 24px;background:var(--bg1);border-bottom:1px solid var(--border);
  font-family:var(--mono);font-size:11px;}
.pnode{display:flex;align-items:center;gap:5px;padding:4px 10px;
  border-radius:4px;border:1px solid rgba(59,130,246,0.3);
  background:rgba(59,130,246,0.08);color:#93c5fd;white-space:nowrap;}
.pnode.ai{border-color:rgba(168,85,247,0.4);background:rgba(168,85,247,0.08);color:#d8b4fe;}
.pdot{width:5px;height:5px;border-radius:50%;background:var(--up);}
.parr{color:var(--muted);}
.wrap{padding:20px 24px;display:grid;gap:16px;}
.metrics{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:12px;}
.mc{background:var(--bg2);border:1px solid var(--border);border-radius:10px;padding:14px 16px;}
.mc-label{font-family:var(--mono);font-size:10px;color:var(--muted);margin-bottom:8px;text-transform:uppercase;letter-spacing:.5px;}
.mc-value{font-size:22px;font-weight:700;line-height:1;}
.mc-sub{font-family:var(--mono);font-size:10px;color:var(--muted);margin-top:6px;}
.cu{color:var(--up)}.cd{color:var(--down)}.cb{color:var(--accent)}.cp{color:var(--pred)}.ct{color:var(--text)}
.row-main{display:grid;grid-template-columns:1fr 300px;gap:14px;}
.row-bottom{display:grid;grid-template-columns:1fr 1fr;gap:14px;}
.card{background:var(--bg1);border:1px solid var(--border);border-radius:12px;padding:16px 18px;}
.ctitle{font-family:var(--mono);font-size:10px;color:var(--muted);text-transform:uppercase;letter-spacing:.6px;margin-bottom:14px;}
.tabs{display:flex;gap:4px;flex-wrap:wrap;margin-bottom:12px;}
.tab{font-family:var(--mono);font-size:11px;padding:4px 10px;border-radius:4px;
  border:1px solid var(--border);background:var(--bg2);color:var(--muted);cursor:pointer;transition:all .15s;}
.tab.active{background:var(--accent);color:#fff;border-color:var(--accent);}
.tab:hover:not(.active){border-color:rgba(59,130,246,0.4);color:var(--text);}
#mainWrap{position:relative;width:100%;height:200px;}
#volWrap{position:relative;width:100%;height:120px;margin-top:10px;}
.legend{display:flex;gap:16px;margin-bottom:8px;font-size:11px;font-family:var(--mono);color:var(--muted);}
.leg-item{display:flex;align-items:center;gap:4px;}
.leg-line{width:14px;height:2px;display:inline-block;}
.chips{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:12px;}
.chip{background:var(--bg2);border-radius:8px;padding:10px 12px;border:1px solid var(--border);}
.chip-lbl{font-family:var(--mono);font-size:9px;color:var(--muted);margin-bottom:4px;text-transform:uppercase;}
.chip-val{font-size:15px;font-weight:600;}
.trow{display:flex;align-items:center;justify-content:space-between;
  padding:9px 10px;border-radius:8px;border:1px solid transparent;
  background:var(--bg2);cursor:pointer;transition:all .1s;margin-bottom:5px;}
.trow:hover{border-color:var(--border);background:var(--bg3);}
.trow.sel{border-color:rgba(59,130,246,0.5);background:rgba(59,130,246,0.06);}
.tsym{font-family:var(--mono);font-size:13px;font-weight:600;}
.tname{font-size:10px;color:var(--muted);margin-top:1px;}
.tprc{font-family:var(--mono);font-size:13px;font-weight:500;text-align:right;}
.tchg{font-family:var(--mono);font-size:10px;text-align:right;}
.pred-panel{margin-top:12px;padding:12px;background:rgba(168,85,247,0.04);
  border:1px solid rgba(168,85,247,0.2);border-radius:10px;}
.pred-title{font-family:var(--mono);font-size:10px;color:var(--pred);
  text-transform:uppercase;letter-spacing:.6px;margin-bottom:10px;}
.vbars{display:flex;flex-direction:column;gap:7px;}
.vrow{display:grid;grid-template-columns:44px 1fr 48px;align-items:center;gap:8px;}
.vsym{font-family:var(--mono);font-size:11px;color:var(--muted);}
.vbg{background:var(--bg3);border-radius:2px;height:6px;overflow:hidden;}
.vfill{height:100%;border-radius:2px;transition:width .8s ease;}
.vnum{font-family:var(--mono);font-size:10px;color:var(--muted);text-align:right;}
.logbox{height:180px;overflow-y:auto;font-family:var(--mono);font-size:10px;color:var(--muted);line-height:1.8;}
.logbox::-webkit-scrollbar{width:3px;}
.logbox::-webkit-scrollbar-thumb{background:var(--bg3);border-radius:2px;}
.lrow{display:flex;gap:8px;}
.ltime{color:var(--accent);min-width:64px;}
.lsrc{min-width:80px;color:var(--warn);}
.lmsg.ok{color:var(--up);}.lmsg.warn{color:var(--warn);}.lmsg.info{color:var(--muted);}.lmsg.pred{color:var(--pred);}
footer{display:flex;align-items:center;gap:20px;padding:8px 24px;
  border-top:1px solid var(--border);background:var(--bg1);
  font-family:var(--mono);font-size:10px;color:var(--muted);}
.sdot{width:5px;height:5px;border-radius:50%;background:var(--up);display:inline-block;margin-right:4px;}
@media(max-width:900px){.row-main,.row-bottom{grid-template-columns:1fr}.metrics{grid-template-columns:repeat(2,1fr)}}
</style>
</head>
<body>
<header>
  <h1>Stock<span class="blue">Stream</span> <span class="purple">AI</span></h1>
  <div style="display:flex;align-items:center;gap:14px;">
    <div class="badge"><div class="dot"></div>LIVE + AI</div>
    <div id="clock"></div>
  </div>
</header>
<div class="pipeline">
  <div class="pnode"><div class="pdot"></div>Yahoo Finance</div><span class="parr">→</span>
  <div class="pnode"><div class="pdot"></div>Java Kafka Producer</div><span class="parr">→</span>
  <div class="pnode"><div class="pdot"></div>Kafka: stock-feed</div><span class="parr">→</span>
  <div class="pnode"><div class="pdot"></div>Spark Streaming</div><span class="parr">→</span>
  <div class="pnode"><div class="pdot"></div>MySQL</div><span class="parr">→</span>
  <div class="pnode ai"><div class="pdot"></div>MLlib Prediction</div><span class="parr">→</span>
  <div class="pnode ai"><div class="pdot"></div>BUY/HOLD/SELL Signal</div><span class="parr">→</span>
  <div class="pnode"><div class="pdot"></div>Spring Boot Dashboard</div>
</div>
<div class="wrap">
  <div class="metrics">
    <div class="mc"><div class="mc-label">Total Ticks</div><div class="mc-value cu" id="m-ticks">—</div><div class="mc-sub">Kafka messages</div></div>
    <div class="mc"><div class="mc-label">Analytics</div><div class="mc-value cb" id="m-analytics">—</div><div class="mc-sub">Spark computations</div></div>
    <div class="mc"><div class="mc-label">Predictions</div><div class="mc-value cp" id="m-preds">—</div><div class="mc-sub">MLlib models run</div></div>
    <div class="mc"><div class="mc-label">Active Symbols</div><div class="mc-value ct" id="m-symbols">—</div><div class="mc-sub">tickers tracked</div></div>
    <div class="mc"><div class="mc-label">Last Tick</div><div class="mc-value ct" id="m-last" style="font-size:14px">—</div><div class="mc-sub">most recent</div></div>
  </div>
  <div class="row-main">
    <div class="card">
      <div class="ctitle">Price + Moving Averages + AI Prediction</div>
      <div class="tabs" id="tabs"></div>
      <div class="legend">
        <div class="leg-item"><span class="leg-line" style="background:#3b82f6"></span>Price</div>
        <div class="leg-item"><span class="leg-line" style="background:#22c55e"></span>MA5</div>
        <div class="leg-item"><span class="leg-line" style="background:#f59e0b"></span>MA20</div>
        <div class="leg-item"><span class="leg-line" style="background:#a855f7"></span>Predicted</div>
      </div>
      <div id="mainWrap"><canvas id="mainChart"></canvas></div>
      <div class="chips" id="chips"></div>
      <div class="pred-panel">
        <div class="pred-title">AI Prediction (Spark MLlib Linear Regression)</div>
        <div id="predPanel"></div>
      </div>
    </div>
    <div class="card">
      <div class="ctitle">Live Ticker Feed + AI Signals</div>
      <div id="tickerList"></div>
    </div>
  </div>
  <div class="row-bottom">
    <div class="card">
      <div class="ctitle">Volatility Analysis</div>
      <div class="vbars" id="vbars"></div>
      <div id="volWrap"><canvas id="volChart"></canvas></div>
    </div>
    <div class="card">
      <div class="ctitle">Pipeline Event Log</div>
      <div class="logbox" id="logbox"></div>
    </div>
  </div>
</div>
<footer>
  <span><span class="sdot"></span>Kafka</span>
  <span><span class="sdot"></span>Spark</span>
  <span><span class="sdot"></span>MySQL</span>
  <span><span class="sdot" style="background:var(--pred)"></span>MLlib AI</span>
  <span><span class="sdot"></span>Spring Boot</span>
  <span style="margin-left:auto">StockStream AI v1.0 | Yahoo Finance → Kafka → Spark → MLlib → MySQL → Dashboard</span>
</footer>
<script th:src="@{/dashboard.js}"></script>
</body>
</html>
