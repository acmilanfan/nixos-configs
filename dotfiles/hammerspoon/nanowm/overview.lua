-- =============================================================================
-- NanoWM Overview UI
-- Visual tag overview and interactive selection
-- =============================================================================

local config = require("nanowm.config")
local state = require("nanowm.state")
local tags = require("nanowm.tags")
local core = require("nanowm.core")

local M = {}

local overviewCanvas = nil
local overviewModal = nil
-- Grid geometry. Cells 1..CELLS are laid out COLS wide; the last row is partially filled.
local COLS  = 4
local CELLS = 11   -- tags 1-10 plus Special
local ROWS  = math.ceil(CELLS / COLS)

local selectedIndex = 1 -- cell index: 1-10 are tags, 11 is Special

-- Which bank of ten tags the grid is showing: 0 for tags 1-10, 10 for 11-20, and so on.
-- Tags map to monitors in tens (see state.getScreenForTag), and Ctrl+Alt+1-9/0 reach the
-- 11-20 bank, but the overview always rendered 1-10 and silently collapsed a current tag
-- above 10 to cell 1 — so on tag 13 it highlighted tag 1 and offered no way to see that bank.
local bankBase = 0

-- Cell index -> real tag ("special" for the last cell).
local function cellTag(index)
    if index == CELLS then return "special" end
    return bankBase + index
end

-- Move the selection one step. Pure and exported so it can be tested without a canvas.
--
-- The previous implementation was modular arithmetic over the item count:
--     right -> (i % 11) + 1        down -> (i + 3) % 11 + 1
--     left  -> (i - 2) % 11 + 1    up   -> (i - 5) % 11 + 1
-- Left/right were fine (linear next/previous with wrap), but up/down produced non-adjacent
-- cells at the edges: "up" from cell 1 landed on 8 rather than 9, because it wrapped linearly
-- instead of by column. Now up/down move by whole rows and wrap within the same column,
-- skipping the gap in the partially-filled last row.
function M.gridStep(index, dir, cells, cols)
    cells = cells or CELLS
    cols  = cols  or COLS
    local rows = math.ceil(cells / cols)

    if dir == "right" then
        return (index % cells) + 1
    elseif dir == "left" then
        return ((index - 2) % cells) + 1
    end

    local col = (index - 1) % cols
    local row = math.floor((index - 1) / cols)

    if dir == "down" then
        for step = 1, rows do
            local candidate = ((row + step) % rows) * cols + col + 1
            if candidate <= cells then return candidate end
        end
    elseif dir == "up" then
        for step = 1, rows do
            local candidate = ((row - step) % rows) * cols + col + 1
            if candidate <= cells then return candidate end
        end
    end
    return index
end

local COLORS = {
    highlight = { red = 0.2, green = 0.6, blue = 1.0, alpha = 0.8 },
    background = { white = 0, alpha = 0.85 },
    cardBackground = { white = 0.1, alpha = 0.9 },
    placeholder = { white = 0.05, alpha = 1.0 },
    text = { white = 1, alpha = 0.9 },
    textDim = { white = 0.5, alpha = 0.8 }
}

-- =============================================================================
-- Rendering
-- =============================================================================

local function getGridIndexAt(x, y)
    local screen = hs.screen.mainScreen()
    local frame = screen:frame()
    
    local cols = COLS
    local rows = ROWS
    local margin = 60
    local spacing = 30
    
    local cardW = (frame.w - (margin * 2) - (spacing * (cols - 1))) / cols
    local cardH = (frame.h - (margin * 2) - (spacing * (rows - 1))) / rows

    -- Important: Coordinates from mouseCallback are relative to canvas.
    -- Since canvas matches screen frame, we use screen relative coordinates.
    for i = 1, CELLS do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local tx = margin + col * (cardW + spacing)
        local ty = margin + row * (cardH + spacing)
        
        if x >= tx and x <= tx + cardW and y >= ty and y <= ty + cardH then
            return i
        end
    end
    return nil
end

