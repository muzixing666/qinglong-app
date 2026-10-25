# FlClash UI port

Source: https://github.com/chen08209/FlClash

Pinned commit: 7fd417fb9a9a277c6a9339a8ac87f907df7c25f7

The navigation dock, liquid glass renderer and shader, shape, surface, typography,
color and vector icon helpers were copied from this revision on 2026-10-24.
They are covered by the upstream GPL-3.0 license bundled in
`assets/flclash-LICENSE.txt`. Original source comments are retained.

Changes: package imports adapted to qinglong_mobile, material_ui imports mapped
to the Flutter SDK's material compatibility exports, and context extensions
limited to the APIs these components use. Qinglong destinations and business
logic are wired separately in main.dart. No Clash networking core is included.

Post-port fixes: on the atlas capture path, load the fragment program regardless
of ImageFilter.shader support, because the atlas is painted with a regular
FragmentShader. The dock uses one glass lens and one icon pass; the extra platter,
hover tint, copied lens content and moving outer shell are disabled. This removes
the doubled dark selection and preserves a fixed outer dock.
After comparing the installed app's Extreme mode, carrier haze/tint were reduced
and the single lens's bevel/refraction now respond to lift, without adding an
opaque selection platter or drawing the icon row twice.

The upstream OpenContainer implementation is retained as a reference. Runtime
Qinglong entry transitions use origin.dart's single live-page clip, keeping the
source widget in place rather than reparenting or cloning nested action controls.

The distributed application's corresponding source is supplied alongside its APK.
