"""
The game's art, drawn in code, and the script that turns it into
src/client/UI/Sprites.luau (what the game draws) and, optionally, PNGs.

    python3 tools/sprites.py              # regenerate Sprites.luau
    python3 tools/sprites.py --png out/   # also write one PNG per sprite
                                          # plus sheet.png, a preview of all

The style is chibi cartoon: big heads, a thick dark outline, a line
between parts and cel shading, all added by paint.Canvas. Icons are 16x16
and units 32x32. Units face the middle of the screen: the hero looks
right, enemies look left.

Edit the art here, never in Sprites.luau.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paint import Canvas  # noqa: E402

PALETTE = {  # one character per colour; "." is transparent
    "k": (9, 8, 15), "w": (244, 239, 226), "l": (200, 196, 210), "g": (150, 143, 176),
    "d": (80, 74, 104), "f": (50, 46, 68), "r": (217, 80, 74), "R": (140, 40, 48),
    "A": (85, 22, 32), "q": (245, 140, 120), "o": (244, 150, 50), "T": (196, 96, 30),
    "y": (242, 193, 78), "Y": (255, 232, 150), "O": (190, 128, 40), "b": (150, 95, 50),
    "B": (90, 55, 35), "a": (200, 140, 85), "z": (52, 30, 20), "u": (90, 169, 230),
    "U": (45, 85, 150), "V": (28, 48, 95), "c": (170, 225, 255), "n": (110, 200, 110),
    "N": (45, 120, 60), "h": (24, 66, 36), "m": (180, 230, 90), "i": (228, 250, 165),
    "p": (200, 110, 210), "P": (105, 55, 140), "j": (62, 30, 88), "v": (232, 165, 238),
    "s": (244, 196, 150), "S": (196, 136, 100), "Z": (255, 224, 194), "e": (210, 215, 230),
    "E": (120, 130, 150), "G": (135, 190, 90), "H": (78, 128, 58),
}


# Icons (16x16) ----------------------------------------------------------------

def C():
    return Canvas(16, 16)

def heart(color="r"):
    c = C()
    c.ellipse("h", color, 5, 6, 3.6, 3.6).ellipse("h", color, 11, 6, 3.6, 3.6)
    c.poly("h", color, [(1.6, 7), (14.4, 7), (8, 14.5)])
    return c

def shield(color="u"):
    c = C()
    c.poly("s", color, [(2, 2), (14, 2), (14, 8), (8, 14.5), (2, 8)])
    return c

def bolt():
    c = C()
    c.poly("b", "y", [(10, 0.5), (3, 9), (7.5, 9), (5, 15.5), (13.5, 6), (9, 6), (12, 0.5)])
    return c.render()

def coin():
    c = C()
    c.ellipse("c", "y", 8, 8, 6.5, 6.5).ellipse("i", "y", 8, 8, 3.5, 3.5)
    return c.render()

def cards(front="p", back="P", mark="y"):
    c = C()
    c.rect("back", back, 6, 1, 13, 11)
    c.rect("front", front, 2, 4, 9, 14)
    c.ellipse("mark", mark, 6, 9, 2, 2.5, shade=False)
    return c.render()

def cross():
    c = C()
    c.line("x", "l", 2, 2, 12, 12, width=2).line("x", "l", 12, 2, 2, 12, width=2)
    return c.render()

def gem(color="y"):
    c = C()
    c.poly("g", color, [(4, 2.5), (12, 2.5), (15, 6.5), (8, 14.5), (1, 6.5)])
    c.hline("k", 2, 13, 6)
    return c.render()

def bang():
    c = C()
    c.rect("b", "y", 6, 1, 9, 9).ellipse("d", "y", 8, 13, 2, 2)
    return c.render()

def question(color="w"):
    c = C()
    for a, b in [((4, 4), (6, 2)), ((6, 2), (10, 2)), ((10, 2), (12, 4)), ((12, 4), (12, 6)), ((12, 6), (8, 8)), ((8, 8), (8, 10))]:
        c.line("q", color, a[0], a[1], b[0], b[1], width=2)
    c.ellipse("d", color, 9, 13.5, 1.6, 1.6)
    return c.render()

def sword(c=None, flip=False, grip="b"):
    c = c or C()
    if not flip:
        c.line("blade", "e", 5, 9, 13, 1, width=2)
        c.line("guard", "y", 3, 8, 7, 12, width=2)
        c.line("grip", grip, 2, 12, 3, 13, width=2)
    else:
        c.line("blade2", "e", 9, 1, 1, 9, width=2)
        c.line("guard2", "y", 12, 8, 8, 12, width=2)
        c.line("grip2", grip, 12, 13, 13, 12, width=2)
    return c

def swords():
    c = sword(sword(flip=True))
    return c.render()

def skull(color="w"):
    c = C()
    c.rect("j", color, 5, 10, 10, 14).ellipse("s", color, 8, 7, 6.5, 6)
    c.px("k", (5, 6), (6, 6), (5, 7), (6, 7), (9, 6), (10, 6), (9, 7), (10, 7), (8, 9))
    c.px("k", (6, 13), (8, 13), (10, 13))
    return c.render()

def campfire():
    c = C()
    c.line("log", "b", 1, 14, 14, 11, width=2).line("log2", "b", 1, 11, 14, 14, width=2)
    c.poly("f", "o", [(8, 0.5), (13, 8), (12, 12), (4, 12), (3, 8), (6, 5)])
    c.poly("fi", "y", [(8, 5), (10.5, 9), (9.5, 12), (6.5, 12), (5.5, 9)], line=False)
    return c.render()

def bag():
    c = C()
    c.ellipse("bag", "b", 8, 10.5, 6.5, 5)
    c.poly("neck", "b", [(5, 2), (11, 2), (10, 6), (6, 6)])
    c.rect("tie", "y", 5, 5, 10, 6, shade=False)
    c.px("Y", (7, 9), (8, 9), (9, 9), (7, 10), (8, 11), (9, 11), (9, 12), (7, 13), (8, 13), (9, 13), (8, 8), (8, 14))
    return c.render()

def chest():
    c = C()
    c.rect("box", "b", 1, 7, 14, 14)
    c.ellipse("lid", "b", 7.5, 7, 7, 4)
    c.erase([(x, y) for y in range(8, 16) for x in range(16) if c.owner[y][x] == "lid"])
    c.vline("y", 3, 4, 14).vline("y", 12, 4, 14).hline("k", 1, 14, 7)
    c.rect("lock", "y", 6, 6, 9, 9)
    return c.render()

def crown(gold="y", gem="u"):
    c = C()
    c.poly("c", gold, [(1, 13), (1, 3.5), (4.5, 7.5), (8, 1.5), (11.5, 7.5), (15, 3.5), (15, 13)])
    c.px(gem, (7, 9), (8, 9), (7, 10), (8, 10)).px("r", (3, 10), (12, 10))
    return c.render()

def arrow(up=True):
    c = C()
    pts = [(8, 0.5), (15.5, 8), (11, 8), (11, 15), (5, 15), (5, 8), (0.5, 8)]
    if up:
        c.poly("a", "n", pts)
        return c.render()
    c.poly("a", "p", [(x, 16 - y) for x, y in pts])
    return c.render()

def cloud():
    c = C()
    c.ellipse("c", "l", 5, 8, 4, 3.5).ellipse("c", "l", 10, 6, 4.5, 4.5).ellipse("c", "l", 12, 9, 3, 2.5)
    c.rect("c", "l", 4, 8, 13, 11)
    c.line("drip", "m", 5, 12, 5, 14).line("drip2", "m", 10, 12, 10, 15)
    return c.render()

def drop(color="r"):
    c = C()
    c.ellipse("d", color, 8, 10, 5, 5).poly("d", color, [(8, 0.5), (3.3, 8.5), (12.7, 8.5)])
    return c

def flame():
    c = C()
    c.poly("f", "o", [(8, 0.5), (13, 6), (14, 11), (11, 15), (5, 15), (2, 11), (3, 6), (6, 8)])
    c.poly("fi", "y", [(8, 6), (11, 10), (10, 14), (6, 14), (5, 10)], line=False)
    return c.render()

def star(color="y"):
    c = C()
    pts = []
    for i in range(10):
        r = 7.5 if i % 2 == 0 else 3.2
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((8 + r * math.cos(a), 8.5 + r * math.sin(a)))
    c.poly("s", color, pts)
    return c.render()

def eye():
    c = C()
    c.ellipse("e", "w", 8, 8, 7.5, 4.5)
    c.ellipse("i", "u", 8, 8, 3, 3)
    c.px("k", (7, 7), (8, 7), (7, 8), (8, 8)).px("w", (9, 6))
    return c.render()

def fist():
    c = C()
    c.rect("cuff", "r", 4, 12, 11, 15)
    c.ellipse("f", "s", 8, 7.5, 6, 5.5)
    c.ellipse("thumb", "s", 4, 9, 2.5, 2)
    c.vline("k", 6, 3, 6).vline("k", 9, 3, 6).vline("k", 12, 4, 6)
    return c.render()

def feather():
    c = C()
    c.poly("f", "n", [(14, 1), (11, 9), (5, 13), (3, 12), (6, 6)])
    c.line("q", "b", 1, 15, 12, 3, width=1, line=False)
    return c.render()

def thorn():
    c = C()
    for a, b in [((8, 0), (8, 15)), ((0, 8), (15, 8)), ((2, 2), (13, 13)), ((13, 2), (2, 13))]:
        c.line("spike", "N", a[0], a[1], b[0], b[1], width=1)
    c.ellipse("ball", "n", 8, 8, 4.5, 4.5)
    return c.render()

def plus_stamp(c, color="w", cx=8, cy=8):
    c.px(color, (cx - 1, cy - 2), (cx, cy - 2), (cx - 1, cy + 1), (cx, cy + 1))
    c.hline(color, cx - 2, cx + 1, cy - 1).hline(color, cx - 2, cx + 1, cy)
    return c

def crack(c):
    c.px("k", (8, 3), (8, 4), (7, 5), (7, 6), (8, 7), (9, 8), (9, 9), (8, 10), (8, 11))
    return c

def broken_sword():
    c = C()
    c.line("blade", "g", 5, 9, 9, 5, width=2)
    c.line("tip", "g", 11, 3, 13, 1, width=2)
    c.line("guard", "d", 3, 8, 7, 12, width=2)
    c.line("grip", "B", 2, 12, 3, 13, width=2)
    return c.render()

def flask():
    c = C()
    c.ellipse("b", "r", 8, 10.5, 5.5, 4.5)
    c.rect("n", "l", 6, 2, 9, 6)
    c.rect("cork", "b", 5, 0, 10, 2)
    c.px("w", (5, 9), (5, 10))
    return c.render()

def lens():
    c = C()
    c.line("h", "b", 10, 10, 14, 14, width=2)
    c.ellipse("rim", "y", 6.5, 6.5, 5.5, 5.5)
    c.ellipse("glass", "c", 6.5, 6.5, 3.5, 3.5, shade=False)
    c.px("w", (5, 4), (4, 5))
    return c.render()

def amulet():
    c = C()
    c.line("cord", "B", 2, 0, 7, 5, line=False).line("cord", "B", 13, 0, 8, 5, line=False)
    c.ellipse("set", "y", 8, 10, 5, 5)
    c.ellipse("gem", "o", 8, 10, 2.8, 2.8)
    return c.render()

def mail(color="e"):
    c = C()
    c.poly("m", color, [(3, 2), (6, 2), (8, 4), (10, 2), (13, 2), (15, 6), (12, 7), (12, 14), (4, 14), (4, 7), (1, 6)])
    for y in (8, 10, 12):
        c.px("k", (6, y), (8, y), (10, y))
    return c

def scroll(seal):
    c = C()
    c.rect("paper", "w", 3, 3, 12, 12)
    c.ellipse("top", "l", 7.5, 2.5, 6, 1.6).ellipse("bot", "l", 7.5, 13, 6, 1.6)
    c.hline("g", 5, 10, 6).hline("g", 5, 9, 8).hline("g", 5, 10, 10)
    c.ellipse("seal", seal, 12, 12, 2.4, 2.4)
    return c.render()

def chalice():
    c = C()
    c.rect("base", "y", 4, 13, 11, 15)
    c.rect("stem", "y", 7, 9, 8, 13)
    c.poly("cup", "y", [(1.5, 1.5), (14.5, 1.5), (12.5, 7), (8, 10), (3.5, 7)])
    c.hline("r", 3, 12, 2).hline("R", 3, 12, 3)
    return c.render()

def buckle():
    c = C()
    c.rect("frame", "e", 1, 3, 14, 13)
    c.erase([(x, y) for x in range(5, 11) for y in range(6, 11)])
    c.line("prong", "E", 4, 8, 11, 8, width=1)
    return c.render()

ICONS = {
    "hp": heart().render(),
    "block": shield().render(),
    "energy": bolt(),
    "gold": coin(),
    "deck": cards(),
    "draw": cards("u", "U", "w"),
    "discard": cards("g", "d", "l"),
    "exhaust": cross(),
    "relic": gem(),
    "qte": bang(),
    "Unknown": question("g"),
    "Combat": swords(),
    "Elite": skull(),
    "Event": question(),
    "Rest": campfire(),
    "Shop": bag(),
    "Treasure": chest(),
    "Boss": crown(),
    "Attack": sword(grip="r").render(),
    "Defend": shield().render(),
    "Buff": arrow(True),
    "Debuff": arrow(False),
    "Pollute": cloud(),
    "AttackCard": sword().render(),
    "SkillCard": shield().render(),
    "PowerCard": star("p"),
    "StatusCard": question("g"),
    "CurseCard": skull("p"),
    "Strength": fist(),
    "Dexterity": feather(),
    "Fortify": plus_stamp(shield()).render(),
    "Thorns": thorn(),
    "Regen": plus_stamp(heart("n"), cy=8).render(),
    "Vulnerable": crack(shield("o")).render(),
    "Weak": broken_sword(),
    "Frail": crack(shield("g")).render(),
    "Poison": drop("n").render(),
    "Bleed": drop("r").render(),
    "Burn": flame(),
    "Stun": star("y"),
    "Focus": eye(),
    "Dazed": star("l"),
    "IronBuckle": buckle(),
    "VigorFlask": flask(),
    "FocusLens": lens(),
    "EmberCharm": amulet(),
    "ThornMail": mail("n").render(),
    "WardensOath": scroll("u"),
    "BloodChalice": chalice(),
    "HeavyCrown": crown("E", "r"),
    "BloodOath": scroll("r"),
    "CrackedWard": crack(shield()).render(),
}
# Attack with a debuff: the sword plus a small purple drop.
_c = sword(grip="p")
_c.ellipse("drop", "p", 12.5, 12.5, 2.5, 2.5)
ICONS["AttackDebuff"] = _c.render()


# Units (32x32) ----------------------------------------------------------------

def warden():
    c = Canvas(32, 32)
    c.poly("cape", "U", [(9, 17), (23, 17), (26, 30), (6, 30)])
    c.rect("legL", "E", 11, 25, 14, 30)
    c.rect("legR", "E", 17, 25, 20, 30)
    c.ellipse("body", "e", 16, 23, 7, 5.5)
    c.rect("tabard", "u", 13, 19, 19, 28)
    c.line("blade", "e", 27, 21, 29, 3, width=2)
    c.rect("guard", "y", 24, 21, 30, 22)
    c.rect("grip", "b", 26, 23, 27, 26)
    c.ellipse("hand", "E", 26.5, 24.5, 2, 2)
    c.ellipse("helm", "e", 16, 11, 8.5, 8.5)
    c.ellipse("plume", "r", 15, 2.5, 3.5, 2.5)
    c.poly("shield", "u", [(1, 16), (11, 16), (11, 23), (6, 29), (1, 23)])
    # Visor slit with eyes looking right, and a gold cross like a crusader
    c.hline("k", 9, 23, 10).hline("k", 10, 22, 11)
    c.px("c", (18, 10), (21, 10))
    c.vline("y", 16, 13, 18).hline("y", 14, 18, 15)
    c.vline("y", 6, 18, 25).hline("y", 3, 9, 20)
    c.vline("y", 16, 21, 26).hline("y", 14, 18, 23)
    return c.render()

def cultist():
    c = Canvas(32, 32)
    c.line("staff", "b", 5, 4, 5, 30, width=2)
    c.ellipse("orb", "y", 5.5, 4, 3, 3)
    c.poly("robe", "p", [(16, 10), (26, 29), (6, 29)])
    c.ellipse("hood", "p", 16, 11, 8.5, 8.5)
    c.ellipse("face", "f", 15, 13, 5.5, 4.5, shade=False)
    c.ellipse("hand", "s", 7.5, 19, 2, 2)
    c.ellipse("sash", "P", 16, 23, 6, 1.5)
    c.px("Y", (12, 13), (13, 13), (17, 13), (18, 13))
    c.px("y", (12, 14), (17, 14))
    c.px("Y", (16, 26), (15, 25), (17, 25))
    return c.render()

def slime():
    c = Canvas(32, 32)
    c.poly("blob", "m", [(4, 30), (3, 24), (6, 16), (11, 10), (16, 8), (21, 10), (26, 16), (29, 24), (28, 30)])
    c.ellipse("eyeL", "w", 11.5, 18, 3, 3.5, shade=False)
    c.ellipse("eyeR", "w", 20.5, 18, 3, 3.5, shade=False)
    c.px("k", (11, 18), (12, 18), (11, 19), (12, 19), (19, 18), (20, 18), (19, 19), (20, 19))
    c.px("w", (11, 18), (19, 18))
    # Angry brows and a fanged grin
    c.px("k", (9, 14), (10, 14), (11, 15), (12, 15), (22, 14), (21, 14), (20, 15), (19, 15))
    c.hline("k", 12, 19, 23).px("k", (11, 22), (20, 22)).px("w", (13, 24), (18, 24))
    c.px("i", (9, 12), (8, 13), (10, 12))
    c.ellipse("drip", "m", 8, 31, 1.5, 1.5)
    return c.render()

def bandit():
    c = Canvas(32, 32)
    c.rect("legL", "B", 11, 25, 14, 30)
    c.rect("legR", "B", 17, 25, 20, 30)
    c.ellipse("body", "b", 16, 22, 7, 5.5)
    c.rect("belt", "B", 10, 24, 22, 25)
    c.line("knife", "e", 3, 16, 7, 21, width=2)
    c.ellipse("hand", "s", 8, 22, 2, 2)
    c.ellipse("head", "s", 16, 12, 8, 8)
    c.ellipse("bandana", "r", 16, 7, 8.5, 5)
    c.rect("bandanaFlat", "r", 8, 7, 24, 9)
    c.poly("knot", "r", [(24, 7), (29, 5), (29, 11)])
    c.rect("mask", "d", 9, 14, 23, 19)
    c.px("k", (11, 12), (12, 12), (19, 12), (20, 12))
    c.px("w", (11, 12), (19, 12))
    c.hline("k", 10, 13, 10).hline("k", 18, 21, 10)
    c.px("y", (16, 24), (17, 24))
    return c.render()

def wolf():
    c = Canvas(32, 32)
    c.poly("tail", "g", [(25, 18), (31, 10), (30, 20), (27, 23)])
    c.rect("legBR", "d", 23, 23, 26, 30)
    c.rect("legBL", "d", 18, 24, 21, 30)
    c.ellipse("body", "g", 20, 20, 9, 6.5)
    c.rect("legFR", "g", 11, 23, 14, 30)
    c.rect("legFL", "g", 6, 23, 9, 30)
    c.poly("earL", "d", [(5, 4), (8, 9), (3, 10)])
    c.poly("earR", "d", [(12, 3), (14, 9), (9, 8)])
    c.ellipse("head", "g", 9, 13, 7, 6)
    c.ellipse("snout", "l", 4, 17, 4, 3)
    c.ellipse("chest", "l", 12, 21, 3, 4)
    c.px("k", (1, 15), (2, 15))
    c.px("r", (6, 12), (7, 12), (11, 12))
    c.px("k", (6, 11), (7, 11), (10, 11), (11, 11))
    c.hline("k", 1, 6, 19).px("w", (2, 19), (4, 19)).px("w", (3, 20))
    return c.render()

def sporeling():
    c = Canvas(32, 32)
    c.rect("footL", "S", 10, 27, 13, 30)
    c.rect("footR", "S", 18, 27, 21, 30)
    c.ellipse("stalk", "s", 16, 22, 6.5, 6.5)
    c.ellipse("cap", "r", 16, 11, 13, 8.5)
    c.erase([(x, y) for x in range(32) for y in range(16, 20) if c.owner[y][x] == "cap"])
    c.ellipse("gills", "l", 16, 16, 11, 2)
    c.ellipse("spot1", "w", 10, 9, 2.5, 2, shade=False)
    c.ellipse("spot2", "w", 19, 6, 2, 1.5, shade=False)
    c.ellipse("spot3", "w", 24, 11, 2, 2, shade=False)
    c.px("k", (13, 21), (13, 22), (18, 21), (18, 22))
    c.px("w", (13, 21), (18, 21))
    c.hline("k", 15, 16, 25)
    c.px("q", (11, 24), (20, 24))
    return c.render()

def grave_knight():
    c = Canvas(32, 32)
    c.poly("cape", "P", [(9, 16), (23, 16), (27, 30), (5, 30)])
    c.rect("legL", "d", 11, 25, 14, 30)
    c.rect("legR", "d", 17, 25, 20, 30)
    c.ellipse("body", "d", 16, 22, 7, 6)
    c.line("blade", "E", 3, 3, 3, 24, width=3)
    c.rect("guard", "R", 1, 22, 7, 23)
    c.ellipse("hand", "f", 4.5, 25, 2, 2)
    c.ellipse("helm", "d", 16, 11, 8, 8.5)
    c.poly("hornL", "l", [(9, 6), (4, 0), (7, 8)])
    c.poly("hornR", "l", [(23, 6), (28, 0), (25, 8)])
    c.hline("k", 9, 23, 11).hline("k", 10, 22, 12)
    c.px("r", (12, 11), (13, 11), (19, 11), (20, 11))
    c.vline("k", 16, 13, 18)
    c.px("R", (14, 21), (18, 21), (16, 23))
    return c.render()

def hexer():
    c = Canvas(32, 32)
    c.poly("robe", "P", [(16, 14), (26, 30), (6, 30)])
    c.ellipse("hair", "f", 16, 15, 9, 6)
    c.ellipse("head", "G", 16, 15, 6.5, 6)
    c.poly("nose", "G", [(10, 15), (7, 18), (11, 18)])
    c.ellipse("brim", "f", 16, 9, 12, 2.5)
    c.poly("hat", "P", [(10, 9), (22, 9), (19, 3), (24, -1), (15, 1)])
    c.rect("band", "p", 10, 7, 21, 8)
    c.line("wand", "b", 3, 20, 7, 25, width=1)
    c.ellipse("hand", "G", 7.5, 25, 2, 2)
    c.px("k", (12, 15), (13, 15), (18, 15), (19, 15))
    c.px("y", (12, 14), (18, 14))
    c.hline("k", 12, 16, 19)
    c.px("Y", (2, 19), (1, 18), (3, 18), (2, 17), (2, 20), (1, 20))
    c.px("y", (16, 24), (16, 26), (15, 25), (17, 25))
    return c.render()

def hollow_king():
    c = Canvas(32, 32)
    c.poly("cape", "R", [(8, 16), (24, 16), (29, 30), (3, 30)])
    c.ellipse("collar", "w", 16, 18, 10, 3)
    c.ellipse("body", "P", 16, 25, 5.5, 4.5)
    c.line("scepter", "y", 4, 6, 4, 29, width=2)
    c.ellipse("gem", "u", 4.5, 5, 2.5, 2.5)
    c.ellipse("hand", "l", 5, 21, 2, 2)
    c.ellipse("skull", "w", 16, 11, 7.5, 7)
    c.rect("jaw", "w", 12, 16, 20, 18)
    c.poly("crown", "y", [(8, 6), (8, 0), (11, 3), (13, -1), (16, 2), (19, -1), (21, 3), (24, 0), (24, 6)])
    c.ellipse("eyeL", "k", 12.5, 11, 2, 2, shade=False, line=False)
    c.ellipse("eyeR", "k", 19.5, 11, 2, 2, shade=False, line=False)
    c.px("r", (12, 11), (19, 11))
    c.px("k", (16, 14))
    c.hline("k", 12, 20, 16).vline("k", 14, 17, 18).vline("k", 16, 17, 18).vline("k", 18, 17, 18)
    c.px("r", (16, 3))
    return c.render()

UNITS = {
    "Warden": warden(),
    "Cultist": cultist(),
    "AcidSlime": slime(),
    "Bandit": bandit(),
    "DireWolf": wolf(),
    "Sporeling": sporeling(),
    "GraveKnight": grave_knight(),
    "Hexer": hexer(),
    "HollowKing": hollow_king(),
}


SPRITES = {**ICONS, **UNITS}


def check(name, rows):
    size = (len(rows[0]), len(rows))
    if size not in ((16, 16), (32, 32)):
        raise ValueError(f"{name} is {size[0]}x{size[1]}")
    for row in rows:
        for ch in row:
            if ch != "." and ch not in PALETTE:
                raise ValueError(f"{name}: unfilled colour {ch!r}")


def write_luau(path):
    for name, rows in SPRITES.items():
        check(name, rows)
    out = []
    out.append("--[[")
    out.append("\tGenerated by tools/sprites.py. Edit the art there and run it again.")
    out.append("")
    out.append("\tPixel sprites as text grids: one character per pixel, naming a colour")
    out.append('\tin `palette`; "." is transparent. Kit.icon draws them.')
    out.append("]]")
    out.append("")
    out.append("local Sprites = {}")
    out.append("")
    out.append("Sprites.palette = {")
    for ch, (r, g, b) in PALETTE.items():
        out.append(f"\t{ch} = {{ {r}, {g}, {b} }},")
    out.append("}")
    out.append("")
    out.append("Sprites.art = {")
    for name, rows in SPRITES.items():
        out.append(f"\t{name} = {{")
        for row in rows:
            out.append(f'\t\t"{row}",')
        out.append("\t},")
    out.append("}")
    out.append("")
    out.append("return Sprites")
    out.append("")
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(out))


def write_pngs(folder, scale=8):
    from PIL import Image

    os.makedirs(folder, exist_ok=True)
    images = {}
    for name, rows in SPRITES.items():
        h, w = len(rows), len(rows[0])
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch != ".":
                    img.putpixel((x, y), PALETTE[ch] + (255,))
        # Upload at 8x so Roblox's resampling stays crisp even without
        # ResampleMode = Pixelated.
        big = img.resize((w * scale, h * scale), Image.NEAREST)
        big.save(os.path.join(folder, f"{name}.png"))
        images[name] = big

    cell, cols = 32 * scale + 16, 10
    rows_n = (len(images) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows_n * cell), (37, 33, 56, 255))
    for i, (name, img) in enumerate(images.items()):
        x, y = (i % cols) * cell + 8, (i // cols) * cell + 8
        sheet.alpha_composite(img, (x, y))
    sheet.save(os.path.join(folder, "sheet.png"))


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    write_luau(os.path.join(root, "src", "client", "UI", "Sprites.luau"))
    if "--png" in sys.argv:
        write_pngs(sys.argv[sys.argv.index("--png") + 1])
    print(f"{len(SPRITES)} sprites")
