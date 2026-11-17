-- Hand-written test fixture in ATT syntax; the quests are made up.
maproot(MAP.EASTERN_KINGDOMS, MAP.WESTFALL, {
	groups = {
		n(QUESTS, {
			q(100, {	-- Duplicate Of A Kept Quest
				lvl = 12,
			}),
			{
				allianceQuestData = q(140, {	-- Both Factions (A)
					coord = { 1.0, 2.0, MAP.WESTFALL },
				}),
				hordeQuestData = q(142, {	-- Both Factions (H)
					coord = { 1.0, 2.0, MAP.WESTFALL },
				}),
				lvl = 9,
			},
			q(143, {	-- Westfall Own
				lvl = 14,
			}),
		}),
	},
});
