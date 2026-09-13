local Rules = {}

local WHITE, BLACK = 1, 2
local EMPTY = 0
local PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING = 1, 2, 3, 4, 5, 6
local BLACK_OFFSET = 8

local WHITE_PAWN, WHITE_KNIGHT, WHITE_BISHOP = 1, 2, 3
local WHITE_ROOK, WHITE_QUEEN, WHITE_KING = 4, 5, 6
local BLACK_PAWN, BLACK_KNIGHT, BLACK_BISHOP = 9, 10, 11
local BLACK_ROOK, BLACK_QUEEN, BLACK_KING = 12, 13, 14

local CASTLE_WK, CASTLE_WQ, CASTLE_BK, CASTLE_BQ = 1, 2, 4, 8

local FLAG_NORMAL = 0
local FLAG_DOUBLE_PUSH = 1
local FLAG_EN_PASSANT = 2
local FLAG_CASTLE_KING = 3
local FLAG_CASTLE_QUEEN = 4

local FILE_CHARS = "abcdefgh"

local STARTING_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

local TYPE_OF = {}
local IS_COLOR = { {}, {} }
local PIECE_OF = { {}, {} }

for code = 0, 14 do
    TYPE_OF[code] = 0
    IS_COLOR[WHITE][code] = false
    IS_COLOR[BLACK][code] = false
end

for pieceType = PAWN, KING do
    TYPE_OF[pieceType] = pieceType
    TYPE_OF[pieceType + BLACK_OFFSET] = pieceType
    IS_COLOR[WHITE][pieceType] = true
    IS_COLOR[BLACK][pieceType + BLACK_OFFSET] = true
    PIECE_OF[WHITE][pieceType] = pieceType
    PIECE_OF[BLACK][pieceType] = pieceType + BLACK_OFFSET
end

local PIECE_FROM_FEN = {
    P = WHITE_PAWN, N = WHITE_KNIGHT, B = WHITE_BISHOP,
    R = WHITE_ROOK, Q = WHITE_QUEEN, K = WHITE_KING,
    p = BLACK_PAWN, n = BLACK_KNIGHT, b = BLACK_BISHOP,
    r = BLACK_ROOK, q = BLACK_QUEEN, k = BLACK_KING,
}

local FEN_FROM_PIECE = {}
for letter, code in pairs(PIECE_FROM_FEN) do FEN_FROM_PIECE[code] = letter end

local PROMOTION_FROM_LETTER = { n = KNIGHT, b = BISHOP, r = ROOK, q = QUEEN }
local CASTLE_BIT_FROM_FEN = { K = CASTLE_WK, Q = CASTLE_WQ, k = CASTLE_BK, q = CASTLE_BQ }

local FILE_OF, RANK_OF, SQUARE_NAME, LIGHT_SQUARE = {}, {}, {}, {}
local SQUARE_FROM_NAME = {}

for square = 0, 63 do
    local file = square % 8
    local rank = (square - file) / 8
    FILE_OF[square] = file
    RANK_OF[square] = rank
    LIGHT_SQUARE[square] = ((file + rank) % 2) == 1
    local name = FILE_CHARS:sub(file + 1, file + 1) .. tostring(rank + 1)
    SQUARE_NAME[square] = name
    SQUARE_FROM_NAME[name] = square
end

local AND16 = {}
local CASTLE_BITS = { 1, 2, 4, 8 }
for left = 0, 15 do
    AND16[left] = {}
    for right = 0, 15 do
        local combined = 0
        for index = 1, 4 do
            local bit = CASTLE_BITS[index]
            if left % (bit + bit) >= bit and right % (bit + bit) >= bit then
                combined = combined + bit
            end
        end
        AND16[left][right] = combined
    end
end

local CASTLE_MASK = {}
for square = 0, 63 do CASTLE_MASK[square] = 15 end
CASTLE_MASK[0] = 15 - CASTLE_WQ
CASTLE_MASK[4] = 15 - CASTLE_WK - CASTLE_WQ
CASTLE_MASK[7] = 15 - CASTLE_WK
CASTLE_MASK[56] = 15 - CASTLE_BQ
CASTLE_MASK[60] = 15 - CASTLE_BK - CASTLE_BQ
CASTLE_MASK[63] = 15 - CASTLE_BK

local DIRECTIONS = {
    { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 },
    { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 },
}
local ORTHOGONAL_FIRST, ORTHOGONAL_LAST = 1, 4
local DIAGONAL_FIRST, DIAGONAL_LAST = 5, 8

local KNIGHT_DELTAS = {
    { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 },
    { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 },
}

local RAYS, KNIGHT_MOVES, KING_MOVES = {}, {}, {}
local PAWN_TARGETS = { {}, {} }
local PAWN_ATTACKERS = { {}, {} }

