-- Hand-written test fixture in ATT syntax; the quests are made up.
maproot(MAP.EASTERN_KINGDOMS, MAP.ELWYNN_FOREST, {
	lore = "A made-up zone.",
	groups = {
		m(MAP.NORTHSHIRE_VALLEY, {
			groups = {
				n(QUESTS, {
					q(100, {	-- Kept Simple
						coord = { 48.1, 42.9, MAP.ELWYNN_FOREST },
						races = ALLIANCE_ONLY,
						lvl = 5,
					}),
					q(101, {	-- Kept Chain
						sourceQuest = 100,	-- Kept Simple
						coord = { 10.0, 20.0, MAP.NORTHSHIRE_VALLEY },
						races = ALLIANCE_ONLY,
						lvl = 6,
					}),
				}),
			},
		}),
		m(SHADOWGLEN_LIKE, {
			groups = {
				n(QUESTS, {
					q(136, {	-- Local Bare Map
						coord = { 10.0, 20.0, SHADOWGLEN_LIKE },
						lvl = 3,
					}),
				}),
			},
		}),
		n(QUESTS, {
			q(102, {	-- Parent Walk
				coord = { 1.0, 2.0, MAP.TEST_CAVE },
				lvl = 8,
			}),
			q(103, {	-- Stormwind Giver
				coord = { 1.0, 2.0, MAP.STORMWIND_CITY },
				lvl = 8,
			}),
			q(104, {	-- Never Implemented
				lvl = 8,
			}),
			q(105, {	-- Unobtainable
				u = 1,
				lvl = 8,
			}),
			q(106, {	-- Not Yet Added
				timeline = { TIMELINE.ADDED_1_61_0 },
				lvl = 8,
			}),
			q(107, {	-- Added In Forever
				timeline = { TIMELINE.ADDED_1_60_1 },
				lvl = 8,
			}),
			q(108, {	-- Removed Again
				timeline = { ADDED_1_4_0, REMOVED_1_7_0 },
				lvl = 8,
			}),
			q(109, {	-- Removed Then Added
				timeline = { REMOVED_1_4_0, TIMELINE.ADDED_1_60_1 },
				lvl = 8,
			}),
			q(110, {	-- Created Only
				timeline = { TIMELINE.CREATED_1_60_1 },
				lvl = 8,
			}),
			q(111, {	-- Repeatable
				repeatable = true,
				lvl = 8,
			}),
			q(112, {	-- Daily
				isDaily = true,
				lvl = 8,
			}),
			q(113, {	-- Breadcrumb
				isBreadcrumb = true,
				lvl = 8,
			}),
			q(114, {	-- After A Breadcrumb
				sourceQuest = 113,	-- Breadcrumb
				sourceQuests = { 111 },	-- Repeatable
				lvl = 8,
			}),
			q(115, {	-- Mage Only
				classes = { MAGE },
				lvl = 8,
			}),
			q(116, {	-- After The Mage
				sourceQuest = 115,
				lvl = 8,
			}),
			q(117, {	-- After After The Mage
				sourceQuest = 116,
				lvl = 8,
			}),
			q(118, {	-- Humans Only
				races = { HUMAN },
				lvl = 8,
			}),
			q(119, {	-- Needs Alchemy
				requireSkill = ALCHEMY,
				lvl = 8,
			}),
			q(120, {	-- Needs Reputation
				minReputation = { FACTION_X, FRIENDLY },
				lvl = 8,
			}),
			q(121, {	-- Lock Criteria
				lockCriteria = { 1, 2 },
				lvl = 8,
			}),
			q(122, {	-- Alternative Quests
				altQuests = { 1, 2 },
				lvl = 8,
			}),
			q(123, {	-- Horde In The Alliance Zone
				races = HORDE_ONLY,
				lvl = 8,
			}),
			q(20000000, {	-- Id Out Of Range
				lvl = 8,
			}),
			q(125, {
				lvl = 8,
			}),
			q(127, {	-- No Level
				races = ALLIANCE_ONLY,
			}),
			q(128, {	-- Twin Name
				lvl = 9,
			}),
			q(129, {	-- Twin Name
				lvl = 9,
			}),
			q(130, {	-- Unknown Prerequisite
				sourceQuest = 99999,
				lvl = 8,
			}),
			q(131, {	-- Two Prerequisites
				sourceQuests = { 101, 100 },
				lvl = 10,
			}),
			q(132, {	-- Level Clamped
				lvl = 75,
			}),
			q(133, {	-- Level From A Call
				lvl = level(12, 3),
			}),
			q(134, {	-- Flat Coords And Maps
				coords = { 1.0, 2.0, MAP.WESTFALL },
				maps = { MAP.TEST_CAVE },
				lvl = 11,
			}),
			q(135, {	-- Bare Legacy Map Name
				coord = { 1.0, 2.0, WESTFALL },
				lvl = 11,
			}),
			q(137, {	-- Takes The Faction Of Its Prerequisite
				sourceQuest = 100,
				lvl = 7,
			}),
			q(138, {	-- Race Written As A Call
				races = exclude(HUMAN, ALLIANCE_ONLY),
				lvl = 7,
			}),
			q(139, {	-- Tricky Name -- with a dash, a "quote" and a, comma
				lvl = 7,
			}),
			q(141, {	-- Class Quest With Odd Races
				classes = { PALADIN },
				races = ALLIANCE_PALADINS,
			}),
		}),
	},
});
root(ROOTS.HiddenQuestTriggers, {
	q(150, {	-- Hidden Trigger
	}),
});
