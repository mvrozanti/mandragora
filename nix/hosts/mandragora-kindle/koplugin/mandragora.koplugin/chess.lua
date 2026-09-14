local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Rules = require("chess/rules")
local Engine = require("chess/engine")

local Screen = Device.screen

local PIECE_DIR = "/mnt/us/mandragora/chess/pieces"
local STATE_FILE = "/mnt/us/mandragora/state/chess.lua"

local GREY = Blitbuffer.COLOR_LIGHT_GRAY
local WHITE = Blitbuffer.COLOR_WHITE
local BLACK = Blitbuffer.COLOR_BLACK
local MID = Blitbuffer.COLOR_LIGHT_GRAY
local SOFT = Blitbuffer.COLOR_GRAY

local PIECE_FILE = {
    K = "wK", Q = "wQ", R = "wR", B = "wB", N = "wN", P = "wP",
    k = "bK", q = "bQ", r = "bR", b = "bB", n = "bN", p = "bP",
}

local ChessBoard = InputContainer:extend{
    human = "w",
    flipped = false,
    selected = nil,
    targets = nil,
    thinking = false,
    message = nil,
}

local image_cache = {}

local function pieceImage(code, size)
    local key = code .. "@" .. size
    if image_cache[key] ~= nil then return image_cache[key] or nil end
    local file = PIECE_DIR .. "/" .. PIECE_FILE[code] .. ".svg"
    local fh = io.open(file, "r")
    if not fh then
        image_cache[key] = false
        return nil
    end
    fh:close()
    local widget = ImageWidget:new{ file = file, width = size, height = size, alpha = true }
    image_cache[key] = widget
    return widget
end

function ChessBoard:layout()
    local w, h = Screen:getWidth(), Screen:getHeight()
    local margin = math.floor(w * 0.019)
    local gutter = math.floor(w * 0.036)
    local square = math.floor((w - gutter - margin) / 8)
    local board = square * 8
    local board_x = gutter
    local board_y = math.floor(h * 0.088)
    local button_h = math.floor(h * 0.065)
    local button_y = h - button_h - margin * 2
    return {
        w = w, h = h,
        margin = margin,
        gutter = gutter,
        square = square,
        board = board,
        board_x = board_x,
        board_y = board_y,
        files_y = board_y + board + math.floor(margin * 0.3),
        moves_y = board_y + board + math.floor(margin * 2.1),
        engine_y = button_y - math.floor(margin * 2.4),
        rule_y = button_y - math.floor(margin * 0.9),
        button_y = button_y,
        button_h = button_h,
    }
end

function ChessBoard:squareAt(x, y)
    local L = self.L
    local col = math.floor((x - L.board_x) / L.square)
    local row = math.floor((y - L.board_y) / L.square)
    if col < 0 or col > 7 or row < 0 or row > 7 then return nil end
    if self.flipped then row, col = 7 - row, 7 - col end
    return Rules.squareFromRowCol(row, col)
end

function ChessBoard:squareRect(square)
    local L = self.L
    local row, col = Rules.rowColOf(square)
    if not row then return nil end
    if self.flipped then row, col = 7 - row, 7 - col end
    return L.board_x + col * L.square, L.board_y + row * L.square
end

function ChessBoard:save()
    local fh = io.open(STATE_FILE, "w")
    if not fh then return end
    fh:write("return {\n")
    fh:write(string.format("  fen = %q,\n", Rules.toFEN(self.position)))
    fh:write(string.format("  human = %q,\n", self.human))
    fh:write(string.format("  flipped = %s,\n", tostring(self.flipped)))
    fh:write("  san = {\n")
    for _, entry in ipairs(self.san) do
        fh:write(string.format("    %q,\n", entry))
    end
    fh:write("  },\n}\n")
    fh:close()
end

function ChessBoard:restore()
    local chunk = loadfile(STATE_FILE)
    if not chunk then return false end
    local ok, saved = pcall(chunk)
    if not ok or type(saved) ~= "table" or not saved.fen then return false end
    local position = Rules.fromFEN(saved.fen)
    if not position then return false end
    self.position = position
    self.human = saved.human == "b" and "b" or "w"
    self.flipped = saved.flipped == true
    self.san = type(saved.san) == "table" and saved.san or {}
    self.history = { Rules.toFEN(position) }
    return true
end

function ChessBoard:newGame()
    self.position = Rules.startPosition()
    self.san = {}
    self.history = { Rules.toFEN(self.position) }
    self.selected = nil
    self.targets = nil
    self.message = nil
end

function ChessBoard:init()
    self.L = self:layout()
    self.cfg = Engine.readConfig()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.L.w, h = self.L.h }
    self.covers_fullscreen = true

    if not self:restore() then self:newGame() end

    if Device:isTouchDevice() then
        self.ges_events = {
            Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
            DoubleTap = { GestureRange:new{ ges = "double_tap", range = self.dimen } },
            Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        }
    end
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
end

