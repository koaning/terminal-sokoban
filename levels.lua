-- the levels, in order
-- puzzles use the usual sokoban text format, see sokoban.lua:
--   # wall   $ crate   . goal   * crate on a goal   @ player   + player on a goal
--   > the way out   < the way in, both in the outer wall
-- the way out opens once every crate is on a goal, a puzzle is solved when the player walks through it
-- to lists the rooms the ways out lead to: a room with two ways out is a fork; a room with an empty list is a dead end,
-- with no way out at all, solved as soon as every crate is on a goal (the map takes you back, see picker.lua); the
-- last room is the exception: its one way out leads to the island
-- paths don't join up again, every room has one way in, so every room shares a doorway with the room before it
-- at is roughly where the room goes on the map, as {column, row}, row numbers going up (north): rooms that lead to
-- each other should be next to each other on it
-- the rooms are packed into one castle, see world.lua: each room is turned or mirrored so its way in is the way out of
-- the room that leads to it, a doorway in the wall they share (or a short corridor, where that doesn't fit)
-- saved progress is kept per name (see progress.lua), so renaming a puzzle forgets whether it was solved

local sokoban = require "sokoban"

local puzzles = {
    {name = "First push", at = {0, 0}, to = {"Around the corner"}, text = [[
##>####
#@ $ .#
#######
]]},
    {name = "Around the corner", at = {0, 1}, to = {"Gallery"}, text = [[
######
#.   #
#  $ #
## @ >
 ##<##
]]},
    {name = "Gallery", at = {1, 1}, to = {"Doorstep"}, text = [[
####>####
#.     .#
##  #  ##
 ##$#$##
 <  @  #
 #######
]]},
    {name = "Doorstep", at = {1, 2}, to = {"Two by two"}, text = [[
  #<#
 ##@##
 #.$.#
##   ##
# $   >
##   ##
 ## ##
  ###
]]},
    {name = "Two by two", at = {0, 3}, to = {"The hallway"}, text = [[
###>###
#     #
# $$  #
#  @ ##
#..  #
###<##
]]},
    {name = "The hallway", at = {1, 3}, to = {"Storeroom"}, text = [[
  ##<##
###   #
#. $# #
#  .$ #
## @  >
 ######
]]},
    {name = "Storeroom", at = {2, 3}, to = {"Well", "Terrace"}, text = [[
#####>##
#  .   #
# $$#  #
<  @ $ >
##.#  .#
 #     #
 #######
]]},
    {name = "Well", at = {3, 3}, to = {"Way out"}, text = [[
   ##>##
  ##. .##
### $$$ ###
<    @    #
#####.#####
 #########
]]},
    {name = "Terrace", at = {2, 2}, to = {"Loading dock"}, text = [[
####>####
# #   # #
# $   $ #
#.     .#
# ##@## #
####<####
]]},
    {name = "Way out", at = {4, 3}, to = {"Keyhole"}, text = [[
 ##>##
 #   #
 # $ #
## . ##
# $#$ #
<  @  #
#.###.#
#######
]]},
    {name = "Loading dock", at = {3, 2}, to = {}, text = [[
#######
#. .  #
# $$  #
##  # #
 # $$ #
 <@ ..#
 ######
]]},
    {name = "Keyhole", at = {4, 2}, to = {"Passing place"}, text = [[
   #<#
  ##@##
  ##.##
### $ ###
#  $ $  >
##     ##
 #.###.#
 #######
]]},
    {name = "Passing place", at = {4, 1}, to = {"Row of three", "Boxed in"}, text = [[
  #<#####
###  @  ###
# ##$  ## #
# #  *  # >
#  . $ .  #
#####>#####
]]},
    {name = "Row of three", at = {4, 0}, to = {"Attic"}, text = [[
######>##
#   #   #
#   .   #
#.#$$$#.#
# # @ # #
###<#####
]]},
    {name = "Boxed in", at = {3, 1}, to = {"Bookshelf"}, text = [[
####>####
# .   . #
##  $  ##
 ##* *##
  # $ #
  ##@##
   #<#
]]},
    {name = "Attic", at = {3, 0}, to = {"Crossroads"}, text = [[
#########>#
#   ###   #
#    .    #
####. .## #
   # $ ## #
   #$#$## #
   # @    #
   ##<#####
]]},
    {name = "Bookshelf", at = {2, 1}, to = {}, text = [[
    #####
 ####. .####
## $ $ $ $ ##
#   . @ .   #
######<######
]]},
    {name = "Crossroads", at = {2, 0}, to = {"Courtyard"}, text = [[
   #<#
#### ####
#   @   >
### # ###
 ## $ ##
## $#$ ##
#.  .  .#
#########
]]},
    {name = "Courtyard", at = {2, -1}, to = {"Warehouse", "Lifts"}, text = [[
 #>#####
 #  .  #
##$# #$##
<.  @  .#
# $# #$ >
#   .   #
#########
]]},
    {name = "Warehouse", at = {1, -1}, to = {"Mask"}, text = [[
  ######
  #    #
### ## #
# $ $  >
# .*.  #
## $ ###
 <.@ #
 #####
]]},
    {name = "Lifts", at = {2, -2}, to = {}, text = [[
 #<#####
##  #  ##
#.@    .#
###$#$###
##  $  ##
#   .   #
##  #  ##
 #######
]]},
    {name = "Mask", at = {1, -2}, to = {"Alcoves"}, text = [[
####     ####
#  ### ###  #
##.  # #  .##
# $ ##### $ #
<  $ #@# $  >
##   . .   ##
 ###########
]]},
    {name = "Alcoves", at = {0, -2}, to = {}, text = [[
#########
#. # # .#
# $###$ #
<  $@$  #
#.     .#
# ## ## #
####>####
]]},
}

local levels = {}
for i,puzzle in ipairs(puzzles) do
    levels[i] = sokoban.parse(puzzle.text, puzzle.name)
    levels[i].text, levels[i].to, levels[i].at = puzzle.text, puzzle.to, puzzle.at
end

local island = require "level"
island.name = "The island"
island.crates = {}
levels[#levels+1] = island

return levels
