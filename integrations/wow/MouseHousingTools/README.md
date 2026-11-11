# Mouse Housing Tools

Mouse Housing Tools applies mesh-to-housing to World of Warcraft's housing
system. The housing API can't place an item at a chosen position and
rotation. So the addon first works out how to get an item into an exact pose
using only what the editor allows. On top of that it builds simple shapes
(stairs, circles) and, later, any 3D model that mesh-to-housing represents as
a set of decor items.

## Folders

| Folder | What it holds | WoW-specific? |
|---|---|---|
| `Geometry/` | The plan definition (`Plan.lua`: which items go where, relative to the source item) and orientations as rotation matrices (`Rotation.lua`) | No |
| `Shapes/` | Presets that produce plans. Each shape file (stairs, circle) registers itself with `Layout.lua`, which turns any shape's settings into a plan. Saved models are in `ModelLibrary.lua` (for now only the test sphere) | No |
| `Items/` | What we know about decor items: logged and calibrated pivots, ring directions and sizes. `ItemProfiles.lua` defines a profile's fields and reads them; `ItemCatalog.lua` holds the logged profiles | Yes |
| `Placement/` | How WoW gets an item to its place: editor calls (`Housing.lua`), turning a plan item into editor moves (`NativeEdit.lua`), timed key holds (`Motion.lua`), and the whole build (`Placement.lua`) | Yes |
| `Dev/` | Calibration and test logic, including test figures in `Dev/Figures/`. | Yes |
| `UI/` | Everything drawn on screen. Building blocks: `Theme.lua` (the look: colors, fonts, skins, icons, logo), `UI.lua` (widgets), `Preview.lua`. The main window: `Window.lua`, its settings column `SettingsPanel.lua` and `Footer.lua`. `UI/Tabs/` holds each tab's settings: Shapes, 3D Sketch and 3D Sculpt, with the shared `ModelPicker.lua`. `UI/Editor/` holds what goes into Blizzard's housing editor: the launcher button and `EditorChrome.lua`, which adjusts the editor's own UI. Dev tools open in their own window (`UI/Dev/DeveloperWindow.lua`) when `MHT.DEV_MODE` is on at the top of `Init.lua` | Yes |

## What the housing editor allows

The editor has no call that puts an item at given coordinates. It can't put
a new item anywhere on its own either. What an addon can do:

- **Copy a placed item.** While the cursor hovers a placed item, the addon
  can start placing another copy. The new item comes from storage
  and lands wherever the cursor points.
- **Move the selected item.** In Advanced mode, the addon can trigger the
  editor's move, rotate and resize actions, the same ones the keybinds
  trigger. They only act on the selected item, and only the player can select
  an item, by clicking it.

**Movement is timed, not measured.** The addon can't move an item by a set
amount. It can only start continuous movement and stop it after a set time. The
editor moves at fixed speeds:
- move: about 1 unit per second
- turn: about 45° per second
- resize: about 20% per second

`Motion.lua` holds each action for distance ÷ speed.

## How a build works

Because of those limits, every shape or model is built in two steps:

1. **Make a pile.** The addon places copies of the source item, all in the
   same spot.
2. **Move each copy.** The addon switches to Advanced mode. The user clicks a copy,
   and the addon moves, turns and resizes it into its place in the plan, then
   saves it. The user clicks the next copy, and so on.

Every copy starts from the same known spot, so each target can be reached as
a fixed move from the pile.

### Making the pile

The user hovers
the source and keeps the cursor still. What happens next depends on the item:

- **The cursor stays on the source.** After a copy is placed, the cursor
  still hovers the source item. The addon keeps copying and placing, with no
  clicks, and every copy lands in the same spot.
- **The cursor ends up on the new copy.** The next copy would land on top of
  this one, not in the same spot. So the addon switches to Advanced mode, the
  user clicks the new copy, and the addon moves it aside by a fixed step. It then
  switches back and places the next copy. If the cursor hasn't moved, that
  copy lands in the original spot again, and the same step moves it exactly
  onto the first copy. The pile forms beside the source.

### Moving copies

