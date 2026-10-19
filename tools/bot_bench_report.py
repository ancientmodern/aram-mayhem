#!/usr/bin/env python3
"""[bot-diff] Summarise tools/bot_bench.sh logs: per pairing (higher level vs lower level) win rate, kills, damage, skillshot hit rate, dodge rate."""
import glob, json, os, sys, collections

d = sys.argv[1] if len(sys.argv) > 1 else "tools/extracted/botdiff/bench"
runs = []
for f in sorted(glob.glob(os.path.join(d, "m_*.log"))):
    bench = None
    errs = 0
    for line in open(f, encoding="utf-8", errors="replace"):
        if line.startswith("BENCH "):
            bench = json.loads(line[6:])
        elif "SCRIPT ERROR" in line:
            errs += 1
    if bench is None:
        print("NO RESULT:", f)
        continue
    bench["errs"] = errs
    runs.append(bench)

# group by unordered pairing; "hi" = the higher level (mirror: team 0)
groups = collections.defaultdict(list)
for r in runs:
    lo, hi = sorted(r["levels"])
    groups[(hi, lo)].append(r)

NAMES = ["Intro", "Beginner", "Interm.", "Hard"]
def side(r, lvl, first_hi=True):
    """index of the team playing level `lvl` (for mirrors: team 0 is 'hi')."""
    lv = r["levels"]
    if lv[0] == lv[1]:
        return 0 if first_hi else 1
    return lv.index(lvl)

def pct(a, b):
    return 100.0 * a / b if b else 0.0

print()
print("%-22s %3s %6s %5s %8s %8s %8s %8s %8s %8s %6s" % ("pairing (hi vs lo)", "n", "hi win", "draw", "kills hi", "kills lo", "dmg hi", "dmg lo", "shot% hi", "shot% lo", "time"))
for (hi, lo), rs in sorted(groups.items(), reverse=True):
    n = len(rs)
    wins = draws = 0
    nexus = 0
    k = [0, 0]; dm = [0.0, 0.0]; sh = [0, 0]; shh = [0, 0]; th = [0, 0]; dg = [0, 0]; cs = [0, 0]; gold = [0.0, 0.0]; casts = [0, 0]; struct = [0, 0]
    t = 0.0
    for r in rs:
        ih = side(r, hi)
        il = 1 - ih
        if r["winner"] == -1:
            draws += 1
        elif r["winner"] == ih:
            wins += 1
        if r["decided"] == "nexus":
            nexus += 1
        t += r["time"]
        for j, idx in enumerate((ih, il)):
            tm = r["teams"][idx]
            k[j] += tm["kills"]; dm[j] += tm["dmg"]; sh[j] += tm["shots"]; shh[j] += tm["shot_hits"]
            th[j] += tm["threats"]; dg[j] += tm["dodges"]; cs[j] += tm["cs"]; gold[j] += tm["gold"]; casts[j] += tm["casts"]; struct[j] += tm["struct"]
    label = "%s(%d) vs %s(%d)" % (NAMES[hi], hi, NAMES[lo], lo)
    if hi == lo:
        label = "%s mirror (ORDER side)" % NAMES[hi]
    print("%-22s %3d %5.0f%% %5d %8.1f %8.1f %8.0f %8.0f %7.0f%% %7.0f%% %5.0fs" % (label, n, pct(wins + 0.5 * draws, n), draws,
          k[0] / n, k[1] / n, dm[0] / n, dm[1] / n, pct(shh[0], sh[0]), pct(shh[1], sh[1]), t / n))
print()
print("Per level (all runs, per team per match): skillshots launched at champions / hit%, sidestep rate of threatened shots, casts, kills, deaths-per-kill, CS, gold")
agg = collections.defaultdict(lambda: collections.Counter())
for r in runs:
    for idx in (0, 1):
        lv = r["levels"][idx]
        tm = r["teams"][idx]
        a = agg[lv]
        a["n"] += 1
        for key in ("kills", "deaths", "dmg", "cs", "gold", "casts", "summ", "shots", "shot_hits", "threats", "dodges", "hits_taken", "items"):
            a[key] += tm[key]
print("%-12s %4s %7s %7s %8s %8s %7s %7s %7s %7s %7s" % ("level", "n", "shots", "hit%", "threats", "dodge%", "evade%", "casts", "kills", "deaths", "gold"))
for lv in sorted(agg):
    a = agg[lv]; n = a["n"]
    evade = 100.0 - pct(a["hits_taken"], a["threats"]) if a["threats"] else 0.0
    print("%-12s %4d %7.1f %6.0f%% %8.1f %7.0f%% %7.0f%% %7.1f %7.1f %7.1f %7.0f" % ("%s(%d)" % (NAMES[lv], lv), n, a["shots"] / n, pct(a["shot_hits"], a["shots"]),
          a["threats"] / n, pct(a["dodges"], a["threats"]), max(evade, 0.0), a["casts"] / n, a["kills"] / n, a["deaths"] / n, a["gold"] / n))
errs = sum(r["errs"] for r in runs)
print("\nmatches: %d, script errors in logs: %d" % (len(runs), errs))
