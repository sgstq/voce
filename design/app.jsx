// app.jsx — assembles the Cadence exploration canvas + Tweaks.

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "accent": "oklch(0.55 0.17 285)",
  "dark": false,
  "density": "regular",
  "shape": "Soft"
}/*EDITMODE-END*/;

const SHAPE_RADIUS = { Pill: "28px", Soft: "18px", Crisp: "8px" };
const ACCENTS = [
  "oklch(0.55 0.17 285)", // indigo-violet
  "oklch(0.55 0.15 250)", // cobalt
  "oklch(0.60 0.13 165)", // teal
  "oklch(0.66 0.14 65)",  // amber
  "oklch(0.62 0.18 28)",  // coral
];

function Rationale() {
  const Pt = ({ k, children }) => (
    <div style={{ display: "flex", gap: 10, marginBottom: 11 }}>
      <span style={{ flex: "0 0 auto", width: 7, height: 7, borderRadius: "50%", background: "var(--accent)", marginTop: 6 }} />
      <div style={{ fontSize: 13.5, lineHeight: 1.55, color: "var(--ink-soft)" }}>
        <b style={{ color: "var(--ink)", fontWeight: 700 }}>{k}</b> {children}
      </div>
    </div>
  );
  return (
    <div className="cad-frame" style={{ padding: "30px 34px", overflow: "auto" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 9, marginBottom: 4 }}>
        <Logo size={24} />
        <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: 0.6, textTransform: "uppercase",
          color: "var(--accent)", background: "var(--accent-wash)", padding: "3px 9px", borderRadius: 6 }}>Concept</span>
      </div>
      <h1 style={{ fontSize: 26, fontWeight: 800, letterSpacing: -0.8, color: "var(--ink)", margin: "14px 0 6px" }}>
        A dictation app you talk to, not at.
      </h1>
      <p style={{ fontSize: 14, lineHeight: 1.6, color: "var(--ink-soft)", margin: "0 0 20px", maxWidth: 560 }}>
        Press a key anywhere, speak naturally, and polished text lands at your cursor in under two seconds.
        These frames explore the signature moment — the floating recorder — five ways, then the desktop app around it.
      </p>

      <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 0.6, textTransform: "uppercase",
        color: "var(--ink-faint)", marginBottom: 10 }}>The system</div>
      <Pt k="Type —">Hanken Grotesk for UI, JetBrains Mono for timers, shortcuts & counts.</Pt>
      <Pt k="Color —">warm paper / ink in light & dark, one AI accent, a warm hue reserved for the live recording state.</Pt>
      <Pt k="Recorder —">a calm rounded dock; motion (waveform, pulse, shimmer) carries the "listening → polishing → done" arc.</Pt>
      <Pt k="Differentiators —">speed (raw → polished), Command Mode (edit by voice), and context-aware Modes are each given their own variation.</Pt>

      <div style={{ marginTop: 20, padding: 14, borderRadius: 12, background: "var(--surface-2)",
        border: "1px solid var(--line)", fontSize: 12.5, lineHeight: 1.55, color: "var(--ink-soft)", maxWidth: 560 }}>
        <b style={{ color: "var(--ink)" }}>Try it →</b> open <b>Tweaks</b> (toolbar) to swap accent, flip light/dark,
        change recorder shape and density. Drag any frame to reorder; click a frame's ⤢ to focus it fullscreen.
      </div>
    </div>
  );
}

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const { RecPill, RecCapsule, RecInline, RecCommand, RecContext } = window.Recorders;

  React.useEffect(() => {
    const r = document.documentElement;
    r.setAttribute("data-theme", t.dark ? "dark" : "light");
    r.setAttribute("data-density", t.density);
    const c = t.dark ? `color-mix(in oklab, ${t.accent}, white 12%)` : t.accent;
    r.style.setProperty("--accent", c);
    r.style.setProperty("--accent-press", `color-mix(in oklab, ${c}, black 16%)`);
    r.style.setProperty("--accent-wash", `color-mix(in oklab, ${c}, transparent 86%)`);
    r.style.setProperty("--radius", SHAPE_RADIUS[t.shape] || "18px");
  }, [t.dark, t.density, t.accent, t.shape]);

  const recW = 560, recH = 384;

  return (
    <React.Fragment>
      <DesignCanvas style={{ background: t.dark ? "#1c1916" : "#f0eee9" }}>
        <DCSection id="start" title="Start here" subtitle="Assumptions, system & how to drive these frames">
          <DCArtboard id="rationale" label="Design rationale" width={680} height={560}
            style={{ background: "var(--paper)" }}><Rationale /></DCArtboard>
        </DCSection>

        <DCSection id="recorder" title="The recorder — 5 directions"
          subtitle="The hotkey moment, over a team-chat. Basic → expressive → novel.">
          <DCArtboard id="v1" label="01 · The Pill — refined baseline" width={recW} height={recH}
            style={{ background: "var(--paper)" }}><RecPill /></DCArtboard>
          <DCArtboard id="v2" label="02 · Live Capsule — raw transcript forms" width={recW} height={recH}
            style={{ background: "var(--paper)" }}><RecCapsule /></DCArtboard>
          <DCArtboard id="v3" label="03 · Inline Polish — cleanup in place (novel)" width={recW} height={recH}
            style={{ background: "var(--paper)" }}><RecInline /></DCArtboard>
          <DCArtboard id="v4" label="04 · Command Mode — edit by voice (novel)" width={recW} height={recH}
            style={{ background: "var(--paper)" }}><RecCommand /></DCArtboard>
          <DCArtboard id="v5" label="05 · Context Orb — auto-picks a mode (novel)" width={recW} height={recH}
            style={{ background: "var(--paper)" }}><RecContext /></DCArtboard>
        </DCSection>

        <DCSection id="app" title="The desktop app" subtitle="Where the history, stats, modes & preferences live">
          <DCArtboard id="dash" label="Dashboard" width={1180} height={760}
            style={{ background: "var(--paper)" }}><Dashboard /></DCArtboard>
          <DCArtboard id="settings" label="Settings" width={980} height={720}
            style={{ background: "var(--paper)" }}><Settings /></DCArtboard>
        </DCSection>
      </DesignCanvas>

      <TweaksPanel>
        <TweakSection label="Theme" />
        <TweakColor label="Accent" value={t.accent} options={ACCENTS}
          onChange={(v) => setTweak("accent", v)} />
        <TweakToggle label="Dark mode" value={t.dark} onChange={(v) => setTweak("dark", v)} />
        <TweakSection label="Recorder & layout" />
        <TweakRadio label="Recorder shape" value={t.shape} options={["Pill", "Soft", "Crisp"]}
          onChange={(v) => setTweak("shape", v)} />
        <TweakRadio label="Density" value={t.density} options={["compact", "regular", "comfy"]}
          onChange={(v) => setTweak("density", v)} />
      </TweaksPanel>
    </React.Fragment>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
