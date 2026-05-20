/**
 * StockStream AI Dashboard — dashboard.js
 * Live ticks via STOMP WebSocket + AI predictions via REST polling.
 */
const TICKERS = ["AAPL","GOOGL","MSFT","TSLA","AMZN","NVDA","META","NFLX"];
const NAMES   = {AAPL:"Apple Inc.",GOOGL:"Alphabet Inc.",MSFT:"Microsoft Corp.",
  TSLA:"Tesla Inc.",AMZN:"Amazon.com",NVDA:"NVIDIA Corp.",META:"Meta Platforms",NFLX:"Netflix Inc."};

let state = { selected:"AAPL", latest:{}, history:{}, predictions:{} };

// ── WebSocket ─────────────────────────────────────────────────────────────────
let stomp = null;
function connect() {
  stomp = Stomp.over(new SockJS("/ws"));
  stomp.debug = null;
  stomp.connect({}, () => {
    stomp.subscribe("/topic/ticks", msg => {
      JSON.parse(msg.body).data?.forEach(r => { state.latest[r.symbol]=r; });
      renderList(); renderChips(); renderVolBars(); renderVolChart();
    });
    stomp.subscribe("/topic/stats", msg => applyStats(JSON.parse(msg.body)));
  }, () => setTimeout(connect, 3000));
}

// ── Clock ─────────────────────────────────────────────────────────────────────
setInterval(()=>{ document.getElementById("clock").textContent =
  new Date().toLocaleTimeString("en-US",{hour12:false}); }, 1000);

// ── Stats ─────────────────────────────────────────────────────────────────────
function applyStats(d) {
  document.getElementById("m-ticks").textContent     = (d.total_ticks||0).toLocaleString();
  document.getElementById("m-analytics").textContent = (d.total_analytics||0).toLocaleString();
  document.getElementById("m-symbols").textContent   = (d.active_symbols||0).toString();
  const ts = d.last_tick && d.last_tick!=="N/A" ? new Date(d.last_tick).toLocaleTimeString() : "—";
  document.getElementById("m-last").textContent = ts;
}
function fetchStats() { fetch("/api/stats").then(r=>r.json()).then(applyStats).catch(()=>{}); }

// ── Predictions ───────────────────────────────────────────────────────────────
function fetchPredictions() {
  fetch("/api/predictions").then(r=>r.json()).then(d=>{
    (d.data||[]).forEach(p=>{ state.predictions[p.symbol]=p; });
    renderList(); renderPredPanel(); renderMainChart();
    const count = (d.data||[]).length;
    document.getElementById("m-preds").textContent = count.toString();
  }).catch(()=>{});
}

// ── Tabs ──────────────────────────────────────────────────────────────────────
function renderTabs() {
  document.getElementById("tabs").innerHTML = TICKERS.map(s=>
    `<div class="tab ${s===state.selected?"active":""}" onclick="pick('${s}')">${s}</div>`).join("");
}
function pick(s) { state.selected=s; renderTabs(); renderList(); renderChips(); renderPredPanel(); loadHistory(s); }

// ── History ───────────────────────────────────────────────────────────────────
function loadHistory(s) {
  fetch(`/api/history/${s}?limit=60`).then(r=>r.json()).then(d=>{
    state.history[s]=d.data||[]; renderMainChart();
  }).catch(()=>{});
}

