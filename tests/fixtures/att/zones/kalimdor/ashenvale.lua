-- Hand-written test fixture in ATT syntax: a zone open to both factions.
maproot(MAP.KALIMDOR, MAP.ASHENVALE, {
	groups = {
		n(QUESTS, {
			q(170, {	-- Anyone Can Do This
				lvl = 20,
			}),
			q(171, {	-- Alliance Start
				races = ALLIANCE_ONLY,
				lvl = 20,
			}),
			q(172, {	-- Follows The Alliance
				sourceQuest = 171,
				lvl = 21,
			}),
			q(173, {	-- Horde Start
				races = HORDE_ONLY,
				lvl = 20,
			}),
			q(174, {	-- Follows Both Factions
				sourceQuests = { 171, 173 },
				lvl = 22,
			}),
		}),
	},
});
