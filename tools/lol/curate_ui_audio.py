"""Copy the curated set of League client UI sounds into assets/audio/ui/.

Source: a directory produced by `python tools/lol/extract_client_audio.py <dir>` (every client .ogg recovered from
the Plugins/rcp-fe-* WADs). The list below is every sound the game's menus / HUD hooks use, taken from how the real
client wires them (rcp-fe-lol-uikit sound map, champ-select, postgame, parties bundles).
Then run tools/lol/ui_audio_gain.py to measure them (data/audio/ui_gain.json) and `godot --headless --import`.

Usage: python tools/lol/curate_ui_audio.py <extract_dir>
"""
import os
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DST = os.path.join(ROOT, "assets", "audio", "ui")

NAMES = """
sfx-celebrate-notif-intro sfx-celebrate-receive-generic sfx-champ-select-bench-update
sfx-cs-aram-card-2-appear sfx-cs-aram-card-3-appear sfx-cs-aram-card-hover sfx-cs-aram-card-select
sfx-cs-button-reroll-click sfx-cs-button-reroll-hover sfx-cs-button-swap-click sfx-cs-button-thumbnail-click
sfx-cs-champgrid-button-close sfx-cs-champgrid-button-open sfx-cs-draft-ban-button-hover
sfx-cs-draft-notif-yourpick sfx-cs-draft-pick-intro sfx-cs-lockin-button-click sfx-cs-lockin-button-hover
sfx-cs-notif-boost-unlocked sfx-cs-notif-swaprequest-accepted sfx-cs-notif-swaprequest-declined
sfx-cs-notif-swaprequest-rcvd sfx-cs-spells-open sfx-cs-splash-back sfx-cs-splash-forward
sfx-cs-timer-tick sfx-cs-timer-tick-small sfx-cs-ward-select
sfx-eog-chaos-order sfx-eog-ui-edge-flare sfx-eog-ui-exp-burst sfx-eog-ui-exp-burst-negative
sfx-eog-ui-neutral-burst sfx-gameselect-button-confirm-click sfx-gameselect-button-confirm-hover
sfx-gameselect-trans-to-lobby sfx-honor-scoreboard-team-choice sfx-honor-vote-cast sfx-honor-voting-intro
sfx-levelup-postgame-generic sfx-lobby-button-find-match-click sfx-lobby-button-find-match-hover
sfx-lobby-button-quit-click sfx-lobby-button-quit-hover sfx-lobby-trans-to-gameselect
sfx-nav-button-play-click sfx-nav-button-play-hover sfx-nav-button-text-click
sfx-purchase-button-click sfx-purchase-button-hover
sfx-readycheck-accept-button-click sfx-readycheck-accept-button-hover sfx-readycheck-decline-button-click
sfx-readycheck-ringmagic-countdown
sfx-soc-notif-chat-rcvd sfx-soc-ui-click-generic sfx-soc-ui-drag sfx-soc-ui-drop
sfx-ui-jade-buttonlocked sfx-ui-jade-buttonpress sfx-ui-jade-buttonpress-1 sfx-ui-jade-champselect-browse-skins
sfx-ui-jade-champselect-countdown-single sfx-ui-jade-champselect-countdown10 sfx-ui-jade-champselect-exit
sfx-ui-jade-champselect-lockchampion sfx-ui-jade-champselect-lockchampion-confirmed
sfx-ui-jade-champselect-yourturn sfx-ui-jade-chat-message-receive sfx-ui-jade-match-accept
sfx-ui-jade-match-decline sfx-ui-jade-openstore
sfx-uikit-arrow-button-click sfx-uikit-arrow-button-hover sfx-uikit-button-arrowback-click
sfx-uikit-button-arrowfwd-click sfx-uikit-button-big-click sfx-uikit-button-circlegold-click
sfx-uikit-button-circlegold-hover sfx-uikit-button-circlex-click sfx-uikit-button-flyout-close-click
sfx-uikit-button-flyout-open-click sfx-uikit-button-generic-click sfx-uikit-button-generic-hover
sfx-uikit-button-gold-click sfx-uikit-button-gold-hover sfx-uikit-button-locked-click
sfx-uikit-button-pageup-click sfx-uikit-button-pip-click sfx-uikit-button-replay-click
sfx-uikit-button-text-click sfx-uikit-checkbox-click sfx-uikit-click-and-slide sfx-uikit-click-generic
sfx-uikit-consolation-stinger sfx-uikit-drag sfx-uikit-drop sfx-uikit-dropdown-click
sfx-uikit-dropdown-select sfx-uikit-edit-click sfx-uikit-framed-icon-click sfx-uikit-generic-click-big
sfx-uikit-generic-click-small sfx-uikit-grid-big-click sfx-uikit-grid-big-hover sfx-uikit-grid-click
sfx-uikit-grid-click-release sfx-uikit-grid-drag sfx-uikit-grid-hover sfx-uikit-magic-button-click
sfx-uikit-magic-button-hover sfx-uikit-radio-click sfx-uikit-reward-toast sfx-uikit-text-click-small
sfx-vc-volume-bar-click sfx-vc-volume-scroll-click sfx-vc-volume-scroll-release
sfx-vignette-celebration-intro sfx-vignette-celebration-outro
""".split()


def main():
    src = sys.argv[1]
    os.makedirs(DST, exist_ok=True)
    miss = []
    new = 0
    for n in NAMES:
        s = os.path.join(src, n + ".ogg")
        d = os.path.join(DST, n + ".ogg")
        if not os.path.exists(s):
            miss.append(n)
            continue
        if not os.path.exists(d):
            shutil.copyfile(s, d)
            new += 1
    print(len(NAMES), "wanted,", new, "copied,", len(miss), "missing", miss)


if __name__ == "__main__":
    main()
