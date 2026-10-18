"""[juice] Extract League's key-moment particle systems (respawn, bounty gold, global hit/crit, turret/nexus death...)
from Global.wad.client + Map12.wad.client into data/vfx/moments.json (+ textures/meshes under assets/vfx/).

Re-uses tools/lol/extract_vfx.py (imported, not modified) so the emitter format is identical to shared.json and
loads with LolVfx.load_set("moments").

Usage: python tools/lol/extract_moments.py            (extract)
       python tools/lol/extract_moments.py --list     (print the matched system names only)
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extract_vfx as ev  # noqa: E402
from binfile import BinFile, to_py  # noqa: E402
from vfx_names import TABLE  # noqa: E402

PATTERNS = [
    r"^HA_Respawn$", r"^HA_Spawn$",
    r"^ChampBountyGet_", r"^Gold_Shower", r"^Perks_Looter_Gold", r"^Perks_FirstStrike_GoldReward$",
    r"^globalhit_", r"^Jade_GlobalHit_", r"^6029_Hit_Tar_Crit$", r"^6676_Execute_Tar$", r"^HitEffect_Physical_S_01$",
    r"^Damage_Tar$", r"^BloodSlash$", r"^Shield_Break$",
    r"^SRU_(Order|Chaos)_Turret1_Explode$", r"^SRU_(Order|Chaos)Turret1_(break\d|Rubble|Rubble_dust)$",
    r"^SRU_(Order|Chaos)Turret_onHit_dust$", r"^DestroyedExplosion_Chaos$",
    r"^HA_AP_(Order|Chaos)_Turret_Shatter_0[123]$", r"^HA_(Order|Chaos)_Turret_Weapon_Glow$",
    r"^SRU_Chaos_Inhibitor_Explosion$", r"^Confetti$", r"^Recall_Honor_Teleport", r"^Recall_Challenger_2022_Teleport",
    r"^Teleport_Arrival$", r"^TeleportHome$", r"^Turret_Nexus_RespawnTimer$",
    r"^HA_(Order|Chaos)_Nexus_", r"^HA_(Order|Chaos)_Inhibitor_",
    r"^Chaos_Nexus", r"^Crepe_Order_Nexus_",
    r"^PreSeason_Turret_Shield_",
]


def main():
    pats = [re.compile(p) for p in PATTERNS]
    out = {}
    names = {}
    ctx = {"resolve": lambda k: None}
    for wn in ("Global.wad.client", "Maps/Shipping/Map12.wad.client"):
        w = ev.wad(f"{ev.GAME}/{wn}")
        es = w.entries.values() if isinstance(w.entries, dict) else w.entries
        for e in es:
            if e.size > 30_000_000:
                continue
            try:
                d = w.read_entry(e)
            except Exception:
                continue
            if d[:4] not in (b"PROP", b"PTCH"):
                continue
            try:
                bf = BinFile(d)
            except Exception:
                continue
            for k, v in bf.entries.items():
                if v.cls != 0x45cd899f:
                    continue
                nm = None
                for fk, fv in v.fields.items():
                    if TABLE.get(fk) == "particleName":
                        nm = fv
                if not nm or nm in out or nm in names or not any(p.search(nm) for p in pats):
                    continue
                names[nm] = wn
                if "--list" in sys.argv:
                    continue
                name, sysd = ev.system(w, to_py(v, TABLE), ctx)
                if sysd is not None:
                    out[name] = sysd
    if "--list" in sys.argv:
        for n in sorted(names):
            print(n, names[n])
        return
    path = os.path.join(ev.ROOT, "data", "vfx", "moments.json")
    json.dump(out, open(path, "w", encoding="utf-8"), separators=(",", ":"))
    print(f"moments: {len(out)} systems")
    for n in sorted(out):
        print("  ", n, round(out[n].get("dur", 0), 2), len(out[n]["emitters"]))


if __name__ == "__main__":
    main()
