-- Hand-written test fixture in ATT syntax: a zone that is not in zones.csv.
maproot(MAP.EASTERN_KINGDOMS, MAP.STORMWIND_CITY, {
	groups = {
		n(QUESTS, {
			q(160, {	-- City Quest
				races = ALLIANCE_ONLY,
				lvl = 5,
			}),
			q(161, {	-- City Quest With A Future Race
				races = { SOME_NEW_RACE },
				lvl = 5,
			}),
		}),
	},
});
