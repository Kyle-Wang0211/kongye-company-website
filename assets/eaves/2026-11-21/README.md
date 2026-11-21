# 徽派高低墙

- [`hui-eaves-solid-r2.blend`](https://github.com/Kyle-Wang0211/kongye-company-website/releases/tag/hui-eaves-20261121-r2) 是砖列匀排、檐下换砖和内衬补齐后的 Blender 实体工程，贴图已封装，打开后以白模显示。
- [`hui-eaves-ink-r3.blend`](https://github.com/Kyle-Wang0211/kongye-company-website/releases/tag/hui-eaves-20261121-r3) 是相同几何体的水墨版。瓦片和砖分别用五天晴的原笔刷绘制重按、转锋、提笔三道，主光从画面左上方斜入。
- `wireframe/` 是同一模型的 Three.js 0.187.0 线框版。保留正面和背面的模型边。拖动或双指滑动可旋转，捏合缩放。Three.js 许可证位于 `wireframe/package/LICENSE`。

从仓库根目录启动本地查看器

```sh
python3 -m http.server 8769 --bind 127.0.0.1 --directory assets/eaves/2026-11-21/wireframe
```

打开 `http://127.0.0.1:8769/` 查看全景。加上 `?detail=1` 可查看垛头近景。两个 Blender 工程保存在同一仓库的 Release 附件。将附件下载到此目录后，可用 `SHA256SUMS` 核对。

笔刷出处 [五天晴 · 水墨笔刷 3D Ink Brush v1.0](https://wutianqing.gumroad.com/l/inkbrush)。
