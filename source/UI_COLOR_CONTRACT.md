# Interface color contract

User instruction, revised 2026-11-06. Website, mobile App, activity pages and 3D guide chrome use black, white and neutral gray. Errors, delete actions and account cancellation may use red. Success, ordinary feedback, selected states, hover/focus states, buttons, labels, dialogs and annotation markers use grayscale.

Canonical product guidance lives in `design/README.md` and `design/ui-spec.html` of the shared application source. Shared implementation is `lib/ui/design_system.dart`, mirrored under `source/community_app/lib/ui/design_system.dart` in this repository. Site styles follow this same contract. Content media and model data carry their source colors.

The resort green theme was introduced in a5b3ee62464b1885d3886f0a0996e5e15d66ce38 without a user-approved theme requirement. It and the ceramic page green-gray styling are replaced by grayscale. The former success-green exception in the design guide is superseded.
