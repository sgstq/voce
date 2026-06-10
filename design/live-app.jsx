// live-app.jsx — runs the live-dictation interaction inside a chat app.

const LD = window.LiveDictation;
const { useState, useRef, useEffect, useCallback } = React;
const { TAKES, BASE_DELAY, nid, tokensToText, Wave, Composer, LiveOverlay } = LD;

const ACCENTS = [
  "oklch(0.55 0.17 285)", "oklch(0.55 0.15 250)", "oklch(0.60 0.13 165)",
  "oklch(0.66 0.14 65)", "oklch(0.62 0.18 28)",
];
const LD_DEFAULTS = /*EDITMODE-BEGIN*/{
  "accent": "oklch(0.55 0.17 285)",
  "dark": false,
  "density": "regular",
  "speed": 1,
  "cleanup": true
}/*EDITMODE-END*/;

function Avatar({ initials, hue, size = 30 }) {
  return (
    <div style={{ width: size, height: size, borderRadius: 9, flex: "0 0 auto",
      display: "flex", alignItems: "center", justifyContent: "center",
      fontWeight: 700, fontSize: size * 0.36, color: "#fff", background: `oklch(0.62 0.13 ${hue})` }}>
      {initials}
    </div>
  );
}

function Message({ m }) {
  if (m.me) {
    return (
      <div style={{ display: "flex", justifyContent: "flex-end", padding: "5px 0",
        animation: "cadRise .25s ease" }}>
        <div style={{ maxWidth: "76%", background: "var(--accent)", color: "var(--accent-ink)",
          padding: "9px 13px", borderRadius: "14px 14px 4px 14px", fontSize: 13.5, lineHeight: 1.5 }}>
          {m.text}
        </div>
      </div>
    );
  }
  return (
    <div style={{ display: "flex", gap: 10, padding: "6px 0" }}>
      <Avatar initials={m.ini} hue={m.hue} />
      <div style={{ minWidth: 0 }}>
        <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
          <span style={{ fontWeight: 700, fontSize: 13, color: "var(--ink)" }}>{m.name}</span>
          <span className="mono" style={{ fontSize: 10.5, color: "var(--ink-faint)" }}>{m.time}</span>
        </div>
        <div style={{ fontSize: 13.5, lineHeight: 1.5, color: "var(--ink-soft)", marginTop: 1 }}>{m.text}</div>
      </div>
    </div>
  );
}

const SEED = [
  { ini: "JR", hue: 28, name: "Jordan Reyes", time: "9:14", text: "shipping the new onboarding today — can someone sanity-check the empty states?" },
  { ini: "DK", hue: 255, name: "Devin Kwon", time: "9:18", text: "looks good to me. the first-run copy is the only thing I'd revisit" },
];