function ChessBoard:statusLine()
    if self.message then return self.message end
    if self.thinking then return "thinking…" end
    local state = Rules.status(self.position)
    if state == "checkmate" then
        return (Rules.sideToMove(self.position) == self.human) and "checkmate — you lose"
            or "checkmate — you win"
    end
    if state == "stalemate" then return "stalemate" end
    if state == "draw-fifty" then return "draw — fifty moves" end
    if state == "draw-material" then return "draw — insufficient material" end
    if state == "draw-repetition" then return "draw — repetition" end
    local turn = (Rules.sideToMove(self.position) == self.human) and "your move" or "engine to move"
    if state == "check" then return turn .. " — check" end
    return turn
end

function ChessBoard:buttons()
    local L = self.L
    local labels = { "new", "undo", "flip", "close" }
    local span = L.w - L.margin * 2
    local width = math.floor(span / #labels)
    local out = {}
    for i, label in ipairs(labels) do
        out[i] = {
            label = label,
            x = L.margin + (i - 1) * width,
            y = L.button_y,
            w = width,
            h = L.button_h,
        }
    end
    return out
end

function ChessBoard:paintTo(bb, x, y)
    local L = self.L
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, L.w, L.h, WHITE)

    local head = TextWidget:new{
        text = self:statusLine(),
        face = Font:getFace("tfont", 42),
    }
    head:paintTo(bb, x + L.board_x, y + math.floor(L.margin * 0.9))
    head:free()

    for row = 0, 7 do
        for col = 0, 7 do
            if (row + col) % 2 == 1 then
                bb:paintRect(x + L.board_x + col * L.square, y + L.board_y + row * L.square,
                    L.square, L.square, GREY)
            end
        end
    end
    bb:paintBorder(x + L.board_x, y + L.board_y, L.board, L.board, 2, BLACK)

    local coord_face = Font:getFace("infofont", 24)
    for i = 0, 7 do
        local rank = tostring(self.flipped and i + 1 or 8 - i)
        local rw = TextWidget:new{ text = rank, face = coord_face, fgcolor = SOFT }
        local rs = rw:getSize()
        rw:paintTo(bb, x + math.floor((L.gutter - rs.w) / 2),
                       y + L.board_y + i * L.square + math.floor((L.square - rs.h) / 2))
        rw:free()

        local file = string.char(string.byte("a") + (self.flipped and 7 - i or i))
        local fw = TextWidget:new{ text = file, face = coord_face, fgcolor = SOFT }
        local fs = fw:getSize()
        fw:paintTo(bb, x + L.board_x + i * L.square + math.floor((L.square - fs.w) / 2),
                       y + L.files_y)
        fw:free()
    end

    if self.selected then
        local sx, sy = self:squareRect(self.selected)
        if sx then bb:paintBorder(x + sx, y + sy, L.square, L.square, 6, BLACK) end
    end

    if self.targets then
        local dot = math.floor(L.square * 0.15)
        for _, move in ipairs(self.targets) do
            local sx, sy = self:squareRect(move.to)
            if sx then
                bb:paintCircle(x + sx + math.floor(L.square / 2),
                               y + sy + math.floor(L.square / 2), dot, BLACK)
            end
        end
    end

    local inset = math.floor(L.square * 0.06)
    local size = L.square - inset * 2
    for row = 0, 7 do
        for col = 0, 7 do
            local br, bc = row, col
            if self.flipped then br, bc = 7 - row, 7 - col end
            local square = Rules.squareFromRowCol(br, bc)
            local code = square and Rules.pieceAt(self.position, square)
            if code then
                local widget = pieceImage(code, size)
                if widget then
                    widget:paintTo(bb, x + L.board_x + col * L.square + inset,
                                       y + L.board_y + row * L.square + inset)
                end
            end
        end
    end

    local moves_face = Font:getFace("infofont", 28)
    local shown = {}
    local start_at = math.max(1, #self.san - 7)
    for i = start_at, #self.san do
        local n = math.floor((i + 1) / 2)
        if i % 2 == 1 then
            shown[#shown + 1] = n .. ". " .. self.san[i]
        else
            shown[#shown] = (shown[#shown] or (n .. ".")) .. " " .. self.san[i]
        end
    end
    if #shown == 0 then
        local empty = TextWidget:new{
            text = "tap a piece to see where it can go",
            face = moves_face, fgcolor = SOFT,
        }
        empty:paintTo(bb, x + L.board_x, y + L.moves_y)
        empty:free()
    else
        local cursor = x + L.board_x
        for i = 1, #shown do
            local entry = TextWidget:new{ text = shown[i], face = moves_face, fgcolor = SOFT }
            local es = entry:getSize()
            if cursor + es.w > x + L.w - L.margin then break end
            entry:paintTo(bb, cursor, y + L.moves_y)
            cursor = cursor + es.w + 26
            entry:free()
        end
    end

    local sub = TextWidget:new{
        text = Engine.describe(self.cfg),
        face = Font:getFace("infofont", 22), fgcolor = SOFT,
    }
    sub:paintTo(bb, x + L.board_x, y + L.engine_y)
    sub:free()

    local buttons = self:buttons()
    local first, last = buttons[1], buttons[#buttons]
    local strip_w = last.x + last.w - first.x
    bb:paintBorder(x + first.x, y + first.y, strip_w, first.h, 3, BLACK)
    for i, button in ipairs(buttons) do
        if i > 1 then
            bb:paintRect(x + button.x, y + button.y, 2, button.h, BLACK)
        end
        local label = TextWidget:new{ text = button.label, face = Font:getFace("tfont", 38) }
        local ls = label:getSize()
        label:paintTo(bb, x + button.x + math.floor((button.w - ls.w) / 2),
                          y + button.y + math.floor((button.h - ls.h) / 2))
        label:free()
    end
end

function ChessBoard:repaint(mode)
    UIManager:setDirty(self, function() return mode or "ui", self.dimen end)
end

function ChessBoard:playMove(move)
    self.san[#self.san + 1] = Rules.toSAN(self.position, move)
    self.position = Rules.apply(self.position, move)
    self.history[#self.history + 1] = Rules.toFEN(self.position)
    self.selected = nil
    self.targets = nil
    self:save()
end

function ChessBoard:engineTurn()
    if Rules.sideToMove(self.position) == self.human then return end
    local state = Rules.status(self.position)
    if state == "checkmate" or state == "stalemate" or state:match("^draw") then return end

    self.thinking = true
    self.message = nil
    self:repaint()

    UIManager:scheduleIn(0.05, function()
        local uci, err = Engine.bestMove(self.cfg, Rules.toFEN(self.position))
        self.thinking = false
        if not uci then
            self.message = "engine: " .. tostring(err)
            logger.warn("mandragora: chess: engine", tostring(err))
            self:repaint()
            return
        end
        local move = Rules.fromUCI(self.position, uci)
        if not move then
            self.message = "engine sent " .. uci
            self:repaint()
            return
        end
        self:playMove(move)
        self:repaint()
    end)
end

function ChessBoard:onTap(_, ges)
    local px, py = ges.pos.x, ges.pos.y

    for _, button in ipairs(self:buttons()) do
        if px >= button.x and px < button.x + button.w and py >= button.y then
            return self:onButton(button.label)
        end
    end

    if self.thinking then return true end
    if Rules.sideToMove(self.position) ~= self.human then return true end

    local square = self:squareAt(px, py)
    if not square then return true end

    if self.targets then
        for _, move in ipairs(self.targets) do
            if move.to == square or Rules.squareName(move.to) == Rules.squareName(square) then
                if move.promotion and move.promotion ~= "q" and move.promotion ~= "Q" then
                    move = self:queenPromotion(square) or move
                end
                self:playMove(move)
                self.message = nil
                self:repaint()
                self:engineTurn()
                return true
            end
        end
    end

    local code = Rules.pieceAt(self.position, square)
    if code then
        local white = code:match("%u") ~= nil
        if (white and self.human == "w") or (not white and self.human == "b") then
            self.selected = square
            self.targets = Rules.legalMovesFrom(self.position, square)
            self.message = nil
            self:repaint()
            return true
        end
    end

    self.selected = nil
    self.targets = nil
    self:repaint()
    return true
end

function ChessBoard:queenPromotion(square)
    for _, move in ipairs(self.targets or {}) do
        local promo = move.promotion and tostring(move.promotion):lower()
        if move.to == square and promo == "q" then return move end
    end
    return nil
end

function ChessBoard:onButton(label)
    if label == "close" then return self:onClose() end
    if label == "flip" then
        self.flipped = not self.flipped
        self:save()
        self:repaint("full")
        return true
    end
    if label == "new" then
        self:newGame()
        self:save()
        self:repaint("full")
        if self.human == "b" then self:engineTurn() end
        return true
    end
    if label == "undo" then
        if #self.san < 2 or #self.history < 3 then return true end
        table.remove(self.san)
        table.remove(self.san)
        table.remove(self.history)
        table.remove(self.history)
        self.position = Rules.fromFEN(self.history[#self.history]) or self.position
        self.selected = nil
        self.targets = nil
        self.message = nil
        self:save()
        self:repaint("full")
        return true
    end
    return true
end

function ChessBoard:onDoubleTap()
    return self:onClose()
end

function ChessBoard:onSwipe(_, ges)
    if ges.direction == "south" or ges.direction == "north" then
        return self:onClose()
    end
    return true
end

function ChessBoard:onClose()
    self:save()
    UIManager:close(self)
    return true
end

function ChessBoard:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

function ChessBoard:onShow()
    self:repaint("full")
    return true
end

function ChessBoard.open()
    local board = ChessBoard:new{}
    UIManager:show(board)
    if Rules.sideToMove(board.position) ~= board.human then board:engineTurn() end
    return board
end

return ChessBoard
