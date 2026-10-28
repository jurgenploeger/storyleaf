---
name: sprite-idle-animation
description: How sprites in Tales of Dorlune come alive while standing still (blinking, breathing in whole pixels, a monster's squish or hop) and the acceptance criteria every change to it must pass. Use it whenever a monster, boss, pet, townsperson sheet, hero body or hair, helmet or armour layer is added or changed (a new sprite needs its eyes boxed in art/eyes.json, or a reason it has none), whenever art/eyes.json, IdlePoses.swift, the eye code in ArtLibrary.swift or IdleMotion is edited, and whenever someone says a sprite looks frozen, stares, doesn't blink, winks, blinks oddly, smears when it breathes, or asks to animate sprites, even if they only ask about AI video or animation tools.
---

# Sprite idle animation

Standing still, everyone in Dorlune moves a little: monsters squish, hop, sway or bounce, people
breathe a pixel at a time, and everyone with eyes blinks every few seconds. All of it is made in
code from the art the game already has, so it costs nothing and never redraws Retro Diffusion's
art. This skill is how to extend it without breaking the look, and the bar every result has to clear.

## Where it lives

- `art/eyes.json`: every sprite's eyes. `pictures` (a monster's single picture: boxes on it),
  `sheets` (a walk sheet or body layer: boxes in each direction's first frame, which is the
  standing pose), `skipped` (every monster picture with no eyes, and why). An eye is
  `[x, y, w, h, fx, fy]`: its box from the top left, shut by painting it the colour at `(fx, fy)`.
- `TalesOfDorlune/Art/IdlePoses.swift` (`EyeBlink`): shutting eyes, the evenness check, the whole-pixel
  breath, the blink rhythm. `ArtLibrary.swift`: `eyeKey`, `stacked(shut:)`, `idlePoses`, `cleanFaces`
  build each direction's shut and breathing poses (`WalkCycle.poses`). `Walker.swift` and
  `BattleScene.swift` (`BattleActor`) play them; `IdleMotion` (Nodes.swift) is the monsters' motion.
- `scripts/eyes.py` (this skill): the same rules in Python, so you can find, preview and check eyes
  in a cloud session, which can't build the app. Run it from the repo root.

A cloud session can't compile Swift, and CI's macOS runners have sat queued for hours and been
cancelled before now. Treat `eyes.py check` and the zoomed previews as the real test of anything
eye- or breath-related, and say plainly when the Swift itself is still untested.

## Choosing how to animate

Before reaching for a generator, know why the game does it this way (tried 2026-10-26):

- Image-to-video models (Figma Weave's Kling, Veo, Seedance and the rest) want 300 px or more in and give 720p
  of smooth, repainted frames out. Shrunk back to a 40 px sprite and snapped to its palette, the
  motion turns to flicker, the outline and colours drift from the original (a redraw of Retro
  Diffusion's art, which the game doesn't allow), and every frame needs its background cut away.
  Fine for marketing clips, wrong for sprites.
- Retro Diffusion's animation styles make pixel-true sheets, but cost money: dry-run and ask first
  (CLAUDE.md).
- Code tricks cost nothing and keep every pixel RD drew: move whole pixels, swap a few for the
  sprite's own colours, transform the whole node for a monster's motion. Prefer these.

## Making a sprite blink

1. **Decide whether it has eyes that can shut.** Not every sprite does: no eyes drawn, eyes
   drawn shut already (happy arcs, a squint), empty sockets, a visor or a hood with no face. Those
   go in `skipped` with the reason. If the eyes are there but you can't tell them from the shading,
   skip it as `unclear: ...` and say what you couldn't tell apart; that's a candidate for later,
   not a failure. `check_content.py` won't let a monster picture be neither boxed nor skipped.
2. **Find the eye pixels with `dump`, not by eye.** `eyes.py dump ID X0 Y0 W H [--dir down]`
   prints a letter per colour with each colour's brightness. Use a zoomed grid
   (`eyes.py zoom`) only to find roughly where to look: coordinates read off a picture come out a
   pixel off nearly every time.
3. **Box the eye.**
   - Take every pixel that is eye: white, iris, pupil, glint, and a dark ring that belongs to it.
   - A person's eyes sit under a lid line drawn above them. Leave that line out of the box: shut,
     it's the closed eye.
   - A pair is boxed alike: the same width, so their lashes match, and the same rows unless the
     art has the eyes at different heights.
   - A one-pixel-wide eye gets a three-pixel lash, so give its partner a box one pixel wide too.
   - Check the ring round the box for an eye pixel you left out (a white below the dwarf's
     left eye stayed open once).
4. **Choose the fill pixel**, the colour the eye shuts in. It has to be the face's own colour
   beside the eye: a person's main skin (not a cheek's shade, a lock of hair or the outline), a
   monster's fur, both eyes of a pair the same colour. Pick it on the inner side of the face where
   hair can't reach it. `eyes.py fills` suggests fills by that rule and `--write` applies them, but
   it's a suggestion: look at the zoom after.
