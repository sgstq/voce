// settings-app.jsx — Duper Disper Settings. Grouped-card design, real settings.
// New logo mark: an I-beam text caret (insertion point) — not a waveform.

const { useState, useEffect } = React;

const ACCENTS = [
  "oklch(0.55 0.17 285)", "oklch(0.55 0.15 250)", "oklch(0.60 0.13 165)",
  "oklch(0.66 0.14 65)", "oklch(0.62 0.18 28)",
];

// ── Logo: "Listen" — a dot with concentric pulse rings ───────────────────
function Mark({ size = 30, r }) {
  const dot = Math.round(size * 0.30), ring = Math.round(size * 0.34);
  const ringStyle = {
    position: "absolute", left: "50%", top: "50%", width: ring, height: ring,
    borderRadius: "50%", border: "2px solid var(--accent-ink)", transform: "translate(-50%,-50%)",
  };
  return (
    <div style={{ width: size, height: size, borderRadius: r ?? size * 0.3, background: "var(--accent)",
      position: "relative", overflow: "hidden", display: "flex", alignItems: "center",
      justifyContent: "center", flex: "0 0 auto" }}>
      <span style={{ ...ringStyle, animation: "ddRing 2s ease-out infinite" }} />
      <span style={{ ...ringStyle, animation: "ddRing 2s ease-out 1s infinite" }} />
      <span style={{ width: dot, height: dot, borderRadius: "50%", background: "var(--accent-ink)" }} />
    </div>
  );
}

function Toggle({ on, onClick }) {
  return (
    <div onClick={onClick} style={{ width: 40, height: 24, borderRadius: 999, flex: "0 0 auto",
      cursor: "pointer", background: on ? "var(--accent)" : "var(--line)", position: "relative",
      transition: "background .2s" }}>
      <div style={{ position: "absolute", top: 3, left: on ? 19 : 3, width: 18, height: 18,
        borderRadius: "50%", background: "#fff", boxShadow: "0 1px 3px rgba(0,0,0,.3)", transition: "left .2s" }} />
    </div>
  );
}

function Seg({ options, value, onChange }) {
  return (
    <div style={{ display: "inline-flex", padding: 3, borderRadius: 10, background: "var(--surface-2)",
      border: "1px solid var(--line)", gap: 2 }}>
      {options.map(o => (
        <span key={o} onClick={() => onChange && onChange(o)} style={{ padding: "5px 12px", borderRadius: 7,
          fontSize: 12.5, fontWeight: 600, cursor: "pointer",
          color: o === value ? "var(--accent-ink)" : "var(--ink-soft)",
          background: o === value ? "var(--accent)" : "transparent" }}>{o}</span>
      ))}
    </div>
  );
}

// read-only value chip (api key / url / model)
function Field({ children, mask, w = 230, mono = true }) {
  return (
    <span className={mono ? "mono" : ""} style={{ display: "inline-flex", alignItems: "center", height: 32,
      padding: "0 12px", borderRadius: 8, background: "var(--surface-2)", border: "1px solid var(--line)",
      color: "var(--ink-soft)", fontSize: 12.5, maxWidth: w, overflow: "hidden", whiteSpace: "nowrap",
      letterSpacing: mask ? 2 : 0 }}>{children}</span>
  );
}

function Status({ ok, label }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 7, height: 28, padding: "0 11px",
      borderRadius: 999, fontSize: 12, fontWeight: 600,
      background: ok ? "oklch(0.6 0.13 155 / .14)" : "var(--live-wash)",
      color: ok ? "oklch(0.52 0.13 155)" : "var(--live)" }}>
      <span style={{ width: 7, height: 7, borderRadius: "50%", background: "currentColor" }} />{label}
    </span>
  );
}
function Btn({ children, onClick }) {
  return <span className="pill" onClick={onClick} style={{ height: 30 }}>{children}</span>;
}

function SRow({ title, desc, children, last }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 16, padding: "14px 0",
      borderBottom: last ? "none" : "1px solid var(--line-soft)" }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 13.5, fontWeight: 600, color: "var(--ink)" }}>{title}</div>
        {desc && <div style={{ fontSize: 12, color: "var(--ink-faint)", marginTop: 2, lineHeight: 1.4 }}>{desc}</div>}
      </div>
      <div style={{ flex: "0 0 auto" }}>{children}</div>
    </div>
  );
}

function Group({ label, action, children }) {
  return (
    <div style={{ marginBottom: 22 }}>
      <div style={{ display: "flex", alignItems: "baseline", marginBottom: 6 }}>
        <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: 0.7, textTransform: "uppercase",
          color: "var(--ink-faint)" }}>{label}</span>
        {action && <span style={{ flex: 1 }} />}
        {action}
      </div>
      <div style={{ background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 14,
        boxShadow: "var(--shadow-1)", padding: "2px 16px" }}>{children}</div>
    </div>
  );
}

