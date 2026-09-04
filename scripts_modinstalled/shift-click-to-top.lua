-- Shift+click a work order's up arrow to move it to the top of the list.
--@ module = true
--[====[

shift-click-to-top
==================

Overlay for the Work Orders screen. Hold Shift and click the up arrow on a
work order to move that order straight to the top of the list (highest
priority). Shift+clicking the down arrow moves the order to the bottom.

The overlay is enabled automatically. To toggle it, use
``gui/control-panel`` (Overlays tab) or::

    overlay enable shift-click-to-top.arrows
    overlay disable shift-click-to-top.arrows

]====]

local overlay = require('plugins.overlay')
local ui = reqscript('internal/work-orders-qol/ui')

local mi = df.global.game.main_interface

-- How many frames to wait for vanilla to react to the click before giving up.
local PENDING_FRAMES = 5

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
    if mi.info.work_orders.entering_number or mi.info.work_orders.b_entering_number then
        return
    end
    if not dfhack.internal.getModifiers().shift then return end

    local idx = ui.get_order_under_mouse()
    if not idx then return end

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
        elseif p.clicked == k then
            -- clicked order moved down: down arrow -> send to bottom
            local id = orders[k + 1].id
            move_order(k + 1, '#')
            notify_filter('pin_bottom', id)
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