local function onBoard(file, rank)
    return file >= 0 and file <= 7 and rank >= 0 and rank <= 7
end

for square = 0, 63 do
    local baseFile, baseRank = FILE_OF[square], RANK_OF[square]

    local rays = {}
    for direction = 1, 8 do
        local step = DIRECTIONS[direction]
        local ray = {}
        local file, rank = baseFile + step[1], baseRank + step[2]
        while onBoard(file, rank) do
            ray[#ray + 1] = rank * 8 + file
            file = file + step[1]
            rank = rank + step[2]
        end
        rays[direction] = ray
    end
    RAYS[square] = rays

    local jumps = {}
    for index = 1, 8 do
        local delta = KNIGHT_DELTAS[index]
        local file, rank = baseFile + delta[1], baseRank + delta[2]
        if onBoard(file, rank) then jumps[#jumps + 1] = rank * 8 + file end
    end
    KNIGHT_MOVES[square] = jumps

    local steps = {}
    for index = 1, 8 do
        local delta = DIRECTIONS[index]
        local file, rank = baseFile + delta[1], baseRank + delta[2]
        if onBoard(file, rank) then steps[#steps + 1] = rank * 8 + file end
    end
    KING_MOVES[square] = steps

    for color = WHITE, BLACK do
        local forward = (color == WHITE) and 1 or -1
        local targets = {}
        local rank = baseRank + forward
        if onBoard(baseFile - 1, rank) then targets[#targets + 1] = rank * 8 + baseFile - 1 end
        if onBoard(baseFile + 1, rank) then targets[#targets + 1] = rank * 8 + baseFile + 1 end
        PAWN_TARGETS[color][square] = targets
    end
end

for color = WHITE, BLACK do
    for square = 0, 63 do PAWN_ATTACKERS[color][square] = {} end
    for square = 0, 63 do
        local targets = PAWN_TARGETS[color][square]
        for index = 1, #targets do
            local attackers = PAWN_ATTACKERS[color][targets[index]]
            attackers[#attackers + 1] = square
        end
    end
end

local function hasCastleRight(rights, bit)
    return rights % (bit + bit) >= bit
end

local function encodeMove(from, to, promotion, flag)
    return from + to * 64 + promotion * 4096 + flag * 32768
end

local function decodeMove(code)
    local from = code % 64
    local rest = (code - from) / 64
    local to = rest % 64
    rest = (rest - to) / 64
    local promotion = rest % 8
    return from, to, promotion, (rest - promotion) / 8
end

local function isAttacked(board, square, byColor)
    local attacker = PIECE_OF[byColor]

    local pawn = attacker[PAWN]
    local origins = PAWN_ATTACKERS[byColor][square]
    for index = 1, #origins do
        if board[origins[index]] == pawn then return true end
    end

    local knight = attacker[KNIGHT]
    local jumps = KNIGHT_MOVES[square]
    for index = 1, #jumps do
        if board[jumps[index]] == knight then return true end
    end

    local king = attacker[KING]
    local steps = KING_MOVES[square]
    for index = 1, #steps do
        if board[steps[index]] == king then return true end
    end

    local rays = RAYS[square]
    local queen = attacker[QUEEN]

    local rook = attacker[ROOK]
    for direction = ORTHOGONAL_FIRST, ORTHOGONAL_LAST do
        local ray = rays[direction]
        for index = 1, #ray do
            local piece = board[ray[index]]
            if piece ~= EMPTY then
                if piece == rook or piece == queen then return true end
                break
            end
        end
    end

    local bishop = attacker[BISHOP]
    for direction = DIAGONAL_FIRST, DIAGONAL_LAST do
        local ray = rays[direction]
        for index = 1, #ray do
            local piece = board[ray[index]]
            if piece ~= EMPTY then
                if piece == bishop or piece == queen then return true end
                break
            end
        end
    end

    return false
end

local function generatePseudoMoves(position, out)
    local board = position.board
    local side = position.side
    local mine = IS_COLOR[side]
    local theirs = IS_COLOR[3 - side]
    local forward = (side == WHITE) and 8 or -8
    local homeRank = (side == WHITE) and 1 or 6
    local promotionRank = (side == WHITE) and 6 or 1
    local enPassantSquare = position.ep
    local count = 0

    for square = 0, 63 do
        local piece = board[square]
        if mine[piece] then
            local pieceType = TYPE_OF[piece]

            if pieceType == PAWN then
                local single = square + forward
                if board[single] == EMPTY then
                    if RANK_OF[square] == promotionRank then
                        count = count + 1; out[count] = encodeMove(square, single, QUEEN, FLAG_NORMAL)
                        count = count + 1; out[count] = encodeMove(square, single, ROOK, FLAG_NORMAL)
                        count = count + 1; out[count] = encodeMove(square, single, BISHOP, FLAG_NORMAL)
                        count = count + 1; out[count] = encodeMove(square, single, KNIGHT, FLAG_NORMAL)
                    else
                        count = count + 1; out[count] = encodeMove(square, single, 0, FLAG_NORMAL)
                        if RANK_OF[square] == homeRank then
                            local double = single + forward
                            if board[double] == EMPTY then
                                count = count + 1
                                out[count] = encodeMove(square, double, 0, FLAG_DOUBLE_PUSH)
                            end
                        end
                    end
                end
                local targets = PAWN_TARGETS[side][square]
                for index = 1, #targets do
                    local target = targets[index]
                    local victim = board[target]
                    if theirs[victim] then
                        if RANK_OF[square] == promotionRank then
                            count = count + 1; out[count] = encodeMove(square, target, QUEEN, FLAG_NORMAL)
                            count = count + 1; out[count] = encodeMove(square, target, ROOK, FLAG_NORMAL)
                            count = count + 1; out[count] = encodeMove(square, target, BISHOP, FLAG_NORMAL)
                            count = count + 1; out[count] = encodeMove(square, target, KNIGHT, FLAG_NORMAL)
                        else
                            count = count + 1; out[count] = encodeMove(square, target, 0, FLAG_NORMAL)
                        end
                    elseif victim == EMPTY and target == enPassantSquare then
                        count = count + 1
                        out[count] = encodeMove(square, target, 0, FLAG_EN_PASSANT)
                    end
                end

            elseif pieceType == KNIGHT or pieceType == KING then
                local targets = (pieceType == KNIGHT) and KNIGHT_MOVES[square] or KING_MOVES[square]
                for index = 1, #targets do
                    local target = targets[index]
                    if not mine[board[target]] then
                        count = count + 1
                        out[count] = encodeMove(square, target, 0, FLAG_NORMAL)
                    end
                end

            else
                local first, last
                if pieceType == ROOK then
                    first, last = ORTHOGONAL_FIRST, ORTHOGONAL_LAST
                elseif pieceType == BISHOP then
                    first, last = DIAGONAL_FIRST, DIAGONAL_LAST
                else
                    first, last = ORTHOGONAL_FIRST, DIAGONAL_LAST
                end
                local rays = RAYS[square]
                for direction = first, last do
                    local ray = rays[direction]
                    for index = 1, #ray do
                        local target = ray[index]
                        local victim = board[target]
                        if victim == EMPTY then
                            count = count + 1
                            out[count] = encodeMove(square, target, 0, FLAG_NORMAL)
                        else
                            if theirs[victim] then
                                count = count + 1
                                out[count] = encodeMove(square, target, 0, FLAG_NORMAL)
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    local rights = position.castling
    if side == WHITE then
        if board[4] == WHITE_KING then
            if hasCastleRight(rights, CASTLE_WK)
                and board[5] == EMPTY and board[6] == EMPTY and board[7] == WHITE_ROOK
                and not isAttacked(board, 4, BLACK)
                and not isAttacked(board, 5, BLACK)
                and not isAttacked(board, 6, BLACK) then
                count = count + 1
                out[count] = encodeMove(4, 6, 0, FLAG_CASTLE_KING)
            end
            if hasCastleRight(rights, CASTLE_WQ)
                and board[3] == EMPTY and board[2] == EMPTY and board[1] == EMPTY and board[0] == WHITE_ROOK
                and not isAttacked(board, 4, BLACK)
                and not isAttacked(board, 3, BLACK)
                and not isAttacked(board, 2, BLACK) then
                count = count + 1
                out[count] = encodeMove(4, 2, 0, FLAG_CASTLE_QUEEN)
            end
        end
    else
        if board[60] == BLACK_KING then
            if hasCastleRight(rights, CASTLE_BK)
                and board[61] == EMPTY and board[62] == EMPTY and board[63] == BLACK_ROOK
                and not isAttacked(board, 60, WHITE)
                and not isAttacked(board, 61, WHITE)
                and not isAttacked(board, 62, WHITE) then
                count = count + 1
                out[count] = encodeMove(60, 62, 0, FLAG_CASTLE_KING)
            end
            if hasCastleRight(rights, CASTLE_BQ)
                and board[59] == EMPTY and board[58] == EMPTY and board[57] == EMPTY and board[56] == BLACK_ROOK
                and not isAttacked(board, 60, WHITE)
                and not isAttacked(board, 59, WHITE)
                and not isAttacked(board, 58, WHITE) then
                count = count + 1
                out[count] = encodeMove(60, 58, 0, FLAG_CASTLE_QUEEN)
            end
        end
    end

    return count
end

local function makeMove(position, code)
    local from, to, promotion, flag = decodeMove(code)
    local board = position.board
    local side = position.side
    local moving = board[from]
    local previousEnPassant = position.ep
    local previousCastling = position.castling
    local previousHalfmove = position.halfmove

    local captureSquare = to
    if flag == FLAG_EN_PASSANT then
        captureSquare = (side == WHITE) and (to - 8) or (to + 8)
    end
    local captured = board[captureSquare]

    board[captureSquare] = EMPTY
    board[from] = EMPTY
    if promotion ~= 0 then
        board[to] = PIECE_OF[side][promotion]
    else
        board[to] = moving
    end

    if flag == FLAG_CASTLE_KING then
        board[to - 1] = board[to + 1]
        board[to + 1] = EMPTY
    elseif flag == FLAG_CASTLE_QUEEN then
        board[to + 1] = board[to - 2]
        board[to - 2] = EMPTY
    end

    local movingType = TYPE_OF[moving]
    if movingType == KING then position.kingSquare[side] = to end

    position.castling = AND16[AND16[previousCastling][CASTLE_MASK[from]]][CASTLE_MASK[to]]

    if flag == FLAG_DOUBLE_PUSH then
        position.ep = (from + to) / 2
    else
        position.ep = nil
    end

    if movingType == PAWN or captured ~= EMPTY then
        position.halfmove = 0
    else
        position.halfmove = previousHalfmove + 1
    end

    if side == BLACK then position.fullmove = position.fullmove + 1 end
    position.side = 3 - side

    return captured, captureSquare, previousEnPassant, previousCastling, previousHalfmove
end

local function unmakeMove(position, code, captured, captureSquare, previousEnPassant, previousCastling, previousHalfmove)
    local from, to, promotion, flag = decodeMove(code)
    local board = position.board
    local side = 3 - position.side

    if promotion ~= 0 then
        board[from] = PIECE_OF[side][PAWN]
    else
        board[from] = board[to]
    end
    board[to] = EMPTY
    board[captureSquare] = captured

    if flag == FLAG_CASTLE_KING then
        board[to + 1] = board[to - 1]
        board[to - 1] = EMPTY
    elseif flag == FLAG_CASTLE_QUEEN then
        board[to - 2] = board[to + 1]
        board[to + 1] = EMPTY
    end

    if TYPE_OF[board[from]] == KING then position.kingSquare[side] = from end

    position.ep = previousEnPassant
    position.castling = previousCastling
    position.halfmove = previousHalfmove
    if side == BLACK then position.fullmove = position.fullmove - 1 end
    position.side = side
end

local function leavesKingSafe(position, code)
    local captured, captureSquare, previousEnPassant, previousCastling, previousHalfmove =
        makeMove(position, code)
    local mover = 3 - position.side
    local safe = not isAttacked(position.board, position.kingSquare[mover], position.side)
    unmakeMove(position, code, captured, captureSquare, previousEnPassant, previousCastling, previousHalfmove)
    return safe
end

local function clonePosition(position)
    local source = position.board
    local board = {}
    for square = 0, 63 do board[square] = source[square] end
    return {
        board = board,
        side = position.side,
        castling = position.castling,
        ep = position.ep,
        halfmove = position.halfmove,
        fullmove = position.fullmove,
        kingSquare = { position.kingSquare[WHITE], position.kingSquare[BLACK] },
        history = position.history or {},
    }
end

local function legalCodes(position)
    local work = clonePosition(position)
    local buffer = {}
    local generated = generatePseudoMoves(work, buffer)
    local codes = {}
    local kept = 0
    for index = 1, generated do
        local code = buffer[index]
        if leavesKingSafe(work, code) then
            kept = kept + 1
            codes[kept] = code
        end
    end
    return codes
end

local function toSquareIndex(value)
    if type(value) == "number" then
        if value < 0 or value > 63 or value % 1 ~= 0 then return nil end
        return value
    end
    if type(value) == "string" then return SQUARE_FROM_NAME[value] end
    return nil
end

local function describeMove(position, code)
    local from, to, promotion, flag = decodeMove(code)
    local board = position.board
    local captureSquare = to
    if flag == FLAG_EN_PASSANT then
        captureSquare = (position.side == WHITE) and (to - 8) or (to + 8)
    end
    local captured = board[captureSquare]

    local move = {
        from = from,
        to = to,
        fromName = SQUARE_NAME[from],
        toName = SQUARE_NAME[to],
        piece = FEN_FROM_PIECE[board[from]],
        code = code,
    }
    if captured ~= EMPTY then
        move.captured = FEN_FROM_PIECE[captured]
        move.captureSquare = captureSquare
    end
    if promotion ~= 0 then
        move.promotion = FEN_FROM_PIECE[promotion + BLACK_OFFSET]
    end
    if flag == FLAG_EN_PASSANT then
        move.enPassant = true
    elseif flag == FLAG_DOUBLE_PUSH then
        move.doublePush = true
    elseif flag == FLAG_CASTLE_KING then
        move.castle = "k"
        move.rookFrom = to + 1
        move.rookTo = to - 1
    elseif flag == FLAG_CASTLE_QUEEN then
        move.castle = "q"
        move.rookFrom = to - 2
        move.rookTo = to + 1
    end
    return move
end

local function parseUCI(text)
    local fromName, toName, promotionLetter = text:match("^([a-h][1-8])([a-h][1-8])([qrbnQRBN]?)$")
    if not fromName then return nil end
    local promotion = 0
    if promotionLetter ~= "" then
        promotion = PROMOTION_FROM_LETTER[promotionLetter:lower()]
    end
    return SQUARE_FROM_NAME[fromName], SQUARE_FROM_NAME[toName], promotion
end

local function resolveCode(position, move, codes)
    codes = codes or legalCodes(position)
    local wantFrom, wantTo, wantPromotion

    if type(move) == "string" then
        wantFrom, wantTo, wantPromotion = parseUCI(move)
        if not wantFrom then return nil, "malformed uci move: " .. move end
    elseif type(move) == "table" then
        wantFrom = toSquareIndex(move.from)
        wantTo = toSquareIndex(move.to)
        if not wantFrom or not wantTo then return nil, "move needs from and to squares" end
        wantPromotion = 0
        if move.promotion then
            wantPromotion = PROMOTION_FROM_LETTER[tostring(move.promotion):lower()]
            if not wantPromotion then return nil, "unknown promotion piece" end
        end
    else
        return nil, "move must be a table or a uci string"
    end

    local promotionPending = false
    for index = 1, #codes do
        local code = codes[index]
        local from, to, promotion = decodeMove(code)
        if from == wantFrom and to == wantTo then
            if promotion == wantPromotion then return code end
            if promotion ~= 0 and wantPromotion == 0 then promotionPending = true end
        end
    end
    if promotionPending then return nil, "promotion piece required" end
    return nil, "illegal move"
end

local function placementString(position)
    local board = position.board
    local rows = {}
    for rank = 7, 0, -1 do
        local cells = {}
        local run = 0
        for file = 0, 7 do
            local piece = board[rank * 8 + file]
            if piece == EMPTY then
                run = run + 1
            else
                if run > 0 then
                    cells[#cells + 1] = tostring(run)
                    run = 0
                end
                cells[#cells + 1] = FEN_FROM_PIECE[piece]
            end
        end
        if run > 0 then cells[#cells + 1] = tostring(run) end
        rows[#rows + 1] = table.concat(cells)
    end
    return table.concat(rows, "/")
end

local function castlingString(rights)
    local text = ""
    if hasCastleRight(rights, CASTLE_WK) then text = text .. "K" end
    if hasCastleRight(rights, CASTLE_WQ) then text = text .. "Q" end
    if hasCastleRight(rights, CASTLE_BK) then text = text .. "k" end
    if hasCastleRight(rights, CASTLE_BQ) then text = text .. "q" end
    if text == "" then return "-" end
    return text
end

local function enPassantIsPlayable(position)
    if not position.ep then return false end
    local codes = legalCodes(position)
    for index = 1, #codes do
        local _, _, _, flag = decodeMove(codes[index])
        if flag == FLAG_EN_PASSANT then return true end
    end
    return false
end

local function hasInsufficientMaterial(position)
    local board = position.board
    local minors, knights = 0, 0
    local darkBishop, lightBishop = false, false
    for square = 0, 63 do
        local piece = board[square]
        if piece ~= EMPTY then
            local pieceType = TYPE_OF[piece]
            if pieceType == PAWN or pieceType == ROOK or pieceType == QUEEN then
                return false
            elseif pieceType == KNIGHT then
                knights = knights + 1
                minors = minors + 1
            elseif pieceType == BISHOP then
                minors = minors + 1
                if LIGHT_SQUARE[square] then lightBishop = true else darkBishop = true end
            end
        end
    end
    if minors <= 1 then return true end
    if knights == 0 and not (darkBishop and lightBishop) then return true end
    return false
end

function Rules.fromFEN(fen)
    if type(fen) ~= "string" then return nil, "fen must be a string" end

    local fields = {}
    for token in fen:gmatch("%S+") do fields[#fields + 1] = token end
    if #fields < 4 then return nil, "fen needs at least 4 fields" end
    if #fields > 6 then return nil, "fen has more than 6 fields" end

    local placement, activeField = fields[1], fields[2]
    local castlingField, enPassantField = fields[3], fields[4]
    local halfmoveField, fullmoveField = fields[5] or "0", fields[6] or "1"

    local _, separators = placement:gsub("/", "")
    if separators ~= 7 then return nil, "fen placement needs 8 ranks" end

    local ranks = {}
    for part in placement:gmatch("[^/]+") do ranks[#ranks + 1] = part end
    if #ranks ~= 8 then return nil, "fen placement has an empty rank" end

    local board = {}
    for square = 0, 63 do board[square] = EMPTY end
    local kingSquare = {}
    local kingCount = { 0, 0 }

    for index = 1, 8 do
        local text = ranks[index]
        local rank = 8 - index
        local file = 0
        for offset = 1, #text do
            local character = text:sub(offset, offset)
            local skip = character:match("^%d$") and tonumber(character) or nil
            if skip then
                if skip < 1 then return nil, "zero skip count in fen placement" end
                file = file + skip
            else
                local piece = PIECE_FROM_FEN[character]
                if not piece then
                    return nil, "unknown symbol '" .. character .. "' in fen placement"
                end
                if file > 7 then return nil, "rank " .. tostring(rank + 1) .. " overflows" end
                local square = rank * 8 + file
                board[square] = piece
                local pieceType = TYPE_OF[piece]
                if pieceType == PAWN and (rank == 0 or rank == 7) then
                    return nil, "pawn on a back rank"
                end
                if pieceType == KING then
                    local color = IS_COLOR[WHITE][piece] and WHITE or BLACK
                    kingCount[color] = kingCount[color] + 1
                    kingSquare[color] = square
                end
                file = file + 1
            end
        end
        if file ~= 8 then
            return nil, "rank " .. tostring(rank + 1) .. " does not cover 8 squares"
        end
    end

    if kingCount[WHITE] ~= 1 then return nil, "white needs exactly one king" end
    if kingCount[BLACK] ~= 1 then return nil, "black needs exactly one king" end

    local side
    if activeField == "w" then
        side = WHITE
    elseif activeField == "b" then
        side = BLACK
    else
        return nil, "side to move must be w or b"
    end

    local rights = 0
    if castlingField ~= "-" then
        local seen = {}
        for offset = 1, #castlingField do
            local character = castlingField:sub(offset, offset)
            local bit = CASTLE_BIT_FROM_FEN[character]
            if not bit or seen[character] then return nil, "bad castling field" end
            seen[character] = true
            rights = rights + bit
        end
    end
    if board[4] ~= WHITE_KING then rights = AND16[rights][15 - CASTLE_WK - CASTLE_WQ] end
    if board[7] ~= WHITE_ROOK then rights = AND16[rights][15 - CASTLE_WK] end
    if board[0] ~= WHITE_ROOK then rights = AND16[rights][15 - CASTLE_WQ] end
    if board[60] ~= BLACK_KING then rights = AND16[rights][15 - CASTLE_BK - CASTLE_BQ] end
    if board[63] ~= BLACK_ROOK then rights = AND16[rights][15 - CASTLE_BK] end
    if board[56] ~= BLACK_ROOK then rights = AND16[rights][15 - CASTLE_BQ] end

    local enPassant = nil
    if enPassantField ~= "-" then
        enPassant = SQUARE_FROM_NAME[enPassantField]
        if not enPassant then return nil, "bad en passant square" end
        local expectedRank = (side == WHITE) and 5 or 2
        if RANK_OF[enPassant] ~= expectedRank then
            return nil, "en passant square is on the wrong rank"
        end
        local pushedFrom = (side == WHITE) and (enPassant + 8) or (enPassant - 8)
        local pushedTo = (side == WHITE) and (enPassant - 8) or (enPassant + 8)
        if board[enPassant] ~= EMPTY or board[pushedFrom] ~= EMPTY
            or board[pushedTo] ~= PIECE_OF[3 - side][PAWN] then
            return nil, "en passant square does not match the board"
        end
    end

    local halfmove = tonumber(halfmoveField)
    if not halfmove or halfmove < 0 or halfmove % 1 ~= 0 then
        return nil, "bad halfmove clock"
    end
    local fullmove = tonumber(fullmoveField)
    if not fullmove or fullmove < 1 or fullmove % 1 ~= 0 then
        return nil, "bad fullmove number"
    end

    if isAttacked(board, kingSquare[3 - side], side) then
        return nil, "the side not to move is in check"
    end

    return {
        board = board,
        side = side,
        castling = rights,
        ep = enPassant,
        halfmove = halfmove,
        fullmove = fullmove,
        kingSquare = kingSquare,
        history = {},
    }
end

function Rules.toFEN(position)
    return placementString(position)
        .. " " .. ((position.side == WHITE) and "w" or "b")
        .. " " .. castlingString(position.castling)
        .. " " .. (position.ep and SQUARE_NAME[position.ep] or "-")
        .. " " .. tostring(position.halfmove)
        .. " " .. tostring(position.fullmove)
end

function Rules.startPosition()
    return Rules.fromFEN(STARTING_FEN)
end

function Rules.copy(position)
    return clonePosition(position)
end

function Rules.sideToMove(position)
    return (position.side == WHITE) and "w" or "b"
end

function Rules.pieceAt(position, square)
    local index = toSquareIndex(square)
    if not index then return nil end
    local piece = position.board[index]
    if piece == EMPTY then return nil end
    return FEN_FROM_PIECE[piece]
end

function Rules.squareName(square)
    return SQUARE_NAME[square]
end

function Rules.squareIndex(name)
    return SQUARE_FROM_NAME[name]
end

function Rules.squareFromRowCol(row, col)
    if row < 0 or row > 7 or col < 0 or col > 7 then return nil end
    return (7 - row) * 8 + col
end

function Rules.rowColOf(square)
    local index = toSquareIndex(square)
    if not index then return nil end
    return 7 - RANK_OF[index], FILE_OF[index]
end

function Rules.kingSquare(position, color)
    if color == nil then return position.kingSquare[position.side] end
    if color == "w" or color == WHITE then return position.kingSquare[WHITE] end
    return position.kingSquare[BLACK]
end

function Rules.inCheck(position)
    return isAttacked(position.board, position.kingSquare[position.side], 3 - position.side)
end

function Rules.isSquareAttacked(position, square, byColor)
    local index = toSquareIndex(square)
    if not index then return false end
    local color = BLACK
    if byColor == "w" or byColor == WHITE then color = WHITE end
    return isAttacked(position.board, index, color)
end

function Rules.legalMoves(position)
    local codes = legalCodes(position)
    local moves = {}
    for index = 1, #codes do
        moves[index] = describeMove(position, codes[index])
    end
    return moves
end

function Rules.legalMovesFrom(position, square)
    local origin = toSquareIndex(square)
    local moves = {}
    if not origin then return moves end
    local codes = legalCodes(position)
    local kept = 0
    for index = 1, #codes do
        local code = codes[index]
        if code % 64 == origin then
            kept = kept + 1
            moves[kept] = describeMove(position, code)
        end
    end
    return moves
end

function Rules.isLegalMove(position, move)
    return resolveCode(position, move) ~= nil
end

function Rules.repetitionKey(position)
    local enPassant = "-"
    if enPassantIsPlayable(position) then enPassant = SQUARE_NAME[position.ep] end
    return placementString(position)
        .. " " .. ((position.side == WHITE) and "w" or "b")
        .. " " .. castlingString(position.castling)
        .. " " .. enPassant
end

function Rules.repetitionCount(position)
    local history = position.history
    if not history or #history == 0 then return 1 end
    local key = Rules.repetitionKey(position)
    local seen = 1
    for index = 1, #history do
        if history[index] == key then seen = seen + 1 end
    end
    return seen
end

function Rules.apply(position, move)
    local code, reason = resolveCode(position, move)
    if not code then return nil, reason end

    local key = Rules.repetitionKey(position)
    local result = clonePosition(position)
    makeMove(result, code)

    if result.halfmove == 0 then
        result.history = {}
    else
        local previous = position.history or {}
        local history = {}
        for index = 1, #previous do history[index] = previous[index] end
        history[#history + 1] = key
        result.history = history
    end

    return result
end

function Rules.status(position)
    local codes = legalCodes(position)
    local check = Rules.inCheck(position)
    if #codes == 0 then
        if check then return "checkmate" end
        return "stalemate"
    end
    if hasInsufficientMaterial(position) then return "draw-material" end
    if position.halfmove >= 100 then return "draw-fifty" end
    if Rules.repetitionCount(position) >= 3 then return "draw-repetition" end
    if check then return "check" end
    return "ok"
end

function Rules.toUCI(move)
    if type(move) == "string" then return move end
    if type(move) ~= "table" then return nil end
    local from = toSquareIndex(move.from)
    local to = toSquareIndex(move.to)
    if not from or not to then return nil end
    local text = SQUARE_NAME[from] .. SQUARE_NAME[to]
    if move.promotion then text = text .. tostring(move.promotion):lower() end
    return text
end

function Rules.fromUCI(position, text)
    if type(text) ~= "string" then return nil, "uci move must be a string" end
    local codes = legalCodes(position)
    local code, reason = resolveCode(position, text, codes)
    if not code then return nil, reason end
    return describeMove(position, code)
end

function Rules.toSAN(position, move)
    local codes = legalCodes(position)
    local code, reason = resolveCode(position, move, codes)
    if not code then return nil, reason end

    local from, to, promotion, flag = decodeMove(code)
    local board = position.board
    local movingType = TYPE_OF[board[from]]
    local text

    if flag == FLAG_CASTLE_KING then
        text = "O-O"
    elseif flag == FLAG_CASTLE_QUEEN then
        text = "O-O-O"
    elseif movingType == PAWN then
        local capture = (board[to] ~= EMPTY) or (flag == FLAG_EN_PASSANT)
        if capture then
            text = FILE_CHARS:sub(FILE_OF[from] + 1, FILE_OF[from] + 1) .. "x" .. SQUARE_NAME[to]
        else
            text = SQUARE_NAME[to]
        end
        if promotion ~= 0 then text = text .. "=" .. FEN_FROM_PIECE[promotion] end
    else
        local ambiguous, sharesFile, sharesRank = false, false, false
        for index = 1, #codes do
            local otherFrom, otherTo = decodeMove(codes[index])
            if otherTo == to and otherFrom ~= from and TYPE_OF[board[otherFrom]] == movingType then
                ambiguous = true
                if FILE_OF[otherFrom] == FILE_OF[from] then sharesFile = true end
                if RANK_OF[otherFrom] == RANK_OF[from] then sharesRank = true end
            end
        end
        local disambiguation = ""
        if ambiguous then
            if not sharesFile then
                disambiguation = FILE_CHARS:sub(FILE_OF[from] + 1, FILE_OF[from] + 1)
            elseif not sharesRank then
                disambiguation = tostring(RANK_OF[from] + 1)
            else
                disambiguation = SQUARE_NAME[from]
            end
        end
        local capture = (board[to] ~= EMPTY) and "x" or ""
        text = FEN_FROM_PIECE[movingType] .. disambiguation .. capture .. SQUARE_NAME[to]
    end

    local work = clonePosition(position)
    makeMove(work, code)
    if isAttacked(work.board, work.kingSquare[work.side], 3 - work.side) then
        if #legalCodes(work) == 0 then
            text = text .. "#"
        else
            text = text .. "+"
        end
    end
    return text
end

local function perftNode(position, depth, buffers)
    local moves = buffers[depth]
    if not moves then
        moves = {}
        buffers[depth] = moves
    end
    local generated = generatePseudoMoves(position, moves)
    local nodes = 0

    if depth == 1 then
        for index = 1, generated do
            if leavesKingSafe(position, moves[index]) then nodes = nodes + 1 end
        end
        return nodes
    end

    for index = 1, generated do
        local code = moves[index]
        local captured, captureSquare, previousEnPassant, previousCastling, previousHalfmove =
            makeMove(position, code)
        local mover = 3 - position.side
        if not isAttacked(position.board, position.kingSquare[mover], position.side) then
            nodes = nodes + perftNode(position, depth - 1, buffers)
        end
        unmakeMove(position, code, captured, captureSquare,
            previousEnPassant, previousCastling, previousHalfmove)
    end
    return nodes
end

function Rules.perft(position, depth)
    if depth <= 0 then return 1 end
    return perftNode(clonePosition(position), depth, {})
end

function Rules.perftDivide(position, depth)
    local results = {}
    if depth <= 0 then return results end
    local work = clonePosition(position)
    local buffer = {}
    local generated = generatePseudoMoves(work, buffer)
    local buffers = {}
    for index = 1, generated do
        local code = buffer[index]
        local captured, captureSquare, previousEnPassant, previousCastling, previousHalfmove =
            makeMove(work, code)
        local mover = 3 - work.side
        if not isAttacked(work.board, work.kingSquare[mover], work.side) then
            local nodes = 1
            if depth > 1 then nodes = perftNode(work, depth - 1, buffers) end
            local from, to, promotion = decodeMove(code)
            local label = SQUARE_NAME[from] .. SQUARE_NAME[to]
            if promotion ~= 0 then label = label .. FEN_FROM_PIECE[promotion + BLACK_OFFSET] end
            results[#results + 1] = { move = label, nodes = nodes }
        end
        unmakeMove(work, code, captured, captureSquare,
            previousEnPassant, previousCastling, previousHalfmove)
    end
    table.sort(results, function(left, right) return left.move < right.move end)
    return results
end

Rules.STARTING_FEN = STARTING_FEN

return Rules
