# Remplace l'icône d'un exe Windows (ressources RT_ICON / RT_GROUP_ICON) en place, sans rcedit.
import struct, sys, io
from PIL import Image

def parse(data):
    pe = struct.unpack_from('<I', data, 0x3C)[0]
    nsec = struct.unpack_from('<H', data, pe + 6)[0]
    optsz = struct.unpack_from('<H', data, pe + 20)[0]
    opt = pe + 24
    magic = struct.unpack_from('<H', data, opt)[0]
    dd = opt + (112 if magic == 0x20b else 96)
    rsrc_rva, rsrc_size = struct.unpack_from('<II', data, dd + 2 * 8)
    sec = opt + optsz
    sections = []
    for i in range(nsec):
        o = sec + 40 * i
        name = data[o:o + 8].rstrip(b'\0')
        vsize, va, rawsize, rawptr = struct.unpack_from('<IIII', data, o + 8)
        sections.append((name, va, vsize, rawptr, rawsize))
    def rva2off(rva):
        for n, va, vs, rp, rs in sections:
            if va <= rva < va + vs:       # taille virtuelle d'abord (la section « pck » de Godot est trompeuse)
                return rva - va + rp
        for n, va, vs, rp, rs in sections:
            if va <= rva < va + rs:
                return rva - va + rp
        raise ValueError(hex(rva))
    base = rva2off(rsrc_rva)
    res = {}
    def walk(off, path):
        nnamed, nid = struct.unpack_from('<HH', data, off + 12)
        for i in range(nnamed + nid):
            name, ptr = struct.unpack_from('<II', data, off + 16 + 8 * i)
            key = path + [name]
            if ptr & 0x80000000:
                walk(base + (ptr & 0x7fffffff), key)
            else:
                ent = base + ptr
                rva, size = struct.unpack_from('<II', data, ent)
                res[tuple(key)] = (ent, rva2off(rva), size)
    walk(base, [])
    return res

def dib(img):
    """Image RGBA -> entrée d'icône BMP 32 bits (en-tête + pixels BGRA de bas en haut + masque AND)."""
    w, h = img.size
    px = img.tobytes('raw', 'BGRA')
    rows = [px[y * w * 4:(y + 1) * w * 4] for y in range(h)]
    mask_row = ((w + 31) // 32) * 4
    header = struct.pack('<IiiHHIIiiII', 40, w, h * 2, 1, 32, 0, w * h * 4 + mask_row * h, 0, 0, 0, 0)
    return header + b''.join(reversed(rows)) + b'\0' * (mask_row * h)

def main(exe_path, ico_path):
    data = bytearray(open(exe_path, 'rb').read())
    res = parse(data)
    icons = {k[1]: v for k, v in res.items() if k[0] == 3}
    groups = {k[1]: v for k, v in res.items() if k[0] == 14}
    gid = sorted(groups)[0]
    gent, goff, gsize = groups[gid]
    cnt = struct.unpack_from('<H', data, goff + 4)[0]
    slots = []
    for i in range(cnt):
        e = goff + 6 + 14 * i
        w, h, cc, r, planes, bpp, size, iid = struct.unpack_from('<BBBBHHIH', data, e)
        slots.append((e, w or 256, iid))
    src = Image.open(ico_path).convert('RGBA')
    for e, w, iid in slots:
        ent, off, cap = icons[iid]
        img = src.resize((w, w), Image.LANCZOS)
        blob = None
        if w < 256:
            # Petites tailles : format BMP 32 bits (comme l'icône d'origine), lu partout par Windows
            blob = dib(img)
            if len(blob) > cap:
                blob = None
        if blob is None and w >= 256:
            for colors in (None, 256, 128, 64):
                buf = io.BytesIO()
                im = img if colors is None else img.quantize(colors=colors, method=Image.FASTOCTREE).convert('RGBA')
                im.save(buf, 'PNG', optimize=True)
                if len(buf.getvalue()) <= cap:
                    blob = buf.getvalue()
                    break
        if blob is None:
            print(f"  {w}px : place insuffisante ({cap} octets), image d'origine conservée")
            continue
        data[off:off + len(blob)] = blob
        data[off + len(blob):off + cap] = b'\0' * (cap - len(blob))
        struct.pack_into('<I', data, ent + 4, len(blob))          # taille de la ressource RT_ICON
        struct.pack_into('<I', data, e + 8, len(blob))            # taille dans le groupe
        struct.pack_into('<HH', data, e + 4, 1, 32)               # planes, bpp
        print(f"  {w}px : remplacée ({len(blob)}/{cap} octets)")
    open(exe_path, 'wb').write(data)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
