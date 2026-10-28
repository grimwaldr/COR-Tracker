-- Phoenix XI roll data.
--
-- Values come from the Phoenix server scripts, not wikis:
--   scripts/globals/job_utils/corsair.lua           (base rollData)
--   modules/era/lua/globals/job_utils/corsair.lua   (pre-SoA and pre-Abyssea power/bonus overrides,
--                                                    plus the era effect swaps for Healer's,
--                                                    Gallant's, Drachen and Puppet)
--
-- values      Effect power for totals 1 to 11.
-- bonus       Added when anyone in the party has bonus_job as their main job (totals 1 to 11 only).
-- bonus_job   Job ID: WAR 1, MNK 2, WHM 3, BLM 4, RDM 5, THF 6, PLD 7, DRK 8, BST 9, BRD 10,
--             RNG 11, SAM 12, NIN 13, DRG 14, SMN 15, BLU 16, COR 17, PUP 18, DNC 19, SCH 20.
-- bust        Flat penalty on the roller only. The era module never overrides bustPower or
--             bustMod, so these are the server's base values and can differ from the roll's own
--             stat. nil means the bust carries no penalty (bustMod NONE).

return {
    ['Corsair\'s Roll'] = {
        lucky = 5, unlucky = 9, desc = 'Experience / Limit Points', percent = true,
        values = { 10, 11, 11, 12, 20, 13, 15, 16, 8, 17, 24 },
        bust = { value = 6, desc = 'Experience / Limit Points', percent = true },
    },

    ['Ninja Roll'] = {
        lucky = 4, unlucky = 8, desc = 'Evasion',
        values = { 4, 6, 8, 25, 10, 12, 14, 2, 17, 20, 30 },
        bonus = 10, bonus_job = 13,
        bust = { value = 15, desc = 'Evasion' },
    },

    ['Hunter\'s Roll'] = {
        lucky = 4, unlucky = 8, desc = 'Accuracy / Ranged Accuracy',
        values = { 10, 13, 15, 40, 18, 20, 25, 5, 28, 30, 50 },
        bonus = 15, bonus_job = 11,
        bust = { value = 15, desc = 'Accuracy / Ranged Accuracy' },
    },

    ['Chaos Roll'] = {
        lucky = 4, unlucky = 8, desc = 'Attack / Ranged Attack', percent = true,
        values = { 6, 8, 9, 25, 11, 13, 16, 3, 17, 19, 31 },
        bonus = 10, bonus_job = 8,
        bust = { value = 10, desc = 'Attack / Ranged Attack', percent = true },
    },

    ['Magus\'s Roll'] = {
        lucky = 2, unlucky = 6, desc = 'Magic Defense Bonus',
        values = { 5, 20, 6, 8, 9, 3, 10, 13, 14, 15, 25 },
        bonus = 8, bonus_job = 16,
        bust = { value = 8, desc = 'Magic Defense Bonus' },
    },

    ['Healer\'s Roll'] = {
        lucky = 3, unlucky = 7, desc = 'MP Recovered while healing',
        values = { 2, 3, 10, 4, 4, 5, 1, 6, 7, 7, 12 },
        bonus = 3, bonus_job = 3,
        bust = { value = 4, desc = 'Cure Potency Received', percent = true },
    },

    ['Drachen Roll'] = {
        lucky = 3, unlucky = 7, desc = 'Pet: Magic Accuracy / Magic Attack',
        values = { 4, 5, 18, 7, 9, 10, 2, 11, 13, 15, 22 },
        bonus = 8, bonus_job = 14,
        bust = nil,
    },

    ['Choral Roll'] = {
        lucky = 2, unlucky = 6, desc = 'Spell Interruption Rate down', percent = true,
        values = { 4, 17, 5, 6, 7, 2, 8, 10, 11, 12, 21 },
        bonus = 8, bonus_job = 10,
        bust = { value = 25, desc = 'Spell Interruption Rate down', percent = true },
    },

    ['Monk\'s Roll'] = {
        lucky = 3, unlucky = 7, desc = 'Subtle Blow',
        values = { 8, 10, 32, 12, 14, 16, 4, 20, 22, 24, 40 },
        bonus = 10, bonus_job = 2,
        bust = { value = 11, desc = 'Subtle Blow' },
    },

    ['Beast Roll'] = {
        lucky = 4, unlucky = 8, desc = 'Pet: Attack / Ranged Attack', percent = true,
        values = { 5, 6, 7, 19, 8, 9, 12, 2, 13, 14, 23 },
        bonus = 8, bonus_job = 9,
        bust = nil,
    },

    ['Samurai Roll'] = {
        lucky = 2, unlucky = 6, desc = 'Store TP',
        values = { 8, 32, 10, 12, 14, 4, 16, 20, 22, 24, 40 },
        bonus = 10, bonus_job = 12,
        bust = { value = 10, desc = 'Store TP' },
    },

    ['Evoker\'s Roll'] = {
        lucky = 5, unlucky = 9, desc = 'Refresh',
        values = { 1, 1, 1, 1, 3, 2, 2, 2, 1, 3, 4 },
        bonus = 1, bonus_job = 15,
        bust = { value = 1, desc = 'Refresh' },
    },

    ['Rogue\'s Roll'] = {
        lucky = 5, unlucky = 9, desc = 'Critical Hit Rate', percent = true,
        values = { 2, 2, 3, 4, 12, 5, 6, 6, 1, 8, 19 },
        bonus = 6, bonus_job = 6,
        bust = { value = 6, desc = 'Critical Hit Rate', percent = true },
    },

    ['Warlock\'s Roll'] = {
        lucky = 4, unlucky = 8, desc = 'Magic Accuracy',
        values = { 2, 3, 4, 10, 4, 5, 6, 1, 7, 7, 12 },
        bonus = 4, bonus_job = 5,
        bust = { value = 15, desc = 'Magic Accuracy' },
    },

    ['Fighter\'s Roll'] = {
        lucky = 5, unlucky = 9, desc = 'Double Attack', percent = true,
        values = { 2, 2, 3, 4, 12, 5, 6, 7, 1, 9, 18 },
        bonus = 6, bonus_job = 1,
        bust = { value = 6, desc = 'Double Attack', percent = true },
    },

    ['Puppet Roll'] = {
        lucky = 4, unlucky = 8, desc = 'Pet: Accuracy / Ranged Accuracy',
        values = { 10, 13, 15, 40, 18, 20, 25, 5, 28, 30, 50 },
        bonus = 15, bonus_job = 18,
        bust = nil,
    },

    ['Gallant\'s Roll'] = {
        lucky = 3, unlucky = 7, desc = 'Reflects Damage', percent = true,
        values = { 4, 5, 15, 6, 7, 8, 3, 9, 10, 12, 20 },
        bonus = 10, bonus_job = 7,
        bust = { value = 11, desc = 'Defense', percent = true },
    },

    ['Wizard\'s Roll'] = {
        lucky = 5, unlucky = 9, desc = 'Magic Attack Bonus',
        values = { 2, 3, 4, 4, 10, 5, 6, 7, 1, 7, 12 },
        bonus = 4, bonus_job = 4,
        bust = { value = 10, desc = 'Magic Attack Bonus' },
    },

    ['Dancer\'s Roll'] = {
        lucky = 3, unlucky = 7, desc = 'Regen',
        values = { 3, 4, 11, 4, 5, 6, 1, 7, 8, 8, 14 },
        bonus = 3, bonus_job = 19,
        bust = { value = 4, desc = 'Regen' },
    },

    ['Scholar\'s Roll'] = {
        lucky = 2, unlucky = 6, desc = 'Conserve MP', percent = true,
        values = { 2, 10, 3, 4, 4, 1, 5, 6, 7, 7, 12 },
        bonus = 4, bonus_job = 20,
        bust = { value = 4, desc = 'Conserve MP', percent = true },
    },
}
