#!/usr/bin/env python3
"""Extract TF2 hats from a local Team Fortress 2 install for dys_hats (LOCAL TESTING ONLY).

The models and materials are Valve's TF2 assets: this script copies them from YOUR TF2 install into a Dystopia
folder on the same machine (default: the game's dystopia/download, which is a game search path). Don't commit them
or offer them to other players for download.

For every hat it computes where the hat sits relative to Dystopia's "eyes" attachment:
  * the hat's runtime placement = its first animation, frame 0 (bone chain) x poseToBone (mesh -> bone),
  * the TF2 class model the hat was made for gives the "eyes" and "head" attachments in the same mesh space,
  * so: hat-in-TF2-eyes-frame = inverse(eyes) x mesh, and the entity offset from Dystopia's eyes =
        translate(dys_head_top - tf2_head_top) x inverse(tf2 eyes) x inverse(hat runtime placement).
VMTs are copied without their Proxies block (TF2-only proxies such as ItemTintColor / invis don't exist in Dystopia).

Usage:
  python tools/tf2_hats.py --tf2 "C:/Program Files (x86)/Steam/steamapps/common/Team Fortress 2" \
      --out "C:/Program Files (x86)/Steam/steamapps/common/Dystopia/dystopia/download" --cfg dys_hats_tf2.cfg
"""
import argparse, math, os, re, struct, sys

# id, menu name, model (the TF2 class in the path decides which head the hat was made for)
HATS = [
    ("bills", "Bill's Hat", "models/player/items/soldier/soldier_bill.mdl"),
    ("ellis", "Ellis' Cap", "models/player/items/soldier/soldier_ellis.mdl"),
    ("gibus", "Ghastly Gibus", "models/player/items/all_class/ghostly_gibus_soldier.mdl"),
    ("stash", "Soldier's Stash", "models/player/items/soldier/soldier_hat.mdl"),
    ("tyrant", "Tyrant's Helm", "models/player/items/soldier/soldier_viking.mdl"),
    ("stainless", "Stainless Pot", "models/player/items/soldier/soldier_pot.mdl"),
    ("kabuto", "Killer's Kabuto", "models/player/items/soldier/japan_hat.mdl"),
    ("maxhead", "Max's Severed Head", "models/player/items/soldier/soldier_ttg_max.mdl"),
    ("hattower", "Hat tower", "models/player/items/soldier/hardhat_tower.mdl"),
    ("summer", "Summer Hat", "models/player/items/soldier/summer_hat_soldier.mdl"),
    ("santa", "Santa Hat", "models/player/items/all_class/xms_santa_hat_soldier.mdl"),
    ("pith", "Pith Helmet", "models/player/items/soldier/drg_pith_hat.mdl"),
    ("horns", "Horns", "models/player/items/soldier/skull_horns_b.mdl"),
    ("paperhat", "Paper Hat", "models/player/items/soldier/paper_hat.mdl"),
    ("beanie", "Brisk-weather Beanie", "models/workshop/player/items/all_class/briskweather_beanie/briskweather_beanie_soldier.mdl"),
    ("crown", "Candy Crown", "models/workshop/player/items/all_class/dec19_candy_crown/dec19_candy_crown_soldier.mdl"),
    ("beanies", "Pillar of Beanies", "models/workshop/player/items/all_class/dec20_pillar_of_beanies/dec20_pillar_of_beanies_soldier.mdl"),
    ("cowboy", "Cowboy Hat", "models/workshop/player/items/all_class/fwk_cowboyhat/fwk_cowboyhat_soldier.mdl"),
    ("ushanka", "Officer's Ushanka", "models/player/items/heavy/heavy_ushanka.mdl"),
    ("football", "Football Helmet", "models/player/items/heavy/football_helmet.mdl"),
    ("tiara", "Fairy Tiara", "models/player/items/heavy/heavy_fairy_tiara.mdl"),
    ("fedora", "Fancy Fedora", "models/player/items/spy/spy_hat.mdl"),
    ("tengallon", "Texas Ten Gallon", "models/player/items/engineer/engineer_cowboy_hat.mdl"),
    ("pickelhaube", "Prussian Pickelhaube", "models/player/items/medic/medic_helmet.mdl"),
    ("brigade", "Brigade Helm", "models/player/items/pyro/fireman_helmet.mdl"),
    ("batter", "Batter's Helmet", "models/player/items/scout/batter_helmet.mdl"),
]
# what players WITHOUT the TF2 files see instead (an HL2 hat id from configs/dys_hats.cfg)
FALLBACK = {"bills": "pot", "ellis": "pot", "gibus": "bucket", "stash": "pot", "tyrant": "bucket", "stainless": "pot",
            "kabuto": "bucket", "maxhead": "melon", "hattower": "cone", "summer": "lampshade", "santa": "cone", "pith": "pot",
            "horns": "pot", "paperhat": "cone", "beanie": "pot", "crown": "halo", "beanies": "pail", "cowboy": "lampshade",
            "ushanka": "bucket", "football": "melon", "tiara": "halo", "fedora": "lampshade", "tengallon": "lampshade",
            "pickelhaube": "cone", "brigade": "bucket", "batter": "pot"}
