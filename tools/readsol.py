"""Read the fps_unlock plugin's live telemetry from outside the game.

The plugin writes a plain-text status file twice a second to the AIR
application storage directory (the same place the game keeps bvnsave*.json):

    %APPDATA%\\com.1212321.bvn.sports\\Local Store\\fps_unlock_status.txt

It mirrors the in-process state: GameConfig.FPS_GAME, stage.frameRate, the
measured real frame rate, SPEED_PLUS, IS_LOW_QUALITY, the unlock toggle and the
netplay suspension flag. A SharedObject copy (fps_unlock.sol, AMF3-encoded) is
written alongside it; this reader only reports its presence because AMF3 is not
worth parsing for the same values.

Usage: python readsol.py [path-to-status.txt]
"""
import os
import sys
import time


def default_path():
    return os.path.join(os.environ.get("APPDATA", ""),
                        "com.1212321.bvn.sports", "Local Store",
                        "fps_unlock_status.txt")


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else default_path()
    if not os.path.exists(path):
        print("NO TELEMETRY FILE: %s" % path)
        print("(plugin not loaded yet, or the game has not reached menu init)")
        sys.exit(1)
    data = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if "=" in line:
            k, v = line.split("=", 1)
            data[k] = v

    st = os.stat(path)
    age = time.time() - st.st_mtime
    print("file        : %s" % path)
    print("age         : %.1fs  (%s)" % (age, "LIVE" if age < 5 else "stale"))
    print("-" * 62)
    for k in ("version", "uptime_ms", "target", "engine_fps_game",
              "stage_framerate", "measured_fps", "speed_plus",
              "speed_plus_default", "is_low_quality", "unlocked",
              "netplay_suspended", "hud_visible"):
        if k in data:
            print("  %-20s = %s" % (k, data[k]))
    print("-" * 62)
    try:
        tgt = float(data["target"])
        eng = float(data["engine_fps_game"])
        stg = float(data["stage_framerate"])
        meas = float(data["measured_fps"])
        sp = float(data["speed_plus"])
    except (KeyError, ValueError):
        sys.exit(0)
    ok_engine = abs(eng - tgt) < 0.5
    ok_stage = abs(stg - tgt) < 0.5
    ok_sp = abs(sp - 30.0 / tgt) < 1e-6 if tgt else False
    print("engine==target   : %s" % ("OK" if ok_engine else "MISMATCH"))
    print("stage ==target   : %s" % ("OK" if ok_stage else "MISMATCH"))
    print("speed+==30/target: %s  (%.10f vs %.10f)" % (
        "OK" if ok_sp else "MISMATCH", sp, 30.0 / tgt if tgt else -1))
    print("measured/target  : %.1f / %.0f = %.0f%%" % (
        meas, tgt, 100.0 * meas / tgt if tgt else 0))
    if data.get("netplay_suspended") == "true":
        print("NOTE: netplay active - unlock correctly suspended")
