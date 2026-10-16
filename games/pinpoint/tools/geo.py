"""Shared geometry helpers for the Pinpoint curation tools (stdlib only)."""

import math

EARTH_R_KM = 6371.0088


def haversine_km(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_R_KM * math.asin(min(1.0, math.sqrt(a)))


def ring_area(ring):
    """Signed shoelace area in degrees² (ring = [(x, y), ...], open)."""
    s = 0.0
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        s += x1 * y2 - x2 * y1
    return s / 2


def point_in_ring(x, y, ring):
    inside = False
    n = len(ring)
    j = n - 1
    for i in range(n):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-300) + xi:
            inside = not inside
        j = i
    return inside


def _perp_dist(p, a, b):
    (x, y), (x1, y1), (x2, y2) = p, a, b
    dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0:
        return math.hypot(x - x1, y - y1)
    t = max(0.0, min(1.0, ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - (x1 + t * dx), y - (y1 + t * dy))


def simplify(points, tol):
    """Iterative Douglas-Peucker on an open polyline."""
    if len(points) < 3:
        return list(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        s, e = stack.pop()
        best, idx = 0.0, -1
        for i in range(s + 1, e):
            d = _perp_dist(points[i], points[s], points[e])
            if d > best:
                best, idx = d, i
        if best > tol and idx > 0:
            keep[idx] = True
            stack.append((s, idx))
            stack.append((idx, e))
    return [p for p, k in zip(points, keep) if k]


def simplify_ring(ring, tol):
    """Simplify a closed ring (open list, no repeated first point)."""
    if len(ring) <= 4:
        return list(ring)
    # Split at the point farthest from vertex 0 so both halves are anchored.
    far = max(range(len(ring)), key=lambda i: (ring[i][0] - ring[0][0]) ** 2 + (ring[i][1] - ring[0][1]) ** 2)
    a = simplify(ring[: far + 1], tol)
    b = simplify(ring[far:] + [ring[0]], tol)
    return a[:-1] + b[:-1]


def _seg_intersect(p1, p2, p3, p4):
    def orient(a, b, c):
        v = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        return 0 if abs(v) < 1e-12 else (1 if v > 0 else -1)

    o1, o2 = orient(p1, p2, p3), orient(p1, p2, p4)
    o3, o4 = orient(p3, p4, p1), orient(p3, p4, p2)
    return o1 != o2 and o3 != o4 and 0 not in (o1, o2, o3, o4)


def ring_is_simple(ring):
    n = len(ring)
    if n < 3:
        return False
    if len(set(ring)) != n:
        return False
    # Bucket segments by bbox grid to keep this fast for long rings.
    segs = [(ring[i], ring[(i + 1) % n]) for i in range(n)]
    for i in range(n):
        a, b = segs[i]
        minx, maxx = min(a[0], b[0]), max(a[0], b[0])
        miny, maxy = min(a[1], b[1]), max(a[1], b[1])
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue
            c, d = segs[j]
            if max(c[0], d[0]) < minx or min(c[0], d[0]) > maxx or max(c[1], d[1]) < miny or min(c[1], d[1]) > maxy:
                continue
            if _seg_intersect(a, b, c, d):
                return False
    return True


def dist_point_ring_km(lat, lon, ring):
    """Approximate distance from a point to a ring's edges (km)."""
    kx = math.cos(math.radians(lat)) * 111.32
    ky = 110.57
    p = (lon * kx, lat * ky)
    best = float("inf")
    n = len(ring)
    for i in range(n):
        a = (ring[i][0] * kx, ring[i][1] * ky)
        b = (ring[(i + 1) % n][0] * kx, ring[(i + 1) % n][1] * ky)
        best = min(best, _perp_dist(p, a, b))
    return best
