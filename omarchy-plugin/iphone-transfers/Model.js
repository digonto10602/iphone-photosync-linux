.pragma library

// Formatting and validation helpers for the iPhone Transfers widget.

function human(n) {
  n = Number(n) || 0
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (Math.abs(n) >= 1000 && i < units.length - 1) { n /= 1000; i++ }
  return i === 0 ? Math.round(n) + " " + units[i] : n.toFixed(n >= 100 ? 0 : 1) + " " + units[i]
}

function duration(s) {
  s = Number(s)
  if (!isFinite(s) || s < 0 || s > 99 * 3600) return "--:--"
  s = Math.round(s)
  var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60
  var mm = (h > 0 && m < 10 ? "0" : "") + m
  return (h > 0 ? h + ":" : "") + mm + ":" + (sec < 10 ? "0" : "") + sec
}

function clampText(v, max) {
  var s = String(v === undefined || v === null ? "" : v)
  return s.length > max ? s.substring(0, max - 1) + "…" : s
}

function num(v, fallback) {
  var n = Number(v)
  return isFinite(n) ? n : fallback
}

// Validate one feed line; returns null if it is not a sane status object.
function parse(line) {
  var d
  try { d = JSON.parse(line) } catch (e) { return null }
  if (!d || typeof d !== "object") return null
  function files(list, max) {
    var out = []
    if (!Array.isArray(list)) return out
    for (var i = 0; i < list.length && out.length < max; i++) {
      var f = list[i]
      if (!f || typeof f !== "object") continue
      out.push({
        name: clampText(f.name, 120),
        folder: clampText(f.folder, 120),
        size: Math.max(0, num(f.size, 0)),
        expected: Math.max(0, num(f.expected, 0)),
        speed: Math.max(0, num(f.speed, 0)),
        eta: num(f.eta, -1),
        idle: Math.max(0, num(f.idle, 0))
      })
    }
    return out
  }
  var speeds = []
  if (Array.isArray(d.speeds)) for (var i = 0; i < d.speeds.length && i < 120; i++) speeds.push(Math.max(0, num(d.speeds[i], 0)))
  var peers = []
  if (Array.isArray(d.peers)) for (var j = 0; j < d.peers.length && j < 4; j++) peers.push(clampText(d.peers[j], 48))
  return {
    live: d.live === true,
    peers: peers,
    speed: Math.max(0, num(d.speed, 0)),
    speeds: speeds,
    total: Math.max(0, Math.floor(num(d.total, 0))),
    done: Math.max(0, Math.floor(num(d.done, 0))),
    doneBytes: Math.max(0, num(d.doneBytes, 0)),
    fraction: num(d.fraction, -1),
    eta: num(d.eta, -1),
    sessionEnd: Math.max(0, num(d.sessionEnd, 0)),
    active: files(d.active, 6),
    stalled: files(d.stalled, 4),
    recent: files(d.recent, 8)
  }
}
