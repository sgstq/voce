// recorders.jsx — five takes on the floating dictation recorder.
// Each exports a full self-contained frame (ChatHost backdrop + overlay).
// Range: refined-baseline → expressive → novel inline → command mode → context.

const Wave = ({ n = 22, idle = false, h = 22, color }) => (
  <div className={"wave" + (idle ? " is-idle" : "")} style={{ height: h, color }}>
    {Array.from({ length: n }).map((_, i) => (
      <i key={i} style={{
        animationDuration: (0.7 + ((i * 37) % 9) / 10).toFixed(2) + "s",
        animationDelay: (-((i * 53) % 11) / 10).toFixed(2) + "s",
        opacity: 0.55 + ((i * 29) % 5) / 10,
      }} />
    ))}
  </div>
);

// floating dock anchored bottom-center over the composer
const Dock = ({ children, w, bottom = 18 }) => (
  <div style={{
    position: "absolute", left: "50%", bottom, transform: "translateX(-50%)",
    width: w, zIndex: 10,
  }}>{children}</div>
);

const MicDot = ({ size = 26, live = true }) => (
  <span style={{
    width: size, height: size, borderRadius: "50%", flex: "0 0 auto",
    display: "flex", alignItems: "center", justifyContent: "center",
    background: live ? "var(--live)" : "var(--surface-2)",
    animation: live ? "cadPulse 1.6s ease-out infinite" : "none",
  }}>
    <svg width={size * 0.5} height={size * 0.5} viewBox="0 0 24 24" fill="none"
      stroke={live ? "#fff" : "var(--ink-soft)"} strokeWidth="2.4" strokeLinecap="round">
      <rect x="9" y="2" width="6" height="12" rx="3" fill={live ? "#fff" : "none"} stroke="none" />
      <path d="M5 11a7 7 0 0 0 14 0M12 18v3" />
    </svg>
  </span>
);

/* ── V1 · The Pill — refined baseline, picked shape #3 ─────────── */
function RecPill() {
  return (
    <div className="cad-frame">
      <ChatHost dim={0.6} />
      <Dock w={372}>
        <div style={{
          display: "flex", alignItems: "center", gap: 12,
          height: 56, padding: "0 8px 0 8px",
          borderRadius: "var(--radius)", background: "var(--surface)",
          border: "1px solid var(--line)", boxShadow: "var(--shadow-pop)",
        }}>
          <MicDot />
          <Wave n={16} color="var(--accent)" />
          <div style={{ flex: 1 }} />
          <span className="mono" style={{ fontSize: 12.5, color: "var(--ink-soft)", fontWeight: 600 }}>0:07</span>
          <span style={{ width: 1, height: 22, background: "var(--line)" }} />
          <span className="chip is-on" style={{ marginRight: 4 }}>Message</span>
        </div>
        <div style={{ textAlign: "center", marginTop: 9, fontSize: 11.5, color: "var(--ink-faint)" }}>
          Release <span className="kbd">fn</span> to insert · <span className="kbd">esc</span> to cancel
        </div>
      </Dock>
    </div>
  );
}

/* ── V2 · Live Capsule — expressive, shows raw transcript forming ─ */
function RecCapsule() {
  return (
    <div className="cad-frame">
      <ChatHost dim={0.6} />
      <Dock w={418}>
        <div style={{
          borderRadius: "var(--radius)", background: "oklch(0.24 0.012 70)", color: "#fff",
          boxShadow: "var(--shadow-pop)", overflow: "hidden",
        }}>
          <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "12px 16px" }}>
            <MicDot />
            <Wave n={26} h={26} color="color-mix(in oklab, var(--accent), white 32%)" />
            <div style={{ flex: 1 }} />
            <span className="mono" style={{ fontSize: 12, opacity: 0.7 }}>EN</span>
            <span className="mono" style={{ fontSize: 12.5, fontWeight: 600 }}>0:11</span>
          </div>
          <div style={{
            padding: "11px 16px 14px", borderTop: "1px solid rgba(255,255,255,.1)",
            fontSize: 13.5, lineHeight: 1.5,
          }}>
            <span style={{ opacity: 0.45 }}>um so i think we </span>
            <span style={{ opacity: 0.45 }}>should </span>
            <span>rewrite the onboarding copy and</span>
            <span style={{
              display: "inline-block", width: 2, height: 15, background: "color-mix(in oklab, var(--accent), white 32%)",
              marginLeft: 3, verticalAlign: -2, animation: "cadCaret 1s steps(1) infinite",
            }} />
          </div>
        </div>
      </Dock>
    </div>
  );
}

