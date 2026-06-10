// live-dictation.jsx — Cadence "Inline Polish" interaction, made real.
// Hold the mic (or Space) → words stream into an overlay ON the text field
// and refine themselves live (fillers fall away, caps + punctuation snap in).
// Release → the clean text is inserted. No status chrome, no buttons.

const { useState, useRef, useEffect, useCallback } = React;

/* ---- authored takes ----------------------------------------------------
   ops: w=word · f=filler (will fall away) · drop=remove oldest filler ·
        cap=capitalize last word · p=tight punctuation · dash=spaced em-dash
   Authored so the raw stream reads disfluent and the refined result reads clean. */
const TAKES = [
  [
    {k:'f',t:'um'}, {k:'w',t:'hey'}, {k:'w',t:'team'}, {k:'drop'}, {k:'cap'},
    {k:'dash'}, {k:'f',t:'so'}, {k:'w',t:'I'}, {k:'w',t:'think'}, {k:'drop'},
    {k:'w',t:'we'}, {k:'w',t:'should'}, {k:'f',t:'like'}, {k:'w',t:'rewrite'}, {k:'drop'},
    {k:'w',t:'the'}, {k:'w',t:'onboarding'}, {k:'w',t:'copy'}, {k:'p',t:'.'},
    {k:'f',t:'uh'}, {k:'w',t:'it'}, {k:'drop'}, {k:'cap'}, {k:'w',t:'reads'},
    {k:'w',t:'a'}, {k:'w',t:'bit'}, {k:'w',t:'robotic'}, {k:'w',t:'right'}, {k:'w',t:'now'}, {k:'p',t:','},
    {k:'w',t:'so'}, {k:'w',t:"let's"}, {k:'w',t:'make'}, {k:'w',t:'it'}, {k:'w',t:'warmer'}, {k:'p',t:'.'},
  ],
  [
    {k:'f',t:'uh'}, {k:'w',t:'can'}, {k:'w',t:'you'}, {k:'drop'}, {k:'cap'},
    {k:'w',t:'add'}, {k:'w',t:'a'}, {k:'w',t:'debounce'}, {k:'f',t:'um'},
    {k:'w',t:'of'}, {k:'w',t:'250'}, {k:'w',t:'milliseconds'}, {k:'drop'},
    {k:'w',t:'to'}, {k:'w',t:'the'}, {k:'w',t:'search'}, {k:'w',t:'input'}, {k:'p',t:'?'},
    {k:'f',t:'like'}, {k:'w',t:'and'}, {k:'drop'}, {k:'cap'}, {k:'w',t:'memoize'},
    {k:'w',t:'the'}, {k:'w',t:'filtered'}, {k:'w',t:'results'}, {k:'p',t:'.'},
  ],
];
const BASE_DELAY = { w:148, f:135, drop:150, p:155, dash:185, cap:110 };

let _id = 0;
const nid = () => ++_id;

function Wave({ n = 5, color = "var(--accent)", h = 16 }) {
  return (
    <span className="wave" style={{ height: h, color, gap: 2 }}>
      {Array.from({ length: n }).map((_, i) => (
        <i key={i} style={{ width: 2.5,
          animationDuration: (0.6 + ((i * 37) % 7) / 10).toFixed(2) + "s",
          animationDelay: (-((i * 53) % 9) / 10).toFixed(2) + "s" }} />
      ))}
    </span>
  );
}

function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1); }

// build the final clean string from the live token list
function tokensToText(tokens) {
  let out = "";
  tokens.filter(t => t.state !== "out").forEach((t, i) => {
    const word = t.cap ? cap(t.t) : t.t;
    if (i === 0) out = word;
    else if (t.tight) out += word;
    else out += " " + word;
  });
  return out;
}

function Composer({ value, placeholder, dictating, onSend }) {
  return (
    <div style={{ position: "relative" }}>
      <div style={{
        minHeight: 50, borderRadius: 13, border: "1px solid var(--line)",
        background: "var(--surface)", display: "flex", alignItems: "center",
        padding: "0 8px 0 16px", gap: 10,
        opacity: dictating ? 0 : 1, transition: "opacity .25s",
      }}>
        <div style={{ flex: 1, fontSize: 14.5, color: value ? "var(--ink)" : "var(--ink-faint)",
          lineHeight: 1.45, padding: "12px 0" }}>
          {value || placeholder}
        </div>
        <button onClick={onSend} disabled={!value} className="pill is-accent"
          style={{ height: 36, opacity: value ? 1 : 0.4, cursor: value ? "pointer" : "default" }}>
          Send
        </button>
      </div>
    </div>
  );
}

function LiveOverlay({ tokens }) {
  const ref = useRef(null);
  // keep the latest word in view as text grows
  useEffect(() => { if (ref.current) ref.current.scrollTop = ref.current.scrollHeight; }, [tokens]);
  const visible = tokens;
  return (
    <div style={{
      position: "absolute", left: 0, right: 0, bottom: 0,
      borderRadius: 14, background: "var(--surface)",
      border: "1.5px solid var(--accent)", boxShadow: "0 0 0 5px var(--accent-wash), var(--shadow-pop)",
      padding: "12px 15px 13px", zIndex: 20, opacity: 1,
    }}>
      <div ref={ref} style={{ maxHeight: 132, overflow: "hidden", fontSize: 15, lineHeight: 1.62,
        color: "var(--ink)", fontWeight: 450 }}>
        {visible.map((t, i) => {
          const isOut = t.state === "out";
          const word = t.cap ? cap(t.t) : t.t;
          const sep = (i > 0 && !t.tight) ? " " : "";
          return (
            <React.Fragment key={t.id}>
              {sep}
              <span style={{
                display: "inline-block",
                color: t.kind === "filler" ? "var(--ink-faint)" : (t.flash ? "var(--accent)" : "var(--ink)"),
                opacity: isOut ? 0 : (t.kind === "filler" ? 0.5 : 1),
                transform: isOut ? "translateY(-2px)" : "none",
                transition: "opacity .24s ease, transform .24s ease, color .5s ease",
                animation: t._new ? "wordIn .22s ease both" : "none",
              }}>{word}</span>
            </React.Fragment>
          );
        })}
        <span style={{ display: "inline-block", width: 2, height: 17, background: "var(--accent)",
          marginLeft: 3, verticalAlign: -3, animation: "cadCaret 1s steps(1) infinite" }} />
      </div>
      {/* live indicator only — no wording */}
      <div style={{ display: "flex", alignItems: "center", gap: 9, marginTop: 11,
        paddingTop: 10, borderTop: "1px solid var(--line-soft)" }}>
        <span style={{ width: 9, height: 9, borderRadius: "50%", background: "var(--live)",
          animation: "livePulse 1.3s ease-in-out infinite" }} />
        <Wave n={7} h={15} color="var(--accent)" />
        <span style={{ flex: 1 }} />
        <span className="kbd" style={{ fontSize: 10.5 }}>release to insert</span>
      </div>
    </div>
  );
}

window.LiveDictation = { TAKES, BASE_DELAY, nid, tokensToText, cap, Wave, Composer, LiveOverlay,
  useState, useRef, useEffect, useCallback };
