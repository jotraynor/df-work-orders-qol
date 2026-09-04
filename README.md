# Work Orders QoL for Dwarf Fortress

Two small quality-of-life additions to the **Work Orders** screen in Dwarf
Fortress (Steam version, v50+). Needs [DFHack](https://dfhack.org), which is
free and installs from Steam in one click.

1. **Shift+click to top.** Hold Shift and click an order's up arrow to send it
   straight to the top of the list. Shift+click the down arrow to send it to
   the bottom. No more clicking the arrow twenty times.
2. **Filter box.** Type `wood` and the list shrinks to just your wooden
   orders. Edit them right there, clear the box, and the full list comes back.

## Download and install

1. **Install DFHack** if you don't have it. Search for "DFHack" in the Steam
   store, install it, and it will run automatically whenever you launch Dwarf
   Fortress.
2. **Download the mod.** Go to the
   [Releases page](../../releases/latest) and download the `.zip` file.
3. **Unzip it.** You get a folder called `DFShiftClickToTop`.
4. **Put that folder in your game's `mods` folder.** To find it: in Steam,
   right-click Dwarf Fortress, then Manage, then Browse local files. If there
   is no `mods` folder there yet, create one. You should end up with:

       Dwarf Fortress\mods\DFShiftClickToTop\info.txt
       Dwarf Fortress\mods\DFShiftClickToTop\scripts_modinstalled\...

5. **Start the game and load a fort.** Open the Work Orders tab and you are
   done. You do not need to add the mod to your world's mod list; DFHack finds
   it on its own, and it works on existing saves.

To uninstall, delete the folder. The mod never changes your save files.

## Using it

### Shift+click to top

Hold **Shift** and click an order's **up arrow**. The order jumps to the top
of the list (highest priority). **Shift** + the **down arrow** sends it to the
bottom. A normal click still moves the order one step as usual.

### Filter box

A **Filter orders** box sits at the bottom right of the Work Orders screen.
Click it or press **Ctrl+F**, then type. The list narrows to the orders whose
name, material, job or assigned workshop contains every word you typed:

- `wood` finds "Make wooden barrel", and also "Make bed" if that bed is set to
  wood.
- `rock door` narrows to rock doors.

Edit the remaining rows exactly as usual: quantities, conditions, priority
arrows, delete, and shift+click to top all work on the filtered list. Press
**Enter** to hand the keyboard back to the game, or just click a row. The
`clear` button, emptying the box, or leaving the Work Orders screen brings the
full list back with every edit you made kept.

The game stays paused while a filter is active (the status line says so).
That is deliberate; see below.

## Turning it off or moving it

Both parts are on by default. Turn either off from DFHack's control panel
(`gui/control-panel`, Overlays tab) or from the DFHack console:

    overlay disable shift-click-to-top.arrows
    overlay disable work-order-filter.filter

Re-enable with `overlay enable` and the same names. To move the filter box,
run `gui/overlay` and drag it, or use `overlay position work-order-filter.filter <x> <y>`.

## How it works, and why the filter pauses the game

**Shift+click** lets the game handle the click as normal, notices that the
clicked order moved one step, and then finishes the move to the top or
bottom. Because it reacts to what the game actually did rather than to pixel
positions, it keeps working if the row layout shifts a little. If what moved
doesn't match the row that was clicked, it does nothing rather than guess.

**The filter** works the same way DFHack's own `sort` plugin filters the
other Info screens: it removes non-matching entries from the game's list
vector, keeps them in memory, and puts them back afterwards. The difference is
that the other Info screens draw from throwaway display lists the game
rebuilds, while Work Orders draws straight from the real order list, so this
mod adds guards that `sort` doesn't need:

- the game is held **paused** while a filter is active, so nothing can save
  or process orders in the meantime;
- the filter is dropped automatically the moment you leave the Work Orders
  screen or anything requests a save;
- when you start typing a filter, all orders are backed up to
  `dfhack-config/orders/work-order-filter-backup.json` (once per filter, not
  on every keystroke). If anything ever goes wrong,
  `orders import work-order-filter-backup` in the DFHack console brings them
  back. If the backup itself cannot be written, a warning is printed to the
  DFHack console so you know the safety net is missing.

Two things to know:

- **Clear the filter before you save.** Saving from the Escape menu is safe,
  because opening that menu already drops the filter. DFHack's `quicksave`
  command is different: it asks the game to save on the spot. The mod
  notices the request and puts the orders back, but that happens a frame
  later, so do not rely on it. Clear the box first.
- **Opening another window drops the filter.** Clicking **New work order**,
  or anything else that leaves the plain order list, brings the full list
  back, exactly as leaving the screen does. Nothing is lost; just type the
  filter again when you return.

When the list is restored, hidden orders keep their original positions and
the orders you could see fill the remaining positions in the order you left
them. Shift+click to top or bottom while filtered still means the top or
bottom of the full list.

## For developers

Everything that depends on the vanilla screen layout (row height, where the
list starts, the bottom margin) lives in one place,
`scripts_modinstalled/internal/work-orders-qol/ui.lua`, and both overlays
read it from there. If a Dwarf Fortress update changes the Work Orders
layout, that is the only file to update. The numbers mirror the ones in
DFHack's `hack/lua/plugins/orders.lua`, which is the first place to compare
against.

## Troubleshooting

If the boxes don't appear on the Work Orders screen, open the DFHack console
and run:

    overlay list work

You should see `shift-click-to-top.arrows` and `work-order-filter.filter` both
marked `[enabled]`. If they are missing, check the folder layout in the
install steps above. If you see red error text, please open an issue and paste
it.

## License

MIT. See `LICENSE`.
