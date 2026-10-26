# The CPU braid: design note

People open a system monitor with a question ("why is it hot, slow,
loud?") and want a culprit, not a graph
([research note 12](research/notes/12-user-jobs-to-be-done.md)).
Coreography's rare asset is memory: its ledger keeps every app's
CPU-seconds, disk and network bytes for each two-second interval of the
last hour. Any moment of the CPU line can be taken apart into who made
it. Before this prototype that knowledge hid in a one-line caption. Each concept below puts the invention at a
different moment of the same arc: finding the culprit, acting on it,
keeping the evidence.

## 1. Unbraid (discovery)

**Inspiration.** CPU is the one per-app quantity that adds up: the apps'
shares plus an unattributed remainder equal the host's busy share over each
interval. The total line is literally a rope made of apps.

**Before.** The CPU area is drawn as stacked strands in the lane's blue,
darkest at the bottom, with hairline seams like fibres. The host line stays
on top. Hovering lifts the strand under the pointer with a highlight.

**During.** Press on a spike and pull up. After 12 pt of mostly vertical
travel (horizontal still selects a range) the strands part around the
pointer: 8 pt gaps with a smoothstep falloff, a lens 56 pt wide growing to
44% of the plot, fully open at 48 pt, with a little extra tension to
96 pt. Strands bloom from blue into muted versions of their apps' icon hues,
spread at least 30 degrees apart and never red. The display holds; a card
names each strand with icon, share and the interval ("14:02:12–14:02:14 ·
2 s average").

**After.** Release past a quarter-open and the lens stays for reading.
Click an app (or Return) to catch it: a pluck in the app's own note and the
window scopes to it. Esc folds, and the seams ring for 300 ms.

**You have to see this.** An anonymous spike fraying into Xcode, Safari and
Spotlight's indexer, each in its own colour, with the compile that already
quit still named: "exited · recorded".

**Every day.** Click or U opens it without a drag; arrows step intervals,
Option-arrows jump peaks; Command-Z restores the previous scope.

## 2. Cold storage (control)

**Inspiration.** Coreography's process actions land on the same timeline
as their aftermath, re-checked by PID and start time, and Suspend is the
rare intervention you can undo.

**Before.** A caught strand or a process row grows a frost handle. Drag it
down into a 64 pt cold tray under the lanes.

**During.** The confirmation names every helper and what stops ("audio
stops, downloads pause"). On confirm, a pale seam with crystalline ticks
crosses every lane at that second. To its right the app's strand renders as
ice; a dotted ghost of its pre-freeze average runs on for ten seconds as a
reference. A dry crackle, 180 ms.

**After.** The tray tile shows the frozen icon and a timer ("frozen
0:12"). Click it, press Command-Z or quit Coreography to thaw: a second seam,
then "CPU 61% → 24% while frozen; observed, not proof".

**You have to see this.** Freeze a runaway browser helper and hear the fans
wind down while its strand turns to ice.

**Every day.** F freezes the focused app, T thaws; the tray lists
everything frozen, so nothing is forgotten. WindowServer and loginwindow
are refused with the reason. A watchdog resumes processes if Coreography
dies.

## 3. Tear-off (creation)

**Inspiration.** Coreography can freeze any range into a redacted,
portable `.coreotrace`: evidence you can hand to someone. Today that is a
Save button in a panel.

**Before.** The lanes read as one chart-recorder roll; selecting a range
punches perforations across every lane at its edges.

**During.** Drag the selection down past 24 pt and it tears off the roll:
deckled edges from seeded noise, a tearing sound whose grain follows drag
speed. The live roll keeps running behind it. The strip curls into a
220×90 pt receipt: name, duration, miniature lanes and a "names hidden"
stamp.

**After.** Receipts collect on a shelf. Drag one straight into Messages,
Mail or Finder; double-click to unroll it as a replay.

**You have to see this.** Tearing the minute your Mac froze off its
timeline and dropping it into a chat.

**Every day.** Command-S on a selection does the same without the gesture;
redaction is the default; VoiceOver reads "Recording, 2 minutes, CPU peak
92%".

## Committed: Unbraid

Unbraid sits where the user's question and the app's unique capability
meet. It needs no new collector: the ledger, the host samples and the
attribution arithmetic already exist. Its ten-second demo is self-evident,
and on the hundredth use it is simply the fastest answer to "who?", with no
setup and nothing to undo. The other two concepts act on what Unbraid finds;
they are its sequels. Of four independent Codex (Sol 6.1) explorations,
each sent to a different lens, three chose this same moment.

Codex's adversarial reviews reshaped the details. Release latches instead
of scoping, so pulling just to read never filters the window. Strands are
drawn as interval steps, not lines, because the ledger knows averages, not
instants. The axis never compresses: lifted strands rise into headroom
above the plot. The twang lives in the seams' highlight, never in measured
boundaries. Pitch belongs to the app, not to its rank.

The vocabulary: blue at rest, colour as revelation, light on lifted
fibres, a soft shadow only where the lens lifts, the host line fading
behind them, a white grip under the hand, and three sounds synthesized as
plucked strings (Karplus-Strong), quiet and only for the person's own
gestures.

## What I deliberately did not do

- No per-app colour at rest: the everyday lane stays calm and blue; colour
  is the reward for pulling.
- No braids for memory or GPU time: footprints and GPU milliseconds do not
  add up, so stacking them would lie. Disk and network could follow; they
  are not in this prototype.
- No stored-history braid: stored ledgers index apps differently, so
  beyond the live hour the lane falls back to the plain line.
- No instantaneous attribution, no rescaling: the remainder is "host minus
  observed apps", and when apps exceed the host the card says the samples
  disagree.
- No overshoot of data, no auto-scope, no sound for live data, no haptic
  chatter (one tick per focus change, at most every 100 ms).
- No demo data: every frame of the prototype's film comes from a real Mac
  under real load.
- Cold storage and Tear-off stay on paper until the discovery feels right.
