local scriptPath = (arg and arg[0]) or "perft.lua"
local scriptDir = scriptPath:match("^(.*)[/\\][^/\\]+$") or "."
package.path = scriptDir .. "/?.lua;" .. scriptDir .. "/../?.lua;" .. package.path

local loaded, Rules = pcall(require, "chess/rules")
if not loaded then Rules = require("rules") end

local SUITE = {
    {
        name = "startpos",
        fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        expected = { 20, 400, 8902, 197281, 4865609 },
    },
    {
        name = "kiwipete",
        fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -",
        expected = { 48, 2039, 97862, 4085603 },
    },
    {
        name = "position 3",
        fen = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -",
        expected = { 14, 191, 2812, 43238, 674624 },
    },
    {
        name = "position 4",
        fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq -",
        expected = { 6, 264, 9467, 422333 },
    },
    {
        name = "position 5",
        fen = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ -",
        expected = { 44, 1486, 62379, 2103487 },
    },
}

local function runDivide(fen, depth)
    local position, err = Rules.fromFEN(fen)
    if not position then
        io.write("bad fen: ", tostring(err), "\n")
        os.exit(1)
    end
    local total = 0
    for _, entry in ipairs(Rules.perftDivide(position, depth)) do
        io.write(entry.move, ": ", tostring(entry.nodes), "\n")
        total = total + entry.nodes
    end
    io.write("\nnodes ", tostring(total), "\n")
end

local function runSuite()
    local failures = 0
    local startposDepth3 = nil

    for _, case in ipairs(SUITE) do
        io.write(case.name, "\n  ", case.fen, "\n")
        local position, err = Rules.fromFEN(case.fen)
        if not position then
            io.write("  FEN REJECTED: ", tostring(err), "\n\n")
            failures = failures + 1
        else
            for depth = 1, #case.expected do
                local started = os.clock()
                local nodes = Rules.perft(position, depth)
                local elapsed = os.clock() - started
                local expected = case.expected[depth]
                local verdict = "ok"
                if nodes ~= expected then
                    verdict = "FAIL"
                    failures = failures + 1
                end
                local rate = ""
                if elapsed > 0 then
                    rate = string.format("  %.0f nodes/s", nodes / elapsed)
                end
                io.write(string.format("  depth %d  %10d  expected %10d  %-4s  %7.3fs%s\n",
                    depth, nodes, expected, verdict, elapsed, rate))
                if case.name == "startpos" and depth == 3 then
                    startposDepth3 = elapsed
                end
            end
            local roundTrip = Rules.toFEN(position)
            io.write("  toFEN   ", roundTrip, "\n\n")
        end
    end

    if startposDepth3 then
        io.write(string.format("startpos depth 3 took %.4f s\n", startposDepth3))
    end
    if failures == 0 then
        io.write("all perft counts match\n")
        os.exit(0)
    end
    io.write(tostring(failures), " mismatch(es)\n")
    os.exit(1)
end

if arg and arg[1] == "divide" then
    runDivide(arg[2], tonumber(arg[3]) or 1)
else
    runSuite()
end