CLASSES = ["soldier", "heavy", "spy", "engineer", "medic", "pyro", "scout", "demo", "sniper"]
# top-centre of the head in Dystopia's "eyes" frame (x forward, y left, z up): mean of the six class models
DYS_HEAD_TOP = (-5.9, 0.0, 4.9)
# TF2's "head" attachment sits a little above the skull: lift the hats so the crowns clear Dystopia's heads
LIFT = 1.5
MODEL_EXTS = [".mdl", ".vvd", ".dx80.vtx", ".dx90.vtx", ".sw.vtx", ".vtx", ".phy", ".ani"]
TEXTURE_KEYS = re.compile(r"^\$(basetexture\d?|bumpmap\d?|normalmap\d?|envmapmask|detail\d?|lightwarptexture|phongexponenttexture|"
                          r"phongwarptexture|selfillummask|selfillumtexture|blendmodulatetexture|ambientoccltexture|iris|corneatexture|"
                          r"emissiveblendtexture|emissiveblendbasetexture|emissiveblendflowtexture|ssbump)$", re.I)


# ------------------------------------------------------------------------------------------------ VPK
class VPK:
    def __init__(self, dirpath):
        self.base = dirpath[:-len("_dir.vpk")]
        with open(dirpath, "rb") as f:
            self.data = f.read()
        sig, ver, tree = struct.unpack_from("<III", self.data, 0)
        if sig != 0x55AA1234:
            raise ValueError("not a VPK: " + dirpath)
        hdr = 12 if ver == 1 else 28
        self.treeend = hdr + tree
        self.files = {}
        p = hdr

        def rs():
            nonlocal p
            e = self.data.index(b"\0", p)
            s = self.data[p:e].decode("latin1")
            p = e + 1
            return s
        while True:
            ext = rs()
            if not ext:
                break
            while True:
                path = rs()
                if not path:
                    break
                while True:
                    name = rs()
                    if not name:
                        break
                    _crc, pre, arc, off, ln, _term = struct.unpack_from("<IHHIIH", self.data, p)
                    p += 18
                    preload = self.data[p:p + pre]
                    p += pre
                    full = (name + "." + ext) if path == " " else (path + "/" + name + "." + ext)
                    self.files[full.lower()] = (arc, off, ln, preload)

    def read(self, name):
        arc, off, ln, preload = self.files[name.lower()]
        if ln == 0:
            return preload
        if arc == 0x7FFF:
            return preload + self.data[self.treeend + off:self.treeend + off + ln]
        with open("%s_%03d.vpk" % (self.base, arc), "rb") as f:
            f.seek(off)
            return preload + f.read(ln)


