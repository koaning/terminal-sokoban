-- which puzzles have been solved, and the fewest moves each one took, and which rooms have been visited (the map
-- can take you back to those), saved between sessions
-- kept per level name, so adding or reordering levels doesn't mix up what was solved
-- saved in the save folder of love.filesystem, one line per solved level, `name<tab>moves<tab>pushes`, and one per
-- visited room, `visited<tab>name`

local progress = {file = "progress.txt", enabled = true, results = {}, visited = {}}

function progress.load()
    progress.results, progress.visited = {}, {}
    if not love.filesystem.getInfo(progress.file) then return end
    for line in love.filesystem.lines(progress.file) do
        local name, moves, pushes = line:match("^(.-)\t(%d+)\t(%d+)$")
        if name then progress.results[name] = {moves = tonumber(moves), pushes = tonumber(pushes)} end
        local visited = line:match("^visited\t(.+)$")
        if visited then progress.visited[visited] = true end
    end
end

local function save()
    local lines = {}
    for name,result in pairs(progress.results) do
        lines[#lines+1] = ("%s\t%d\t%d"):format(name, result.moves, result.pushes)
    end
    for name in pairs(progress.visited) do lines[#lines+1] = "visited\t" .. name end
    table.sort(lines)
    local ok, message = love.filesystem.write(progress.file, table.concat(lines, "\n") .. "\n")
    if not ok then print("couldn't save progress: " .. tostring(message)) end
end

-- the best result for a level, or nil if it hasn't been solved
function progress.best(name)
    return progress.results[name]
end

function progress.isSolved(name)
    return progress.results[name] ~= nil
end

function progress.isVisited(name)
    return progress.visited[name] == true
end

-- remembers that a room has been walked into
function progress.visit(name)
    if progress.visited[name] then return end
    progress.visited[name] = true
    if progress.enabled then save() end
end

-- remembers a solve, if it took fewer moves than the best one so far (or as many moves but fewer pushes)
-- returns true when it is a new best
function progress.record(name, moves, pushes)
    local best = progress.results[name]
    if best and (best.moves < moves or best.moves == moves and best.pushes <= pushes) then return false end
    progress.results[name] = {moves = moves, pushes = pushes}
    if progress.enabled then save() end
    return true
end

-- forgets every solve, best and visited room, also in the save file: a new game
function progress.reset()
    progress.results, progress.visited = {}, {}
    if progress.enabled then save() end
end

return progress
