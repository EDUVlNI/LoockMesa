# Golden Gate cursor integration

The user-provided GoldenGate.cape is bundled unchanged. It contains 42 cursor definitions. Artwork metadata is preserved (point sizes, hotspots, scale representations, frame count and duration); bitmap representations are sorted by pixel size before registration.

The opt-in setting is under Tela / Ponteiro. Gergelim registers native cursor images globally through dynamically resolved APIs, without hiding/warping the pointer, tracking mouse movement, drawing a second cursor, modifying system files or changing SIP. App-specific custom cursors and secure system surfaces are outside this feature's scope.

Before any registration, existing compatible cursors are captured and saved atomically under Application Support/Gergelim/CursorOriginals.plist. Unsupported identifiers are skipped and the applied count is shown. The arrow must be recoverable. Registration failures roll back; unsuccessful restoration retains the snapshot for recovery next launch. Disabling or quitting restores the captured images. After a crash, recovery occurs on the next launch, not immediately. Wake/session/display notifications trigger one debounced reapplication, with no recurring polling. Do not use two cursor theme managers simultaneously.

Private API ABI reference: Alex Zielenski / Alacatia Labs, CGSInternal/CGSCursor.h in https://github.com/alexzielenski/Mousecape (184f87b5d8ba52e0529f0ca8a7bd15b25b101358). This implementation is independent Swift code; Mousecape application code is not bundled. The uploaded artwork's metadata identifies Apple, Inc.; this does not establish independent provenance or redistribution rights.

Automated tests decode every representation, verify frame geometry and exact hotspot preservation, round-trip the recovery serialization and reject invalid input. CI does not globally apply the theme. Required on-device tests: Ventura 13.7.8 Intel activation, arrow/I-beam/resize/hand/wait, dragging and exact click position, Retina/external displays, wake, disable/quit/relaunch and recovery after forced termination. Native API compatibility is unverified until these tests run.
