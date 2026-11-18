# Terminal Sokoban

A Sokoban game you can play in a terminal, over ssh too, with nothing but [LuaJIT](https://luajit.org). It's drawn in 8×8 pixel art (Kenney's [Micro Roguelike](https://kenney.nl/assets/micro-roguelike) tiles). In terminals that can show images (Ghostty, kitty, WezTerm) every frame arrives as a picture. Anywhere else it's drawn in coloured character cells.

Every puzzle is a room in one castle floating in the sky. Push every crate onto a goal and the gate out of the room sinks into the floor, so you can walk into the next room. There are 23 rooms, a few forks with dead-end side paths, a map for fast travel, and an island with units to move around past the last room. Progress is saved.

It's written as a [LÖVE](https://love2d.org) game, so `love .` runs it in a window as well. In a terminal, `term.lua` runs that same game on `softlove.lua`, a small stand-in for LÖVE that draws in software.

## Play

```sh
brew install luajit        # or: sudo apt install luajit
git clone https://github.com/koaning/terminal-sokoban
cd terminal-sokoban
make term                  # or: luajit term.lua
```

Tab switches between the ways it can look while you play:

- **pictures**: every frame sent as images with the kitty graphics protocol. It starts with this where the terminal can show it.
- **blocks**: the art in character cells, two pixels a cell (`▀`). It works in any terminal with 24-bit colour, and it starts with this everywhere else.
- **octants**: eight dots a cell (Unicode 16 octants), so a room takes a quarter of the space. Ghostty and kitty draw these characters themselves.
- **small**: blocks with every pixel the average of four. It's as small as octants but blurrier.
- **text**: the castle in coloured text, two characters a tile.

Options: `--look <name>` starts with a look, `--fresh` starts with nothing solved and doesn't save, and `--pixel-scale <n>` sets how many terminal pixels make one pixel of the art. With keys piped in, it plays them and prints the last frame, so it can be scripted: `printf 'dddaaww' | luajit term.lua --fresh`.

## The demo: a game you ssh into

The fun part is running it on a server and playing it from your own terminal. Here it's done with an [exe.dev](https://exe.dev) VM, but any Debian or Ubuntu machine you can ssh into works.

1. Make a VM, say `<your-vm>.exe.xyz`, and check that `ssh <your-vm>.exe.xyz` gets you in.
2. Copy the game to it, from this folder: `make vm VM=<your-vm>.exe.xyz`. This installs LuaJIT on the VM if it's missing and puts the game in `~/terminal-sokoban`. Run it again after pulling changes. Progress is kept in `~/.local/share/ps1-sokoban`, so updating doesn't lose it.
3. Play: `ssh -t <your-vm>.exe.xyz luajit terminal-sokoban/term.lua`

The pictures come through ssh because the game asks the terminal what it can do when it starts (images, the cell size in pixels, key releases) rather than reading environment variables. The terminal on your end answers through the ssh connection. After the first frame, only the parts of the screen that changed are sent, which is a few kilobytes a frame while you walk around. It needs to talk to your terminal directly: tmux and screen don't pass the pictures on, but the cell looks work there.

### `ssh sokoban`

To play with one word, give the VM a second name in `~/.ssh/config` on your own computer, one that starts the game in place of a shell:

```
Host sokoban
  HostName <your-vm>.exe.xyz
  RequestTTY yes
  RemoteCommand luajit ~/terminal-sokoban/term.lua
```

`ssh sokoban` plays, and quitting closes the connection. `ssh <your-vm>.exe.xyz` is still an ordinary shell, and `scp` and `make vm` aren't affected.

### Or: the game on every login

To have the game start for anyone who logs in, from any computer, add this to `~/.profile` on the VM:

```sh
# Terminal Sokoban on ssh login; quitting leaves you in the shell
if [ -n "$SSH_TTY" ] && [ -z "$TMUX" ] && [ -t 0 ]; then
    luajit ~/terminal-sokoban/term.lua
fi
```

Put it in `~/.profile`, not `~/.bashrc`. Bash reads `~/.profile` only for a login shell, which is what a plain `ssh <your-vm>.exe.xyz` gives. So a plain ssh plays and then leaves you in the shell, and `ssh -t <your-vm>.exe.xyz bash` skips straight to the shell. `ssh <host> <command>`, `scp` and `make vm` don't start the game. In `~/.bashrc` it would also start for `ssh -t <host> bash`. Setting an environment variable on your own computer can't switch it off either, because ssh doesn't pass them on unless the server allows it.

## Controls

| Key | Action |
| --- | --- |
| WASD / arrow keys | walk, or push a crate; on the island, move the cursor |
| Z / Backspace | undo a move, in any room |
| R | back to how the room was when you walked in; again for its start |
| M | the map: travel to the start of any room you've been in |
| Esc | pause menu: resume, restart, map, next/previous room, new game, quit |
| Space / Enter | go to the island from the last room; on the island, select and move units |
| [ / ] | the start of the previous / next room |
| Tab | switch looks (terminal only) |

In the text look: arrows or WASD move, z undoes, r restarts, [ and ] change rooms, and q quits. In the pictures look the mouse works too, for the map and the island.

Crates can't go through doors, and the push that places the last crate mustn't shut you off from the way out. Nothing can leave you stuck, though: crates never leave their room, so restarting the room fixes it.

## Where things live

- `term.lua`: runs the game in a terminal. It hands the game the keys and the mouse, and sends its frames out as pictures or character cells.
- `softlove.lua`: just enough of LÖVE in plain LuaJIT to run the game without a window: PNG reading, a software renderer, text, and the save folder.
- `termcells.lua`: the art in character cells (half blocks, octants), sending only the cells that changed.
- `levels.lua`: the puzzles, in the usual Sokoban text format (`#` wall, `$` crate, `.` goal, `@` player, `>` / `<` the ways out and in).
- `sokoban.lua`: the rules and a solver. `world.lua` packs the rooms into one castle. `game.lua` has the world, undo and the HUD.
- `draw2d.lua` and `tiles.lua` draw the castle. `map.lua` and `picker.lua` are the map, `menu.lua` the pause menu, and `units.lua` the island.
- `check.lua` (`make check`): solves every level with a breadth-first search and checks that the castle fits together.

## Credits

- Tiles: Kenney's [Micro Roguelike](https://kenney.nl/assets/micro-roguelike), CC0 (`assets/micro-roguelike-LICENSE.txt`), recoloured when loaded.
- Font: a bitmap of [DejaVu Sans](https://dejavu-fonts.github.io), made by `tools/make_term_font.py` (`assets/dejavu-LICENSE.txt`).
- The tile grid and player movement started from groverburger's [g3d_fps](https://github.com/groverburger/g3d_fps), MIT.
- The code is MIT licensed, see `LICENSE`.
