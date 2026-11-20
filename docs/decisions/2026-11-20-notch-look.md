# How should the notch look?

Decided: 2026-11-20 · Case: c_144f4911-9225-4292-aca6-4b05dcbb2236

## Question and choice
How should the notch look once it shows music with a live spectrum and an AI-agents panel (plan usage, credits, live sessions, runaway warnings)?

Chosen: "Approve the look. Write the design doc from these mockups." The approved mockup is `docs/superpowers/mockups/notch-look/index.html`:

- Closed notch, 270 wide: artwork + 3 smooth spectrum bars left of the camera; the tightest plan-limit percentage right of it, with a hairline fill.
- Runaway warning, 360 wide, drops down on its own: agent, project, first prompt, burn rate vs normal; Stop and Redirect as keycaps; Redirect opens a text field.
- Hover panel, 440 wide, **tabs** (Agents, Music) in a floating pill under the panel, as in NotchNook. Opens on Agents while a session runs.
- Agents side in Hex's style: black and white, Inter, monospace figures, hairline panels, one glossy keycap.
- Music side and the tab pill follow NotchNook.

## Why
- "I'd like it to keep a very clean style anyway; Hex is a bit cyberpunk too, but it's all black and white and very, very clean." The agents side uses Hex's style and its font (Inter).
- "The notch is too wide, we need to make it shorter in order to not waste menu bar space." Every state got narrower and grows down instead of sideways.
- "I prefer tabs instead of stacked… if possible, look at how NotchNook does it." The tab pill copies NotchNook's floating pill.
- "Make the music histogram with fewer bars, even just 3 is fine, and much smoother." 3 rounded bars, low-pass smoothed.
- Agent's reason: height costs no menu-bar space and only shows on hover, so the panel grows down.

## Constraints
- Closed notch stays at or under today's width (about 285 on a 14-inch MacBook); target 270.
- Runaway warning at most 360 wide; hover panel at most 440 wide.
- Agents UI uses only black, white and greys (Hex tokens: #070707, #F2F2EF, ink at 7/10/14% for lines); no accent colours.
- Agents text is Inter (bundled in the app); figures are the system monospace font.
- Music visualizer: 3 bars, smooth, no jitter.
- Tabs live in a pill under the panel; the open tab shows icon + name, others icon only.

## Ruled out
- Pixel / bitmap-font cyberpunk (neon, CRT, CRT-on-alert): too busy; the human asked for Hex's clean black-and-white style.
- Split layout (music and agents side by side, 700 wide): wastes menu-bar space.
- Stacked layout (music row above agents, 440 wide): the human prefers tabs.
- 14-bar spectrum: the human asked for about 3 smooth bars.

## Comments
- "Too wide, wastes menu bar space": closed 420 → 270, warning 540 → 360, hover 700 → 440.
- "Clean like Hex, same font": restyled the agents side with Hex's measured tokens and Inter.
- "Fewer, smoother bars; tabs like NotchNook": 3 low-pass bars; floating tab pill taken from NotchNook's demo video.

## Open questions
none

## Sources
- Case c_144f4911-9225-4292-aca6-4b05dcbb2236
- `docs/superpowers/mockups/notch-look/index.html` (approved mockup)
- https://anoma.ly/hex/ (computed styles: Inter Variable, #070707, #F2F2EF, hairlines, 12.8px radius, keycap)
- https://lo.cafe/notchnook (demo video frames: few-bar visualizer when closed, floating tab pill)
- `Sources/OpenNotch/NotchWindow.swift` (today's ambient width ≈ notch gap + 94; expanded 416 × 124)
