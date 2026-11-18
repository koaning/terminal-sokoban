.PHONY: help term check run vm

help:
	@echo "Terminal Sokoban"
	@echo ""
	@echo "  make term          play in this terminal (needs luajit)"
	@echo "  make check         check that every level can be solved"
	@echo "  make run           play in a window instead (needs LÖVE 11)"
	@echo "  make vm VM=<host>  put the game on a Linux machine you can ssh into"

# play the game in a terminal: pictures in Ghostty, kitty and WezTerm, character cells elsewhere; Tab switches
term:
	luajit term.lua

# check every level, the castle and the framing
check:
	luajit check.lua

# the same game in a LÖVE window
run:
	love .

# copy the committed game (HEAD) to ~/terminal-sokoban on a Linux machine over ssh, installing LuaJIT if it's missing
vm:
ifndef VM
	$(error set the machine to copy to: make vm VM=<your-vm>.exe.xyz)
endif
	ssh $(VM) 'command -v luajit >/dev/null || (sudo apt-get update -qq && sudo apt-get install -y -qq luajit)'
	git archive HEAD | ssh $(VM) 'rm -rf ~/terminal-sokoban && mkdir -p ~/terminal-sokoban && tar -x -C ~/terminal-sokoban'
	@echo "copied to $(VM), play it with: ssh -t $(VM) luajit terminal-sokoban/term.lua"