Advanced-mode edits apply to the item the player selected. Switching modes or
changing the selection also cancels an unfinished edit. So the user clicks each copy
once, after the mode switch, and the addon finishes it before the user clicks
the next.

## The pipeline

```
shape settings ──> plan (list of items: position, rotation, scale)
                     │   Shapes/, Geometry/
                     ▼
source item ──> item data (pivots, ring directions, size)
                     │   Items/
                     ▼
for each plan item:  NativeEdit: editor commands (move, resize, turn X/Y/Z)
                     Motion: hold actions for the right times
                     Placement: pile, click, move, save, next
                         Placement/
```

## Why rotation is hard here

A plan gives each item's rotation as a matrix, relative to a freshly placed
copy. Turning a real item into that orientation isn't simple:

- **The rotation axes are attached to the item.** The editor turns one ring
  at a time (X, then Y, then Z). Each turn also turns the other two axes with
  the item. So the matrix has to be broken down into three angles that,
  applied in this order, give the same orientation.
- **For some items the axes don't meet in one point.** They are still perpendicular to each
  other, but each ring turns around its own pivot, and resizing has its own
  pivot too. So every turn also moves the item, and turning alone can carry an
  item away from where it was. `NativeEdit.lua` works out that drift and adds
  the opposite shift to the move, so the item ends up where the plan says.
- **None of this is in the API.** The game reports neither the pivots nor the
  item's pose after an edit. Pivots, ring directions and sizes have to be
  found by experiments in game.

## Calibration (dev tools)

The dev tools measure items in game. Players never use them: each item is
calibrated once and its values are logged in `Items/ItemCatalog.lua`, so players
build without measuring anything. Saved calibration replaces logged values.

**Movement capture** turns hand movement into numbers. While the user aligns a copy
with the movement keys, it records which keys they hold and for how long. The
measured speeds then turn those times into units.

### Rotation pivots

This is the most important measurement. Each of the X, Y and Z rings is
measured on its own:

1. The addon places two copies on top of each other.
2. The addon turns one copy 180° on the ring being measured. It swings around
   the ring's pivot and ends up displaced by twice the pivot's offset from the
   item's center.
3. The user moves it back by hand until the two copies overlap again. The
   pivot is minus half of that movement.


The automatic test checks a pivot in reverse. It turns a copy 180°, moves it
back by the trial pivot, and the user checks by eye that the copies overlap.

### Rotation axes

The user clicks a placed copy, the addon turns it +90° on one ring, and the
user answers where its top surface went. That tells which item axis the ring turns around and in which direction.

### Size

For simple, box-like items such as tiles and walls, we log their exact size.
The addon places two copies, and the user moves one along an axis until its
face touches the other.
That movement is the size on that axis. The test moves a copy by the full X, Y
and Z sizes, and the two should meet corner to corner.

### Resize pivot

Resizing doesn't scale an item around its center either. The resize pivot can
sit off-center, even outside the item itself.

It is measured much like the rotation pivots, and it needs the item's size
first:

1. The addon lifts a copy and shrinks it to 50%. The copy shifts toward the
   resize pivot as it shrinks.
2. The user moves the small copy by hand until it lines up with the full-size
   one on one side.
3. Comparing how far the user had to move it with the item's size gives the
   pivot.

## Tests (dev tools)

- **Corner test:** checks that the rotation math matches the game. The user
  places small marker items on the corners of a calibrated tile. The addon turns the
  tile with raw ring turns, works out where each corner should have gone, and
  moves each marker there. In game, the markers should sit on the turned
  tile's corners.
- **Figure tests:** full builds that use several rings at once, as an
  end-to-end check of a calibrated item. They live in `Dev/Figures/`:
  - Cube: 6 square tiles; each face needs at most one ring.
  - Sphere: 30 square tiles, a rhombicosidodecahedron with triangular and
    pentagonal openings.
  - Tilted circle: 5 tiles, 72° apart and tilted 30° outward, so each tile
    needs combined turns.

  They use the item's saved size, pivots and rotation axes, plus the resize
  pivot when the figure resizes tiles.
