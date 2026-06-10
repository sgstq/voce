// host-slack.jsx — generic team-chat backdrop the recorder floats over.
// Original layout (not a branded clone). Exports window.ChatHost.

function Avatar({ initials, hue, size = 30 }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: 9, flex: '0 0 auto',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontFamily: 'var(--font-sans)', fontWeight: 700,
      fontSize: size * 0.36, color: '#fff',
      background: `oklch(0.62 0.13 ${hue})`,
    }}>{initials}</div>
  );
}

function Msg({ initials, hue, name, time, children, accent }) {
  return (
    <div style={{ display: 'flex', gap: 10, padding: '7px 0' }}>
      <Avatar initials={initials} hue={hue} />
      <div style={{ minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
          <span style={{ fontWeight: 700, fontSize: 13.5, color: 'var(--ink)' }}>{name}</span>
          <span className="mono" style={{ fontSize: 10.5, color: 'var(--ink-faint)' }}>{time}</span>
        </div>
        <div style={{
          fontSize: 13.5, lineHeight: 1.5, color: accent ? 'var(--accent)' : 'var(--ink-soft)',
          marginTop: 1, fontWeight: accent ? 600 : 400,
        }}>{children}</div>
      </div>
    </div>
  );
}

// dim: 0 = crisp, 1 = pushed back behind the recorder
function ChatHost({ dim = 0, channel = "design-team", composer = null, members = 12 }) {
  return (
    <div className="cad-frame" style={{ display: 'flex', background: 'var(--paper)' }}>
      {/* slim rail */}
      <div style={{
        width: 52, flex: '0 0 auto', background: 'var(--paper-2)',
        borderRight: '1px solid var(--line-soft)',
        display: 'flex', flexDirection: 'column', alignItems: 'center',
        paddingTop: 14, gap: 10,
      }}>
        <div style={{ width: 28, height: 28, borderRadius: 9, background: 'var(--accent)' }} />
        <div style={{ width: 1, height: 8 }} />
        {['#', '#', '@', '+'].map((c, i) => (
          <div key={i} style={{
            width: 30, height: 30, borderRadius: 9,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: i === 0 ? 'var(--ink)' : 'var(--ink-faint)',
            background: i === 0 ? 'var(--surface)' : 'transparent',
            border: i === 0 ? '1px solid var(--line)' : 'none',
            fontSize: 15, fontWeight: 700,
          }}>{c}</div>
        ))}
      </div>

      {/* conversation column */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0,
        transition: 'filter .4s, opacity .4s',
        filter: dim ? 'blur(2px)' : 'none', opacity: dim ? 0.55 : 1 }}>
        {/* channel header */}
        <div style={{
          height: 46, flex: '0 0 auto', borderBottom: '1px solid var(--line-soft)',
          display: 'flex', alignItems: 'center', gap: 8, padding: '0 18px',
        }}>
          <span style={{ fontWeight: 800, fontSize: 14.5, color: 'var(--ink)' }}>
            <span style={{ color: 'var(--ink-faint)', marginRight: 2 }}>#</span>{channel}
          </span>
          <span style={{ fontSize: 12, color: 'var(--ink-faint)' }}>· {members} members</span>
        </div>

        {/* messages */}
        <div style={{ flex: 1, padding: '10px 18px', overflow: 'hidden' }}>
          <Msg initials="JR" hue={28} name="Jordan Reyes" time="9:14">
            shipping the new onboarding today — can someone sanity-check the empty states?
          </Msg>
          <Msg initials="MP" hue={155} name="Mira Patel" time="9:16">
            on it. the first-run copy still reads a little robotic imo
          </Msg>
          <Msg initials="DK" hue={255} name="Devin Kwon" time="9:18">
            agreed. want me to rewrite or do you have a pass?
          </Msg>
        </div>

        {/* composer slot — recorder floats above this */}
        <div style={{ padding: '0 16px 16px', flex: '0 0 auto' }}>
          {composer || (
            <div style={{
              minHeight: 46, borderRadius: 12, border: '1px solid var(--line)',
              background: 'var(--surface)', display: 'flex', alignItems: 'center',
              padding: '0 14px', color: 'var(--ink-faint)', fontSize: 13.5,
            }}>
              Message #{channel}
              <span style={{ width: 1, height: 16, background: 'var(--accent)', marginLeft: 2,
                animation: 'cadCaret 1.1s steps(1) infinite' }} />
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

window.ChatHost = ChatHost;
window.Avatar = Avatar;
