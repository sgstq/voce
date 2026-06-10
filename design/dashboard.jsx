// dashboard.jsx — Cadence desktop app dashboard. Frame 1180×760.

function Logo({ size = 22 }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
      <div style={{ width: size, height: size, borderRadius: 7, background: "var(--accent)",
        display: "flex", alignItems: "center", justifyContent: "center", flex: "0 0 auto" }}>
        <Wave n={4} h={size * 0.5} color="#fff" />
      </div>
      <span style={{ fontWeight: 800, fontSize: 16, letterSpacing: -0.4, color: "var(--ink)" }}>Cadence</span>
    </div>
  );
}

function NavItem({ icon, label, on }) {
  return (
    <div style={{
      display: "flex", alignItems: "center", gap: 10, height: 36, padding: "0 12px",
      borderRadius: 9, cursor: "pointer",
      background: on ? "var(--accent-wash)" : "transparent",
      color: on ? "var(--accent)" : "var(--ink-soft)",
      fontWeight: on ? 700 : 500, fontSize: 13.5,
    }}>
      <span style={{ width: 16, display: "flex", justifyContent: "center" }}>{icon}</span>{label}
    </div>
  );
}
const I = {
  home: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 10l9-7 9 7v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>,
  hist: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 7v5l3 2"/><circle cx="12" cy="12" r="9"/></svg>,
  modes: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></svg>,
  dict: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 4v16M4 5a2 2 0 0 1 2-2h12v15H6a2 2 0 0 0-2 2"/></svg>,
  snip: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M13 3L4 14h7l-1 7 9-11h-7z"/></svg>,
  gear: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="3.2"/><path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-2.7 1.1V21a2 2 0 1 1-4 0v-.1A1.6 1.6 0 0 0 7 19.4a1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1A1.6 1.6 0 0 0 2.6 14H2.5a2 2 0 1 1 0-4h.1A1.6 1.6 0 0 0 4 7.6a1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1A1.6 1.6 0 0 0 9 3.6h.1A1.6 1.6 0 0 0 10 2.5V2.5a2 2 0 1 1 4 0v.1A1.6 1.6 0 0 0 17 4.6a1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.1 1.5h.1"/></svg>,
};

function Stat({ value, unit, label, spark }) {
  return (
    <div style={{ flex: 1, padding: "16px 18px", borderRight: "1px solid var(--line-soft)" }}>
      <div style={{ fontSize: 11.5, color: "var(--ink-faint)", fontWeight: 600, marginBottom: 8 }}>{label}</div>
      <div style={{ display: "flex", alignItems: "baseline", gap: 4 }}>
        <span className="mono" style={{ fontSize: 26, fontWeight: 700, letterSpacing: -1, color: "var(--ink)" }}>{value}</span>
        <span style={{ fontSize: 12.5, color: "var(--ink-soft)", fontWeight: 600 }}>{unit}</span>
      </div>
      {spark}
    </div>
  );
}
const Spark = ({ vals, color = "var(--accent)" }) => (
  <div style={{ display: "flex", alignItems: "flex-end", gap: 2.5, height: 20, marginTop: 9 }}>
    {vals.map((v, i) => (
      <div key={i} style={{ flex: 1, height: v + "%", minWidth: 3, borderRadius: 2,
        background: i === vals.length - 1 ? color : "var(--line)" }} />
    ))}
  </div>
);

