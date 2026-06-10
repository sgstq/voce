// settings.jsx — Cadence preferences. Frame 980×720.

function Toggle({ on }) {
  return (
    <div style={{ width: 40, height: 24, borderRadius: 999, flex: "0 0 auto",
      background: on ? "var(--accent)" : "var(--line)", position: "relative", transition: "background .2s" }}>
      <div style={{ position: "absolute", top: 3, left: on ? 19 : 3, width: 18, height: 18, borderRadius: "50%",
        background: "#fff", boxShadow: "0 1px 3px rgba(0,0,0,.3)", transition: "left .2s" }} />
    </div>
  );
}

function Seg({ options, value }) {
  return (
    <div style={{ display: "inline-flex", padding: 3, borderRadius: 10, background: "var(--surface-2)",
      border: "1px solid var(--line)", gap: 2 }}>
      {options.map(o => (
        <span key={o} style={{ padding: "5px 12px", borderRadius: 7, fontSize: 12.5, fontWeight: 600,
          cursor: "pointer", color: o === value ? "var(--accent-ink)" : "var(--ink-soft)",
          background: o === value ? "var(--accent)" : "transparent" }}>{o}</span>
      ))}
    </div>
  );
}

function SRow({ title, desc, children, last }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 16, padding: "15px 0",
      borderBottom: last ? "none" : "1px solid var(--line-soft)" }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 13.5, fontWeight: 600, color: "var(--ink)" }}>{title}</div>
        {desc && <div style={{ fontSize: 12, color: "var(--ink-faint)", marginTop: 2, lineHeight: 1.4 }}>{desc}</div>}
      </div>
      <div style={{ flex: "0 0 auto" }}>{children}</div>
    </div>
  );
}

function Group({ label, children }) {
  return (
    <div style={{ marginBottom: 24 }}>
      <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 0.7, textTransform: "uppercase",
        color: "var(--ink-faint)", marginBottom: 4 }}>{label}</div>
      <div className="card" style={{ padding: "2px 18px", borderRadius: 14 }}>{children}</div>
    </div>
  );
}

function Settings() {
  const tabs = ["Activation", "Audio & Language", "AI & Privacy", "Behavior"];
  return (
    <div className="cad-frame" style={{ display: "flex", flexDirection: "column" }}>
      {/* header */}
      <div style={{ padding: "22px 32px 0", flex: "0 0 auto" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <Logo />
          <span style={{ color: "var(--ink-faint)", fontSize: 15 }}>/</span>
          <span style={{ fontSize: 17, fontWeight: 800, letterSpacing: -0.4, color: "var(--ink)" }}>Settings</span>
        </div>
        <div style={{ display: "flex", gap: 4, marginTop: 16, borderBottom: "1px solid var(--line)" }}>
          {tabs.map((t, i) => (
            <span key={t} style={{ padding: "9px 14px", fontSize: 13, fontWeight: i === 0 ? 700 : 500,
              color: i === 0 ? "var(--ink)" : "var(--ink-soft)", cursor: "pointer",
              borderBottom: i === 0 ? "2px solid var(--accent)" : "2px solid transparent", marginBottom: -1 }}>{t}</span>
          ))}
        </div>
      </div>

      {/* body */}
      <div style={{ flex: 1, padding: "22px 32px", overflow: "hidden" }}>
        <div style={{ maxWidth: 620 }}>
          <Group label="Activation">
            <SRow title="Activation key" desc="Hold anywhere to dictate, release to insert.">
              <span className="kbd" style={{ fontSize: 12.5, padding: "5px 11px" }}>fn</span>
            </SRow>
            <SRow title="Trigger style" desc="Hold-to-talk or tap once to start and stop.">
              <Seg options={["Hold", "Toggle"]} value="Hold" />
            </SRow>
            <SRow title="Command mode key" desc="Select text, hold to edit it by voice." last>
              <span style={{ display: "inline-flex", gap: 4 }}>
                <span className="kbd" style={{ fontSize: 12.5, padding: "5px 9px" }}>⌘</span>
                <span className="kbd" style={{ fontSize: 12.5, padding: "5px 9px" }}>fn</span>
              </span>
            </SRow>
          </Group>

          <Group label="Audio & Language">
            <SRow title="Input device" desc="Source microphone for dictation.">
              <span className="pill" style={{ height: 32 }}>MacBook Pro Mic ▾</span>
            </SRow>
            <SRow title="Spoken languages" desc="Auto-detected and switchable mid-sentence." last>
              <span style={{ display: "inline-flex", gap: 6 }}>
                <span className="chip is-on" style={{ height: 28 }}>English</span>
                <span className="chip is-on" style={{ height: 28 }}>Español</span>
                <span className="chip" style={{ height: 28 }}>+ Add</span>
              </span>
            </SRow>
          </Group>

          <Group label="AI & Privacy">
            <SRow title="Processing" desc="On-device is private & offline; Cloud is faster & smarter.">
              <Seg options={["On-device", "Cloud", "Auto"]} value="Auto" />
            </SRow>
            <SRow title="Zero data retention" desc="Never store audio or transcripts on our servers.">
              <Toggle on />
            </SRow>
            <SRow title="Filler-word removal" desc="Strip “um”, “uh”, false starts before inserting." last>
              <Toggle on />
            </SRow>
          </Group>

          <Group label="Behavior">
            <SRow title="Restore clipboard" desc="Put your clipboard back after pasting dictated text.">
              <Toggle on />
            </SRow>
            <SRow title="Completion sound" desc="Subtle chime when polished text is inserted." last>
              <Toggle on={false} />
            </SRow>
          </Group>
        </div>
      </div>
    </div>
  );
}

window.Settings = Settings;