class TF2:
    def __init__(self, root):
        tf = os.path.join(root, "tf")
        self.vpks = [VPK(os.path.join(tf, n)) for n in ("tf2_misc_dir.vpk", "tf2_textures_dir.vpk")]

    def has(self, name):
        return any(name.lower() in v.files for v in self.vpks)

    def read(self, name):
        for v in self.vpks:
            if name.lower() in v.files:
                return v.read(name)
        raise KeyError(name)


# ------------------------------------------------------------------------------------------------ math
def mul34(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(3)) + (a[r][3] if c == 3 else 0) for c in range(4)] for r in range(3)]


def inv34(m):
    rt = [[m[c][r] for c in range(3)] for r in range(3)]
    t = [m[r][3] for r in range(3)]
    return [rt[r] + [-sum(rt[r][k] * t[k] for k in range(3))] for r in range(3)]


def apply34(m, v):
    return tuple(sum(m[r][k] * v[k] for k in range(3)) + m[r][3] for r in range(3))


def qmat(q, p):
    x, y, z, w = q
    return [[1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y), p[0]],
            [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x), p[1]],
            [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y), p[2]]]


def euler_quat(a):  # RadianEuler (x, y, z) -> quaternion, as Source's AngleQuaternion
    sr, cr = math.sin(a[0] * 0.5), math.cos(a[0] * 0.5)
    sp, cp = math.sin(a[1] * 0.5), math.cos(a[1] * 0.5)
    sy, cy = math.sin(a[2] * 0.5), math.cos(a[2] * 0.5)
    return (sr * cp * cy - cr * sp * sy, cr * sp * cy + sr * cp * sy, cr * cp * sy - sr * sp * cy, cr * cp * cy + sr * sp * sy)


def matrix_angles(m):  # Source MatrixAngles: columns = forward, left, up -> (pitch, yaw, roll) in degrees
    f = [m[0][0], m[1][0], m[2][0]]
    left = [m[0][1], m[1][1], m[2][1]]
    up = [m[0][2], m[1][2], m[2][2]]
    xy = math.hypot(f[0], f[1])
    if xy > 0.001:
        yaw = math.atan2(f[1], f[0])
        pitch = math.atan2(-f[2], xy)
        roll = math.atan2(left[2], up[2])
    else:
        yaw = math.atan2(-left[0], left[1])
        pitch = math.atan2(-f[2], xy)
        roll = 0.0
    return tuple(math.degrees(v) for v in (pitch, yaw, roll))


# ------------------------------------------------------------------------------------------------ MDL
def cstr(b, o):
    return b[o:b.index(b"\0", o)].decode("latin1")


