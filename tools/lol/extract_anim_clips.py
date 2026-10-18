"""Export the League animation-graph clips that the main character .glb leaves out (transition clips
such as Spell1_To_Idle / Attack1_ToRun, idle-in clips, unnamed graph clips) into a companion .glb:

    data/anim/clips/<alias>.glb      (tiny textures; only the missing animations)

Same skeleton/node layout as assets/.../<alias>.glb, so Assets merges its AnimationLibrary into the
model's AnimationPlayer as library "x" ("x/<clip>"). extract_anim.py records the names as "xanim".

Usage:  python extract_anim_clips.py [Alias ...]
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import export_character as ec  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "data", "anim", "clips")


def main():
    chars = sys.argv[1:] or ec.ROSTER
    os.makedirs(OUT, exist_ok=True)
    orig_add = ec.add_animation
    for ch in chars:
        main_json = os.path.splitext(ec.model_path(ch, 0))[0] + ".anims.json"
        have = set()
        if os.path.exists(main_json):
            have = set(json.load(open(main_json)).get("anims", []))
        added = []

        def filtered(gl, name, anm, joints, joint_nodes, hash_to_joint, _have=have, _added=added):
            if name in _have:
                return
            _added.append(name)
            orig_add(gl, name, anm, joints, joint_nodes, hash_to_joint)

        ec.add_animation = filtered
        out = os.path.join(OUT, ch.lower() + ".glb")
        try:
            ec.export(ch, 0, out, ec.open_wads(ch), max_tex=8, keep_unnamed=True, verbose=False,
                      skip_transitions=False)
        except Exception as ex:
            import traceback
            traceback.print_exc()
            print("!! failed", ch, ex)
            continue
        finally:
            ec.add_animation = orig_add
        side = os.path.splitext(out)[0] + ".anims.json"
        with open(side, "w", newline="\n") as f:
            json.dump({"anims": sorted(added)}, f, indent=1)
        print(f"{ch}: {len(added)} extra clips -> {os.path.getsize(out) / 1e6:.1f}MB")


if __name__ == "__main__":
    main()