// ── Ticker list with signals ──────────────────────────────────────────────────
function renderList() {
  document.getElementById("tickerList").innerHTML = TICKERS.map(s=>{
    const r=state.latest[s]||{}, p=state.predictions[s]||{};
    const price=r.price?parseFloat(r.price).toFixed(2):"—";
    const chg=r.changePct?parseFloat(r.changePct):0;
    const sig=p.trade_signal||"";
    const sc=sig==="BUY"?"#22c55e":sig==="SELL"?"#ef4444":"#f59e0b";
    const sb=sig==="BUY"?"rgba(34,197,94,0.12)":sig==="SELL"?"rgba(239,68,68,0.12)":"rgba(245,158,11,0.12)";
    const conf=p.confidence?`${(parseFloat(p.confidence)*100).toFixed(0)}%`:"";
    return `<div class="trow ${s===state.selected?"sel":""}" onclick="pick('${s}')">
      <div>
        <div style="display:flex;align-items:center;gap:5px;">
          <div class="tsym">${s}</div>
          ${sig?`<span style="font-size:9px;padding:1px 6px;border-radius:3px;font-family:var(--mono);
            color:${sc};background:${sb};border:1px solid ${sc}33">${sig}</span>`:""}
          ${conf?`<span style="font-size:9px;color:var(--muted);font-family:var(--mono)">${conf}</span>`:""}
        </div>
        <div class="tname">${NAMES[s]||""}</div>
      </div>
      <div>
        <div class="tprc">$${price}</div>
        <div class="tchg ${chg>=0?"cu":"cd"}">${chg>=0?"+":""}${chg.toFixed(2)}%</div>
      </div>
    </div>`;
  }).join("");
}

// ── Main chart ────────────────────────────────────────────────────────────────
let mainChart=null;
function renderMainChart() {
  const s=state.selected, hist=state.history[s]||[];
  if(!hist.length) return;
  const prices=hist.map(r=>parseFloat(r.price));
  const labels=hist.map(r=>new Date(r.timestamp).toLocaleTimeString("en-US",{hour:"2-digit",minute:"2-digit",hour12:false}));
  const ma5=prices.map((_,i)=>i<4?null:parseFloat((prices.slice(i-4,i+1).reduce((a,b)=>a+b,0)/5).toFixed(4)));
  const ma20=prices.map((_,i)=>i<19?null:parseFloat((prices.slice(i-19,i+1).reduce((a,b)=>a+b,0)/20).toFixed(4)));

  const pred=state.predictions[s];
  const extLabels=pred?[...labels,"Next →"]:labels;
  const extPrices=pred?[...prices,null]:prices;
  const extMa5=pred?[...ma5,null]:ma5;
  const extMa20=pred?[...ma20,null]:ma20;
  const predDs=pred?[{
    label:"Predicted",
    data:[...Array(prices.length-1).fill(null), prices[prices.length-1], parseFloat(pred.predicted_price)],
    borderColor:"#a855f7",borderWidth:2,
    pointRadius:[...Array(prices.length-1).fill(0),0,7],
    pointBackgroundColor:"#a855f7",fill:false,tension:0,borderDash:[5,3]
  }]:[];

  if(mainChart) mainChart.destroy();
  mainChart=new Chart(document.getElementById("mainChart"),{
    type:"line",
    data:{labels:extLabels,datasets:[
      {label:"Price",data:extPrices,borderColor:"#3b82f6",borderWidth:1.5,pointRadius:0,fill:false,tension:0.3},
      {label:"MA5",data:extMa5,borderColor:"#22c55e",borderWidth:1.5,pointRadius:0,fill:false,tension:0.3,borderDash:[4,2]},
      {label:"MA20",data:extMa20,borderColor:"#f59e0b",borderWidth:1.5,pointRadius:0,fill:false,tension:0.3,borderDash:[6,3]},
      ...predDs
    ]},
    options:{responsive:true,maintainAspectRatio:false,
      plugins:{legend:{display:false},tooltip:{mode:"index",intersect:false,
        callbacks:{label:c=>c.raw!=null?`${c.dataset.label}: $${parseFloat(c.raw).toFixed(2)}`:null}}},
      scales:{
        x:{ticks:{font:{family:"IBM Plex Mono",size:9},color:"#6b7280",maxTicksLimit:8,maxRotation:0},
           grid:{color:"rgba(255,255,255,0.04)"},border:{display:false}},
        y:{ticks:{font:{family:"IBM Plex Mono",size:9},color:"#6b7280",callback:v=>"$"+v.toFixed(0)},
           grid:{color:"rgba(255,255,255,0.04)"},border:{display:false}}
      }
    }
  });
}

// ── Chips ─────────────────────────────────────────────────────────────────────
function renderChips() {
  const r=state.latest[state.selected]||{};
  const m5=parseFloat(r.ma5||0),m20=parseFloat(r.ma20||0),vol=parseFloat(r.volatility||0);
  const f=(v,d)=>v?parseFloat(v).toFixed(d):"—";
  document.getElementById("chips").innerHTML=`
    <div class="chip"><div class="chip-lbl">MA5</div><div class="chip-val" style="color:${m5>=m20?"#22c55e":"#ef4444"}">$${f(r.ma5,2)}</div></div>
    <div class="chip"><div class="chip-lbl">MA20</div><div class="chip-val" style="color:#f59e0b">$${f(r.ma20,2)}</div></div>
    <div class="chip"><div class="chip-lbl">Volatility</div><div class="chip-val" style="color:${vol>3?"#ef4444":vol>1.5?"#f59e0b":"#22c55e"}">${f(r.volatility,2)}%</div></div>
    <div class="chip"><div class="chip-lbl">Trend</div><div class="chip-val" style="color:${(r.trend||"")==="Bullish"?"#22c55e":"#ef4444"}">${r.trend||"—"}</div></div>
    <div class="chip"><div class="chip-lbl">Price</div><div class="chip-val" style="color:#e8eaf0">$${f(r.price,2)}</div></div>
    <div class="chip"><div class="chip-lbl">Volume</div><div class="chip-val" style="color:#6b7280">${r.volume?parseInt(r.volume).toLocaleString():"—"}</div></div>`;
}

// ── Prediction panel ──────────────────────────────────────────────────────────
function renderPredPanel() {
  const el=document.getElementById("predPanel");
  const p=state.predictions[state.selected];
  if(!p||!p.predicted_price){
    el.innerHTML=`<div style="font-family:var(--mono);font-size:11px;color:var(--muted)">
      Waiting for prediction engine...</div>`;
    return;
  }
  const sig=p.trade_signal||"HOLD";
  const sc=sig==="BUY"?"#22c55e":sig==="SELL"?"#ef4444":"#f59e0b";
  const sb=sig==="BUY"?"rgba(34,197,94,0.15)":sig==="SELL"?"rgba(239,68,68,0.15)":"rgba(245,158,11,0.15)";
  const chg=parseFloat(p.price_change_pct||0);
  const conf=(parseFloat(p.confidence||0)*100).toFixed(1);
  const confC=parseFloat(conf)>70?"#22c55e":parseFloat(conf)>40?"#f59e0b":"#ef4444";
  el.innerHTML=`
    <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-bottom:12px;">
      <div class="chip">
        <div class="chip-lbl">Predicted Price</div>
        <div class="chip-val" style="color:#a855f7">$${parseFloat(p.predicted_price).toFixed(2)}</div>
      </div>
      <div class="chip">
        <div class="chip-lbl">Expected Change</div>
        <div class="chip-val" style="color:${chg>=0?"#22c55e":"#ef4444"}">${chg>=0?"+":""}${chg.toFixed(2)}%</div>
      </div>
      <div class="chip">
        <div class="chip-lbl">Confidence</div>
        <div class="chip-val" style="color:${confC}">${conf}%</div>
      </div>
    </div>
    <div style="display:flex;align-items:center;justify-content:space-between;">
      <div>
        <div style="font-family:var(--mono);font-size:10px;color:var(--muted);margin-bottom:6px;">AI SIGNAL</div>
        <div style="font-size:32px;font-weight:700;color:${sc};background:${sb};
          padding:8px 28px;border-radius:10px;border:1px solid ${sc}44;letter-spacing:3px;">${sig}</div>
      </div>
      <div style="text-align:right;font-family:var(--mono);font-size:11px;">
        <div style="color:var(--muted)">Model RMSE</div>
        <div style="color:var(--text);font-size:13px;">${parseFloat(p.rmse||0).toFixed(4)}</div>
        <div style="color:var(--muted);margin-top:6px;">Training rows</div>
        <div style="color:var(--text);font-size:13px;">${p.data_points||0}</div>
        <div style="color:var(--muted);margin-top:6px;">Winner model</div>
        <div style="color:#a855f7;font-size:12px;">${p.model_used||"LinearRegression"}</div>
        <div style="color:var(--muted);margin-top:6px;">Winner RMSE</div>
        <div style="color:var(--text);font-size:13px;">${parseFloat(p.rmse||0).toFixed(4)}</div>
      </div>
    </div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:10px;">
      <div class="chip" style="border-color:${(p.model_used||'LinearRegression')==='LinearRegression'?'#a855f7':'rgba(255,255,255,0.08)'}">
        <div class="chip-lbl" style="color:${(p.model_used||'LinearRegression')==='LinearRegression'?'#a855f7':'var(--muted)'}">Linear Reg ${(p.model_used||'LinearRegression')==='LinearRegression'?'★':''}</div>
        <div class="chip-val" style="color:${(p.model_used||'LinearRegression')==='LinearRegression'?'#a855f7':'var(--text)'}">$${p.lr_predicted_price?parseFloat(p.lr_predicted_price).toFixed(2):'—'}</div>
        <div style="font-family:var(--mono);font-size:10px;color:var(--muted);margin-top:3px;">RMSE: ${p.lr_rmse?parseFloat(p.lr_rmse).toFixed(4):'—'}</div>
      </div>
      <div class="chip" style="border-color:${(p.model_used||'LinearRegression')==='RandomForest'?'#3b82f6':'rgba(255,255,255,0.08)'}">
        <div class="chip-lbl" style="color:${(p.model_used||'LinearRegression')==='RandomForest'?'#3b82f6':'var(--muted)'}">Random Forest ${(p.model_used||'LinearRegression')==='RandomForest'?'★':''}</div>
        <div class="chip-val" style="color:${(p.model_used||'LinearRegression')==='RandomForest'?'#3b82f6':'var(--text)'}">$${p.rf_predicted_price?parseFloat(p.rf_predicted_price).toFixed(2):'—'}</div>
        <div style="font-family:var(--mono);font-size:10px;color:var(--muted);margin-top:3px;">RMSE: ${p.rf_rmse?parseFloat(p.rf_rmse).toFixed(4):'—'}</div>
      </div>
    </div>`;
}

// ── Vol bars & chart ──────────────────────────────────────────────────────────
function renderVolBars() {
  const sorted=TICKERS.map(s=>({s,v:parseFloat((state.latest[s]||{}).volatility||0)})).sort((a,b)=>b.v-a.v);
  const mx=sorted[0]?.v||1;
  document.getElementById("vbars").innerHTML=sorted.map(({s,v})=>{
    const c=v>3?"#ef4444":v>1.5?"#f59e0b":"#22c55e";
    return `<div class="vrow"><div class="vsym">${s}</div>
      <div class="vbg"><div class="vfill" style="width:${(v/mx*100).toFixed(1)}%;background:${c}"></div></div>
      <div class="vnum">${v.toFixed(2)}%</div></div>`;
  }).join("");
}
let volChart=null;
function renderVolChart(){
  const data=TICKERS.map(s=>parseFloat((state.latest[s]||{}).volatility||0));
  if(volChart)volChart.destroy();
  volChart=new Chart(document.getElementById("volChart"),{
    type:"bar",data:{labels:TICKERS,datasets:[{data,backgroundColor:data.map(v=>v>3?"#ef4444":v>1.5?"#f59e0b":"#22c55e"),borderRadius:3,borderWidth:0}]},
    options:{responsive:true,maintainAspectRatio:false,plugins:{legend:{display:false}},
      scales:{x:{ticks:{font:{family:"IBM Plex Mono",size:9},color:"#6b7280"},grid:{display:false},border:{display:false}},
        y:{ticks:{font:{family:"IBM Plex Mono",size:9},color:"#6b7280",callback:v=>v+"%"},grid:{color:"rgba(255,255,255,0.04)"},border:{display:false}}}}
  });
}

// ── Log ───────────────────────────────────────────────────────────────────────
const LOGS=[
  ["ok","KafkaProducer","StockTick published → topic stock-feed"],
  ["ok","SparkConsumer","Batch processed — MA5/MA20 computed"],
  ["info","MySQLWriter","writeBatch() committed to stock_ticks"],
  ["pred","PredictionEngine","Linear Regression trained for AAPL"],
  ["pred","PredictionEngine","BUY signal — GOOGL confidence=82%"],
  ["ok","SparkConsumer","Volatility computed for NVDA"],
  ["info","MySQLWriter","stock_latest UPSERT successful"],
  ["pred","PredictionEngine","HOLD signal — TSLA predicted=$362.10"],
  ["warn","KafkaProducer","Yahoo Finance rate limit: 890/1000"],
  ["pred","PredictionEngine","SELL signal — META confidence=71%"],
];
let li=0;
function addLog(){
  const el=document.getElementById("logbox");
  const [t,s,m]=LOGS[li++%LOGS.length];
  const d=document.createElement("div"); d.className="lrow";
  d.innerHTML=`<span class="ltime">${new Date().toLocaleTimeString("en-US",{hour12:false})}</span>`+
    `<span class="lsrc">[${s}]</span><span class="lmsg ${t}">${m}</span>`;
  el.appendChild(d);
  if(el.children.length>60)el.removeChild(el.firstChild);
  el.scrollTop=el.scrollHeight;
}

// ── Init ──────────────────────────────────────────────────────────────────────
function init(){
  renderTabs(); renderList(); renderChips(); renderVolBars();
  fetch("/api/latest").then(r=>r.json()).then(d=>{
    (d.data||[]).forEach(r=>{state.latest[r.symbol]=r;});
    renderList();renderChips();renderVolBars();renderVolChart();
  }).catch(()=>{});
  loadHistory(state.selected);
  fetchStats(); fetchPredictions();
  for(let i=0;i<10;i++) addLog();
  setInterval(addLog,      2200);
  setInterval(fetchStats,  5000);
  setInterval(fetchPredictions, 30000);
  connect();
}
document.addEventListener("DOMContentLoaded", init);
