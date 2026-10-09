"""把 Microsoft Rocketbox 的 *_facial.fbx 轉成 avatar.js 能用的 .glb（在 Blender 裡執行）。

用法（之後再用 shrink_glb.py 縮小）：
  blender -b --python tools/rocketbox_to_glb.py -- <人物>/Export/<人物>_facial.fbx <人物>/Textures 輸出.glb

做的事：
- 貼圖改指向 Textures 資料夾（FBX 內記錄的是原作者電腦的絕對路徑）
- 臉部控制點改成 ARKit 名稱（AK_25_JawOpen → jawOpen、AA_VI_10_aa → viseme_aa），對照表同 TalkingHead
- 拿掉高光貼圖、金屬度設 0；骨架維持 Rocketbox 原本的 Bip01 命名（avatar.js 認得）
"""
import ntpath
import os
import re
import sys

import bpy

VISEMES = {'Sil': 'sil', 'KK': 'kk'}   # 其餘 viseme 名稱照抄（PP、FF、aa、E…）


def arkit_name(name):
    m = re.fullmatch(r'AK_\d+_(\w+)', name)
    if m:
        return m.group(1)[0].lower() + m.group(1)[1:]
    m = re.fullmatch(r'AA_VI_\d+_(\w+)', name)
    if m:
        return 'viseme_' + VISEMES.get(m.group(1), m.group(1))
    return None


def main(fbx, tex_dir, out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fbx, use_anim=False)

    # 貼圖
    for img in bpy.data.images:
        path = os.path.join(tex_dir, ntpath.basename(img.filepath))
        if os.path.exists(path):
            img.filepath = path
            img.reload()
        print('IMG', img.name, img.filepath, tuple(img.size))

    # 材質：移除高光貼圖、金屬度 0
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        nt = mat.node_tree
        for link in list(nt.links):
            if link.to_node.type == 'BSDF_PRINCIPLED' and link.to_socket.name.startswith('Specular'):
                node = link.from_node
                nt.links.remove(link)
                if node.type == 'TEX_IMAGE' and not node.outputs['Color'].links:
                    nt.nodes.remove(node)
        for node in list(nt.nodes):
            if node.type != 'BSDF_PRINCIPLED':
                continue
            node.inputs['Metallic'].default_value = 0.0
            # 頭髮、睫毛的透明度改成「切邊」（glTF 的 MASK）：半透明混合會在髮絲邊緣透出貼圖底色的白邊
            alpha = node.inputs['Alpha']
            if alpha.links:
                src = alpha.links[0].from_socket
                nt.links.remove(alpha.links[0])
                rnd = nt.nodes.new('ShaderNodeMath')
                rnd.operation = 'ROUND'
                nt.links.new(src, rnd.inputs[0])
                nt.links.new(rnd.outputs[0], alpha)

    # 臉部控制點改名
    renamed = 0
    for obj in bpy.data.objects:
        keys = obj.data.shape_keys.key_blocks if obj.type == 'MESH' and obj.data.shape_keys else []
        for kb in keys:
            new = arkit_name(kb.name)
            if new:
                kb.name = new
                renamed += 1
    print('SHAPEKEYS renamed', renamed)

    bpy.ops.export_scene.gltf(
        filepath=out, export_format='GLB',
        export_morph=True, export_morph_normal=False,
        export_animations=False, export_apply=False, export_skins=True,
        export_image_format='AUTO',
    )


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:]
    main(*args)
