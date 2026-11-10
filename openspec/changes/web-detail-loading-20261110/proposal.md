# Website detail loading and comment selection

## Approved scope

- Render known work text in the existing startup shell before Flutter and GLB readiness. Preserve normal access validation.
- Preserve the public model controller across browser authentication changes. A different model URL still initializes a new controller. Native session ownership retains its current behavior.
- Restore percentage labels using the HTTP length or the existing published model size. Retain the last known percentage when progress is unknown and keep below 100 until first-frame readiness.
- While the website comments pane is visible, show its text once in the pane. Model points remain visible. Selection highlights the chosen point and makes the others faint. Deselecting or closing the pane restores normal points.
- Base this change on the actual deployed source and preserve all other website functionality. Store version archives remotely, with local files limited to active development and temporary builds.

## Verification

Use the existing metadata, model progress, startup shell and surface-comment regressions plus one browser identity regression. Check real website entry, percentage, point selection, and unchanged asset identities before publishing.
