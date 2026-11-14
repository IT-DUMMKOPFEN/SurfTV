#!/usr/bin/env python3
"""Prints how Pluto TV HLS playlists look (ads, bumpers, discontinuities)."""
import json, re, time, urllib.request, urllib.parse, collections
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
def get(u):
    r = urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=30)
    return r.geturl(), r.read().decode("utf-8", "replace")
pl = []
for s in json.loads(get("https://iptv-org.github.io/api/streams.json")[1]):
    if "pluto" in (s.get("url") or "").lower() or "pluto" in (s.get("title") or "").lower():
        pl.append(s["url"])
m3u = get("https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8")[1]
pl += [l.strip() for l in m3u.splitlines() if "pluto" in l.lower() and not l.startswith("#")]
for c in json.loads(get("https://raw.githubusercontent.com/famelack/famelack-channels/main/tv/categories/all.json")[1]):
    for s in (c.get("sources") or {}).get("streams") or []:
        if "pluto" in s.lower() or "pluto" in (c.get("name") or "").lower():
            pl.append(s)
print("sample urls:", pl[:6])
print("pluto streams in iptv-org:", len(pl))
for u in pl[:3]:
    print("\n=== ", u[:140])
    try:
        final, master = get(u)
        print("final:", final[:140])
        print("\n".join(master.splitlines()[:12]))
        lines = [l for l in master.splitlines() if l and not l.startswith("#")]
        media = urllib.parse.urljoin(final, lines[0]) if lines else final
        for rnd in range(3):
            mf, m = get(media)
            ls = m.splitlines()
            segs = [l for l in ls if l and not l.startswith("#")]
            hosts = collections.Counter(urllib.parse.urlsplit(urllib.parse.urljoin(mf, s)).netloc for s in segs)
            print(f"-- media round {rnd}: {len(segs)} segs, discont={sum(1 for l in ls if l.startswith('#EXT-X-DISCONTINUITY'))}, hosts={dict(hosts)}")
            for l in ls[:6]: print("   ", l[:160])
            # show context around discontinuities
            for i, l in enumerate(ls):
                if l.startswith("#EXT-X-DISCONTINUITY") and not l.startswith("#EXT-X-DISCONTINUITY-SEQ"):
                    for k in range(max(0, i-2), min(len(ls), i+4)):
                        print("   |", ls[k][:200])
                    print("   ---")
            paths = collections.Counter(re.sub(r"[0-9]+", "N", urllib.parse.urlsplit(urllib.parse.urljoin(mf, s)).path)[:90] for s in segs)
            for p, n in paths.most_common(8): print("    path", n, p)
            time.sleep(8)
    except Exception as e:
        print("error", e)
