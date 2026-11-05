# Silent Hills design decisions

The launcher and the companion app share one design system (`ui/style.gd`).
It follows the build-and-review checklist in the Claude vault note
"Front End UI Design Techniques" (Oct 2026). These are the five decisions,
written down once so they stay chosen rather than defaulted.

1. **Theme: dark only, the art does the talking.** Every page sits on the game's
   or film's own key art; the UI is quiet around it. A light theme would fight
   the art and the series' mood, so there is none. Depth comes from lighter
   surfaces (BG .145 → SURFACE .18 → RAISED .215 → HOVER .25 in OKLCH
   lightness) and one shadow for raised things (menus, modals, toasts).
2. **Colour: warm-tinted neutrals and one rust accent.** Neutrals are OKLCH
   steps at hue 70, chroma 0.006 (a fog-grey, not blue-grey), each with one job
   (background, surface, raised, hover, separator, border, three text levels,
   disabled). The accent is rust (hue 32) for actions and status only; each
   game's own accent is made readable at runtime (`accent_text`, `accent_fill`).
   Focus is an amber "fog lamp" ring, 2 px, 10:1. `tests/contrast.gd` checks
   every text token at 4.5:1 and every border/focus token at 3:1 on every
   surface, and every game accent too.
3. **Type: Cormorant Garamond for titles, IBM Plex Sans for everything else.**
   Cormorant carries the series' literary, unsettling tone in the display tier
   (64 / 40 / 26). Plex Sans replaces Inter: its slightly mechanical, industrial
   shapes suit Silent Hill better than the default UI face, and it has tabular
   figures (used for times, counts and progress). The UI tier has three sizes:
   16 body, 14 meta, 12 tracked caps. Weights 400 / 500 / 600 only.
4. **Layout: a 4/8 spacing scale, one radius, one border, one shadow.**
   4, 8, 12, 16, 24, 32, 48, 64. Radius 4 on every control and card; 1 px
   borders only where a control needs marking (at 3:1); separators use the
   decorative LINE. Desktop controls are 40 px tall, phone controls 48 dp.
   Icons are Lucide (one set): 16 inline, 20 in buttons, 24 standalone.
   One primary (filled) button per view; secondary is outlined; everything
   else is text.
5. **Tone and motion: plain words, quiet movement.** Buttons are verb + object
   ("Get it ready for the phone", "Keep on phone"); errors say what to do in
   the field's own words; no "invalid", "oops" or "please". Motion is 150 ms
   for micro feedback and 250 ms for menus and toasts, ease-out, opacity or
   transform only, never on keyboard actions; Reduce motion (Settings) turns
   movement into fades and stops the atmosphere. Loading follows the response
   limits: nothing under 1 s, static skeletons for a page, a spinner for one
   module, a progress bar with Cancel past 10 s; empty areas explain what goes
   there and offer one action. Ctrl+K opens a command palette that reaches
   every game, film, comic, album and action and shows each shortcut.
