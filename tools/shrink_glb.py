"""把含 ARKit 臉部控制點的 .glb 縮小給手機用（avatar/models/female.glb 就是這樣從 TalkingHead 的 mpfb.glb 產生的）：
- 只保留 avatar.js 會用到的臉部控制點（morph targets），並移除控制點的 NORMAL
- 貼圖縮小（預設最長邊 1024），沒有透明度的改存 JPEG
用法：python tools/shrink_glb.py 原檔.glb 輸出.glb（需要 Pillow）
"""
import io
import json
import struct
import sys

from PIL import Image

KEEP = {
    'jawOpen', 'mouthClose', 'mouthFunnel', 'mouthPucker',
    'mouthSmileLeft', 'mouthSmileRight', 'mouthFrownLeft', 'mouthFrownRight',
    'mouthStretchLeft', 'mouthStretchRight', 'mouthPressLeft', 'mouthPressRight',
    'mouthLowerDownLeft', 'mouthLowerDownRight', 'mouthUpperUpLeft', 'mouthUpperUpRight',
    'mouthDimpleLeft', 'mouthDimpleRight', 'mouthShrugLower', 'mouthShrugUpper',
    'browDownLeft', 'browDownRight', 'browInnerUp', 'browOuterUpLeft', 'browOuterUpRight',
    'eyeBlinkLeft', 'eyeBlinkRight', 'eyeSquintLeft', 'eyeSquintRight', 'eyeWideLeft', 'eyeWideRight',
    'cheekSquintLeft', 'cheekSquintRight', 'noseSneerLeft', 'noseSneerRight', 'cheekPuff',
    'viseme_aa', 'viseme_O', 'viseme_E', 'viseme_I', 'viseme_U',
}
# mpfb.glb 的圖片名稱 → (最大邊長, 格式)；其他圖片：有透明度存 PNG、沒有存 JPEG，最長邊 1024
IMAGES = {
    'young_lightskinned_female_diffuse2': (1024, 'jpeg'),
    'female_casualsuit01_normal': (512, 'jpeg'),
    'female_casualsuit01_diffuse': (1024, 'jpeg'),
    'brown_eye': (512, 'png'),
    'ponytail01_diffuse': (1024, 'png'),
    'teeth': (512, 'jpeg'),        # 材質沒有開透明，alpha 用不到
    'tongue01_diffuse': (256, 'jpeg'),
}


def main(src, dst):
    d = open(src, 'rb').read()
    jl, = struct.unpack_from('<I', d, 12)
    j = json.loads(d[20:20 + jl])
    bin_start = 20 + jl + 8
    old_bv = j['bufferViews']

    def view_bytes(i):
        b = old_bv[i]
        o = bin_start + b.get('byteOffset', 0)
        return d[o:o + b['byteLength']]

    # 1) 篩選 morph targets
    for m in j['meshes']:
        names = m.get('extras', {}).get('targetNames')
        if not names:
            continue
        keep_idx = [i for i, n in enumerate(names) if n in KEEP]
        m['extras']['targetNames'] = [names[i] for i in keep_idx]
        if 'weights' in m:
            m['weights'] = [m['weights'][i] for i in keep_idx]
        for p in m['primitives']:
            p['targets'] = [{'POSITION': p['targets'][i]['POSITION']} for i in keep_idx]
            if not p['targets']:
                del p['targets']

    # 2) 收集仍被使用的 accessor，重新編號
    used_acc = []
    for m in j['meshes']:
        for p in m['primitives']:
            used_acc += list(p['attributes'].values()) + [p['indices']]
            for t in p.get('targets', []):
                used_acc += list(t.values())
    for s in j.get('skins', []):
        if 'inverseBindMatrices' in s:
            used_acc.append(s['inverseBindMatrices'])
    used_acc = sorted(set(used_acc))
    acc_map = {old: new for new, old in enumerate(used_acc)}

    out = bytearray()
    new_bv = []

    def add_view(data, extra=None):
        while len(out) % 4:
            out.append(0)
        v = {'buffer': 0, 'byteOffset': len(out), 'byteLength': len(data)}
        if extra:
            v.update(extra)
        out.extend(data)
        new_bv.append(v)
        return len(new_bv) - 1

    bv_map = {}

    def copy_view(i):
        if i not in bv_map:
            extra = {k: old_bv[i][k] for k in ('byteStride', 'target') if k in old_bv[i]}
            bv_map[i] = add_view(view_bytes(i), extra)
        return bv_map[i]

    new_acc = []
    for old in used_acc:
        a = dict(j['accessors'][old])
        if 'bufferView' in a:
            a['bufferView'] = copy_view(a['bufferView'])
        if 'sparse' in a:
            sp = json.loads(json.dumps(a['sparse']))
            sp['indices']['bufferView'] = copy_view(sp['indices']['bufferView'])
            sp['values']['bufferView'] = copy_view(sp['values']['bufferView'])
            a['sparse'] = sp
        new_acc.append(a)

    def remap(dct):
        for k in dct:
            dct[k] = acc_map[dct[k]]

    for m in j['meshes']:
        for p in m['primitives']:
            remap(p['attributes'])
            p['indices'] = acc_map[p['indices']]
            for t in p.get('targets', []):
                remap(t)
    for s in j.get('skins', []):
        if 'inverseBindMatrices' in s:
            s['inverseBindMatrices'] = acc_map[s['inverseBindMatrices']]

    # 3) 貼圖
    for im in j['images']:
        img = Image.open(io.BytesIO(view_bytes(im['bufferView'])))
        has_alpha = img.mode in ('RGBA', 'LA') and img.getchannel('A').getextrema()[0] < 255
        size, fmt = IMAGES.get(im.get('name'), (1024, 'png' if has_alpha else 'jpeg'))
        if max(img.size) > size:
            img = img.resize((size, size * img.size[1] // img.size[0]), Image.LANCZOS)
        buf = io.BytesIO()
        if fmt == 'jpeg':
            img.convert('RGB').save(buf, 'JPEG', quality=85, optimize=True)
            im['mimeType'] = 'image/jpeg'
        else:
            img.save(buf, 'PNG', optimize=True)
            im['mimeType'] = 'image/png'
        im['bufferView'] = add_view(buf.getvalue())

    j['accessors'] = new_acc
    j['bufferViews'] = new_bv
    while len(out) % 4:
        out.append(0)
    j['buffers'] = [{'byteLength': len(out)}]
    j.setdefault('asset', {})['extras'] = {
        'source': f'{src} (shrunk by tools/shrink_glb.py)'}

    js = json.dumps(j, separators=(',', ':'), ensure_ascii=False).encode()
    js += b' ' * (-len(js) % 4)
    total = 12 + 8 + len(js) + 8 + len(out)
    with open(dst, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
        f.write(struct.pack('<II', len(out), 0x004E4942) + out)
    print(f'{src} → {dst}: {len(d) / 1e6:.1f} MB → {total / 1e6:.1f} MB')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