function HistRow({ time, mode, app, text, words }) {
  const tone = { Message: 155, Email: 285, Note: 27, Code: 255 }[mode] || 285;
  return (
    <div style={{ display: "flex", gap: 12, padding: "13px 0", borderBottom: "1px solid var(--line-soft)" }}>
      <span className="mono" style={{ fontSize: 11.5, color: "var(--ink-faint)", width: 44, flex: "0 0 auto", paddingTop: 2 }}>{time}</span>
      <div style={{ minWidth: 0, flex: 1 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 7, marginBottom: 3 }}>
          <span style={{ fontSize: 10.5, fontWeight: 700, color: `oklch(0.55 0.12 ${tone})`,
            background: `oklch(0.55 0.12 ${tone} / 0.12)`, padding: "2px 7px", borderRadius: 5 }}>{mode}</span>
          <span style={{ fontSize: 11.5, color: "var(--ink-faint)" }}>{app}</span>
          <span style={{ flex: 1 }} />
          <span className="mono" style={{ fontSize: 11, color: "var(--ink-faint)" }}>{words}w</span>
        </div>
        <div style={{ fontSize: 13, color: "var(--ink-soft)", lineHeight: 1.45, overflow: "hidden",
          textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{text}</div>
      </div>
    </div>
  );
}

function ModeCard({ name, desc, hue, on }) {
  return (
    <div style={{ padding: "12px 13px", borderRadius: 13, border: "1px solid var(--line)",
      background: "var(--surface)", display: "flex", flexDirection: "column", gap: 5 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
        <span style={{ width: 8, height: 8, borderRadius: "50%", background: `oklch(0.6 0.14 ${hue})` }} />
        <span style={{ fontWeight: 700, fontSize: 13, color: "var(--ink)" }}>{name}</span>
        {on && <span style={{ marginLeft: "auto", fontSize: 9.5, fontWeight: 700, color: "var(--accent)",
          background: "var(--accent-wash)", padding: "2px 6px", borderRadius: 5 }}>DEFAULT</span>}
      </div>
      <div style={{ fontSize: 11.5, color: "var(--ink-faint)", lineHeight: 1.4 }}>{desc}</div>
    </div>
  );
}

function Dashboard() {
  return (
    <div className="cad-frame" style={{ display: "flex" }}>
      {/* sidebar */}
      <div style={{ width: 204, flex: "0 0 auto", background: "var(--paper-2)",
        borderRight: "1px solid var(--line)", display: "flex", flexDirection: "column", padding: "18px 12px" }}>
        <div style={{ padding: "0 6px 18px" }}><Logo /></div>
        <NavItem icon={I.home} label="Home" on />
        <NavItem icon={I.hist} label="History" />
        <NavItem icon={I.modes} label="Modes" />
        <NavItem icon={I.dict} label="Dictionary" />
        <NavItem icon={I.snip} label="Snippets" />
        <div style={{ flex: 1 }} />
        <NavItem icon={I.gear} label="Settings" />
        <div style={{ margin: "12px 6px 0", padding: 12, borderRadius: 12, background: "var(--surface)",
          border: "1px solid var(--line)" }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: "var(--ink)" }}>Cadence Pro</div>
          <div style={{ fontSize: 11, color: "var(--ink-faint)", marginTop: 2 }}>Unlimited dictation</div>
          <div style={{ height: 5, borderRadius: 3, background: "var(--line)", marginTop: 9, overflow: "hidden" }}>
            <div style={{ width: "62%", height: "100%", background: "var(--accent)" }} />
          </div>
        </div>
      </div>

      {/* main */}
      <div style={{ flex: 1, minWidth: 0, padding: "26px 30px", overflow: "hidden" }}>
        <div style={{ display: "flex", alignItems: "flex-end", marginBottom: 20 }}>
          <div>
            <div style={{ fontSize: 13, color: "var(--ink-faint)", fontWeight: 500 }}>Good morning, Mira</div>
            <div style={{ fontSize: 23, fontWeight: 800, letterSpacing: -0.6, color: "var(--ink)", marginTop: 2 }}>This week with your voice</div>
          </div>
          <div style={{ flex: 1 }} />
          <div className="pill is-accent" style={{ height: 38, fontSize: 13 }}>
            <span style={{ width: 7, height: 7, borderRadius: "50%", background: "#fff" }} /> Hold <span className="kbd" style={{ background: "rgba(255,255,255,.2)", color: "#fff", borderColor: "transparent" }}>fn</span> anywhere
          </div>
        </div>

        {/* stat strip */}
        <div style={{ display: "flex", border: "1px solid var(--line)", borderRadius: 16,
          background: "var(--surface)", marginBottom: 22, overflow: "hidden" }}>
          <Stat label="Words dictated" value="8,420" unit="words" spark={<Spark vals={[30,45,38,60,52,72,90]} />} />
          <Stat label="Speaking speed" value="168" unit="wpm" spark={<Spark vals={[55,60,58,64,62,70,68]} color="oklch(0.6 0.13 155)" />} />
          <Stat label="Time saved" value="3.2" unit="hrs" spark={<Spark vals={[20,35,30,50,55,68,80]} color="oklch(0.62 0.14 27)" />} />
          <div style={{ flex: 1, padding: "16px 18px" }}>
            <div style={{ fontSize: 11.5, color: "var(--ink-faint)", fontWeight: 600, marginBottom: 8 }}>Accuracy</div>
            <div style={{ display: "flex", alignItems: "baseline", gap: 4 }}>
              <span className="mono" style={{ fontSize: 26, fontWeight: 700, letterSpacing: -1 }}>98.4</span>
              <span style={{ fontSize: 12.5, color: "var(--ink-soft)", fontWeight: 600 }}>%</span>
            </div>
            <div style={{ fontSize: 11, color: "var(--ink-faint)", marginTop: 11 }}>+1.2% after dictionary edits</div>
          </div>
        </div>

        {/* two columns */}
        <div style={{ display: "flex", gap: 22 }}>
          {/* recent */}
          <div style={{ flex: 1.5, minWidth: 0 }}>
            <div style={{ display: "flex", alignItems: "center", marginBottom: 4 }}>
              <span style={{ fontSize: 14, fontWeight: 700, color: "var(--ink)" }}>Recent dictations</span>
              <span style={{ flex: 1 }} />
              <span style={{ fontSize: 12, color: "var(--accent)", fontWeight: 600, cursor: "pointer" }}>View all →</span>
            </div>
            <HistRow time="9:18" mode="Message" app="#design-team" words="24" text="I think we should rewrite the onboarding copy — it reads a little robotic right now." />
            <HistRow time="9:02" mode="Email" app="Gmail" words="86" text="Hi Sam, thanks for the thorough writeup. A few thoughts before we lock the scope…" />
            <HistRow time="8:47" mode="Code" app="VS Code" words="31" text="add a debounce of 250ms to the search input and memoize the filtered results" />
            <HistRow time="8:31" mode="Note" app="Obsidian" words="142" text="Standup: shipped the empty-state pass, blocked on the auth migration, picking up…" />
            <HistRow time="Yesterday" mode="Message" app="Slack DM" words="18" text="sounds good — let's sync after lunch and I'll walk you through the flow" />
          </div>

          {/* modes */}
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: "flex", alignItems: "center", marginBottom: 10 }}>
              <span style={{ fontSize: 14, fontWeight: 700, color: "var(--ink)" }}>Your modes</span>
              <span style={{ flex: 1 }} />
              <span style={{ fontSize: 12, color: "var(--accent)", fontWeight: 600, cursor: "pointer" }}>+ New</span>
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
              <ModeCard name="Message" desc="Casual, concise, emoji ok" hue={155} on />
              <ModeCard name="Email" desc="Polished & professional" hue={285} />
              <ModeCard name="Note" desc="Verbatim, light cleanup" hue={27} />
              <ModeCard name="Code" desc="Symbols & camelCase" hue={255} />
            </div>
            <div style={{ marginTop: 14, padding: 13, borderRadius: 13, border: "1px dashed var(--line)",
              background: "var(--surface-2)" }}>
              <div style={{ fontSize: 12.5, fontWeight: 700, color: "var(--ink)", marginBottom: 6 }}>Dictionary · 3 new</div>
              <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                {["Cadence", "oklch", "Kubernetes", "Reyes", "PostHog"].map(w => (
                  <span key={w} className="mono" style={{ fontSize: 11, padding: "3px 8px", borderRadius: 6,
                    background: "var(--surface)", border: "1px solid var(--line)", color: "var(--ink-soft)" }}>{w}</span>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

window.Dashboard = Dashboard;
window.Logo = Logo;
