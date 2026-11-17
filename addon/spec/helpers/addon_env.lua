-- Loads the addon's files into a fresh namespace in TOC order, the way the game does, on top of the fake game API.
local Stub = require("helpers.wow_stub")

local Env = {}

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
Env.ADDON_DIR = here .. "../../WoWForeverAP/"
Env.INBOX_ADDON_DIR = here .. "../../WoWForeverAP_Inbox/"
Env.SPEC_DIR = here .. "../"

--- File names listed in a TOC file, in order (blank lines and `##` metadata skipped).
function Env.tocFiles(tocPath)
    local files = {}
    for line in io.lines(tocPath) do
        line = line:gsub("%s+$", "")
        if line ~= "" and line:sub(1, 2) ~= "##" and line:sub(1, 1) ~= "#" then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    return files
end

--- Fresh fake game plus a namespace with the files of `names` loaded (default: everything in the main TOC).
--- Returns ns, game. Chat output is captured in game.chat.
function Env.new(names)
    local game = Stub.install()
    local ns = {}
    for _, file in ipairs(names or Env.tocFiles(Env.ADDON_DIR .. "WoWForeverAP.toc")) do
        local chunk = assert(loadfile(Env.ADDON_DIR .. file))
        chunk("WoWForeverAP", ns)
    end
    if ns.Notify then
        ns.Notify.out = function(text)
            game.chat[#game.chat + 1] = text
        end
    end
    return ns, game
end

--- Messages of the chat log without the colour prefix.
function Env.chatText(game)
    local lines = {}
    for _, line in ipairs(game.chat) do
        lines[#lines + 1] = (line:gsub("^|c%x%x%x%x%x%x%x%x%[AP%]|r ", ""))
    end
    return lines
end

--- Builds a one-slot inbox the way the client writes it.
function Env.inbox(overrides)
    local slot = {
        seed = "S1", slot = "Wow", worldVersion = "0.0.0",
        options = { faction = "alliance", startZone = 1429, contentRelease = 1, goalLevel = 60,
                    professions = { 171, 186 }, levelStep = 1, professionStep = 25,
                    economy = { auctionHouse = true, trading = true, mail = false, sharedBanks = false,
                                mainBoosts = false, carePackages = 5, carePackageGold = 50,
                                carePackageStacks = 5 } },
        locations = {}, checked = {}, items = {},
    }
    for key, value in pairs(overrides or {}) do
        slot[key] = value
    end
    return { schema = 1, slots = { ["S1:Wow"] = slot } }
end

return Env
