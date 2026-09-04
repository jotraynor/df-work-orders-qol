-- Filters the Work Orders list in place to the orders matching typed words.
--@ module = true
--[====[

work-order-filter
=================

Overlay for the Work Orders screen. Type in the ``Filter orders`` box
(``Ctrl+F`` focuses it, or click it) and the vanilla list shrinks to only the
work orders whose name, material, job or assigned workshop contains all of the
words you typed (``wood`` matches ``Make wooden barrel``). Edit the remaining
rows exactly as usual. Clear the box (or leave the screen) and the full list
comes back, with any edits, deletions and reordering you made kept.

While a filter is active the non-matching orders are temporarily taken out of
the game's order list, so the game is kept paused and the filter is dropped
automatically the moment you leave the Work Orders screen. A backup of all
orders is also exported to ``dfhack-config/orders/work-order-filter-backup.json``
whenever a filter starts; ``orders import work-order-filter-backup`` restores
it if anything ever goes wrong.

Toggle the overlay with ``gui/control-panel`` (Overlays tab) or::

    overlay enable work-order-filter.filter
    overlay disable work-order-filter.filter

]====]

local gui = require('gui')
local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')

local GLOBAL_KEY = 'work-order-filter'
local SCREEN_PREFIX = 'dwarfmode/Info/WORK_ORDERS'
local BACKUP_NAME = 'work-order-filter-backup'

local mi = df.global.game.main_interface

