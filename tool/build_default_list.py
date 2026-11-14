#!/usr/bin/env python3
"""
Builds the channel list that ships with SlaxxTV (assets/channels_default.json),
so the app has channels on the very first start.

Same logic as the in-app channel search (lib/channel_scanner.dart):
downloads iptv-org + Free-TV, tests every stream, keeps the working ones.
Used by GitHub Actions before building the apps.

    python3 tool/build_default_list.py [output.json]
"""
import concurrent.futures as cf
import datetime
import json
from html import unescape
import pathlib
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "https://iptv-org.github.io/api"
# Categories SlaxxTV shows as filters.
CATS = {"movies", "series", "documentary", "news", "music"}
FREE_TV = "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")
OUT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else
                   pathlib.Path(__file__).resolve().parent.parent / "assets" / "channels_default.json")


def get(url, timeout=90):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def iptv_org(countries):
    for c in json.loads(get(f"{API}/countries.json")):
        countries[c["code"].upper()] = c["name"]
    info = {c["id"]: c for c in json.loads(get(f"{API}/channels.json"))}
    blocked = {b["channel"] for b in json.loads(get(f"{API}/blocklist.json"))}
    logos = {}
    try:
        for l in json.loads(get(f"{API}/logos.json")):
            ch, url = l.get("channel"), l.get("url")
            if not ch or not url:
                continue
            if (l.get("format") or "").upper() == "SVG" or url.lower().endswith(".svg"):
                continue
            if ch not in logos or l.get("feed") is None:
                logos[ch] = url
    except Exception as e:
        print(f"logos failed: {e}")
    out = []
    for s in json.loads(get(f"{API}/streams.json")):
        url = (s.get("url") or "").strip()
        ch_id = s.get("channel")
        ch = info.get(ch_id) if ch_id else None
        if not url or (ch_id and ch_id in blocked):
            continue
        if ch and (ch.get("is_nsfw") or ch.get("closed")):
            continue
        labels = []
        if isinstance(s.get("label"), str):
            labels.append(s["label"])
        if isinstance(s.get("labels"), list):
            labels += [str(x) for x in s["labels"]]
        title = (s.get("title") or "").strip()
        name = title or (ch or {}).get("name") or ch_id or "Unknown"
        country = ((ch or {}).get("country") or "").upper()
        if not country and ch_id and "." in ch_id:
            country = ch_id.split(".")[-1].split("@")[0].upper()
        out.append({
            "n": name, "c": country or "XX", "u": url,
            "r": s.get("referrer"), "a": s.get("user_agent"), "q": s.get("quality"),
            "g": any("geo" in l.lower() for l in labels),
            "na": any("24/7" in l for l in labels),
            "s": "iptv-org",
            "k": [k for k in ((ch or {}).get("categories") or []) if k in CATS],
            "l": logos.get(ch_id) if ch_id else None,
            "i": ch_id,
        })
    return out


def attr(info, key):
    m = re.search(key + r'="([^"]*)"', info)
    return (m.group(1).strip() if m else "") or None


def free_tv():
    out, info = [], None
    for line in get(FREE_TV).splitlines():
        line = line.strip()
        if line.startswith("#EXTINF"):
            info = line
            continue
        if not line or line.startswith("#") or not info:
            continue
        url, inf, info = line, info, None
        low = url.lower()
        if is_youtube(url) or any(x in low for x in ("twitch.tv", "dailymotion.com")):
            continue   # cannot be played
        q = inf.rfind('",')
        name = inf[q + 2:] if q >= 0 else inf[inf.rfind(",") + 1:]
        geo, sd = "Ⓖ" in name, "Ⓢ" in name
        name = re.sub("[ⓎⓉⒹⓈⒼ]", "", name).strip() or attr(inf, "tvg-name") or "Unknown"
        country = (attr(inf, "tvg-country") or "").upper()
        out.append({"n": name, "c": country if len(country) == 2 else "XX", "u": url,
                    "i": attr(inf, "tvg-id"),
                    "q": "SD" if sd else None, "g": geo, "s": "Free-TV"})
    return out


def is_youtube(url):
    u = url.lower()
    return "youtube.com/" in u or "youtube-nocookie.com/" in u or "youtu.be/" in u


FAMELACK = "https://raw.githubusercontent.com/famelack/famelack-channels/main/tv/categories"


def famelack():
    """Famelack (ex tv.garden): first stream per channel (YouTube entries are left out)."""
    allc = json.loads(get(f"{FAMELACK}/all.json"))
    cat_of = {}
    for cat in CATS:
        try:
            for e in json.loads(get(f"{FAMELACK}/{cat}.json")):
                cat_of.setdefault(e.get("nanoid"), set()).add(cat)
        except Exception as e:
            print(f"famelack {cat} failed: {e}")
    out = []
    for m in allc:
        name = (m.get("name") or "Unknown").strip()
        cc = (m.get("country") or "").upper()
        cc = "UK" if cc == "GB" else cc
        cc = cc if len(cc) == 2 else "XX"
        src = m.get("sources") or {}
        cats = sorted(cat_of.get(m.get("nanoid"), set()))
        streams = [s for s in (src.get("streams") or []) if isinstance(s, str)]
        if streams:
            out.append({"n": name, "c": cc, "u": streams[0], "g": bool(m.get("isGeoBlocked")),
                        "s": "Famelack", "k": cats})
    return out