/* ── V3 · Inline polish — NOVEL. No pill; cleanup happens in place ─ */
function RecInline() {
  const composer = (
    <div style={{
      borderRadius: 12, border: "1.5px solid var(--accent)",
      background: "var(--surface)", boxShadow: "0 0 0 4px var(--accent-wash)",
      padding: "10px 12px 10px 14px",
    }}>
      {/* faded raw line being cleaned */}
      <div style={{ fontSize: 11.5, color: "var(--ink-faint)", marginBottom: 5, display: "flex", alignItems: "center", gap: 6 }}>
        <span className="spinner" style={{ width: 11, height: 11 }} />
        polishing — removed <span className="mono" style={{ color: "var(--ink-soft)" }}>“um”, “like”, “basically”</span>
      </div>
      <div style={{ fontSize: 14, lineHeight: 1.55, color: "var(--ink)", fontWeight: 450 }}>
        I think we should rewrite the onboarding copy — it reads a little robotic right now.
        <span style={{
          display: "inline-block", width: 2, height: 15, background: "var(--accent)",
          marginLeft: 2, verticalAlign: -2, animation: "cadCaret 1s steps(1) infinite",
        }} />
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 9 }}>
        <span className="pill is-accent" style={{ height: 28 }}>Insert ↵</span>
        <span className="pill" style={{ height: 28 }}>Redo</span>
        <div style={{ flex: 1 }} />
        <Wave n={9} idle color="var(--accent)" />
        <span className="mono" style={{ fontSize: 11, color: "var(--ink-faint)" }}>cadence</span>
      </div>
    </div>
  );
  return (
    <div className="cad-frame">
      <ChatHost dim={0} composer={composer} />
    </div>
  );
}

/* ── V4 · Command Mode — NOVEL. Edit selected text by voice ───────── */
function RecCommand() {
  return (
    <div className="cad-frame">
      <ChatHost dim={0.6} />
      <Dock w={430}>
        <div style={{
          borderRadius: "var(--radius)", background: "var(--surface)", border: "1px solid var(--line)",
          boxShadow: "var(--shadow-pop)", overflow: "hidden",
        }}>
          <div style={{ display: "flex", alignItems: "center", gap: 9, padding: "11px 14px",
            borderBottom: "1px solid var(--line-soft)" }}>
            <span style={{
              fontFamily: "var(--font-mono)", fontSize: 10.5, fontWeight: 700, letterSpacing: 0.5,
              textTransform: "uppercase", color: "var(--accent)", background: "var(--accent-wash)",
              padding: "3px 8px", borderRadius: 6,
            }}>⌘ Command</span>
            <Wave n={12} color="var(--accent)" />
            <div style={{ flex: 1 }} />
            <span className="mono" style={{ fontSize: 11.5, color: "var(--ink-soft)", fontWeight: 600 }}>0:03</span>
          </div>
          {/* spoken instruction */}
          <div style={{ padding: "12px 14px 6px" }}>
            <div style={{ fontSize: 10.5, color: "var(--ink-faint)", marginBottom: 4, textTransform: "uppercase", letterSpacing: 0.6, fontWeight: 700 }}>You said</div>
            <div style={{ fontSize: 14.5, fontWeight: 600, color: "var(--ink)" }}>“make this more concise and friendly”</div>
          </div>
          {/* before → after */}
          <div style={{ padding: "8px 14px 14px" }}>
            <div style={{ position: "relative", fontSize: 12.5, lineHeight: 1.5, color: "var(--ink-faint)", marginBottom: 6 }}>
              <span>I am writing to inform you that the deployment has been completed.</span>
              <span style={{ position: "absolute", left: 0, top: "50%", height: 1.5, background: "var(--ink-faint)", animation: "cadStrike .5s ease forwards" }} />
            </div>
            <div style={{ fontSize: 13.5, lineHeight: 1.5, color: "var(--ink)", fontWeight: 500, animation: "cadRise .4s .35s both" }}>
              Heads up — the deploy’s done! 🚀
            </div>
            <div style={{ display: "flex", gap: 8, marginTop: 12 }}>
              <span className="pill is-accent" style={{ height: 30 }}>Replace selection</span>
              <span className="pill" style={{ height: 30 }}>Insert below</span>
            </div>
          </div>
        </div>
      </Dock>
    </div>
  );
}

/* ── V5 · Context Orb — NOVEL. Auto-detects app, picks mode ───────── */
function RecContext() {
  const modes = [["Message", true], ["Email", false], ["Note", false], ["Code", false]];
  return (
    <div className="cad-frame">
      <ChatHost dim={0.6} />
      <Dock w={300} bottom={20}>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 14 }}>
          {/* orb */}
          <div style={{
            width: 84, height: 84, borderRadius: "50%", position: "relative",
            display: "flex", alignItems: "center", justifyContent: "center",
            background: "var(--surface)", border: "1px solid var(--line)", boxShadow: "var(--shadow-pop)",
            animation: "cadOrb 2.4s ease-in-out infinite",
          }}>
            <div style={{ position: "absolute", inset: -3, borderRadius: "50%",
              border: "2px solid var(--accent)", opacity: 0.35 }} />
            <Wave n={9} h={30} color="var(--accent)" />
          </div>
          {/* context card */}
          <div style={{
            width: "100%", borderRadius: 16, background: "var(--surface)",
            border: "1px solid var(--line)", boxShadow: "var(--shadow-2)", padding: 12,
          }}>
            <div style={{ fontSize: 11.5, color: "var(--ink-faint)", marginBottom: 8, textAlign: "center" }}>
              Detected <span style={{ color: "var(--ink-soft)", fontWeight: 600 }}>#design-team</span> → tuned for chat
            </div>
            <div style={{ display: "flex", gap: 5, justifyContent: "center", flexWrap: "wrap" }}>
              {modes.map(([m, on]) => (
                <span key={m} className={"chip" + (on ? " is-on" : "")} style={{ height: 27, padding: "0 10px" }}>{m}</span>
              ))}
            </div>
          </div>
        </div>
      </Dock>
    </div>
  );
}

window.Recorders = { RecPill, RecCapsule, RecInline, RecCommand, RecContext };
window.Wave = Wave;