const RailIcon = ({ children, on, href, title }) => {
  const inner = (
    <div title={title} style={{ width: 34, height: 34, borderRadius: 9, display: "flex",
      alignItems: "center", justifyContent: "center",
      color: on ? "var(--accent)" : "var(--ink-faint)",
      background: on ? "var(--accent-wash)" : "transparent", cursor: "pointer" }}>{children}</div>
  );
  return href ? <a href={href} style={{ textDecoration: "none" }}>{inner}</a> : inner;
};

function App() {
  const [dark, setDark] = useState(false);
  const [accent, setAccent] = useState(ACCENTS[0]);
  const [density, setDensity] = useState("regular");
  // real settings
  const [insertion, setInsertion] = useState("Clipboard");
  const [rtDelay, setRtDelay] = useState("Low");
  const [refine, setRefine] = useState(true);
  const [sound, setSound] = useState(true);
  const [overlay, setOverlay] = useState(true);
  const [autostart, setAutostart] = useState(false);
  const [devmode, setDevmode] = useState(false);
  const [promptOpen, setPromptOpen] = useState(false);

  useEffect(() => {
    const r = document.documentElement;
    r.setAttribute("data-theme", dark ? "dark" : "light");
    r.setAttribute("data-density", density);
    const c = dark ? `color-mix(in oklab, ${accent}, white 12%)` : accent;
    r.style.setProperty("--accent", c);
    r.style.setProperty("--accent-press", `color-mix(in oklab, ${c}, black 16%)`);
    r.style.setProperty("--accent-wash", `color-mix(in oklab, ${c}, transparent 86%)`);
  }, [dark, density, accent]);

  return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column", alignItems: "center",
      justifyContent: "center", gap: 18, background: dark ? "#15120f" : "oklch(0.94 0.006 80)", padding: 24 }}>

      <div style={{ width: 780, maxWidth: "94vw", height: 640, borderRadius: 18, background: "var(--paper)",
        border: "1px solid var(--line)", boxShadow: "var(--shadow-pop)", overflow: "hidden", display: "flex" }}>

        {/* rail */}
        <div style={{ width: 56, flex: "0 0 auto", background: "var(--paper-2)",
          borderRight: "1px solid var(--line-soft)", display: "flex", flexDirection: "column",
          alignItems: "center", paddingTop: 14, gap: 8 }}>
          <div style={{ marginBottom: 6 }}><Mark size={30} /></div>
          <RailIcon href="Cadence — Live Dictation.html" title="Conversations">
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 11.5a8.4 8.4 0 0 1-12 7.6L3 21l1.9-5.7A8.4 8.4 0 1 1 21 11.5z"/></svg>
          </RailIcon>
          <div style={{ flex: 1 }} />
          <RailIcon on title="Settings">
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="3.2"/><path d="M19.4 13a1.6 1.6 0 0 0 .3 1.8 2 2 0 1 1-2.8 2.8 1.6 1.6 0 0 0-2.7 1.1 2 2 0 1 1-4 0A1.6 1.6 0 0 0 7 17.6a1.6 1.6 0 0 0-1.8.3 2 2 0 1 1-2.8-2.8 1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1 2 2 0 1 1 0-4 1.6 1.6 0 0 0 1.5-1 1.6 1.6 0 0 0-.3-1.8 2 2 0 1 1 2.8-2.8 1.6 1.6 0 0 0 1.8.3H7a1.6 1.6 0 0 0 1-1.5 2 2 0 1 1 4 0 1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3 2 2 0 1 1 2.8 2.8 1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1 2 2 0 1 1 0 4 1.6 1.6 0 0 0-1.5 1z"/></svg>
          </RailIcon>
          <div style={{ height: 8 }} />
        </div>

        {/* content */}
        <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column" }}>
          <div style={{ padding: "18px 28px 14px", flex: "0 0 auto", borderBottom: "1px solid var(--line-soft)",
            display: "flex", alignItems: "center", gap: 12 }}>
            <Mark size={34} />
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 17, fontWeight: 800, letterSpacing: -0.5, color: "var(--ink)" }}>Duper Disper</div>
              <div style={{ fontSize: 12.5, color: "var(--ink-faint)", marginTop: 1 }}>Voice dictation into any focused text field</div>
            </div>
            <Btn>Show config file</Btn>
            <span className="pill is-accent" style={{ height: 32 }}>Save</span>
          </div>

          <div style={{ flex: 1, overflow: "auto", padding: "20px 28px" }}>
            <div style={{ maxWidth: 560 }}>

              <Group label="Appearance">
                <SRow title="Theme" desc="Match the app to your workspace, light or dark.">
                  <Seg options={["Light", "Dark"]} value={dark ? "Dark" : "Light"}
                    onChange={(v) => setDark(v === "Dark")} />
                </SRow>
                <SRow title="Accent color" desc="Used for the live overlay and highlights." last>
                  <div style={{ display: "flex", gap: 8 }}>
                    {ACCENTS.map(c => (
                      <button key={c} onClick={() => setAccent(c)} title="accent"
                        style={{ width: 22, height: 22, borderRadius: "50%", cursor: "pointer", background: c,
                          border: accent === c ? "2px solid var(--ink)" : "2px solid transparent",
                          boxShadow: "0 0 0 1px var(--line)", outline: "none", padding: 0 }} />
                    ))}
                  </div>
                </SRow>
              </Group>

              <Group label="Activation">
                <SRow title="Hotkey" desc="Hold to record, release to transcribe & insert.">
                  <span style={{ display: "inline-flex", gap: 6, alignItems: "center" }}>
                    <span className="kbd" style={{ fontSize: 12.5, padding: "5px 11px" }}>F5</span>
                    <Btn>Record</Btn><Btn>Reset</Btn>
                  </span>
                </SRow>
                <SRow title="Insertion method" desc="Paste via clipboard, or simulate keystrokes.">
                  <Seg options={["Clipboard", "Type"]} value={insertion} onChange={setInsertion} />
                </SRow>
                <SRow title="Language" desc="Spoken language hint for transcription." last>
                  <Field mono={false} w={150}>English · en ▾</Field>
                </SRow>
              </Group>

              <Group label="Transcription · Speech-to-Text">
                <SRow title="Backend" desc="Where audio is turned into text.">
                  <Field mono={false} w={180}>OpenAI Realtime ▾</Field>
                </SRow>
                <SRow title="API key">
                  <Field mask>•••••••••••••••••••</Field>
                </SRow>
                <SRow title="Model">
                  <Field>gpt-realtime-whisper</Field>
                </SRow>
                <SRow title="Realtime delay" desc="Lower is snappier; higher is steadier.">
                  <Seg options={["Low", "Medium", "High"]} value={rtDelay} onChange={setRtDelay} />
                </SRow>
                <SRow title="Preview cadence" desc="How often the live overlay refreshes. Final text inserts on release." last>
                  <Field w={90}>350 ms</Field>
                </SRow>
              </Group>

              <Group label="Refinement · LLM cleanup"
                action={<span style={{ fontSize: 12, color: "var(--ink-faint)" }}>gpt-4.1-mini</span>}>
                <SRow title="Enable refinement" desc="Clean up filler words, punctuation & casing after transcription.">
                  <Toggle on={refine} onClick={() => setRefine(v => !v)} />
                </SRow>
                <SRow title="Max tokens" desc="Upper bound for the refined output.">
                  <Field w={90}>2048</Field>
                </SRow>
                <SRow title="System prompt" desc="How Duper Disper rewrites your speech." last>
                  <Btn onClick={() => setPromptOpen(o => !o)}>{promptOpen ? "Hide" : "Edit"}</Btn>
                </SRow>
                {promptOpen && (
                  <div style={{ padding: "0 0 14px" }}>
                    <div style={{ fontFamily: "var(--font-mono)", fontSize: 12, lineHeight: 1.6,
                      color: "var(--ink-soft)", background: "var(--surface-2)", border: "1px solid var(--line)",
                      borderRadius: 10, padding: "11px 13px" }}>
                      You are a dictation cleanup assistant. Remove filler words and false starts, fix
                      punctuation and capitalization, and preserve the speaker's meaning and tone. Output only
                      the cleaned text.
                    </div>
                  </div>
                )}
              </Group>

              <Group label="Feedback & Startup">
                <SRow title="Sound feedback" desc="Subtle chime on start, stop and insert.">
                  <Toggle on={sound} onClick={() => setSound(v => !v)} />
                </SRow>
                <SRow title="Show overlay" desc="Display the live recorder while dictating.">
                  <Toggle on={overlay} onClick={() => setOverlay(v => !v)} />
                </SRow>
                <SRow title="Auto-start on login" desc="Launch Duper Disper when you sign in.">
                  <Toggle on={autostart} onClick={() => setAutostart(v => !v)} />
                </SRow>
                <SRow title="Developer mode" desc="Debug tracing enabled · logs written with TRACE detail." last>
                  <Toggle on={devmode} onClick={() => setDevmode(v => !v)} />
                </SRow>
              </Group>

              <Group label="macOS Permissions">
                <SRow title="Accessibility" desc="Lets the app detect the hotkey and send paste / typing events.">
                  <Status ok label="Granted" />
                </SRow>
                <SRow title="Microphone" desc="Required so recording works." last>
                  <Status ok label="Granted" />
                </SRow>
              </Group>

            </div>
          </div>
        </div>
      </div>

      <div style={{ fontSize: 12, color: dark ? "rgba(255,255,255,.4)" : "var(--ink-faint)" }}>
        Duper Disper · Settings — Theme &amp; Accent update the whole app live
      </div>

      <TweaksPanel>
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
