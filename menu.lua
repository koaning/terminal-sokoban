-- the pause menu: Start or Esc opens it, the d-pad / arrow keys pick an item, A / Enter chooses it
-- the game is paused while it is open, but stays visible behind it, so settings can be seen changing

local lg = love.graphics

local menu = {isOpen = false, index = 1}

local font

-- items is a list of {label = string or function returning a string, action = function, keepOpen = boolean,
-- confirm = string}
-- an item with confirm asks first: the first press shows the confirm text instead of the label, the second one does it
function menu.setItems(items)
    menu.items = items
end

function menu.open()
    menu.isOpen, menu.index, menu.confirming = true, 1, nil
end

function menu.close()
    menu.isOpen, menu.confirming = false, nil
end

function menu.keypressed(k)
    if k == "escape" or k == "backspace" then
        menu.close()
    elseif k == "up" or k == "w" then
        menu.index, menu.confirming = (menu.index - 2) % #menu.items + 1, nil
    elseif k == "down" or k == "s" then
        menu.index, menu.confirming = menu.index % #menu.items + 1, nil
    elseif k == "return" or k == "space" then
        local item = menu.items[menu.index]
        if item.confirm and menu.confirming ~= menu.index then
            menu.confirming = menu.index
            return
        end
        if not item.keepOpen then menu.close() end
        menu.confirming = nil
        item.action()
    end
end

local function label(item, i)
    if item.confirm and menu.confirming == i then return item.confirm end
    return type(item.label) == "function" and item.label() or item.label
end

function menu.draw(panel)
    font = font or lg.newFont(18)
    local previousFont = lg.getFont()
    lg.setFont(font)

    local w, h = lg.getDimensions()
    local lineHeight = font:getHeight() + 8
    local bw, bh = 300, 56 + #menu.items*lineHeight
    local bx, by = math.floor((w - bw)/2), math.floor((h - bh)/2)
    panel(bx, by, bw, bh)
    lg.printf("Paused", bx, by + 14, bw, "center")

    for i,item in ipairs(menu.items) do
        local y = by + 46 + (i - 1)*lineHeight
        if i == menu.index then
            lg.setColor(0.95, 0.75, 0.22, 0.35)
            lg.rectangle("fill", bx + 12, y - 3, bw - 24, lineHeight - 2)
            lg.setColor(1, 1, 1)
        end
        lg.printf(label(item, i), bx, y, bw, "center")
    end
    lg.setFont(previousFont)
end

return menu
