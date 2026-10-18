"""Extract League's real item-shop UI sounds (and potion/elixir use cues) from the game's Wwise banks.

Source of truth (all in Maps/Shipping/Common.wad.client + Map12.wad.client, bank units of map12.bin):
  * HUD_Global         shop open/close/buy/sell/undo/tab/filter/quicktab/slot grab+drop events
  * MISC_Gameplay_SFX  Play_sfx_hud_base_store_item_with_debt
  * ITEMS_Global       potion / elixir use cues
Each event is resolved through the HIRC graph (event -> action -> sound/containers -> WEM ids), so an event gets
exactly the WEMs the game plays for it (random-container variants kept as separate files, cap 6).
Events can genuinely share a WEM (distinct sound objects pointing at one source); every event still gets its own
file so the map stays 1:1; sharing and empty events are printed in the report.

Output:
  assets/audio/ui/shop/<event_lower_without_play_sfx_prefix>_<n>.wav   mono 16-bit <=32 kHz (process_audio)
  data/audio/shop.json   {"events": {Event: [res://...wav]}, "actions": {action: Event}}

Usage: python tools/lol/extract_shop_audio.py
(then: python tools/lol/ui_audio_gain.py  and  godot --headless --path . --import)
"""
import glob
import json
import os
import shutil
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wad import Wad  # noqa: E402
from extract_game_audio import (GAME, ROOT, bank_units, convert, load_graph,  # noqa: E402
                                res_path)

OUT = os.path.join(ROOT, "assets", "audio", "ui", "shop")
OUT_JSON = os.path.join(ROOT, "data", "audio", "shop.json")
CAP = 6

UNITS = ("HUD_Global", "MISC_Gameplay_SFX", "ITEMS_Global")

EVENTS = """
Play_sfx_hud_Store_Buy Play_sfx_hud_Store_Close Play_sfx_hud_Store_Open Play_sfx_hud_Store_Sell
Play_sfx_hud_Store_Undo Play_sfx_hud_Store_Upgrade
Play_sfx_hud_base_Store_Click Play_sfx_hud_base_Store_Select Play_sfx_hud_base_Store_Undo
Play_sfx_hud_base_store_expand_open Play_sfx_hud_base_store_filter_invert
Play_sfx_hud_base_store_filter_remove Play_sfx_hud_base_store_filter_select
Play_sfx_hud_base_store_filter_stat_select Play_sfx_hud_base_store_generic_close
Play_sfx_hud_base_store_generic_open Play_sfx_hud_base_store_inventorytab_close
Play_sfx_hud_base_store_inventorytab_open Play_sfx_hud_base_store_item_buy_basic
Play_sfx_hud_base_store_item_buy_components Play_sfx_hud_base_store_item_buy_legendary
Play_sfx_hud_base_store_item_buy_mythic Play_sfx_hud_base_store_item_buy_upgrade
Play_sfx_hud_base_store_item_hover_blue Play_sfx_hud_base_store_item_hover_mythic
Play_sfx_hud_base_store_item_sell Play_sfx_hud_base_store_quicktab_close
Play_sfx_hud_base_store_quicktab_open Play_sfx_hud_base_store_quicktab_open_highlight
Play_sfx_hud_base_store_quicktab_pin Play_sfx_hud_base_store_rec_select
Play_sfx_hud_base_store_tab_select
Play_sfx_hud_base_item_slot_drop Play_sfx_hud_base_item_slot_grab
Play_sfx_hud_item_slot_drop Play_sfx_hud_item_slot_grab
Play_sfx_hud_base_store_item_with_debt Play_sfx_hud_objectivevote_click_deny
Play_sfx_Item2003_OnCast Play_sfx_Item2003_OnBuffActivate
Play_sfx_ItemCrystalFlask_OnCast Play_sfx_ItemCrystalFlask_OnBuffActivate
Play_sfx_ItemMiniRegenPotion_OnCast Play_sfx_ItemPoroSnack_OnCast
Play_sfx_ElixirOfIron_OnBuffCast Play_sfx_ElixirOfSorcery_OnBuffCast Play_sfx_ElixirOfWrath_OnBuffCast
""".split()

