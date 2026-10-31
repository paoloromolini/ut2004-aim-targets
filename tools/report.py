#!/usr/bin/env python3
"""Progress report for the Aim Targets mod.

Reads the round history that the mod saves in System/AimTargets.ini and writes
a self-contained HTML page (no internet needed) with charts, a verdict per mode
("improving / stable / declining") and the last rounds.

usage: report.py [AimTargets.ini] [output.html]
"""
import html
import sys
from collections import OrderedDict
from datetime import datetime

INI = sys.argv[1] if len(sys.argv) > 1 else "/mnt/c/UnrealTournament2004/System/AimTargets.ini"
OUT = sys.argv[2] if len(sys.argv) > 2 else "AimTargetsReport.html"

MODES = ["FLICK", "STRAFE", "SNIPER", "CHASE"]
MODE_INFO = {
    "FLICK": "static targets - reaction and first-shot precision",
    "STRAFE": "strafing targets - tracking while you move",
    "SNIPER": "far, small targets - Lightning Gun precision",
    "CHASE": "targets fly at you, level after level: more of them, faster, more zig-zag",
}
MIN_ROUNDS = 6      # rounds needed before giving a verdict
WINDOW = 5          # rounds compared (last N vs the N before)


def read_history(path):
    rows = []
    try:
        lines = open(path, encoding="latin-1").read().splitlines()
    except OSError:
        return rows
    for line in lines:
        line = line.strip()
        if not line.startswith("History="):
            continue
        f = line[len("History="):].strip().strip('"').split("|")
        if len(f) < 13:
            continue
        try:
            rows.append({
                "date": datetime.strptime(f[0], "%Y-%m-%d %H:%M"),
                "mode": f[1],
                "diff": float(f[2]),
                "score": int(f[3]),
                "acc": int(f[4]),
                "ms": int(f[5]),
                "hit": int(f[6]),
                "expired": int(f[7]),
                "moving": int(f[8]),
                "streak": int(f[9]),
                "bull": int(f[10]),
                "combo": int(f[11]),
                "shots": int(f[12]),
                # Added later: older history lines do not have them.
                "dtouch": int(f[13]) if len(f) > 13 else 0,
                "dstill": int(f[14]) if len(f) > 14 else 0,
            })
        except ValueError:
            continue
    return rows


def avg(xs):
    return sum(xs) / len(xs) if xs else 0.0


def moving_average(xs, w=WINDOW):
    out = []
    for i in range(len(xs)):
        part = xs[max(0, i - w + 1): i + 1]
        out.append(avg(part))
    return out


def chart(values, title, unit="", color="#4fc3f7", lower_is_better=False):
    """Small SVG line chart with a moving average."""
    w, h, pl, pr, pt, pb = 380, 130, 42, 10, 22, 18
    if not values:
        return ""
    lo, hi = min(values), max(values)
    if hi == lo:
        hi, lo = hi + 1, lo - 1
    pad = (hi - lo) * 0.08
    lo, hi = lo - pad, hi + pad
    n = len(values)

    def x(i):
        return pl + (w - pl - pr) * (i / (n - 1) if n > 1 else 0.5)

    def y(v):
        return pt + (h - pt - pb) * (1 - (v - lo) / (hi - lo))

    pts = " ".join(f"{x(i):.1f},{y(v):.1f}" for i, v in enumerate(values))
    ma = moving_average(values)
    mpts = " ".join(f"{x(i):.1f},{y(v):.1f}" for i, v in enumerate(ma))
    dots = "".join(f'<circle cx="{x(i):.1f}" cy="{y(v):.1f}" r="2.5" fill="{color}" opacity="0.75"/>'
                   for i, v in enumerate(values))
    note = "lower is better" if lower_is_better else "higher is better"
    return (
        f'<svg viewBox="0 0 {w} {h}" class="chart" role="img" aria-label="{html.escape(title)}">'
        f'<text x="{pl}" y="14" class="ct">{html.escape(title)} <tspan class="cn">({note})</tspan></text>'
        f'<line x1="{pl}" y1="{y(lo + pad):.1f}" x2="{w - pr}" y2="{y(lo + pad):.1f}" class="grid"/>'
        f'<line x1="{pl}" y1="{y(hi - pad):.1f}" x2="{w - pr}" y2="{y(hi - pad):.1f}" class="grid"/>'
        f'<text x="{pl - 4}" y="{y(hi - pad) + 4:.1f}" class="ax" text-anchor="end">{hi - pad:.0f}{unit}</text>'
        f'<text x="{pl - 4}" y="{y(lo + pad) + 4:.1f}" class="ax" text-anchor="end">{lo + pad:.0f}{unit}</text>'
        f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="1" opacity="0.4"/>'
        f'{dots}'
        f'<polyline points="{mpts}" fill="none" stroke="#ffd54f" stroke-width="2.2"/>'
        f'<text x="{w - pr}" y="{h - 4}" class="ax" text-anchor="end">round {n}</text>'
        f'<text x="{pl}" y="{h - 4}" class="ax">round 1</text>'
        f'</svg>'
    )


