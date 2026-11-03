# Point cloud detail and spatial comments

Reuse pinned Three.js Points.raycast and existing shared viewer, comment anchors, immutable model SHA and backend for PLY. Save actual vertex coordinates, support projected pins and saved camera focus. Point-cloud markers follow transparent point-cloud semantics; mesh occlusion remains. No point-set raycasts per animation frame.

Route PLY detail through ProductModelView: native file paths are unavailable on Web. Direct-linked details return to site homepage; stacked navigation pops. Automatically append feed pages from bottom sentinel while preserving cursor/error/end semantics. No new algorithm, parser, dependency or comment schema.

Backend extends only two existing format guards to GLB/PLY, retaining grants/path/SHA checks; three PLY identities registered. Rejected stylized samples removed from community. Replacement assets must be realistic and commercially reusable.
