# Publication preview, confirmed camera and cover

Baseline production 6ea60d6f524974d0cdde2b00a6eb86ef7be821a1.

The publication page keeps the existing shared Three.js viewer mounted after source and selection confirmation. Orbit, pan and zoom remain available. A separate confirmation freezes the current perspective camera and a local preview PNG. Ordinary movement does not replace the confirmed view. Changing source, selection or account invalidates pending captures and confirmed framing. Existing immutable submissions retain their saved request.

A versioned camera descriptor binds finite camera position, target, up, vertical FOV and viewport aspect to the original source SHA and canonical selection identity. Client PNG is preview only. The backend generates and moderates the public cover against the bound derived asset. Publication detail applies a validated server camera once after the matching model identity is ready. Invalid or mismatched descriptors preserve existing official framing.

Reuse official Three.js PerspectiveCamera and OrbitControls. No renderer, geometry export, reconstruction algorithm, dependency or native change. Existing pre-submit selection is a presentation clipping preview. Exact derived-GLB boundary equivalence requires backend-derived bytes and remains a separately recorded interface constraint.

Focused acceptance covers camera roundtrip/reset/invalid values, immutable request binding, and stale source/selection/account callbacks. Browser rendering and public cover moderation/publication require root-owned real UI/backend evidence. Unit or protocol tests alone do not satisfy that acceptance.
