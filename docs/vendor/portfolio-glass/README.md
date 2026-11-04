# Active Theory pane: direct source port

Source: https://github.com/reverieach/rhine-lab-art/tree/b980da73b37f4b4b75112bc2f3b529e8edb39566
Original publisher: Active Theory https://activetheory.net/
Preserved release: 1780406240914, snapshot 2026-09-30.

`shader-source.json` contains byte-for-byte named sections extracted from the
upstream `vendor/activetheory/compiled.vs` pack (the `{@}` separator is omitted).
`cube.json` is the original `public/assets/geometry/work/cube.json`.
The normal/environment JPEGs under `public/reference/active-theory/` are the
original `tree_room/waternormals.jpg` and `work/env1.jpg` files.
Original statements are retained in UPSTREAM_NOTICES.md. Public availability
is not a uniform MIT grant; this port does not relicense upstream code/assets.
No upstream runtime, credentials, music, project media or font binaries are imported. The pane and floating UI shader sections are reused explicitly as documented below.

## Adapter changes

- `active-theory-pane.ts` resolves Hydra's named requires and selects its desktop
  sine implementation. Three supplies built-in matrices/attributes.
- `vBackface` is explicitly initialized to zero, removing an undefined varying.
- The two Hydra drawbuffer statements become separate material variants. A
  dedicated offscreen WorkRefraction pass writes `refractionOut`, then the main
  pass samples that completed target. The capture never reads its own target.
  Three's output color/tone conversion is applied only to the final main pass.
- Blank black tMap/tVideo replace the reference portfolio's media; uVideoBlend=0,
  uColor=black, uHover=0, uMouse=(.5,.5), uPhone=0, uScale=(1,1). The source UIL
  Fresnel/refraction ratio=1 and distortion strength=0 are preserved. Hover
  deformation is disabled to preserve the approved train clearance. The original
  wave, slant, blur kernel, refraction and blend equations remain unchanged.
- Keep source geometry normals/UVs, scale (4,2.6,1), rotationZ=pi. A uniform
  normalization fits each pane to the existing train width, without changing
  individual rail motion. No independent TV frame or replacement glass model.
- Textures load through fetch/createImageBitmap in the existing OffscreenCanvas
  worker; no DOM TextureLoader or Hydra runtime needed.

- Project covers use native Three r184 DecalGeometry to generate a separate
  `projectUv` attribute (copy UV only). Source positions, normals and atlas stay
  intact. Each glass mesh has one cover sampler, composed on its front fragments
  after the output conversion. There is no second picture plane or independent
  border. The cover shares the original vertex wave/shear; typography uses the reference UI sibling described below. The capture material
  excludes preview composition and restores each mesh's distinct main material.

## Collision bound

At uHover=0/uMouse=.5, source z is at most .0189912349+.1. Dividing by
3.0385975784 gives <.03916, contained by the existing conservative .043 depth
support. Source y slant gives <.352 normalized height support. Rail radius1.42
minus max .64*.043 leaves1.39248, greater than the approved full robot/arms
radius1.3301 plus required .05 clearance. All panels keep the same tangent rail.

## Identity

See SOURCE.json for immutable URLs and SHA-256. ScanCode broker could not run
because its pinned Docker socket was unavailable; no successful automated license
scan or blanket commercial-use authorization is claimed.

## Floating typography correction (2026-10-25)

`ui-shader-source.json` adds the source WorkItemUIShader.glsl and rgb2hsv.fs,
byte-preserved from the same frozen compiled.vs; SOURCE.json records their hashes.
`active-theory-label.ts` uses its exact vertex/fragment equations with the same
100×50 plane, source4×2scale, additive/double-sided/depth-tested material, and
same carriage parent as the pane. Only Three output color conversion and camera
distance units are adapted. The title bitmap is transparent1024² with the source
centered title/category layout; description is hidden. Native system Chinese
fonts replace the reference NBArchitekt binary. No separate opaque image frame.
See docs/project-preview-rendering.md for the source mapping and deviations.

## Upright-view adapter (2026-10-27)

The user requires upright panes and typography throughout free rotation and
selection, with a fully camera-facing selected front and mirrored rear geometry.
The fixed `uPresentationLock=1` adapter disables positional shear/asymmetric wave;
UI uses constant .4 forward depth and removes geometry/UV slant and edge distortion.
Frozen source JSON bytes stay unchanged. Each carriage compensates camera pitch
in place and preserves rail yaw. Ring centers stay horizontal, floating type
stays separate and depth-tested. There is no lock-dependent blend.
