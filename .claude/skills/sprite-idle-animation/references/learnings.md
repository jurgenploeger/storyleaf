# Learnings

Dated, newest last. Each says what happened and what to do instead. Add to it whenever a sprite or a
rule surprises you (see SKILL.md, *Improving this skill*).

## 2026-10-26: the first pass (PRs #295 and #296)

- **Generated video is the wrong tool for sprites.** Figma Weave's image-to-video models need 300 px
  or more, repaint every frame, and shrink back to 40 px as flicker. Code tricks on the existing
  pixels won. Use video models for marketing clips only.
- **Automatic eye detection doesn't work on this art.** Dark-cluster detection picked up fur
  shading, outlines and noses; "snap to the dark blob near a centre" grabbed 7×7 boxes. Find a
  rough centre on a zoomed grid, then read exact pixels with `eyes.py dump`, and box by hand.
- **Zoomed grids are a pixel off.** Every coordinate read off a picture needed correcting from a
  letter dump. Read coordinates from `dump`; use pictures only to find where to look and to judge
  the result.
- **A walk sheet's first frame is mid-stride.** The standing pose is column 0 of each direction's
  row, and it's what idles. Eyes are boxed there only; other frames move.
- **People have lids; monsters mostly don't.** A person's eye sits under a dark lid line: box the
  eye below it, and the line left behind is the shut eye. A monster's eye usually has no lid, so it
  gets a lash two-thirds of the way down. Tall eyes lash at two-thirds, not at the bottom.
- **The lash colour has to come from the eye itself.** Taking the darkest pixel round the eye gave
  the phantom one orange lash and one purple (its outline). Use the eye's own darkest colour, and
  the ring only when the eye is a white glint in a dark face (the black kong).
- **A pair's boxes must match.** The eagle's right eye was boxed one pixel wide and the left two,
  so one lash was three pixels and the other two. Box a pair alike.
- **Look round the box for eye pixels left out.** The dwarf's left eye kept a white pixel one row
  below its box. A ring check (white or iris colours unchanged next to a shut eye) found it.
- **Fills drift onto shades, hair and outlines.** Several fills were a cheek's shade (the right eye
  shut as a lighter smudge) or a lock of hair on the walk sheets the bodies were cut from
  (`elf_walk`'s left eye would have shut gold). Fills must be the face's main skin, shared round
  both eyes: `eyes.py fills` finds them, and its `--write` fixed 29.
- **"Commonest colour round the eye" is not the face's colour.** A first fill picker chose the
  dark outline or the treefrog's black band. For people, restrict to skin; for monsters, only
  unify a pair's two existing fills.
- **Helmets and armour carry their own faces.** Their eyes aren't where the body's are, so shutting
  them with the body's boxes smeared a cheek and left an eye open: a wink. They're left open, and
  such views don't blink (`cleanFaces`). A sweep of every combination is the only way to see this.
- **A head layer covers only part of the face.** On most bodies the armour's face shows through
  two pixels round the eyes, so armour blinks only facing some ways (a human facing you and to the
  right, not to the left). Accepted.
- **Breathing by stretching smears pixels.** A 1.05 vertical scale doubled some rows and not others.
  Move whole pixels instead.
- **Python mirrors are worth it.** Everything above was found by rendering the game's rules in
  Python, because the cloud can't build Swift and CI was queued for hours, then cancelled. Keep
  `eyes.py` in step with the Swift.
