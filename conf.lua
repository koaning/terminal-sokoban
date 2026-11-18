function love.conf(t)
    -- the name of the save folder, for progress.lua
    t.identity = "ps1-sokoban"
    t.window.width = 1280
    t.window.height = 720
    t.window.vsync = true
    t.window.fullscreen = false
    t.window.resizable = true
    t.window.minwidth = 640
    t.window.minheight = 360
    t.window.title = "PS1 Sokoban"

    -- Linux without a desktop, like a handheld running PortMaster: fill the whole screen
    if love._os == "Linux" and not os.getenv("DISPLAY") and not os.getenv("WAYLAND_DISPLAY") then
        t.window.fullscreen = true
    end
end
