-- Written by the game on logout; shaped like a real SavedVariables file.
WoWForeverAP_DB = {
	["schema"] = 1,
	["characters"] = {
		["Player-1234-0A1B2C3D"] = {
			["name"] = "Arthas Menethil",
			["faction"] = "Alliance",
			["classFile"] = "PALADIN",
			["slotKey"] = "AP_1234:Wow\"Slot",
			["linkedAt"] = 1763380000,
			["linkedLevel"] = 1,
			["skillAtLink"] = {
				[171] = 0,
				[186] = 12,
			},
			["seenItemCount"] = 3,
		},
		["Player-1234-0A1B2C3E"] = {
			["name"] = "Jaina Prächtig",
			["faction"] = "Alliance",
			["slotKey"] = nil,
			["neverAsk"] = true,
		},
	},
	["slots"] = {
		["AP_1234:Wow\"Slot"] = {
			["outbox"] = {
				{
					["kind"] = "check",
					["id"] = 5110000783,
					["char"] = "Player-1234-0A1B2C3D",
					["t"] = 1763380100,
				}, -- [1]
				{
					["kind"] = "check",
					["id"] = 5120000002,
					["char"] = "Player-1234-0A1B2C3D",
					["t"] = 1763380200,
				}, -- [2]
			},
			["goal"] = {
				["char"] = "Player-1234-0A1B2C3D",
				["t"] = 1763390000,
			},
		},
	},
	["ratio"] = -0.5,
	["big"] = 0x1F,
	["exp"] = 1.5e3,
	["note"] = [[
long
string with "quotes" and \ backslash]],
	["levelled"] = [==[contains ]] inside]==],
	["escapes"] = "tab\there\ncarriage\rzero\0 \195\164 \\ \"",
}
--[[ trailing block
comment ]]