def freetuxtv():
    """FreetuxTV database: WebTV with status Working, all result pages."""
    out = []
    td_re = re.compile(r"<td[^>]*>(.*?)</td>", re.S)
    for page in range(1, 61):
        url = ("https://database.freetuxtv.net/WebStream/index"
               "?WebStreamSearchForm%5BType%5D=1&WebStreamSearchForm%5BStatus%5D=2"
               + (f"&WebStream_page={page}" if page > 1 else ""))
        html = get(url)
        rows = []
        for row in re.split(r"<tr[\s>]", html)[1:]:
            tds = td_re.findall(row)
            if len(tds) < 3:
                continue
            first = tds[0]
            hrefs = [unescape(h) for h in re.findall(r'href="((?:https?|rtmp|rtsp|mms)://[^"]+)"', first)
                     if "freetuxtv.net" not in h]
            if not hrefs:
                continue
            name = re.sub(r"<[^>]*>", "", re.split(r"<br\s*/?>|=&gt;|=>", first)[0])
            name = unescape(name).strip() or hrefs[0]
            m = re.search(r'alt="([^"]*)"', tds[2])
            cc = (m.group(1) if m else "").strip().upper()
            cc = "UK" if cc == "GB" else cc
            rows.append({"n": name, "c": cc if len(cc) == 2 else "XX", "u": hrefs[0], "s": "FreetuxTV"})
        if page == 1 and rows:
            print("freetuxtv sample:", rows[:3])
        out += rows
        if not rows or f"WebStream_page={page + 1}" not in html:
            break
    return out


def stream_path(url):
    """Host + path, lower-case host, no trailing slash, no default port."""
    try:
        u = urllib.parse.urlsplit(url.strip())
        path = u.path
        while len(path) > 1 and path.endswith("/"):
            path = path[:-1]
        port = f":{u.port}" if u.port and u.port not in (80, 443) else ""
        return f"{(u.hostname or '').lower()}{port}{path}", u.query
    except Exception:
        return url.strip().lower(), ""


def dedupe(chans):
    """Same rules as dedupeChannels() in lib/models.dart."""
    by_key, out = {}, []
    for c in chans:
        path, query = stream_path(c["u"])
        k1, k2 = f"{path}?{query}", f"{path}#{c['n'].strip().lower()}"
        hit = by_key.get(k1, by_key.get(k2))
        if hit is not None:
            kept = out[hit]
            if not kept.get("l") and c.get("l"):
                kept["l"] = c["l"]
            kept["k"] = sorted(set(kept.get("k") or []) | set(c.get("k") or []))
            kept["g"] = bool(kept.get("g") or c.get("g"))
            continue
        by_key[k1] = by_key[k2] = len(out)
        out.append(c)
    return out


def check(ch):
    """'ok', 'vpn' or 'dead' - same rules as the app."""
    url = ch["u"]
    if not url.lower().startswith(("http://", "https://")):
        return "ok"
    headers = {"User-Agent": ch.get("a") or UA}
    if ch.get("r"):
        headers["Referer"] = ch["r"]
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=8) as r:
            return "ok" if r.read(1024) else "dead"
    except urllib.error.HTTPError as e:
        return "vpn" if e.code in (401, 403, 451) else "dead"
    except Exception:
        return "dead"


def main():
    countries, seen, cands = {}, set(), []
    for name, fn in (("iptv-org", lambda: iptv_org(countries)), ("Free-TV", free_tv),
                     ("Famelack", famelack), ("FreetuxTV", freetuxtv)):
        try:
            items = fn()
        except Exception as e:  # keep going with the other source
            print(f"{name} failed: {e}")
            continue
        for c in items:
            if c["u"] not in seen:
                seen.add(c["u"])
                cands.append(c)
        print(f"{name}: {len(items)} streams")

    before = len(cands)
    cands = dedupe(cands)
    print(f"clean up: {before - len(cands)} duplicates removed")

    found = []
    with cf.ThreadPoolExecutor(max_workers=96) as ex:
        for i, (c, r) in enumerate(zip(cands, ex.map(check, cands)), 1):
            if r != "dead":
                if r == "vpn":
                    c["v"] = True
                found.append({k: v for k, v in c.items() if v not in (None, False, [])})
            if i % 1000 == 0:
                print(f"checked {i}/{len(cands)}, found {len(found)}")

    db = {"version": 1,
          "updated": datetime.datetime.now(datetime.timezone.utc).isoformat(),
          "countries": countries,
          "channels": found}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(db, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Wrote {len(found)} channels to {OUT}")


if __name__ == "__main__":
    main()