class MDL:
    def __init__(self, mdl, vvd=None):
        self.b = b = mdl
        self.version = struct.unpack_from("<i", b, 4)[0]
        nb, bi = struct.unpack_from("<ii", b, 156)
        self.bones = []
        for i in range(nb):
            o = bi + i * 216
            name = cstr(b, o + struct.unpack_from("<i", b, o)[0])
            parent = struct.unpack_from("<i", b, o + 4)[0]
            pos = struct.unpack_from("<3f", b, o + 32)
            quat = struct.unpack_from("<4f", b, o + 44)
            rot = struct.unpack_from("<3f", b, o + 60)
            posscale = struct.unpack_from("<3f", b, o + 72)
            rotscale = struct.unpack_from("<3f", b, o + 84)
            p2b = struct.unpack_from("<12f", b, o + 96)
            self.bones.append(dict(name=name, parent=parent, pos=pos, quat=quat, rot=rot, posscale=posscale, rotscale=rotscale,
                                   p2b=[list(p2b[0:4]), list(p2b[4:8]), list(p2b[8:12])]))
        na, ai = struct.unpack_from("<ii", b, 240)
        self.attachments = {}
        for i in range(na):
            o = ai + i * 92
            name = cstr(b, o + struct.unpack_from("<i", b, o)[0])
            bone = struct.unpack_from("<i", b, o + 8)[0]
            lm = struct.unpack_from("<12f", b, o + 12)
            local = [list(lm[0:4]), list(lm[4:8]), list(lm[8:12])]
            self.attachments[name.lower()] = mul34(inv34(self.bones[bone]["p2b"]), local)  # mesh space
        nt, ti = struct.unpack_from("<ii", b, 204)
        self.textures = [cstr(b, ti + i * 64 + struct.unpack_from("<i", b, ti + i * 64)[0]) for i in range(nt)]
        nc, ci = struct.unpack_from("<ii", b, 212)
        self.cdtextures = [cstr(b, struct.unpack_from("<i", b, ci + i * 4)[0]) for i in range(nc)]
        self.numskinfamilies = struct.unpack_from("<i", b, 224)[0]
        nic, ici = struct.unpack_from("<ii", b, 336) if self.version >= 44 else (0, 0)
        self.includemodels = []
        for i in range(nic):
            o = ici + i * 8
            self.includemodels.append(cstr(b, o + struct.unpack_from("<i", b, o + 4)[0]))
        self.verts = []
        if vvd:
            n0 = struct.unpack_from("<i", vvd, 16)[0]
            vs = struct.unpack_from("<i", vvd, 56)[0]
            for k in range(n0):
                o = vs + k * 48
                w = struct.unpack_from("<3f", vvd, o)
                bo = struct.unpack_from("<3B", vvd, o + 12)
                nbw = vvd[o + 15]
                pos = struct.unpack_from("<3f", vvd, o + 16)
                main = max(range(nbw), key=lambda j: w[j]) if nbw else 0
                self.verts.append((pos, bo[main]))

    def anim0_locals(self):
        """Local bone transforms of animation 0, frame 0 (raw and compressed tracks), default values otherwise."""
        b = self.b
        out = [qmat(bn["quat"], bn["pos"]) for bn in self.bones]
        na, ai = struct.unpack_from("<ii", b, 180)
        if na == 0:
            return out
        animblock, animindex = struct.unpack_from("<ii", b, ai + 52)
        if animblock != 0:
            return out
        p = ai + animindex
        for _ in range(len(self.bones) + 1):
            bone, fl, nxt = struct.unpack_from("<BBh", b, p)
            if bone >= len(self.bones):
                break
            bn = self.bones[bone]
            d = p + 4
            q = bn["quat"]
            pos = bn["pos"]
            if fl & 0x20:  # RAWROT2: Quaternion64
                v = struct.unpack_from("<Q", b, d)[0]
                d += 8
                xs = [((v >> s) & 0x1FFFFF) for s in (0, 21, 42)]
                qx, qy, qz = [(x - 1048576) / 1048576.5 for x in xs]
                w = math.sqrt(max(0.0, 1 - qx * qx - qy * qy - qz * qz))
                q = (qx, qy, qz, -w if v >> 63 else w)
            if fl & 0x02:  # RAWROT: Quaternion48
                x, y, zw = struct.unpack_from("<HHH", b, d)
                d += 6
                qx, qy, qz = (x - 32768) / 32768.0, (y - 32768) / 32768.0, ((zw & 0x7FFF) - 16384) / 16384.0
                w = math.sqrt(max(0.0, 1 - qx * qx - qy * qy - qz * qz))
                q = (qx, qy, qz, -w if zw & 0x8000 else w)
            if fl & 0x01:  # RAWPOS: Vector48
                pos = struct.unpack_from("<3e", b, d)
                d += 6
            if fl & 0x08:  # ANIMROT: 3 offsets to mstudioanimvalue_t runs
                base = d
                offs = struct.unpack_from("<3h", b, d)
                d += 6
                e = []
                for j in range(3):
                    val = 0
                    if offs[j]:
                        val = struct.unpack_from("<h", b, base + offs[j] + 2)[0]  # frame 0 = first value after {valid,total}
                    e.append(bn["rot"][j] + val * bn["rotscale"][j])
                q = euler_quat(e)
            if fl & 0x04:  # ANIMPOS
                base = d
                offs = struct.unpack_from("<3h", b, d)
                d += 6
                pos = tuple(bn["pos"][j] + (struct.unpack_from("<h", b, base + offs[j] + 2)[0] if offs[j] else 0) * bn["posscale"][j]
                            for j in range(3))
            out[bone] = qmat(q, pos)
            if nxt == 0:
                break
            p += nxt
        return out

    def bone_index(self, name):
        for i, bn in enumerate(self.bones):
            if bn["name"].lower() == name.lower():
                return i
        return -1

    def bone_mesh(self, name):
        """bind-pose bone frame in mesh space"""
        return inv34(self.bones[self.bone_index(name)]["p2b"])

    def runtime(self, bone):
        """mesh -> entity transform of a bone's vertices when the model plays animation 0 (prop_dynamic default)."""
        locs = self.anim0_locals()
        chain = [None] * len(self.bones)
        for i, bn in enumerate(self.bones):
            chain[i] = locs[i] if bn["parent"] < 0 else mul34(chain[bn["parent"]], locs[i])
        return mul34(chain[bone], self.bones[bone]["p2b"])