# shop action -> League event that plays for it.
# Mythic purchase: Play_sfx_hud_base_store_item_buy_mythic is an EMPTY Wwise container in HUD_Global (no sounds
# attached in this patch), so a mythic buy uses the legendary purchase cue.
ACTIONS = {
    "open": "Play_sfx_hud_base_store_generic_open",
    "close": "Play_sfx_hud_base_store_generic_close",
    "tab": "Play_sfx_hud_base_store_tab_select",
    "select": "Play_sfx_hud_base_Store_Select",
    "rec_select": "Play_sfx_hud_base_store_rec_select",
    "buy_basic": "Play_sfx_hud_base_store_item_buy_basic",
    "buy_components": "Play_sfx_hud_base_store_item_buy_components",
    "buy_legendary": "Play_sfx_hud_base_store_item_buy_legendary",
    "buy_upgrade": "Play_sfx_hud_base_store_item_buy_upgrade",
    "buy_mythic": "Play_sfx_hud_base_store_item_buy_legendary",
    "sell": "Play_sfx_hud_base_store_item_sell",
    "undo": "Play_sfx_hud_base_Store_Undo",
    "filter_class": "Play_sfx_hud_base_store_filter_select",
    "filter_stat": "Play_sfx_hud_base_store_filter_stat_select",
    "filter_remove": "Play_sfx_hud_base_store_filter_remove",
    "filter_invert": "Play_sfx_hud_base_store_filter_invert",
    "hover": "Play_sfx_hud_base_store_item_hover_blue",
    "hover_mythic": "Play_sfx_hud_base_store_item_hover_mythic",
    "quicktab_open": "Play_sfx_hud_base_store_quicktab_open",
    "quicktab_close": "Play_sfx_hud_base_store_quicktab_close",
    "quicktab_pin": "Play_sfx_hud_base_store_quicktab_pin",
    "quicktab_highlight": "Play_sfx_hud_base_store_quicktab_open_highlight",
    "inventory_open": "Play_sfx_hud_base_store_inventorytab_open",
    "inventory_close": "Play_sfx_hud_base_store_inventorytab_close",
    "expand": "Play_sfx_hud_base_store_expand_open",
    "slot_grab": "Play_sfx_hud_base_item_slot_grab",
    "slot_drop": "Play_sfx_hud_base_item_slot_drop",
    "debt": "Play_sfx_hud_base_store_item_with_debt",
    "deny": "Play_sfx_hud_objectivevote_click_deny",
    "potion": "Play_sfx_Item2003_OnCast",
    "potion_refill": "Play_sfx_ItemCrystalFlask_OnBuffActivate",
    "elixir": "Play_sfx_ElixirOfIron_OnBuffCast",
}


def out_name(ev):
    s = ev.lower()
    return s[len("play_sfx_"):] if s.startswith("play_sfx_") else s


def main():
    m12 = Wad(f"{GAME}/Maps/Shipping/Map12.wad.client")
    cm = Wad(f"{GAME}/Maps/Shipping/Common.wad.client")
    by = {}
    for u in bank_units(m12.read("data/maps/shipping/map12/map12.bin")):
        if u.name not in by or len(u.events) > len(by[u.name].events):
            by[u.name] = u
    paths = []
    for n in UNITS:
        paths += by[n].paths
    graph = load_graph([cm, m12], sorted(set(paths), key=str.lower), log=print)

    # remove previous output (stale mislabeled files from earlier runs)
    for f in glob.glob(os.path.join(OUT, "*.wav")) + glob.glob(os.path.join(OUT, "*.wav.import")):
        os.remove(f)
    os.makedirs(OUT, exist_ok=True)

    scratch = tempfile.mkdtemp(prefix="shop_audio_")
    jobs, plan = [], {}
    for ev in EVENTS:
        wems = graph.event_wems(ev)[:CAP]
        plan[ev] = []
        for i, wid in enumerate(wems):
            path = os.path.join(OUT, f"{out_name(ev)}_{i + 1}.wav")
            jobs.append((graph.media[wid], os.path.join(scratch, f"j{len(jobs)}"), path))
            plan[ev].append((wid, path))
    with ThreadPoolExecutor(8) as pool:
        durs = dict(zip((j[2] for j in jobs), pool.map(convert, jobs)))
    shutil.rmtree(scratch, ignore_errors=True)

    events, owner = {}, {}
    print(f"{'event':56s} n  dur(s)           wems")
    for ev in EVENTS:
        good = [(wid, p) for wid, p in plan[ev] if durs.get(p)]
        if not good:
            print(f"{ev:56s} 0  RESOLVES TO NOTHING")
            continue
        events[ev] = [res_path(p) for _w, p in good]
        for wid, _p in good:
            owner.setdefault(wid, []).append(ev)
        ds = "/".join(f"{durs[p]:.2f}" for _w, p in good)
        print(f"{ev:56s} {len(good)}  {ds:16s} {[w for w, _p in good]}")
    print("\nshared WEMs:")
    for wid, evs in owner.items():
        if len(evs) > 1:
            print(f"  {wid}: {', '.join(evs)}")
    for a, ev in ACTIONS.items():
        if ev not in events:
            print(f"WARNING action {a} -> {ev} has no sound")
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"events": events, "actions": ACTIONS}, f, indent=1)
        f.write("\n")
    print(f"wrote {OUT_JSON}: {len(events)} events, {sum(len(v) for v in events.values())} files")


if __name__ == "__main__":
    main()
