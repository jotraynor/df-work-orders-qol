-- Shift+click a work order's up arrow to move it to the top of the list.
--@ module = true
--[====[

shift-click-to-top
==================

Overlay for the Work Orders screen. Hold Shift and click the up arrow on a
work order to move that order straight to the top of the list (highest
priority). Shift+clicking the down arrow moves the order to the bottom.

If DFHack's ``orders-sort`` automation is enabled (``gui/control-panel``,
Automation tab) it re-sorts the whole list once a game day by workshop and
frequency, which undoes any move that crossed one of those groups. The
overlay prints a warning the first time you shift-click in a world where that
automation is on.

The overlay is enabled automatically. To toggle it, use
``gui/control-panel`` (Overlays tab) or::

    overlay enable shift-click-to-top.arrows
    overlay disable shift-click-to-top.arrows

]====]

local overlay = require('plugins.overlay')
local ui = reqscript('internal/work-orders-qol/ui')

local GLOBAL_KEY = 'shift-click-to-top'

local mi = df.global.game.main_interface

-- How many frames to wait for vanilla to react to the click before giving up.
local PENDING_FRAMES = 5

-- Clicking a quantity box puts vanilla into typing mode, and it stays there
-- until Enter or Escape even if you click elsewhere. This overlay used to
-- refuse to act in that state, which made shift-click look dead until the
-- screen was reopened. Cancel the typing the same way DFHack's own
-- orders.quantityrightclick overlay does, then let the click through.
local function cancel_number_entry()
    local wo = mi.info.work_orders
    if wo.entering_number then wo.entering_number = false end
    if wo.b_entering_number then wo.b_entering_number = false end
end

-- DFHack's orders-sort automation (gui/control-panel, Automation tab) runs
-- `orders sort` once a game day. That is a stable sort by workshop
-- assignment and frequency, so it silently undoes any shift-click move that
-- crossed one of those groups. Players read that as "the mod forgot my
-- change", so say so once per world, the first time a move succeeds.
local warned_about_sort = false

local function orders_sort_enabled()
    local ok, output = pcall(dfhack.run_command_silent, 'repeat', '-list')
    return ok and type(output) == 'string' and output:find('orders%-sort', 1, false) ~= nil
end

local function warn_about_orders_sort()
    if warned_about_sort then return end
    warned_about_sort = true
    if not orders_sort_enabled() then return end
    print(('%s: DFHack\'s orders-sort automation is enabled. Once a game day it'
        .. ' re-sorts the list by workshop and frequency, which undoes Shift+click'
        .. ' moves that crossed those groups. Turn it off in gui/control-panel'
        .. ' (Automation tab) if you want manual ordering to stick.'):format(GLOBAL_KEY))
    pcall(dfhack.gui.showAnnouncement,
        'Shift+click: orders-sort automation re-sorts this list daily (see DFHack console)',
        COLOR_YELLOW)
end

dfhack.onStateChange[GLOBAL_KEY] = function(sc)
    if sc == SC_WORLD_LOADED then warned_about_sort = false end
end

local function snapshot_ids()
    local orders = ui.get_orders()
    local ids = {}
    for i = 0, #orders - 1 do
        ids[#ids + 1] = orders[i].id
    end
    return ids
end

-- If `after` is `before` with exactly one pair of neighbours swapped, returns
-- the 0-based index k of the pair (k, k+1). Otherwise returns nil.
local function find_adjacent_swap(before, after)
    if #before ~= #after or #before < 2 then return nil end

    local k = nil
    for i = 1, #before do
        if before[i] ~= after[i] then
            k = i
            break
        end
    end
    if not k or k == #before then return nil end

    if after[k] ~= before[k + 1] or after[k + 1] ~= before[k] then
        return nil
    end
    for i = k + 2, #before do
        if before[i] ~= after[i] then return nil end
    end

    return k - 1
end

-- While work-order-filter has the list narrowed down, tell it that this order
-- should end up at the very top/bottom of the full list once it is restored.
local function notify_filter(fn_name, id)
    local ok, filt = pcall(reqscript, 'work-order-filter')
    if ok and filt and filt.is_active and filt.is_active() and filt[fn_name] then
        filt[fn_name](id)
    end
end

local function move_order(from_idx, to_idx)
    local orders = ui.get_orders()
    if from_idx < 0 or from_idx >= #orders then return end
    local order = orders[from_idx]
    orders:erase(from_idx)
    orders:insert(to_idx, order)
end

-- --------------------------------------------------------------------------

ShiftClickArrowsOverlay = defclass(ShiftClickArrowsOverlay, overlay.OverlayWidget)
ShiftClickArrowsOverlay.ATTRS{
    desc='Shift+click a work order\'s up arrow to send it to the top (down arrow: bottom).',
    default_enabled=true,
    fullscreen=true,
    viewscreens='dwarfmode/Info/WORK_ORDERS/Default',
}

function ShiftClickArrowsOverlay:init()
    self.pending = nil
end

function ShiftClickArrowsOverlay:onInput(keys)
    if not keys._MOUSE_L then return end
    if mi.job_details.open then return end
    if not dfhack.internal.getModifiers().shift then return end

    local idx = ui.get_order_under_mouse()
    if not idx then return end

    cancel_number_entry()

    -- Remember the list, then let vanilla handle the click. If vanilla moves
    -- the clicked order one step, we finish the job in check_pending().
    self.pending = {
        before=snapshot_ids(),
        clicked=idx,
        frames=PENDING_FRAMES,
    }
    return false
end

function ShiftClickArrowsOverlay:check_pending()
    local p = self.pending
    if not p then return end

    local after = snapshot_ids()
    local k = find_adjacent_swap(p.before, after)

    if k then
        self.pending = nil
        -- After the swap, the order that was at k+1 is now at k (it moved up)
        -- and the order that was at k is now at k+1 (it moved down). Only act
        -- when the swap involves the row that was clicked; if the two disagree
        -- the layout assumptions are off, and doing nothing is the safe choice.
        local orders = ui.get_orders()
        if p.clicked == k + 1 then
            -- clicked order moved up: up arrow -> send to top
            local id = orders[k].id
            move_order(k, 0)
            notify_filter('pin_top', id)
            warn_about_orders_sort()
        elseif p.clicked == k then
            -- clicked order moved down: down arrow -> send to bottom
            local id = orders[k + 1].id
            move_order(k + 1, '#')
            notify_filter('pin_bottom', id)
            warn_about_orders_sort()
        end
        return
    end

    -- Something other than an arrow click changed the list (e.g. a removal).
    if #after ~= #p.before then
        self.pending = nil
        return
    end
    for i = 1, #after do
        if after[i] ~= p.before[i] then
            self.pending = nil
            return
        end
    end

    -- No change yet; keep waiting a few frames for vanilla to react.
    p.frames = p.frames - 1
    if p.frames <= 0 then
        self.pending = nil
    end
end

function ShiftClickArrowsOverlay:render(dc)
    ShiftClickArrowsOverlay.super.render(self, dc)
    self:check_pending()
end

OVERLAY_WIDGETS = {
    arrows=ShiftClickArrowsOverlay,
}

if dfhack_flags.module then
    return
end

print(dfhack.script_help())