def verdict(rows):
    """Compare the last WINDOW rounds with the WINDOW before them."""
    n = len(rows)
    if n < MIN_ROUNDS:
        return ("Not enough data", "neutral",
                f"{n} round(s) played: play at least {MIN_ROUNDS} rounds of this mode to see a trend.")
    k = min(WINDOW, n // 2)
    recent, before = rows[-k:], rows[-2 * k:-k]

    def delta(key):
        a, b = avg([r[key] for r in recent]), avg([r[key] for r in before])
        return a, b, a - b

    sa, sb, sd = delta("score")
    aa, ab, ad = delta("acc")
    ma_, mb, md = delta("ms")
    da, db, dd = delta("diff")

    score_pct = (sd / sb * 100) if sb else 0
    ms_pct = (md / mb * 100) if mb else 0

    chase = rows[-1]["mode"] == "CHASE"
    if chase:
        # The level rises by itself, so the score always grows and accuracy drops a
        # little at every level: judge accuracy per level and ignore the score.
        score_pct = 0
        ad = ad + 2 * dd

    good = (score_pct >= 5) + (ad >= 3) + (ms_pct <= -5) + (dd >= 0.5)
    bad = (score_pct <= -5) + (ad <= -3) + (ms_pct >= 5) + (dd <= -0.5)

    if good >= 2 and good > bad:
        label, cls = "Improving", "good"
    elif bad >= 2 and bad > good:
        label, cls = "Declining", "bad"
    else:
        label, cls = "Stable", "neutral"

    parts = [] if chase else [f"score {sb:.0f} -> {sa:.0f} ({score_pct:+.0f}%)"]
    parts.append(f"accuracy {ab:.0f}% -> {aa:.0f}%")
    if ma_ > 0 and mb > 0:
        parts.append(f"time to kill a target {mb:.0f} -> {ma_:.0f} ms ({ms_pct:+.0f}%)")
    parts.append(f"{'level' if chase else 'difficulty'} {db:.1f} -> {da:.1f}")
    text = f"Last {k} rounds vs the {k} before: " + "; ".join(parts) + "."
    if chase and dd >= 1:
        text += " You reached higher levels: some loss of accuracy is expected, the verdict allows for it."
    elif dd >= 0.5 and score_pct < 5:
        text += " The game raised the difficulty, so flat scores can still mean progress."
    return (label, cls, text)


def daily_table(rows):
    days = OrderedDict()
    for r in rows:
        days.setdefault(r["date"].strftime("%Y-%m-%d"), []).append(r)
    out = ["<table><tr><th>Day</th><th>Rounds</th><th>Avg accuracy</th><th>Avg level</th>"
           "<th>Shots while moving</th><th>Best streak</th><th>Deaths</th></tr>"]
    for d, rs in list(days.items())[::-1][:30]:
        out.append(
            f"<tr><td>{d}</td><td>{len(rs)}</td><td>{avg([r['acc'] for r in rs]):.0f}%</td>"
            f"<td>{avg([r['diff'] for r in rs]):.1f}</td>"
            f"<td>{avg([r['moving'] for r in rs]):.0f}%</td>"
            f"<td>{max(r['streak'] for r in rs)}</td>"
            f"<td>{sum(r['dtouch'] + r['dstill'] for r in rs)}</td></tr>"
        )
    out.append("</table>")
    return "".join(out)


def rounds_table(rows):
    out = ["<table><tr><th>Date</th><th>Mode</th><th>Level</th><th>Score</th><th>Accuracy</th>"
           "<th>ms / kill</th><th>Hit</th><th>Moving</th><th>Streak</th>"
           "<th>Bullseyes</th><th>Combos</th><th>Deaths</th></tr>"]
    for r in rows[::-1][:40]:
        out.append(
            f"<tr><td>{r['date'].strftime('%Y-%m-%d %H:%M')}</td><td>{r['mode']}</td><td>{r['diff']:g}</td>"
            f"<td>{r['score']}</td><td>{r['acc']}%</td><td>{r['ms'] or '-'}</td><td>{r['hit']}</td>"
            f"<td>{r['moving']}%</td><td>{r['streak']}</td>"
            f"<td>{r['bull']}</td><td>{r['combo']}</td>"
            f"<td>{r['dtouch'] + r['dstill'] or '-'}</td></tr>"
        )
    out.append("</table>")
    return "".join(out)


CSS = """
body{background:#14161a;color:#e6e6e6;font:15px/1.5 system-ui,Segoe UI,Arial,sans-serif;margin:0;padding:24px;max-width:1180px;margin:auto}
h1{margin:0 0 4px;font-size:26px} h2{margin:34px 0 4px;font-size:20px;border-bottom:1px solid #2c3038;padding-bottom:6px}
.sub{color:#9aa0a8;margin:0 0 18px} .card{background:#1c1f25;border:1px solid #2c3038;border-radius:10px;padding:14px 16px;margin:12px 0}
.badge{display:inline-block;padding:2px 12px;border-radius:12px;font-weight:600;margin-right:8px}
.good{background:#1f5f35;color:#9ff0b5}.bad{background:#6a2424;color:#ffb3b3}.neutral{background:#3a3f48;color:#d0d4da}
.charts{display:flex;flex-wrap:wrap;gap:12px;margin-top:10px}.chart{width:380px;max-width:100%;background:#181b20;border-radius:8px}
.ct{fill:#e6e6e6;font-size:11px;font-weight:600}.cn{fill:#8a9099;font-weight:400}.ax{fill:#8a9099;font-size:9px}.grid{stroke:#2c3038;stroke-width:1}
table{border-collapse:collapse;width:100%;font-size:13px;margin-top:8px}th,td{padding:5px 8px;text-align:right;border-bottom:1px solid #262a31}
th:first-child,td:first-child,th:nth-child(2),td:nth-child(2){text-align:left}th{color:#9aa0a8;font-weight:600}
.legend{color:#9aa0a8;font-size:13px} .y{color:#ffd54f}
"""


def build(rows):
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    parts = [f"<!doctype html><html><head><meta charset='utf-8'><title>Aim Targets - progress</title>"
             f"<style>{CSS}</style></head><body>",
             "<h1>Aim Targets - progress report</h1>"]
    if not rows:
        parts.append(f"<p class='sub'>Generated {now}</p><div class='card'>No rounds recorded yet. "
                     "Play a few rounds (the history starts with the version that saves it), "
                     "then run the report again.</div></body></html>")
        return "".join(parts)

    first, last = rows[0]["date"], rows[-1]["date"]
    days = len({r["date"].date() for r in rows})
    parts.append(f"<p class='sub'>Generated {now} - {len(rows)} rounds on {days} day(s), "
                 f"from {first:%Y-%m-%d} to {last:%Y-%m-%d}</p>")
    parts.append("<p class='legend'>In the charts the dots are single rounds and the "
                 "<span class='y'>yellow line</span> is the average of the last 5 rounds.</p>")

    for m in MODES:
        rs = [r for r in rows if r["mode"] == m]
        parts.append(f"<h2>{m.title()} <span class='sub'>- {MODE_INFO[m]}</span></h2>")
        if not rs:
            parts.append("<div class='card'>No rounds yet.</div>")
            continue
        label, cls, text = verdict(rs)
        best = max(r["score"] for r in rs)
        parts.append(
            f"<div class='card'><span class='badge {cls}'>{label}</span> "
            f"{len(rs)} rounds, best score {best}, {'highest level ' + format(max(r['diff'] for r in rs), 'g') if m == 'CHASE' else 'current difficulty ' + format(rs[-1]['diff'], '.1f')}."
            f"<br><span class='sub'>{html.escape(text)}</span><div class='charts'>"
            + chart([r["score"] for r in rs], "Score", color="#4fc3f7")
            + chart([r["acc"] for r in rs], "Accuracy", "%", color="#81c784")
            + chart([r["ms"] for r in rs if r["ms"] > 0], "Time to kill a target" if m == "CHASE" else "Time per target", " ms",
                    color="#ff8a65", lower_is_better=True)
            + chart([r["diff"] for r in rs], "Level" if m == "CHASE" else "Difficulty", color="#ba68c8")
            + chart([r["moving"] for r in rs], "Shots while moving", "%", color="#4db6ac")
            + (chart([r["dtouch"] + r["dstill"] for r in rs], "Deaths per round", color="#e57373",
                     lower_is_better=True)
               if any(r["dtouch"] + r["dstill"] for r in rs) else "")
            + "</div></div>"
        )

    parts.append("<h2>Day by day</h2>" + daily_table(rows))
    parts.append("<h2>Last rounds</h2>" + rounds_table(rows))
    parts.append("</body></html>")
    return "".join(parts)


if __name__ == "__main__":
    data = read_history(INI)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(build(data))
    print(f"{len(data)} rounds -> {OUT}")
