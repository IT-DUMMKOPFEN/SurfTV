#!/usr/bin/env python3
"""Watches Pluto TV playlists for some minutes and prints every break (discontinuity)."""
import json, re, time, urllib.request, urllib.parse
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
def get(u):
    r = urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=30)
    return r.geturl(), r.read().decode("utf-8", "replace")
pl = [s["url"] for s in json.loads(get("https://iptv-org.github.io/api/streams.json")[1]) if "jmp2.uk/plu-" in (s.get("url") or "")]
watch = []
for u in pl[:6]:
    try:
        final, master = get(u)
        lines = [l for l in master.splitlines() if l and not l.startswith("#")]
        audio = re.search(r'TYPE=AUDIO[^\n]*URI="([^"]+)"', master)
        watch.append((u, urllib.parse.urljoin(final, lines[0]), urllib.parse.urljoin(final, audio.group(1)) if audio else None))
    except Exception as e:
        print("err", e)
seen = {}
end = time.time() + 540
while time.time() < end:
    for u, v, a in watch:
        for kind, m in (("video", v), ("audio", a)):
            if not m: continue
            try:
                mf, txt = get(m)
            except Exception as e:
                print(kind, "err", e); continue
            ls = txt.splitlines()
            ds = int(next((l.split(":")[1] for l in ls if l.startswith("#EXT-X-DISCONTINUITY-SEQUENCE")), "0"))
            tags = [i for i, l in enumerate(ls) if l == "#EXT-X-DISCONTINUITY"]
            key = (u, kind)
            sig = (ds, len(tags))
            if seen.get(key) != sig:
                seen[key] = sig
                if tags:
                    print(f"\n{time.strftime('%H:%M:%S')} {u[-28:]} {kind} disc-seq={ds} tags={len(tags)}")
                    for l in ls[4:]:
                        if l.startswith("#EXTINF") or l.startswith("#EXT-X-DISC") or not l.startswith("#"):
                            print("   ", re.sub(r"\?.*", "", l)[-110:])
    time.sleep(5)