-- Geometry of the vanilla Work Orders list (matches DFHack's orders.lua),
-- used only to keep the scroll position sane.
local ORDER_HEIGHT = 3
local TABS_WIDTH_THRESHOLD = 155
local LIST_START_Y_ONE_TABS_ROW = 8
local LIST_START_Y_TWO_TABS_ROWS = 10
local BOTTOM_MARGIN = 9

-- Filter state lives in the module so it survives the widget being rebuilt.
--   hidden:   list of {id=, order=} taken out of the list, in original order
--   orig_ids: ids of every order, in the order they had before filtering
--   pins_top / pins_bottom: ids that shift-click sent to the absolute top/bottom
state = state or {
    hidden=nil,
    orig_ids=nil,
    pins_top={},
    pins_bottom={},
    watchdog=nil,
    widget=nil,
}

-- --------------------------------------------------------------------------
-- helpers

local function get_orders()
    return df.global.world.manager_orders.all
end

local function get_viewport_size()
    local rect = gui.get_interface_rect()
    local start_y = rect.width >= TABS_WIDTH_THRESHOLD
        and LIST_START_Y_ONE_TABS_ROW or LIST_START_Y_TWO_TABS_ROWS
    return math.max(1, math.floor((rect.height - start_y - BOTTOM_MARGIN) / ORDER_HEIGHT))
end

local function clamp_scroll(wanted)
    local max_scroll = math.max(0, #get_orders() - get_viewport_size())
    mi.info.work_orders.scroll_position_work_orders = math.max(0, math.min(wanted, max_scroll))
end

local function on_work_orders_screen()
    if not dfhack.isWorldLoaded() then return false end
    local ok, focus = pcall(dfhack.gui.getFocusStrings, dfhack.gui.getDFViewscreen(true))
    if not ok then return false end
    for _, fs in ipairs(focus) do
        if fs:startswith(SCREEN_PREFIX) then return true end
    end
    return false
end

local function save_requested()
    local ok, val = pcall(function() return df.global.plotinfo.main.autosave_request end)
    return ok and val
end

local function get_workshop_text(order)
    if order.workshop_id == -1 then return '' end
    local ok, text = pcall(function()
        local bld = df.building.find(order.workshop_id)
        if not bld then return '' end
        local parts = {}
        if bld.name and #bld.name > 0 then parts[#parts+1] = bld.name end
        local btype = bld:getType()
        if btype == df.building_type.Workshop then
            parts[#parts+1] = df.workshop_type[bld.type] or ''
        elseif btype == df.building_type.Furnace then
            parts[#parts+1] = df.furnace_type[bld.type] or ''
        end
        return table.concat(parts, ' ')
    end)
    return ok and text or ''
end

-- everything about an order that a search word may match against
local function get_search_key(order)
    local parts = {dfhack.job.getManagerOrderName(order) or ''}
    local attrs = df.job_type.attrs[order.job_type]
    if attrs and attrs.caption then parts[#parts+1] = attrs.caption end
    for name, set in pairs(order.material_category) do
        if set then parts[#parts+1] = name end
    end
    parts[#parts+1] = get_workshop_text(order)
    return dfhack.toSearchNormalized(table.concat(parts, ' '))
end

local function get_tokens(text)
    local tokens = {}
    for tok in dfhack.toSearchNormalized(text):gmatch('%S+') do
        tokens[#tokens+1] = tok
    end
    return tokens
end

-- every word must appear somewhere in the key (plain substring match, so
-- "wood" finds "wooden" and "rosewood")
local function key_matches(key, tokens)
    for _, tok in ipairs(tokens) do
        if not key:find(tok, 1, true) then return false end
    end
    return true
end

local function is_mouse_key(keys)
    return keys._MOUSE_L or keys._MOUSE_R or keys._MOUSE_M
        or keys.CONTEXT_SCROLL_UP or keys.CONTEXT_SCROLL_DOWN
        or keys.CONTEXT_SCROLL_PAGEUP or keys.CONTEXT_SCROLL_PAGEDOWN
end

-- --------------------------------------------------------------------------
-- filter / restore

function is_active()
    return state.hidden ~= nil
end

function hidden_count()
    return state.hidden and #state.hidden or 0
end

-- Called by shift-click-to-top: while a filter is active, "top" and "bottom"
-- of the visible list should mean the top/bottom of the full list.
local function unpin(id)
    for _, list in ipairs{state.pins_top, state.pins_bottom} do
        for i = #list, 1, -1 do
            if list[i] == id then table.remove(list, i) end
        end
    end
end

function pin_top(id)
    if not is_active() then return end
    unpin(id)
    table.insert(state.pins_top, id)
end

function pin_bottom(id)
    if not is_active() then return end
    unpin(id)
    table.insert(state.pins_bottom, id)
end

-- Take every non-matching order out of the list. Must not be active already.
local function apply_filter(text)
    local tokens = get_tokens(text)
    local orders = get_orders()

    local orig_ids, hidden = {}, {}
    for i = 0, #orders - 1 do
        local o = orders[i]
        orig_ids[#orig_ids+1] = o.id
        if not key_matches(get_search_key(o), tokens) then
            hidden[#hidden+1] = {id=o.id, order=o}
        end
    end

    -- keep a recoverable copy of everything before touching the list
    pcall(dfhack.run_command_silent, 'orders', 'export', BACKUP_NAME)

    -- commit the state before mutating so a restore is always possible
    state.orig_ids = orig_ids
    state.hidden = hidden
    state.pins_top = {}
    state.pins_bottom = {}

    local hidden_ids = {}
    for _, h in ipairs(hidden) do hidden_ids[h.id] = true end
    for i = #orders - 1, 0, -1 do
        if hidden_ids[orders[i].id] then
            orders:erase(i)
        end
    end

    clamp_scroll(0)
end

-- Put the hidden orders back. Hidden orders keep their original positions;
-- the orders that stayed visible fill the remaining positions in whatever
-- order the player left them in, deleted ones are dropped, and new ones go on
-- the end. Then shift-click pins move their orders to the very top/bottom.
local function restore()
    if not is_active() then return end
    local orders = get_orders()

    local hidden_by_id = {}
    for _, h in ipairs(state.hidden) do hidden_by_id[h.id] = h end

    local was_visible = {}
    for _, id in ipairs(state.orig_ids) do
        if not hidden_by_id[id] then was_visible[id] = true end
    end

    -- remember what the player was looking at so the view doesn't jump
    local first_visible_id = #orders > 0
        and orders[math.min(mi.info.work_orders.scroll_position_work_orders, #orders - 1)].id
        or nil

    local fillers, new_orders = {}, {}
    for i = 0, #orders - 1 do
        local o = orders[i]
        if was_visible[o.id] then
            fillers[#fillers+1] = o
        else
            new_orders[#new_orders+1] = o
        end
    end

    local result = {}
    local fi = 1
    for _, id in ipairs(state.orig_ids) do
        local h = hidden_by_id[id]
        if h then
            result[#result+1] = h.order
        elseif fillers[fi] then
            result[#result+1] = fillers[fi]
            fi = fi + 1
        end
    end
    while fillers[fi] do
        result[#result+1] = fillers[fi]
        fi = fi + 1
    end
    for _, o in ipairs(new_orders) do result[#result+1] = o end

    local function pull(id)
        for i, o in ipairs(result) do
            if o.id == id then return table.remove(result, i) end
        end
    end
    for _, id in ipairs(state.pins_top) do
        local o = pull(id)
        if o then table.insert(result, 1, o) end
    end
    for _, id in ipairs(state.pins_bottom) do
        local o = pull(id)
        if o then table.insert(result, o) end
    end

    -- write the merged list back
    while #orders > 0 do orders:erase(#orders - 1) end
    for _, o in ipairs(result) do orders:insert('#', o) end

    state.hidden = nil
    state.orig_ids = nil
    state.pins_top = {}
    state.pins_bottom = {}

    local wanted = 0
    if first_visible_id then
        for i = 0, #orders - 1 do
            if orders[i].id == first_visible_id then wanted = i break end
        end
    end
    clamp_scroll(wanted)
end

-- restore and blank the filter box without re-triggering the filter
local function deactivate()
    restore()
    local w = state.widget
    if w and w.subviews.filter and w.subviews.filter.text ~= '' then
        w.suppress_change = true
        w.subviews.filter:setText('')
        w.suppress_change = false
    end
end

-- Runs every frame while a filter is active: keeps the game paused, and
-- drops the filter as soon as the player leaves the screen, a save is
-- requested, or the world goes away.
local function watchdog()
    state.watchdog = nil
    if not is_active() then return end
    if not dfhack.isWorldLoaded() then
        -- the orders no longer exist; nothing to put back
        state.hidden, state.orig_ids = nil, nil
        return
    end
    if not on_work_orders_screen() or save_requested() then
        deactivate()
        return
    end
    df.global.pause_state = true
    state.watchdog = dfhack.timeout(1, 'frames', watchdog)
end

local function ensure_watchdog()
    if state.watchdog and dfhack.timeout_active(state.watchdog) then return end
    state.watchdog = dfhack.timeout(1, 'frames', watchdog)
end

function set_filter(text)
    if is_active() then restore() end
    if text and text ~= '' then
        apply_filter(text)
        ensure_watchdog()
    end
end

dfhack.onStateChange[GLOBAL_KEY] = function(sc)
    if sc == SC_WORLD_UNLOADED or sc == SC_MAP_UNLOADED then
        state.hidden, state.orig_ids = nil, nil
        state.pins_top, state.pins_bottom = {}, {}
    end
end

-- --------------------------------------------------------------------------

WorkOrderFilterOverlay = defclass(WorkOrderFilterOverlay, overlay.OverlayWidget)
WorkOrderFilterOverlay.ATTRS{
    desc='Adds a filter box to the work orders screen that narrows the list to matching orders.',
    default_pos={x=111, y=-6},
    default_enabled=true,
    viewscreens='dwarfmode/Info/WORK_ORDERS/Default',
    frame={w=42, h=4},
}

function WorkOrderFilterOverlay:init()
    self.suppress_change = false
    -- if the widget is being rebuilt (e.g. "overlay reload") while a filter
    -- is active, put the full list back rather than leave it half shown
    if is_active() then restore() end
    state.widget = self

    self:addviews{
        widgets.Panel{
            frame={t=0, l=0, r=0, h=4},
            frame_style=gui.MEDIUM_FRAME,
            frame_background=gui.CLEAR_PEN,
            frame_title='Filter orders',
            subviews={
                widgets.EditField{
                    view_id='filter',
                    frame={t=0, l=0, r=0},
                    key='CUSTOM_CTRL_F',
                    on_change=self:callback('on_filter_change'),
                    on_submit=self:callback('on_filter_submit'),
                },
                widgets.Label{
                    frame={t=1, l=0},
                    text={{text=function() return self:get_status_text() end}},
                    text_pen=COLOR_GREY,
                },
                widgets.HotkeyLabel{
                    frame={t=1, r=0},
                    auto_width=true,
                    label='clear',
                    on_activate=self:callback('clear_filter'),
                    enabled=function() return self.subviews.filter.text ~= '' end,
                },
            },
        },
    }
end

function WorkOrderFilterOverlay:get_status_text()
    if not is_active() then
        return 'Type to filter the list'
    end
    local shown = #get_orders()
    return ('Showing %d of %d (paused)'):format(shown, shown + hidden_count())
end

function WorkOrderFilterOverlay:on_filter_change(text)
    if self.suppress_change then return end
    set_filter(text)
end

function WorkOrderFilterOverlay:on_filter_submit()
    -- Enter hands the keyboard back to the game
    self.subviews.filter:setFocus(false)
end

function WorkOrderFilterOverlay:clear_filter()
    deactivate()
end

function WorkOrderFilterOverlay:onInput(keys)
    if mi.job_details.open then return end
    local filter = self.subviews.filter

    -- clicking anywhere else (e.g. a vanilla row) releases the keyboard
    if filter.focus and keys._MOUSE_L and not self:getMousePos() then
        filter:setFocus(false)
        return false
    end

    if WorkOrderFilterOverlay.super.onInput(self, keys) then
        return true
    end

    -- keyboard input goes to the filter box, not to vanilla hotkeys
    if filter.focus and not is_mouse_key(keys) then
        return true
    end
end

function WorkOrderFilterOverlay:render(dc)
    if mi.job_details.open then return end
    if is_active() then ensure_watchdog() end
    WorkOrderFilterOverlay.super.render(self, dc)
end

function WorkOrderFilterOverlay:overlay_ondisable()
    deactivate()
end

OVERLAY_WIDGETS = {
    filter=WorkOrderFilterOverlay,
}

if dfhack_flags.module then
    return
end

print(dfhack.script_help())