# ------------------------------------------------------------------------------------------------ VMT
def vmt_tokens(text):
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c.isspace():
            i += 1
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif c in "{}":
            yield c
            i += 1
        elif c == '"':
            j = text.find('"', i + 1)
            j = n if j < 0 else j
            yield text[i + 1:j]
            i = j + 1
        else:
            j = i
            while j < n and not text[j].isspace() and text[j] not in '{}"':
                j += 1
            yield text[i:j]
            i = j


def vmt_parse(text):
    toks = list(vmt_tokens(text))
    pos = 0

    def block():
        nonlocal pos
        items = []
        while pos < len(toks):
            t = toks[pos]
            if t == "}":
                pos += 1
                return items
            key = t
            pos += 1
            if pos < len(toks) and toks[pos] == "{":
                pos += 1
                items.append((key, block()))
            elif pos < len(toks):
                items.append((key, toks[pos]))
                pos += 1
        return items
    shader = toks[0]
    pos = 2 if len(toks) > 1 and toks[1] == "{" else 1
    return shader, block()


def vmt_write(shader, items, depth=1):
    pad = "\t" * depth
    lines = []
    for k, v in items:
        if isinstance(v, list):
            if k.lower() == "proxies":
                continue
            lines.append('%s"%s"\n%s{\n%s%s}' % (pad, k, pad, vmt_write(None, v, depth + 1), pad))
        else:
            lines.append('%s"%s" "%s"' % (pad, k, v))
    body = "\n".join(lines) + "\n"
    return body if shader is None else '"%s"\n{\n%s}\n' % (shader, body)


def vmt_default_tint(items):
    """TF2 tints paintable items through the ItemTintColor proxy ($colortint_base -> $color2); bake the default tint."""
    keys = {k.lower(): v for k, v in items if isinstance(v, str)}
    if "$colortint_base" in keys and "$color2" not in keys:
        nums = [float(x) for x in re.findall(r"[-\d.]+", keys["$colortint_base"])][:3]
        if len(nums) == 3:
            if "{" in keys["$colortint_base"]:
                nums = [n / 255.0 for n in nums]
            items.append(("$color2", "[%.3f %.3f %.3f]" % tuple(nums)))
    return items


def vmt_textures(items):
    for k, v in items:
        if isinstance(v, list):
            yield from vmt_textures(v)
        elif TEXTURE_KEYS.match(k) and v and v.lower() not in ("env_cubemap",) and not v.startswith("_rt_"):
            yield v.replace("\\", "/").lower()


