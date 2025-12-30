---Basic cell data used within the internal buffers of a surface.
---
---@class evcc.cellbuf.Cell
---
---@field char? string The character to print, or `' '` if not present.
---@field fg? ccTweaked.colors.color The foreground color, or the default if not present.
---@field bg? ccTweaked.colors.color The background color, or the default if not present.

---Provides basic swap-buffer-based rendering support for cell-based interfaces.
---
---@class evcc.cellbuf.Lib
local module = {}

---Creates a new surface using the given value.
---
---@param value ccTweaked.peripherals.Monitor | ccTweaked.term.Redirect The value to wrap.
---
---@return evcc.cellbuf.Surface surface The rendering surface.
function module.createSurface(value)
    ---An abstract rendering surface.
    ---
    ---@class evcc.cellbuf.Surface
    local surface = {}

    ---Provides an API to the underlying value.
    surface.api = {
        ---The inner interface, can be either a monitor peripheral or a terminal redirect.
        inner = assert(value, 'The given value must not be nil'),
    }

    ---Returns the size of the rendering surface.
    ---
    ---@return integer width The surface's width.
    ---@return integer height The surface's height.
    function surface.api:getSize()
        return self.inner.getSize()
    end

    ---Returns the scale of the rendering surface.
    ---
    ---If this surface wraps a terminal redirect, this function will always return `1.0`
    ---
    ---@return number scale The surface's scale.
    function surface.api:getScale()
        return self.inner.getTextScale and self.inner.getTextScale() or 1.0
    end

    ---Sets the scale of the rendering surface.
    ---
    ---This is only supported on surfaces that wrap monitors.
    ---
    ---@param scale number A number between `0.5` and `2.0`.
    function surface.api:setScale(scale)
        assert(self.inner.setTextScale, 'Unsupported operation')(scale)
    end

    ---Returns `true` if the surface supports scaling.
    ---
    ---@return boolean supported Whether scaling is supported.
    function surface.api:supportsScaling()
        return self.inner.setTextScale ~= nil
    end

    ---Returns the surface's foreground color.
    ---
    ---@return ccTweaked.colors.color color The color.
    function surface.api:getFgColor()
        return self.inner.getTextColor()
    end

    ---Sets the surface's foreground color.
    ---
    ---@param color ccTweaked.colors.color The color.
    function surface.api:setFgColor(color)
        self.inner.setTextColor(color)
    end

    ---Returns the surface's background color.
    ---
    ---@return ccTweaked.colors.color color The color.
    function surface.api:getBgColor()
        return self.inner.getBackgroundColor()
    end

    ---Sets the surface's background color.
    ---
    ---@param color ccTweaked.colors.color The color.
    function surface.api:setBgColor(color)
        self.inner.setBackgroundColor(color)
    end

    ---Returns the surface's current cell position.
    ---
    ---@return integer x The X position.
    ---@return integer y The Y position.
    function surface.api:getPos()
        return self.inner.getCursorPos()
    end

    ---Sets the surface's cell position.
    ---
    ---@param x integer An integer between `1` and the surface's width.
    ---@param y integer An integer between `1` and the surface's height.
    function surface.api:setPos(x, y)
        self.inner.setCursorPos(x, y)
    end

    ---Clears the surface.
    function surface.api:clear()
        self.inner.clear()
    end

    ---Clears the surface's current line.
    function surface.api:clearLine()
        self.inner.clearLine()
    end

    ---Writes a string to the surface, advancing the current cursor position.
    ---
    ---On X overflow, this function will set the current position to (1, <y> + 1)
    ---
    ---@param text string The string to write.
    function surface.api:write(text)
        self.inner.write(text)
    end

    ---The surface's in-memory cell buffers.
    surface.buffer = {
        ---@type evcc.cellbuf.Cell[]
        [1] = {},
        ---@type evcc.cellbuf.Cell[]
        [2] = {},
        ---The surface's color defaults.
        color = {
            ---The default foreground color.
            fg = 0,
            ---The default background color.
            bg = 0,
        },
        ---The surface's current buffer size.
        size = {
            ---The surface's X width.
            x = 0,
            ---The surface's Y height.
            y = 0,
        }
    }

    ---Returns the current immutable buffer.
    ---
    ---This buffer should displayed and never modified, if you want to modify it, call `swap`.
    ---
    ---@return evcc.cellbuf.Cell[] buffer The buffer.
    function surface.buffer:immutable()
        return self[2]
    end

    ---Returns the current mutable buffer.
    ---
    ---This buffer should be modified and never displayed, if you want to display it, call `swap`.
    ---
    ---@return evcc.cellbuf.Cell[] buffer The buffer.
    function surface.buffer:mutable()
        return self[1]
    end

    ---Swaps the current buffer with the displayed buffer.
    function surface.buffer:swap()
        self[2] = table.remove(self, 1)
    end

    ---Returns the index used to store the data at the given (X, Y) position.
    ---
    ---@param x integer The X position, must be between `1` and the buffer's width.
    ---@param y integer The Y position, must be between `1` and the buffer's height.
    ---
    ---@return integer index The buffer index.
    function surface.buffer:index(x, y)
        assert(x > 0 and x <= self.size.x, 'Invalid X position')
        assert(y > 0 and y <= self.size.y, 'Invalid Y position')

        return 1 + (x - 1) + ((y - 1) * self.size.x)
    end

    ---Returns the screen position of the data at the given index.
    ---
    ---@param index integer The index, must be between `1` and the length of the buffer.
    ---
    ---@return integer x The X position.
    ---@return integer y The Y position.
    function surface.buffer:pos(index)
        assert(index > 0 and index <= self.size.x * self.size.y, 'Invalid index')

        return 1 + ((index - 1) % self.size.x), 1 + math.floor((index - 1) / self.size.x)
    end

    ---Sets the specified cell to the given data.
    ---
    ---@param x integer The X position, must be between `1` and the width of the buffer.
    ---@param y integer The Y position, must be between `1` and the height of the buffer.
    ---@param data evcc.cellbuf.Cell The cell data.
    function surface.buffer:set(x, y, data)
        assert(not data.char or data.char:len() == 1, 'Character must be a single character')

        self:mutable()[self:index(x, y)] = data
    end

    ---Fills the entire buffer with the given data.
    ---
    ---@param data evcc.cellbuf.Cell The cell data.
    function surface.buffer:fill(data)
        assert(not data.char or data.char:len() == 1, 'Character must be a single character')

        local buffer = self:mutable()

        for index = 1, self.size.x * self.size.y do
            buffer[index] = data
        end
    end

    ---Fills the specified range with the given data.
    ---
    ---@param startX integer The starting X position, must be between `1` and the width of the buffer.
    ---@param startY integer The starting Y position, must be between `1` and the height of the buffer.
    ---@param endX integer The ending X position, must be between `startX` and the width of the buffer.
    ---@param endY integer The ending Y position, must be between `endX` and the height of the buffer.
    ---@param data evcc.cellbuf.Cell The cell data.
    function surface.buffer:fillRange(startX, startY, endX, endY, data)
        assert(startX > 0 and startX <= self.size.x, 'Invalid starting X position')
        assert(startY > 0 and startY <= self.size.y, 'Invalid starting Y position')
        assert(endX > 0 and endX <= self.size.x, 'Invalid ending X position')
        assert(endY > 0 and endY <= self.size.y, 'Invalid ending Y position')
        assert(startX <= endX, 'Invalid X position range')
        assert(startY <= endY, 'Invalid Y position range')
        assert(not data.char or data.char:len() == 1, 'Character must be a single character')

        local buffer = self:mutable()

        for y = startY, endY do
            for x = startX, endX do
                buffer[self:index(x, y)] = data
            end
        end
    end

    ---Runs a function for each cell within the buffer.
    ---
    ---@param func fun(x: integer, y: integer, cell: evcc.cellbuf.Cell): evcc.cellbuf.Cell | nil The function to run.
    function surface.buffer:modify(func)
        local buffer = self:mutable()

        for index, cell in ipairs(buffer) do
            local x, y = self:pos(index)
            local output = func(x, y, cell)

            assert(not output or not output.char or output.char:len() == 1, 'Character must be a single character')

            buffer[index] = output or cell
        end
    end

    ---Runs a function for each cell within given range in the buffer.
    ---
    ---@param startX integer The starting X position, must be between `1` and the width of the buffer.
    ---@param startY integer The starting Y position, must be between `1` and the height of the buffer.
    ---@param endX integer The ending X position, must be between `startX` and the width of the buffer.
    ---@param endY integer The ending Y position, must be between `endX` and the height of the buffer.
    ---@param func fun(x: integer, y: integer, cell: evcc.cellbuf.Cell): evcc.cellbuf.Cell | nil The function to run.
    function surface.buffer:modifyRange(startX, startY, endX, endY, func)
        assert(startX > 0 and startX <= self.size.x, 'Invalid starting X position')
        assert(startY > 0 and startY <= self.size.y, 'Invalid starting Y position')
        assert(endX > 0 and endX <= self.size.x, 'Invalid ending X position')
        assert(endY > 0 and endY <= self.size.y, 'Invalid ending Y position')
        assert(startX <= endX, 'Invalid X position range')
        assert(startY <= endY, 'Invalid Y position range')

        local buffer = self:mutable()

        for y = startY, endY do
            for x = startX, endX do
                local index = self:index(x, y)
                local cell = buffer[index]
                local output = func(x, y, cell)

                assert(not output or not output.char or output.char:len() == 1, 'Character must be a single character')

                buffer[index] = output or cell
            end
        end
    end

    ---Resizes the inner buffers to the given dimensions.
    ---
    ---@param x integer The surface width, must be at least `1`.
    ---@param y integer The surface height, must be at least `1`.
    function surface.buffer:resize(x, y)
        assert(x > 0, 'The given width must be at least 1')
        assert(y > 0, 'The given height must be at least 1')

        self.size = { x = x, y = y }
        self[1] = {}
        self[2] = {}
        self:fill({})
    end

    ---Returns the size of the surface.
    ---
    ---@return integer width The surface's width.
    ---@return integer height The surface's height.
    function surface:getSize()
        return self.api:getSize()
    end

    ---Returns `true` if the surface supports scaling.
    ---
    ---@return boolean supported Whether scaling is supported.
    function surface:canScale()
        return self.api:supportsScaling()
    end

    ---Returns the scale of the surface, a number between `0.5` and `5.0`.
    ---
    ---@return number scale The scale.
    function surface:getScale()
        return self.api:getScale()
    end

    ---Returns the scale of the surface, a number between `0.5` and `5.0`.
    ---
    ---This may not be supported if this surface is a terminal redirect.
    ---
    ---@param scale number The scale.
    function surface:setScale(scale)
        self.api:setScale(scale)

        sleep(0.05) -- Wait one tick for the monitor to catch up.

        local x, y = self:getSize()

        self.buffer:resize(x, y)
    end

    ---Returns the default foreground color.
    ---
    ---@return ccTweaked.colors.color color The default foreground color.
    function surface:getFg()
        return self.buffer.color.fg
    end

    ---Sets the default foreground color.
    ---
    ---@param color ccTweaked.colors.color
    function surface:setFg(color)
        self.buffer.color.fg = color
    end

    ---Returns the default background color.
    ---
    ---@return ccTweaked.colors.color color The default background color.
    function surface:getBg()
        return self.buffer.color.bg
    end

    ---Sets the default background color.
    ---
    ---@param color ccTweaked.colors.color
    function surface:setBg(color)
        self.buffer.color.bg = color
    end

    ---Returns the cell data at the given position.
    ---
    ---@param x integer The X position, must be between `1` and the surface's width.
    ---@param y integer The Y position, must be between `1` and the surface's height.
    ---
    ---@return evcc.cellbuf.Cell cell The cell data.
    function surface:getCell(x, y)
        return self.buffer:mutable()[self.buffer:index(x, y)]
    end

    ---Sets the cell data at the given position.
    ---
    ---@param x integer The X position, must be between `1` and the surface's width.
    ---@param y integer The Y position, must be between `1` and the surface's height.
    ---@param cell evcc.cellbuf.Cell The cell data.
    function surface:setCell(x, y, cell)
        self.buffer:mutable()[self.buffer:index(x, y)] = cell
    end

    ---Sets all cells to the given data.
    ---
    ---@param cell evcc.cellbuf.Cell The cell data.
    function surface:setAllCells(cell)
        self.buffer:fill(cell)
    end

    ---Runs a function for each cell within the buffer.
    ---
    ---@param func fun(x: integer, y: integer, cell: evcc.cellbuf.Cell): evcc.cellbuf.Cell | nil The function to run.
    function surface:modifyCells(func)
        self.buffer:modify(func)
    end

    ---Sets the cell data for each cell within the given range.
    ---
    ---@param startX integer The starting X position, must be between `1` and the width of the surface.
    ---@param startY integer The starting Y position, must be between `1` and the height of the surface.
    ---@param endX integer The ending X position, must be between `startX` and the width of the surface.
    ---@param endY integer The ending Y position, must be between `endX` and the height of the surface.
    ---@param cell evcc.cellbuf.Cell The cell data.
    function surface:setCellsInRange(startX, startY, endX, endY, cell)
        self.buffer:fillRange(startX, startY, endX, endY, cell)
    end

    ---Runs a function for each cell within the given range.
    ---
    ---@param startX integer The starting X position, must be between `1` and the width of the surface.
    ---@param startY integer The starting Y position, must be between `1` and the height of the surface.
    ---@param endX integer The ending X position, must be between `startX` and the width of the surface.
    ---@param endY integer The ending Y position, must be between `endX` and the height of the surface.
    ---@param func fun(x: integer, y: integer, cell: evcc.cellbuf.Cell): evcc.cellbuf.Cell | nil The function to run.
    function surface:modifyCellsInRange(startX, startY, endX, endY, func)
        self.buffer:modifyRange(startX, startY, endX, endY, func)
    end

    ---Finishes the current buffer so that it may be rendered.
    function surface:finish()
        self.buffer:swap()
    end

    ---Draws all finished cells to the surface.
    function surface:draw()
        for index, cell in ipairs(self.buffer:immutable()) do
            assert(not cell.char or cell.char:len() == 1, 'Character must be a single character')

            local x, y = self.buffer:pos(index)

            if x == 1 then
                self.api:setPos(x, y)
            end

            self.api:setFgColor(cell.fg or self.api:getFgColor())
            self.api:setBgColor(cell.bg or self.api:getBgColor())
            self.api:write(cell.char or ' ')
        end
    end

    ---Finish rendering and immediately draw the buffer to the surface.
    ---
    ---Convenience method for calling `finish` and `draw` sequentially.
    function surface:finishAndDraw()
        self:finish()
        self:draw()
    end

    do
        local x, y = surface.api:getSize()

        surface.buffer:resize(x, y)
        surface:setFg(surface.api:getFgColor())
        surface:setBg(surface.api:getBgColor())
    end

    return surface
end

---The current terminal.
module.terminal = module.createSurface(term)

---The current peripherals being used by the library.
---
---@type evcc.cellbuf.Surface[]
module.monitors = {}

---Scans and creates surfaces for all attached monitor peripherals.
function module:scanPeripherals()
    self.monitors = {}

    for _, monitor in ipairs({ peripheral.find('monitor') }) do
        ---@diagnostic disable-next-line: param-type-mismatch
        self.monitors[#self.monitors + 1] = self.createSurface(monitor)
    end
end

---Runs the given function on each registered surface.
---
---@param func fun(surface: evcc.cellbuf.Surface) The function to run.
function module:copyToAll(func)
    func(self.terminal)

    for _, surface in ipairs(self.monitors) do
        func(surface)
    end
end

---Runs the given function on each registered surface.
---
---@param func fun(index: integer, surface: evcc.cellbuf.Surface) The function to run.
function module:modifyIndexed(func)
    func(1, self.terminal)

    for index, surface in ipairs(self.monitors) do
        func(index + 1, surface)
    end
end

return module