local function render()
    if not overviewCanvas then return end

    local screen = hs.screen.mainScreen()
    local frame = screen:frame()
    
    local cols = COLS
    local rows = ROWS
    local margin = 60
    local spacing = 30
    
    local cardW = (frame.w - (margin * 2) - (spacing * (cols - 1))) / cols
    local cardH = (frame.h - (margin * 2) - (spacing * (rows - 1))) / rows

    local elements = {}
    
    -- 1. Full-screen background overlay
    table.insert(elements, {
        type = "rectangle",
        action = "fill",
        fillColor = COLORS.background,
        frame = { x = 0, y = 0, w = frame.w, h = frame.h },
        trackMouseMove = true -- Crucial for mouseMove events
    })

    -- 2. Grid of tags (1-11, where 11 is special)
    for i = 1, CELLS do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        
        local x = margin + col * (cardW + spacing)
        local y = margin + row * (cardH + spacing)
        
        -- Card base
        table.insert(elements, {
            type = "rectangle",
            action = "fill",
            fillColor = COLORS.cardBackground,
            frame = { x = x, y = y, w = cardW, h = cardH },
            roundedRectRadii = { xRadius = 12, yRadius = 12 },
            trackMouseMove = true
        })

        -- Snapshot or Placeholder
        local tagKey = cellTag(i)
        local snapshot = state.tagSnapshots[tagKey]
        
        if snapshot then
            table.insert(elements, {
                type = "image",
                image = snapshot,
                frame = { x = x + 8, y = y + 8, w = cardW - 16, h = cardH - 16 },
                imageAlpha = 1.0
            })
        else
            table.insert(elements, {
                type = "rectangle",
                action = "fill",
                fillColor = COLORS.placeholder,
                frame = { x = x + 8, y = y + 8, w = cardW - 16, h = cardH - 16 },
                roundedRectRadii = { xRadius = 8, yRadius = 8 }
            })
            table.insert(elements, {
                type = "text",
                text = "Empty",
                textSize = 24,
                textColor = COLORS.textDim,
                textAlignment = "center",
                frame = { x = x, y = y + (cardH / 2) - 12, w = cardW, h = 30 }
            })
        end

        -- Selection highlight (thick blue border)
        if i == selectedIndex then
            table.insert(elements, {
                type = "rectangle",
                action = "stroke",
                strokeColor = COLORS.highlight,
                strokeWidth = 8,
                frame = { x = x - 4, y = y - 4, w = cardW + 8, h = cardH + 8 },
                roundedRectRadii = { xRadius = 14, yRadius = 14 }
            })
        end

        -- Tag number indicator
        table.insert(elements, {
            type = "rectangle",
            action = "fill",
            fillColor = { white = 0, alpha = 0.6 },
            frame = { x = x + 15, y = y + 15, w = 40, h = 40 },
            roundedRectRadii = { xRadius = 20, yRadius = 20 }
        })
        table.insert(elements, {
            type = "text",
            text = (i == CELLS) and "S" or tostring(bankBase + i),
            textSize = 24,
            textColor = COLORS.text,
            textAlignment = "center",
            frame = { x = x + 15, y = y + 20, w = 40, h = 40 }
        })
    end

    overviewCanvas:replaceElements(elements)
end

-- =============================================================================
-- Lifecycle
-- =============================================================================

function M.show()
    if state.overviewActive then return end
    
    -- Determine starting index
    if state.special.active then
        selectedIndex = CELLS
    else
        -- Show the bank containing the current tag, and select that tag within it.
        local cur = tonumber(state.currentTag) or 1
        bankBase = math.floor((cur - 1) / 10) * 10
        selectedIndex = cur - bankBase
        if selectedIndex < 1 or selectedIndex > 10 then selectedIndex = 1 end
    end

    local screen = hs.screen.mainScreen()
    local frame = screen:frame()
    
    -- Initialize Canvas
    overviewCanvas = hs.canvas.new(frame)
    overviewCanvas:level(hs.canvas.windowLevels.overlay)
    
    -- Mouse interaction
    overviewCanvas:mouseCallback(function(canvas, event, id, x, y)
        if event == "mouseMove" then
            local index = getGridIndexAt(x, y)
            if index and index ~= selectedIndex then
                selectedIndex = index
                render()
            end
        elseif event == "mouseDown" then
            local index = getGridIndexAt(x, y)
            if index then
                -- Hide FIRST to prevent taking a snapshot of the overview
                M.hide()
                if index == CELLS then
                    if not state.special.active then tags.toggleSpecial() end
                else
                    tags.gotoTag(cellTag(index))
                end
            end
        end
    end)
    
    -- Track mouse moves on the canvas
    overviewCanvas:canvasMouseEvents(true, true, true, false)
    
    render()
    overviewCanvas:show()
    
    -- Initialize Modal
    overviewModal = hs.hotkey.modal.new()
    
    -- 1. Grid Navigation (hjkl + Arrows)
    local function move(dir)
        selectedIndex = M.gridStep(selectedIndex, dir)
        render()
    end

    overviewModal:bind({}, "h", function() move("left") end)
    overviewModal:bind({}, "l", function() move("right") end)
    overviewModal:bind({}, "j", function() move("down") end)
    overviewModal:bind({}, "k", function() move("up") end)
    
    overviewModal:bind({}, "left", function() move("left") end)
    overviewModal:bind({}, "right", function() move("right") end)
    overviewModal:bind({}, "down", function() move("down") end)
    overviewModal:bind({}, "up", function() move("up") end)
    
    -- 2. Direct Access (1-9, 0, s)
    for i = 1, 9 do
        overviewModal:bind({}, tostring(i), function()
            M.hide()
            tags.gotoTag(bankBase + i)
        end)
    end
    overviewModal:bind({}, "0", function() 
        M.hide()
        tags.gotoTag(bankBase + 10)
    end)
    overviewModal:bind({}, "s", function()
        M.hide()
        if not state.special.active then tags.toggleSpecial() end
    end)
    
    -- 3. Confirm Selection
    local confirm = function() 
        local target = selectedIndex
        M.hide() 
        if target == CELLS then
            if not state.special.active then tags.toggleSpecial() end
        else
            tags.gotoTag(cellTag(target))
        end
    end
    overviewModal:bind({}, "return", confirm)
    overviewModal:bind({}, "space", confirm)
    
    -- 4. Exit
    overviewModal:bind({}, "escape", function() M.hide() end)
    overviewModal:bind({}, "tab", function() M.hide() end)
    
    overviewModal:enter()
    state.overviewActive = true
end

function M.hide()
    if overviewCanvas then
        overviewCanvas:delete()
        overviewCanvas = nil
    end
    if overviewModal then
        overviewModal:exit()
        overviewModal = nil
    end
    state.overviewActive = false
end

return M
