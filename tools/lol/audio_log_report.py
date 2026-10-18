"""[juice] Summarise a run's `--audiolog` output (lines: "AUDIO <time> <event> <tag>") by sound family.
Usage: python tools/lol/audio_log_report.py tools/extracted/sim.log
"""
import collections
import re
import sys

fam = collections.OrderedDict([
    ("announcer", r"Play_vo_Announcer"), ("champion vo", r"Play_vo_"), ("basic attack cast", r"BasicAttack\d?_OnCast|CritAttack_OnCast"),
    ("basic attack hit", r"BasicAttack\d?_OnHit|CritAttack_OnHit"), ("minion", r"HA_(Order|Chaos)Minion"),
    ("turret", r"Turret"), ("structure death", r"_break0|inhibitor_death|EoG_|Shatter"), ("gold", r"Gold"),
    ("level up", r"levelup"), ("respawn/death", r"Respawn|Death"), ("summoner", r"Summoner"), ("relic", r"healthpickup"),
    ("wave spawn", r"MinionsSpawn"), ("spell (other sfx)", r"Play_sfx_[A-Za-z]+_"),
])
cnt = collections.Counter()
ev = collections.Counter()
rows = []
for line in open(sys.argv[1], encoding="utf-8", errors="ignore"):
    m = re.match(r"AUDIO\s+([\d.]+)\s+(\S+)\s*(.*)", line)
    if not m:
        continue
    t, e, tag = float(m.group(1)), m.group(2), m.group(3)
    ev[e] += 1
    rows.append((t, e, tag))
    for k, rx in fam.items():
        if re.search(rx, e):
            cnt[k] += 1
            break
print("total events", sum(ev.values()), "distinct", len(ev))
for k in fam:
    print("  %-20s %d" % (k, cnt[k]))
print("announcer timeline:")
for t, e, tag in rows:
    if "announcer" in tag:
        print("  %7.2f %s %s" % (t, e.replace("Play_vo_Announcer_", ""), tag))
