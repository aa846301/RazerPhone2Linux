"""Music intents for the hub (rules only; the LLM rewrite produces the same canonical forms, e.g. 「播放 輕音樂」).

parse(text) -> None if the sentence is not about music, else a dict:
  {"op": "play", "query": "七里香"}      search YouTube Music (Music Assistant) and play the first result
  {"op": "another"}                      play the next result of the last search ("換一個")
  {"op": "pause" | "resume" | "stop" | "next" | "previous" | "what"}
  {"op": "volume_step", "delta": +0.1}   {"op": "volume_set", "value": 0.3}
  {"op": "shuffle_on" | "shuffle_off"}   ; a play may carry "shuffle": True/False (「隨機播放我的爽歌清單」)
  A play whose query names one of the user's playlists plays that playlist (matched in the agent).
"""
import re

NUM = {"零": 0, "一": 1, "二": 2, "兩": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10}

PLAY = re.compile(r"^(?:請|幫我|麻煩)?(?:播放|播一下|播|放一下|放首|放一首|放|我想聽|想聽|聽一下|聽|來點|來一首|來首)(.+)$")
GENERIC = re.compile(r"^(?:音樂|歌|歌曲|一首歌|點音樂|些音樂|首歌)$")
TAIL = re.compile(r"(?:的歌|的音樂|這首歌|這首|一下|好嗎|好不好|吧|啦|喔|哦|囉)+$")


def _clean(s):
    return re.sub(r"[\s。，、！？!?,.「」『』\"']", "", s)


def _num(s):
    m = re.search(r"\d+", s)
    if m:
        return int(m.group())
    if "十" in s:
        a, _, b = s.partition("十")
        return (NUM.get(a[-1:], 1) if a else 1) * 10 + (NUM.get(b[:1], 0) if b else 0)
    for ch in s:
        if ch in NUM:
            return NUM[ch]
    return None


DEVICE_WORDS = re.compile(r"燈|冷氣|空調|窗簾|風扇|電扇|插座|開關|除濕|門鎖|溫度")


def parse(text, device_names=()):
    """device_names: the hub's device names; a "play X" whose X names a device is a device command
    (「放下窗簾」), not a song."""
    t = re.sub(r"^(?:嘿|欸|喂|那個|請問)+", "", _clean(text))
    if not t:
        return None
    if re.fullmatch(r"(?:換一個|換一首|換別的|換別首|不是這首|不是這個)(?:版本)?", t):
        return {"op": "another"}
    if re.fullmatch(r"(?:下一首|下首|跳過|切歌)(?:歌)?", t):
        return {"op": "next"}
    if re.fullmatch(r"(?:上一首|上首|前一首)(?:歌)?", t):
        return {"op": "previous"}
    if re.fullmatch(r"(?:暫停|暫停播放|暫停音樂|先暫停|停一下)", t):
        return {"op": "pause"}
    if re.fullmatch(r"(?:停止|停止播放|關掉音樂|音樂關掉|關音樂|別放了|不要放了|不要播了|停止音樂)", t):
        return {"op": "stop"}
    if re.fullmatch(r"(?:繼續|繼續播放|繼續放|繼續播|恢復播放)(?:音樂)?", t):
        return {"op": "resume"}
    if re.fullmatch(r"(?:現在|目前)?(?:在)?(?:放|播|播放)(?:的是)?(?:什麼|甚麼|啥)(?:歌)?|這(?:是)?(?:什麼|甚麼)歌|這首(?:歌)?(?:是|叫)(?:什麼|甚麼)", t):
        return {"op": "what"}
    m = re.fullmatch(r"(?:音樂|歌)?(?:音量)?(?:大聲|調大|開大)(?:一點|點)?", t)
    if m and ("聲" in t or "音量" in t or "音樂" in t):
        return {"op": "volume_step", "delta": 0.1}
    m = re.fullmatch(r"(?:音樂|歌)?(?:音量)?(?:小聲|調小|關小)(?:一點|點)?", t)
    if m and ("聲" in t or "音量" in t or "音樂" in t):
        return {"op": "volume_step", "delta": -0.1}
    m = re.fullmatch(r"(?:音樂|歌)?音量(?:調到|設成|設為|設到|開到)?(.+?)(?:%|趴|百分比)?", t)
    if m:
        v = _num(m.group(1))
        if v is not None and 0 <= v <= 100:
            return {"op": "volume_set", "value": v / 100}
    if re.fullmatch(r"(?:開啟|打開|開|改成|改為|換成|用)?(?:隨機|亂序|隨機播放|隨機模式|隨機撥放)(?:播放|模式)?", t):
        return {"op": "shuffle_on"}
    if re.fullmatch(r"(?:關閉|關掉|取消|不要)(?:隨機|隨機播放|隨機模式)|(?:改成|改為|換成|用)?(?:依序|順序)(?:播放|模式)?", t):
        return {"op": "shuffle_off"}
    shuffle = None
    m = re.match(r"^(?:請|幫我)?(隨機|亂序|依序|順序)(?=播放|播|放)", t)
    if m:                                    # 「隨機播放我的爽歌清單」 = shuffle + play
        shuffle = m.group(1) in ("隨機", "亂序")
        t = t[m.end():]
    m = PLAY.match(t)
    if m and shuffle is not None:
        r = _play(m, device_names)
        if r and r["op"] == "play":
            r["shuffle"] = shuffle
            return r
        return {"op": "shuffle_on" if shuffle else "shuffle_off"}
    if m:
        return _play(m, device_names)
    return None


def _play(m, device_names):
    q = TAIL.sub("", m.group(1))
    q = re.sub(r"^(?:一首|首|點|些|一下)", "", q)
    if not q or GENERIC.fullmatch(q):
        return {"op": "resume"}
    if DEVICE_WORDS.search(q) or any(n and n in q for n in device_names):
        return None
    return {"op": "play", "query": q}
