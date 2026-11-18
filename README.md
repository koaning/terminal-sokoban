# Terminal Sokoban

A Sokoban castle you can play in a terminal, over ssh too, with only [LuaJIT](https://luajit.org). It's drawn based on Kenney's 8×8 pixel art: real pictures in Ghostty, kitty and WezTerm, and coloured characters anywhere else. Tab switches between the looks.

## Quickstart

```sh
brew install luajit   # or: sudo apt install luajit
git clone https://github.com/koaning/terminal-sokoban && cd terminal-sokoban
luajit term.lua
```

Arrows or WASD move, Z undoes, R restarts the room, M opens the map and Esc the menu.

## Play it over ssh

```sh
make vm VM=<your-vm>.exe.xyz                           # installs luajit, copies the game
ssh -t <your-vm>.exe.xyz luajit terminal-sokoban/term.lua
```

Or add this to `~/.ssh/config` and just `ssh sokoban`:

```
Host sokoban
  HostName <your-vm>.exe.xyz
  RequestTTY yes
  RemoteCommand luajit ~/terminal-sokoban/term.lua
```

To start it on every login, put `[ -n "$SSH_TTY" ] && [ -z "$TMUX" ] && luajit ~/terminal-sokoban/term.lua` in the VM's `~/.profile`. Use `~/.profile`, not `~/.bashrc`, so `ssh -t <host> bash` still gets you a plain shell.

## Credits

Tiles by [Kenney](https://kenney.nl/assets/micro-roguelike) (CC0). Font: [DejaVu Sans](https://dejavu-fonts.github.io).  MIT licensed.
