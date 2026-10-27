"""
A tiny shape painter for the cartoon sprites in sprites.py.

Shapes go into named parts. On render, every part gets a thick dark
outline, a line where it meets a part drawn over it, a shaded band on its
bottom-right and a highlight rim on its top-left (light from the top
left), so a sprite reads like an inked, cel-shaded cartoon. Details such
as eyes are stamped on afterwards, unshaded.
"""

# Base colour -> (shade, highlight). Colours missing here stay flat.
RAMPS = {
    "s": ("S", "Z"),
    "r": ("R", "q"),
    "R": ("A", "r"),
    "u": ("U", "c"),
    "U": ("V", "u"),
    "p": ("P", "v"),
    "P": ("j", "p"),
    "n": ("N", "m"),
    "N": ("h", "n"),
    "m": ("n", "i"),
    "b": ("B", "a"),
    "B": ("z", "b"),
    "y": ("O", "Y"),
    "o": ("T", "Y"),
    "e": ("E", "w"),
    "E": ("d", "e"),
    "g": ("d", "l"),
    "d": ("f", "g"),
    "f": ("k", "d"),
    "w": ("l", "w"),
    "l": ("g", "w"),
    "G": ("H", "n"),
}


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.owner = [[None] * w for _ in range(h)]
        self.parts = {}  # name -> {"color", "z", "shade", "line"}
        self.z = 0
        self.stamps = []

    def _part(self, name, color, shade, line):
        self.z += 1
        part = self.parts.get(name)
        if part is None:
            part = {"color": color, "shade": shade, "line": line}
            self.parts[name] = part
        part["z"] = self.z
        return name

    def _set(self, name, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.owner[y][x] = name

    def ellipse(self, name, color, cx, cy, rx, ry, shade=True, line=True):
        self._part(name, color, shade, line)
        for y in range(self.h):
            for x in range(self.w):
                dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1.0:
                    self._set(name, x, y)
        return self

    def rect(self, name, color, x0, y0, x1, y1, shade=True, line=True):
        self._part(name, color, shade, line)
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self._set(name, x, y)
        return self

    def poly(self, name, color, points, shade=True, line=True):
        self._part(name, color, shade, line)
        n = len(points)
        for y in range(self.h):
            for x in range(self.w):
                px, py = x + 0.5, y + 0.5
                inside = False
                j = n - 1
                for i in range(n):
                    xi, yi = points[i]
                    xj, yj = points[j]
                    if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
                        inside = not inside
                    j = i
                if inside:
                    self._set(name, x, y)
        return self

    def line(self, name, color, x0, y0, x1, y1, width=1, shade=True, line=True):
        self._part(name, color, shade, line)
        steps = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(steps + 1):
            x = round(x0 + (x1 - x0) * i / steps)
            y = round(y0 + (y1 - y0) * i / steps)
            for dy in range(width):
                for dx in range(width):
                    self._set(name, x + dx, y + dy)
        return self

    def erase(self, points):
        for x, y in points:
            if 0 <= x < self.w and 0 <= y < self.h:
                self.owner[y][x] = None
        return self

    def px(self, color, *points):
        """Stamp detail pixels after shading: eyes, mouths, emblems."""
        for x, y in points:
            self.stamps.append((x, y, color))
        return self

    def hline(self, color, x0, x1, y):
        return self.px(color, *[(x, y) for x in range(x0, x1 + 1)])

    def vline(self, color, x, y0, y1):
        return self.px(color, *[(x, y) for y in range(y0, y1 + 1)])

    def render(self, flip=False):
        w, h, own = self.w, self.h, self.owner

        def at(x, y):
            return own[y][x] if 0 <= x < w and 0 <= y < h else None

        out = [["."] * w for _ in range(h)]
        for y in range(h):
            for x in range(w):
                name = own[y][x]
                if name is None:
                    # Outline: empty pixels touching any part.
                    if any(at(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                        out[y][x] = "k"
                    continue
                part = self.parts[name]
                # Ink line where this part meets one drawn over it.
                if part["line"]:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        other = at(x + dx, y + dy)
                        if other and other != name and self.parts[other]["line"] and self.parts[other]["z"] > part["z"]:
                            out[y][x] = "k"
                            break
                    if out[y][x] == "k":
                        continue
                color = part["color"]
                ramp = RAMPS.get(color) if part["shade"] else None
                if ramp:
                    def same(dx, dy):
                        return at(x + dx, y + dy) == name

                    if not same(2, 0) or not same(0, 2) or not same(1, 1):
                        color = ramp[0]
                    elif not same(-1, 0) or not same(0, -1):
                        color = ramp[1]
                out[y][x] = color
        for x, y, color in self.stamps:
            if 0 <= x < w and 0 <= y < h:
                out[y][x] = color
        rows = ["".join(row) for row in out]
        return [row[::-1] for row in rows] if flip else rows