function App() {
  const [accent, setAccent] = useState(ACCENTS[0]);
  const [dark, setDark] = useState(false);
  const [density, setDensity] = useState("regular");
  const [speed, setSpeed] = useState(1);
  const [cleanup, setCleanup] = useState(true);
  const [tokens, setTokens] = useState([]);
  const [holding, setHolding] = useState(false);
  const [committed, setCommitted] = useState("");
  const [messages, setMessages] = useState(SEED);

  const tokensRef = useRef([]);
  const holdingRef = useRef(false);
  const finishedRef = useRef(false);
  const timers = useRef([]);
  const takeRef = useRef(0);
  const jitterRef = useRef(0);
  const speedRef = useRef(speed);
  const cleanupRef = useRef(cleanup);

  // theme + tweak refs
  useEffect(() => {
    const r = document.documentElement;
    r.setAttribute("data-theme", dark ? "dark" : "light");
    r.setAttribute("data-density", density);
    const c = dark ? `color-mix(in oklab, ${accent}, white 12%)` : accent;
    r.style.setProperty("--accent", c);
    r.style.setProperty("--accent-press", `color-mix(in oklab, ${c}, black 16%)`);
    r.style.setProperty("--accent-wash", `color-mix(in oklab, ${c}, transparent 86%)`);
  }, [dark, density, accent]);
  useEffect(() => { speedRef.current = speed; }, [speed]);
  useEffect(() => { cleanupRef.current = cleanup; }, [cleanup]);

  const setToks = (next) => { tokensRef.current = next; setTokens(next); };
  const clearTimers = () => { timers.current.forEach(clearTimeout); timers.current = []; };

  const applyOp = useCallback((op) => {
    const cleanup = cleanupRef.current;
    let toks = tokensRef.current.slice();
    const addNew = (tok) => {
      tok.id = nid(); tok._new = true; tok.state = "in";
      toks.push(tok);
      const tm = setTimeout(() => {
        const a = tokensRef.current.map(x => x.id === tok.id ? { ...x, _new: false } : x);
        setToks(a);
      }, 240);
      timers.current.push(tm);
    };
    if (op.k === "w") addNew({ t: op.t, kind: "word" });
    else if (op.k === "dash") { if (cleanup) addNew({ t: "—", kind: "dash" }); }
    else if (op.k === "f") addNew({ t: op.t, kind: "filler" });
    else if (op.k === "p") { if (cleanup) addNew({ t: op.t, kind: "punct", tight: true }); }
    else if (op.k === "cap") {
      if (!cleanup) return;
      // capitalize the first word of the current sentence (after the last . ? !)
      let startIdx = 0;
      for (let i = toks.length - 1; i >= 0; i--) {
        if (toks[i].kind === "punct" && ".?!".includes(toks[i].t)) { startIdx = i + 1; break; }
      }
      for (let i = startIdx; i < toks.length; i++) {
        if (toks[i].kind === "word") {
          toks[i] = { ...toks[i], cap: true, flash: true };
          const id = toks[i].id;
          const tm = setTimeout(() => {
            setToks(tokensRef.current.map(x => x.id === id ? { ...x, flash: false } : x));
          }, 520); timers.current.push(tm);
          break;
        }
      }
    }
    else if (op.k === "drop") {
      if (!cleanup) return;
      const idx = toks.findIndex(x => x.kind === "filler" && x.state === "in");
      if (idx >= 0) {
        const id = toks[idx].id;
        toks[idx] = { ...toks[idx], state: "out" };
        const tm = setTimeout(() => {
          setToks(tokensRef.current.filter(x => x.id !== id));
        }, 270); timers.current.push(tm);
      }
    }
    setToks(toks);
  }, []);

  const start = useCallback(() => {
    if (holdingRef.current) return;
    clearTimers();
    setToks([]);
    finishedRef.current = false;
    holdingRef.current = true; setHolding(true);
    const ops = TAKES[takeRef.current % TAKES.length]; takeRef.current++;
    let i = 0;
    const step = () => {
      if (!holdingRef.current) return;
      if (i >= ops.length) { finishedRef.current = true; return; }
      const op = ops[i++];
      applyOp(op);
      let d = (BASE_DELAY[op.k] || 170) / speedRef.current;
      if (op.k === "w") d += ((jitterRef.current++) % 3) * 28;
      const tm = setTimeout(step, d);
      timers.current.push(tm);
    };
    step();
  }, [applyOp]);

  const stop = useCallback(() => {
    if (!holdingRef.current) return;
    holdingRef.current = false; setHolding(false);
    clearTimers();
    // finalize: keep visible words, drop leftover fillers, ensure end punctuation
    let toks = tokensRef.current.filter(x => x.state !== "out");
    if (cleanupRef.current) {
      toks = toks.filter(x => x.kind !== "filler");
      const last = toks[toks.length - 1];
      if (toks.length && last && last.kind !== "punct" && last.kind !== "dash") {
        toks.push({ id: nid(), t: ".", kind: "punct", tight: true, state: "in" });
      }
    }
    const text = tokensToText(toks);
    setToks([]);
    if (text.trim()) setCommitted(prev => prev ? prev + " " + text : text);
  }, []);

  // hold via Space anywhere
  useEffect(() => {
    const down = (e) => { if (e.code === "Space" && !e.repeat) { e.preventDefault(); start(); } };
    const up = (e) => { if (e.code === "Space") { e.preventDefault(); stop(); } };
    const pUp = () => stop();
    window.addEventListener("keydown", down);
    window.addEventListener("keyup", up);
    window.addEventListener("pointerup", pUp);
    return () => { window.removeEventListener("keydown", down); window.removeEventListener("keyup", up); window.removeEventListener("pointerup", pUp); };
  }, [start, stop]);

  const send = () => { if (!committed.trim()) return;
    setMessages(m => [...m, { me: true, text: committed.trim() }]); setCommitted(""); };

  return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column",
      alignItems: "center", justifyContent: "center", gap: 18,
      background: dark ? "#15120f" : "oklch(0.94 0.006 80)", padding: 24 }}>

      {/* app window */}
      <div style={{ width: 720, maxWidth: "92vw", height: 600, borderRadius: 18,
        background: "var(--paper)", border: "1px solid var(--line)", boxShadow: "var(--shadow-pop)",
        overflow: "hidden", display: "flex" }}>

        {/* rail */}
        <div style={{ width: 56, flex: "0 0 auto", background: "var(--paper-2)",
          borderRight: "1px solid var(--line-soft)", display: "flex", flexDirection: "column",
          alignItems: "center", paddingTop: 14, gap: 10 }}>
          <div style={{ width: 30, height: 30, borderRadius: 9, background: "var(--accent)",
            position: "relative", overflow: "hidden", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <span style={{ position: "absolute", left: "50%", top: "50%", width: 10, height: 10, borderRadius: "50%",
              border: "2px solid var(--accent-ink)", transform: "translate(-50%,-50%)", animation: "ddRing 2s ease-out infinite" }} />
            <span style={{ position: "absolute", left: "50%", top: "50%", width: 10, height: 10, borderRadius: "50%",
              border: "2px solid var(--accent-ink)", transform: "translate(-50%,-50%)", animation: "ddRing 2s ease-out 1s infinite" }} />
            <span style={{ width: 9, height: 9, borderRadius: "50%", background: "var(--accent-ink)" }} />
          </div>
          <div style={{ height: 6 }} />
          {["#", "#", "@"].map((c, i) => (
            <div key={i} style={{ width: 32, height: 32, borderRadius: 9, display: "flex",
              alignItems: "center", justifyContent: "center", fontSize: 15, fontWeight: 700,
              color: i === 0 ? "var(--ink)" : "var(--ink-faint)",
              background: i === 0 ? "var(--surface)" : "transparent",
              border: i === 0 ? "1px solid var(--line)" : "none" }}>{c}</div>
          ))}
          <div style={{ flex: 1 }} />
          <a href="Cadence — Settings.html" title="Settings" style={{ textDecoration: "none", marginBottom: 12 }}>
            <div style={{ width: 34, height: 34, borderRadius: 9, display: "flex", alignItems: "center",
              justifyContent: "center", color: "var(--ink-faint)", cursor: "pointer" }}>
              <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="3.2"/><path d="M19.4 13a1.6 1.6 0 0 0 .3 1.8 2 2 0 1 1-2.8 2.8 1.6 1.6 0 0 0-2.7 1.1 2 2 0 1 1-4 0A1.6 1.6 0 0 0 7 17.6a1.6 1.6 0 0 0-1.8.3 2 2 0 1 1-2.8-2.8 1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1 2 2 0 1 1 0-4 1.6 1.6 0 0 0 1.5-1 1.6 1.6 0 0 0-.3-1.8 2 2 0 1 1 2.8-2.8 1.6 1.6 0 0 0 1.8.3H7a1.6 1.6 0 0 0 1-1.5 2 2 0 1 1 4 0 1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3 2 2 0 1 1 2.8 2.8 1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1 2 2 0 1 1 0 4 1.6 1.6 0 0 0-1.5 1z"/></svg>
            </div>
          </a>
        </div>

        {/* conversation */}
        <div style={{ flex: 1, display: "flex", flexDirection: "column", minWidth: 0 }}>
          <div style={{ height: 48, flex: "0 0 auto", borderBottom: "1px solid var(--line-soft)",
            display: "flex", alignItems: "center", gap: 8, padding: "0 18px" }}>
            <span style={{ fontWeight: 800, fontSize: 14.5, color: "var(--ink)" }}>
              <span style={{ color: "var(--ink-faint)" }}>#</span> design-team
            </span>
            <span style={{ fontSize: 12, color: "var(--ink-faint)" }}>· 12 members</span>
          </div>

          <div style={{ flex: 1, padding: "12px 18px", overflow: "hidden",
            transition: "filter .3s, opacity .3s",
            filter: holding ? "blur(2px)" : "none", opacity: holding ? 0.5 : 1,
            display: "flex", flexDirection: "column", justifyContent: "flex-end" }}>
            {messages.map((m, i) => <Message key={i} m={m} />)}
          </div>

          {/* composer + live overlay */}
          <div style={{ padding: "0 16px 14px", flex: "0 0 auto", position: "relative" }}>
            <div style={{ position: "relative" }}>
              <Composer value={committed} dictating={holding} onSend={send}
                placeholder="Message #design-team" />
              {holding && <LiveOverlay tokens={tokens} />}
            </div>
            <div style={{ height: 18, marginTop: 8, textAlign: "center", fontSize: 11.5,
              color: "var(--ink-faint)" }}>
              {holding ? "" : <span>Hold <span className="kbd">F5</span> <span style={{ opacity: .7 }}>(<span className="kbd">Space</span> in this demo)</span> to dictate — release to insert</span>}
            </div>
          </div>
        </div>
      </div>

      <div style={{ fontSize: 12, color: dark ? "rgba(255,255,255,.4)" : "var(--ink-faint)" }}>
        Duper Disper — hold, speak, watch it refine, release to insert
      </div>

      <TweaksPanel>
        <TweakSection label="Behavior" />
        <TweakRadio label="Dictation speed" value={String(speed)} options={["0.6", "1", "1.5"]}
          onChange={(v) => setSpeed(parseFloat(v))} />
        <TweakToggle label="Live cleanup" value={cleanup} onChange={setCleanup} />
        <TweakSection label="Theme" />
        <TweakColor label="Accent" value={accent} options={ACCENTS} onChange={setAccent} />
        <TweakToggle label="Dark mode" value={dark} onChange={setDark} />
        <TweakRadio label="Density" value={density} options={["compact", "regular", "comfy"]}
          onChange={setDensity} />
      </TweaksPanel>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
