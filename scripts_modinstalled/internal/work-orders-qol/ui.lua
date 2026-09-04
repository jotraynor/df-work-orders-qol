-- Shared knowledge about the vanilla Work Orders screen layout.
-- Both overlays in this mod use this module, so a vanilla UI change only
-- needs fixing here.
--
-- The numbers mirror what DFHack's own orders search overlay uses
-- (hack/lua/plugins/orders.lua); DFHack keeps those locals private, so they
-- are duplicated here rather than imported.
--@ module = true

local gui = require('gui')

local mi = df.global.game.main_interface

-- each order occupies this many text rows
ORDER_HEIGHT = 3
-- below this interface width the tab bar wraps onto two rows
TABS_WIDTH_THRESHOLD = 155
-- first list row (0-based) for a one-row / two-row tab bar
LIST_START_Y_ONE_TABS_ROW = 8
LIST_START_Y_TWO_TABS_ROWS = 10
-- rows below the list reserved for the bottom bar
BOTTOM_MARGIN = 9

function get_orders()
    return df.global.world.manager_orders.all
end

function get_scroll()
    return mi.info.work_orders.scroll_position_work_orders
end

function get_list_start_y()
    if gui.get_interface_rect().width >= TABS_WIDTH_THRESHOLD then
        return LIST_START_Y_ONE_TABS_ROW
    end
    return LIST_START_Y_TWO_TABS_ROWS
end

-- how many orders fit on screen
function get_viewport_size()
    local rect = gui.get_interface_rect()
    local available_height = rect.height - get_list_start_y() - BOTTOM_MARGIN
    return math.max(1, math.floor(available_height / ORDER_HEIGHT))
end

-- first and last order indices currently visible on screen (0-based)
function get_visible_range()
    local orders = get_orders()
    if #orders == 0 then return 0, -1 end

    local viewport_size = get_viewport_size()
    local viewport_start = get_scroll()
    local viewport_end = viewport_start + viewport_size - 1

    if viewport_end >= #orders then
        viewport_end = #orders - 1
        viewport_start = math.max(0, viewport_end - viewport_size + 1)
    end

    return viewport_start, viewport_end
end

-- screen row of the given order's first line, or nil if it is scrolled off
function get_order_y(idx)
    local vstart, vend = get_visible_range()
    if idx < vstart or idx > vend then return nil end
    return get_list_start_y() + (idx - vstart) * ORDER_HEIGHT
end

-- index of the order whose row is under the mouse, or nil
function get_order_under_mouse()
    local mx, my = dfhack.screen.getMousePos()
    if not mx then return nil end

    local rect = gui.get_interface_rect()
    local iy = my - rect.y1
    local start_y = get_list_start_y()
    if iy < start_y then return nil end

    local row = (iy - start_y) // ORDER_HEIGHT
    local vstart, vend = get_visible_range()
    local idx = vstart + row
    if idx > vend then return nil end
    return idx
end

-- scroll so the given index is the first row, as far as vanilla allows
function clamp_scroll(wanted)
    local max_scroll = math.max(0, #get_orders() - get_viewport_size())
    mi.info.work_orders.scroll_position_work_orders = math.max(0, math.min(wanted, max_scroll))
end
