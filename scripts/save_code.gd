# save_code.gd — AUTOLOAD "SaveCode".
#
# The ten-character transferable save code, in the same format as the
# Python editions (die_trying.py and calc/dtsave.py), so a code from the
# calculator loads here and a code from here loads there.
#
#   levels 11 | progress 9 | money 16 | rolls 13 | wipes 11 = 60 bits
#   = ten characters of six bits each.
#
# Spending is the sum of the costs of the levels owned and earnings are
# money + spending, so neither is stored. There is no room for a
# checksum either; loads are sanity-checked instead (levels in range,
# wipes no greater than rolls, no money before the first roll).
#
# Playtime and best run do not fit, so a code does not carry them.

extends Node

const ALPHABET := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-."
const WIDTHS := [11, 9, 16, 13, 11]
const LIMITS := [1889, 511, 65535, 8191, 2047]
const CODE_LEN := 10

## Radices the levels field is packed with. These are FIXED by the code
## format, not read from the tables — adding a row to SPEED_LEVELS,
## MONEY_MULT_LEVELS or MATCH_MULT_LEVELS would break every code that
## already exists (and the calculator edition along with it).
const SPEED_RADIX := 9
const MONEY_RADIX := 6
const MATCH_RADIX := 5

## main.gd owns the balance tables; the cost columns are all that is
## needed here, to derive total_spent from the levels a code carries.
const Rules := preload("res://scripts/main.gd")


# =========================================================
# CODEC — pure, operates on the five packed values
# =========================================================
## Pack five values into a code. Each is clamped to its field limit, so
## a game that runs past a cap saves as the cap instead of corrupting
## the fields packed after it.
func encode_values(vals: Array) -> String:
	var out := ""
	var acc := 0
	var n := 0
	for i in WIDTHS.size():
		var width: int = WIDTHS[i]
		acc = (acc << width) | clampi(int(vals[i]), 0, LIMITS[i])
		n += width
		while n >= 6:
			n -= 6
			out += ALPHABET[(acc >> n) & 63]
			acc &= (1 << n) - 1
	if n > 0:
		out += ALPHABET[(acc << (6 - n)) & 63]
	return out


## Unpack a code into its five values, or an empty array if a character
## is outside the alphabet or the string runs out early.
func decode_values(code: String) -> Array:
	var vals: Array[int] = []
	var acc := 0
	var n := 0
	var pos := 0
	for width: int in WIDTHS:
		while n < width:
			if pos >= code.length():
				return []
			var i := ALPHABET.find(code[pos])
			if i < 0:
				return []
			pos += 1
			acc = (acc << 6) | i
			n += 6
		n -= width
		vals.append((acc >> n) & ((1 << width) - 1))
		acc &= (1 << n) - 1
	return vals


## Two blocks of five: easier to read out and to type back.
func grouped(code: String) -> String:
	return code.substr(0, 5) + " " + code.substr(5)


# =========================================================
# GAMESTATE <-> CODE
# =========================================================
## The code for the game in progress.
func encode() -> String:
	var levels := ((GameState.die_level * SPEED_RADIX + GameState.speed_level) \
		* MONEY_RADIX + GameState.money_mult_level) \
		* MATCH_RADIX + GameState.match_mult_level
	return encode_values([levels, GameState.progress, GameState.money,
		GameState.total_rolls, GameState.bust_count])


## Replace the game in progress with the one a code describes. Everything
## is validated BEFORE anything is written, so a bad code leaves the
## current game untouched instead of half-loaded. Returns false if the
## code is malformed, describes an impossible game, or carries a level
## this build has no row for.
@warning_ignore("integer_division")
func load_code(code: String) -> bool:
	var s := code.strip_edges().replace(" ", "")   # tolerates the grouped form
	if s.length() != CODE_LEN:
		return false
	var vals := decode_values(s)
	if vals.is_empty() or vals[0] > LIMITS[0]:
		return false
	if vals[4] > vals[3]:                          # more wipes than rolls
		return false
	if vals[3] == 0 and (vals[1] != 0 or vals[2] != 0):   # money before rolling
		return false

	var levels: int = vals[0]
	var match_level := levels % MATCH_RADIX
	levels = levels / MATCH_RADIX
	var money_level := levels % MONEY_RADIX
	levels = levels / MONEY_RADIX
	var speed_level := levels % SPEED_RADIX
	var die_level := levels / SPEED_RADIX

	# A code written by a build with more upgrade rows than this one would
	# index past the tables and take the game scene down with it.
	if die_level >= Rules.DICE_TIERS.size() \
	or speed_level >= Rules.SPEED_LEVELS.size() \
	or money_level >= Rules.MONEY_MULT_LEVELS.size() \
	or match_level >= Rules.MATCH_MULT_LEVELS.size():
		return false

	GameState.reset()
	GameState.die_level = die_level
	GameState.speed_level = speed_level
	GameState.money_mult_level = money_level
	GameState.match_mult_level = match_level
	GameState.progress = vals[1]
	GameState.money = vals[2]
	GameState.total_rolls = vals[3]
	GameState.bust_count = vals[4]
	GameState.best_run = GameState.progress
	GameState.total_spent = spent_from_levels()
	GameState.total_earned = GameState.money + GameState.total_spent

	# Mark the milestones this game has already passed as seen, so a
	# loaded save doesn't replay them all one roll at a time.
	Splash.label.catch_up_silently({
		"rolls": GameState.total_rolls,
		"busts": GameState.bust_count,
		"earned": GameState.total_earned,
		"spent": GameState.total_spent,
	})
	return true


## Every purchase is recorded in the levels, so spending is derivable.
## Level 0 of every table costs 0, which is why counting it is harmless.
func spent_from_levels() -> int:
	var total := 0
	for i in GameState.die_level + 1:
		total += Rules.DICE_TIERS[i][2]
	for i in GameState.speed_level + 1:
		total += Rules.SPEED_LEVELS[i][1]
	for i in GameState.money_mult_level + 1:
		total += Rules.MONEY_MULT_LEVELS[i][1]
	for i in GameState.match_mult_level + 1:
		total += Rules.MATCH_MULT_LEVELS[i][1]
	return total