# ------------------------------------------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tf2", required=True, help="Team Fortress 2 install dir (contains tf/)")
    ap.add_argument("--out", required=True, help="where to write models/ and materials/ (e.g. dystopia/download)")
    ap.add_argument("--cfg", help="write the hat entries for dys_hats.cfg here (server operators; players don't need it)")
    a = ap.parse_args()
    tf2 = TF2(a.tf2)
    written = []

    def put(name, data):
        dst = os.path.join(a.out, name)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(data)
        written.append(name)

    classes = {}

    def cls_model(c):
        """class model, its eyes frame (mesh space) and the head top in that frame"""
        if c not in classes:
            m = MDL(tf2.read("models/player/%s.mdl" % c))
            eyes = m.attachments.get("eyes")
            head = m.attachments.get("head") or m.attachments.get("partyhat")
            if eyes is None:
                # engineer, pyro: no "eyes"; use the soldier's eyes and head-top offsets from the head bone, with
                # TF2's bind-pose axes (forward = mesh +z, left = mesh +x, up = mesh +y)
                sm, seyes, stop = cls_model("soldier")
                hb = [m.bone_mesh("bip_head")[r][3] for r in range(3)]
                shb = [sm.bone_mesh("bip_head")[r][3] for r in range(3)]
                o = [hb[r] + seyes[r][3] - shb[r] for r in range(3)]
                eyes = [[0, 1, 0, o[0]], [0, 0, 1, o[1]], [1, 0, 0, o[2]]]
                classes[c] = (m, eyes, stop)
                return classes[c]
            top = apply34(inv34(eyes), [head[r][3] for r in range(3)])
            classes[c] = (m, eyes, top)
        return classes[c]

    entries = []
    done_materials = set()
    for hid, name, model in HATS:
        if not tf2.has(model):
            print("skip %s: %s not in the TF2 VPKs" % (hid, model))
            continue
        c = next((c for c in CLASSES if "/%s/" % c in model or model.endswith("_%s.mdl" % c)), "soldier")
        stem = model[:-4]
        mdl = tf2.read(model)
        vvd = tf2.read(stem + ".vvd")
        m = MDL(mdl, vvd)
        if m.version != 48:
            print("skip %s: MDL version %d (Dystopia loads 48)" % (hid, m.version))
            continue
        for ext in MODEL_EXTS:
            if tf2.has(stem + ext):
                put(stem + ext, tf2.read(stem + ext))
        # the bone most vertices hang on decides the runtime placement
        counts = {}
        for _p, bo in m.verts:
            counts[bo] = counts.get(bo, 0) + 1
        bone = max(counts, key=counts.get)
        cm, eyes, top = cls_model(c)
        place = m.runtime(bone)
        bname = m.bones[bone]["name"]
        # TF2 bone-merges the hat: its bones follow the player's bones of the same name. Use the first bone up the
        # hat's hierarchy that the class skeleton has (jiggle bones such as prp_hat hang below bip_head).
        mb = bone
        while mb >= 0 and cm.bone_index(m.bones[mb]["name"]) < 0:
            mb = m.bones[mb]["parent"]
        if mb >= 0:
            to_class = mul34(cm.bone_mesh(m.bones[mb]["name"]), m.bones[mb]["p2b"])
            how = "merge:" + m.bones[mb]["name"]
        else:
            to_class = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]]
            how = "mesh"
        adj = [[1, 0, 0, DYS_HEAD_TOP[0] - top[0]], [0, 1, 0, DYS_HEAD_TOP[1] - top[1]], [0, 0, 1, DYS_HEAD_TOP[2] - top[2] + LIFT]]
        local = mul34(adj, mul34(inv34(eyes), mul34(to_class, inv34(place))))
        ang = matrix_angles(local)
        pos = tuple(local[r][3] for r in range(3))
        # sanity: the hat geometry in Dystopia's eyes frame should hug the head
        pts = [apply34(local, apply34(place, p)) for p, _ in m.verts]
        lo = [min(p[i] for p in pts) for i in range(3)]
        hi = [max(p[i] for p in pts) for i in range(3)]
        print("%-12s %-9s %-16s bone %-14s pos %7.1f %7.1f %7.1f  ang %6.1f %6.1f %6.1f  skins %d  in eyes frame x %.0f..%.0f y %.0f..%.0f z %.0f..%.0f"
              % (hid, c, how, m.bones[bone]["name"], pos[0], pos[1], pos[2], ang[0], ang[1], ang[2], m.numskinfamilies,
                 lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
        # materials
        for t in m.textures:
            found = None
            for cd in m.cdtextures or [""]:
                cand = ("materials/" + cd.replace("\\", "/") + t.replace("\\", "/")).lower().replace("//", "/") + ".vmt"
                if tf2.has(cand):
                    found = cand
                    break
            if not found:
                print("   material %s not found" % t)
                continue
            todo = [found]
            while todo:
                vmt = todo.pop()
                if vmt in done_materials:
                    continue
                done_materials.add(vmt)
                text = tf2.read(vmt).decode("latin1")
                shader, items = vmt_parse(text)
                put(vmt, vmt_write(shader, vmt_default_tint(items)).encode("latin1"))
                for k, v in items:
                    if k.lower() == "include" and isinstance(v, str):
                        todo.append(v.replace("\\", "/").lower())
                for tex in vmt_textures(items):
                    vtf = "materials/" + tex + ("" if tex.endswith(".vtf") else ".vtf")
                    if tf2.has(vtf) and vtf not in done_materials:
                        done_materials.add(vtf)
                        put(vtf, tf2.read(vtf))
        entries.append('\t\t"%s" { "name" "%s (TF2)" "model" "%s" "pos" "%.1f %.1f %.1f" "ang" "%.1f %.1f %.1f"%s "tf2" "1" "fallback" "%s" }'
                       % (hid, name, model, pos[0], pos[1], pos[2], ang[0], ang[1], ang[2],
                          ' "teamskins" "1"' if m.numskinfamilies >= 2 else "", FALLBACK.get(hid, "cone")))
    if a.cfg:
        os.makedirs(os.path.dirname(os.path.abspath(a.cfg)), exist_ok=True)
        with open(a.cfg, "w", newline="\n") as f:
            f.write("// Dystopia Hats - addons/sourcemod/configs/dys_hats_tf2.cfg (written by tools/tf2_hats.py)\n"
                    "// TF2 hats: the server needs the hat files (run tf2_hats.py with a TF2 install, --out <server>/dystopia/download).\n"
                    "// Only players who set \"setinfo dys_tf2hats 1\" (and ran tf2_hats.py themselves) get the TF2 model; everyone else\n"
                    "// sees the \"fallback\" HL2 hat from dys_hats.cfg. pos/ang: see dys_hats.cfg; keep scale at 1 (origin at the feet).\n"
                    "\"DysHats\"\n{\n\t\"hats\"\n\t{\n" + "\n".join(entries) + "\n\t}\n}\n")
    with open(os.path.join(a.out, "dys_hats_tf2_files.txt"), "w", newline="\n") as f:
        f.write("# files written by dys_hat tools/tf2_hats.py from your own TF2 install; delete these to remove them\n")
        f.write("\n".join(sorted(set(written))) + "\n")
    print("%d hats, %d files -> %s%s" % (len(entries), len(set(written)), a.out, "; cfg entries -> " + a.cfg if a.cfg else ""))
    print("Players: add  setinfo dys_tf2hats 1  to dystopia/cfg/autoexec.cfg, so servers with TF2 hats send them to you.")


if __name__ == "__main__":
    main()