5. **Look at it.** Run `eyes.py zoom OUT ID[@dir][:x0:y0:w:h]` for each sprite and direction you
   touched, at the crop of its face, and read the image. For a townsperson or hero, also look at a
   stack (`body_x+locks_x+hair_y_x@down`) and at the helmet and armour cases if it's a body.
   `eyes.py sheet OUT --pictures` shows every monster at once.
6. **Check it.** Run `python3 .claude/skills/sprite-idle-animation/scripts/eyes.py check` and
   `python3 tools/check_content.py`. Both must pass before you push.

A copy made with `derive` (a palette swap) shuts its base's eyes in its own colours, so it needs no
entry. A new hero body needs eyes for all three directions that show a face (`right`, `down`,
`left`). The walk sheet it was cut from takes the same boxes, with fills chosen on that sheet: its hair
sits over pixels the bald body has bare.

## Acceptance criteria

Every change has to meet all of these. The first five are checked by `eyes.py check` (and the
first two by `check_content.py`); the rest you check by looking at the zoom, because a script can't
tell what reads as a closed eye.

1. Every eye's box is inside its frame and its fill pixel is opaque.
2. Every monster picture has eyes or a `skipped` reason; nothing is both.
3. Fills are the face's own colour: a person's are a skin colour shared round both eyes, and both of a
   monster's pair are the same colour.
4. A pair's lashes match in width and colour.
5. **Never a wink.** In every townsperson and every hero combination (each body, in every
   hairstyle, plain, hooded, under each helmet and in each armour sheet), a view blinks only if
   every eye in it shuts, and no eye white or iris pixel is left open inside a shut eye. A view that
   can't do that doesn't blink at all.
6. Shut, it reads as a closed eye at 1x and 2x: a lid line or a lash, no hole, no smudge of a
   different colour, nothing that looks like the eye moved.
7. Both eyes of a pair shut the same way, and nothing round the eye changes but the eye.
8. Breathing out moves everything above the waist down exactly one pixel and nothing else; the feet
   don't move, and no row is stretched.
9. No Retro Diffusion pixel outside an eye box is changed, and nothing is redrawn.
10. The Swift and `eyes.py` agree: a change to either's rules goes into the other in the same commit.

When a check fails, fix the data or the rule. Never loosen the check to get green, and never
switch the guard off for one sprite.

## Never a wink: why the rules are what they are

A wink, one eye shut and one open, reads as a joke or a glitch, never as a blink. Each rule
below exists because the case happened:

- **A layer shuts all its eyes or none** (`EyeBlink.shut`). The hero's head layer is cut off just
  below the eyes on some bodies, so one eye's fill pixel was clear and only the other shut.
- **A view blinks only if every eye there changed in the finished sprite**
  (`EyeBlink.shutsEvenly`). Long hair, a hood or a festive mask covers one eye, and the other then
  shut alone. The check runs on the sprite as finally drawn, so a mask GearOverlay paints later
  can only turn a blink off, never make a wink.
- **A helmet's or armour's own face stays open; such a view doesn't blink** (`ArtLibrary.cleanFaces`).
  Helmet layers (`hat_*`) and armour sheets (`armor_*`) carry a face of their own, with its eyes
  somewhere else. Shut with the body's boxes, a cheek smeared and an eye stayed open. Under a
  helmet nobody blinks. In armour, a view blinks only where the hero's head layer covers the
  armour's face for two pixels all round the eyes.
- **One-eyed entries must be side or three-quarter views.** A face that shows two eyes but has
  only one boxed is a wink waiting to happen; check every single-eye entry against the picture.

These guards cost some blinks: no helmeted hero blinks, and an armoured one blinks only facing
some ways. That's the right trade. Only claw a view back by covering the face properly (a fix in
the layers), never by relaxing a guard.

## Breathing

Walk sheets breathe in whole pixels: `EyeBlink.exhaled` moves every row above the waist (55% of the
way down what's drawn) one pixel lower, and `Walker.breathe` swaps between the two poses every
0.9 s. It replaced a 1.05 vertical stretch, which smeared pixels unevenly. Shut and breathing poses
combine (`outShut`), so a blink never jumps the head back up. Single pictures (monsters) keep
`IdleMotion` (squish, hop, sway, bounce, breathe), which moves the whole node. The weapon in hand
doesn't follow the one-pixel breath; at one pixel that's fine, so don't add code to chase it.

## Improving this skill

This skill should get better every time it's used. When something new goes wrong or a rule turns
out to be missing:

1. Fix the sprite or the code.
2. Add what you learned to `references/learnings.md`: dated, with the case and what to do instead.
3. If a script could have caught it, add the check to `eyes.py check`, or to `check_content.py` if
   it needs no image library. Then make sure it fails on the old data and passes on the fix.
4. If it changes how the work is done, update the steps or criteria above. Keep them about *why*,
   so the next case that's a little different is still covered.

Read `references/learnings.md` before boxing a sprite that looks unusual: a cyclops, a face in
profile, eyes on stalks, a sprite behind glass or under a hat.
