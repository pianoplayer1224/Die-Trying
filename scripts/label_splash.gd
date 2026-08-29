class_name SplashLabel
extends Label

## Splash text for Die Trying.
##
## - Rotates through a random pool every [member rotate_interval] seconds.
## - Game events (milestones, busts, upgrades) interrupt immediately via
##   [method show_event] and hold the label for one full interval, after
##   which random rotation resumes.
## - Milestones are grouped into categories (rolls, busts, money earned,
##   money spent, playtime), each fed by its own on_*_changed() method.

## wiring in your game script (main.gd):
#	splash_label.on_rolls_changed(GameState.total_rolls)
#	splash_label.on_busts_changed(GameState.bust_count)
#	splash_label.on_money_earned_changed(GameState.total_earned)
#	splash_label.on_money_spent_changed(GameState.total_spent)
#	splash_label.on_playtime_changed(GameState.playtime)
# and in main._ready(), so returning from the menu doesn't refire
# milestones the player has already seen:
#	splash_label.catch_up_silently({ "rolls": GameState.total_rolls, ... })

# --- Tuning -----------------------------------------------------------------

@export var rotate_interval: float = 10.0
## Seconds for the fade-out / fade-in on each change. Set to 0 for a hard cut.
@export var fade_time: float = 0.2
## How many recent messages to avoid repeating. Clamped to pool size - 1.
@export var no_repeat_window: int = 5

@export var random_splashes: PackedStringArray = [
	"Also try Unfair Flips!",
	"Now with twenty sides!",
	"Statistically, you'll be fine.",
	"Money is permanent. Dignity is not.",
	"A one in six chance of regret.",
	"100% organic, free-range pseudorandomness.",
	"The house always wins.",
	"Do not eat the dice.",
	"Snake eyes sold separately.",
	"Every roll is a coin flip if you squint.",
	"More time was spent making these messages than balancing the game.",
	"Though unlikely, this game may never end.",
	"In dice we trust.",
	"Upgrade your dice, not your life choices.",
	"Rolling a 1 builds character. Mostly negative character.",
	"Speed doesn't fix a bad roll. It just gets you there faster.",
	"Somewhere, a d20 is laughing at you.",
	"Play-tested by someone with a gambling addiction.",
	"No dice were harmed. Several were disappointed.",
	"Achievement unlocked: reading splash text instead of playing.",
	"Failure is just progress with extra steps.",
	"You miss 100% of the rolls you don't take.",
	"Optimism is not a valid strategy.",
	"seal",
	"7EAM!",
	"🦆",
	"'It is mathematically proven that on average your partner has more partners than you'",
	"'We are two parts of a song. He is the music, and i am the words' -From some book",
	"'If god would have wanted you to win he wouldn’t have created me'",
]

# --- Milestones (threshold -> message; each fires once, ever) ----------------

@export var roll_milestones: Dictionary = {
	10: "Ten rolls. A promising start.",
	50: "Fifty rolls now.",
	100: "One hundred rolls. Hope you're having fun!",
	250: "250 rolls. This is a lifestyle now.",
	500: "500 rolls. Seek help.",
	1000: "1000 rolls. Seek help, urgently.",
	5000: "5000 rolls. Please stop."
}

@export var bust_milestones: Dictionary = {
	1: "Your first wipe. It won't be your last.",
	5: "Five wipes. The die is just being honest.",
	10: "Ten wipes. Have you considered not rolling ones?",
	25: "25 wipes. That's dedication. Or denial.",
	50: "50 wipes. The one is your most loyal face.",
	100: "100 wipes. Damn, you are unlucky.",
}

@export var money_earned_milestones: Dictionary = {
	100: "First $100 earned. Get yourself something nice.",
	500: "$500 lifetime earnings. The dice are paying rent.",
	1000: "$1,000 earned. The economy fears you.",
	5000: "$5,000 earned. Statistically inevitable, still impressive.",
	10000: "$10,000 earned. Consider diversifying into more dice.",
	20000: "$20,000 lifetime earnings. You Won Capitalism.",
}

@export var money_spent_milestones: Dictionary = {
	100: "$100 spent. Investing in yourself.",
	500: "$500 spent. The upgrade shop thanks you.",
	2000: "$2,000 spent. All purchases are final.",
	5000: "$5,000 spent. No refunds!",
	10000: "$10,000 spent. Money can, in fact, buy happiness.",
	18530: "You really just bought everything in the store, didn't you?"
}

## Keys are SECONDS of playtime.
@export var playtime_milestones: Dictionary = {
	60: "One whole minute of playtime.",
	300: "Five minutes. The dice appreciate your company.",
	600: "Ten minutes. Optimal play suggests you're about halfway.",
	1200: "Twenty minutes. Interesting strategic choices were made.",
	1800: "Thirty minutes. The dice aren't going anywhere. Neither are you.",
}

# --- State ------------------------------------------------------------------

var _rng := RandomNumberGenerator.new()
var _recent: Array[int] = []
var _timer: Timer
var _tween: Tween

## category name -> { milestones, thresholds (sorted), next_idx, fired }
var _trackers: Dictionary = {}

# --- Lifecycle --------------------------------------------------------------

func _ready() -> void:
	_rng.randomize()

	_register_tracker("rolls", roll_milestones)
	_register_tracker("busts", bust_milestones)
	_register_tracker("earned", money_earned_milestones)
	_register_tracker("spent", money_spent_milestones)
	_register_tracker("playtime", playtime_milestones)

	_timer = Timer.new()
	_timer.wait_time = rotate_interval
	_timer.one_shot = false
	_timer.timeout.connect(_on_rotate_timeout)
	add_child(_timer)
	_timer.start()

	_apply_text(_pick_random(), false)


func _register_tracker(category: String, milestones: Dictionary) -> void:
	var thresholds: Array = milestones.keys()
	thresholds.sort()
	_trackers[category] = {
		"milestones": milestones,
		"thresholds": thresholds,
		"next_idx": 0,
		"fired": {},  # threshold -> true
	}


func _on_rotate_timeout() -> void:
	_apply_text(_pick_random())

# --- Public API -------------------------------------------------------------

## Interrupt with an event message. Restarts the rotation timer, so the message
## stays up for a full interval before a random one replaces it.
func show_event(message: String) -> void:
	if message.is_empty():
		return
	_apply_text(message)
	if _timer != null:
		_timer.start()  # start() resets the countdown to wait_time


## Feed these the running totals. All safe to call every roll / every frame —
## they early-out unless a new threshold has been crossed.
func on_rolls_changed(total: int) -> void:
	_report("rolls", total)


func on_busts_changed(total: int) -> void:
	_report("busts", total)


func on_money_earned_changed(total: int) -> void:
	_report("earned", total)


func on_money_spent_changed(total: int) -> void:
	_report("spent", total)


func on_playtime_changed(seconds: float) -> void:
	_report("playtime", seconds)


## Force a random reroll now (e.g. if the player clicks the label).
func reroll() -> void:
	_apply_text(_pick_random())
	if _timer != null:
		_timer.start()

# --- Save / load ------------------------------------------------------------

func get_save_data() -> Dictionary:
	var fired_by_category := {}
	for category in _trackers:
		fired_by_category[category] = _trackers[category].fired.keys()
	return {"fired_milestones": fired_by_category}


func load_save_data(data: Dictionary) -> void:
	var fired_by_category: Dictionary = data.get("fired_milestones", {})
	for category in _trackers:
		var tracker: Dictionary = _trackers[category]
		tracker.fired.clear()
		for t in fired_by_category.get(category, []):
			tracker.fired[int(t)] = true
		tracker.next_idx = 0


## Silently mark every milestone at or below the given totals as seen,
## without showing anything. [param totals] maps category name -> total,
## e.g. { "rolls": 120, "busts": 7, "earned": 900, "spent": 300,
## "playtime": 340.0 }. Call on scene entry so already-earned milestones
## don't refire when returning from the menu.
func catch_up_silently(totals: Dictionary) -> void:
	for category in totals:
		if not _trackers.has(category):
			continue
		var tracker: Dictionary = _trackers[category]
		for threshold in tracker.thresholds:
			if totals[category] >= threshold:
				tracker.fired[threshold] = true
		tracker.next_idx = 0

# --- Internals --------------------------------------------------------------

## Core milestone check. Marks every newly-crossed threshold as fired but
## shows only the HIGHEST one (crossing 10/50/100 at once shows just 100).
## If several categories cross a threshold in the same frame, the last
## _report() call wins the label.
func _report(category: String, total: float) -> void:
	var tracker: Dictionary = _trackers[category]
	var newest: String = ""
	while tracker.next_idx < tracker.thresholds.size():
		var threshold: int = tracker.thresholds[tracker.next_idx]
		if total < threshold:
			break
		tracker.next_idx += 1
		if tracker.fired.has(threshold):
			continue  # already awarded (loaded save / catch-up)
		tracker.fired[threshold] = true
		newest = tracker.milestones[threshold]
	if not newest.is_empty():
		show_event(newest)


func _pick_random() -> String:
	if random_splashes.is_empty():
		return ""

	var window: int = clampi(no_repeat_window, 0, random_splashes.size() - 1)

	# Build the eligible set explicitly rather than rejection-sampling, so the
	# cost is bounded even when the window covers almost the whole pool.
	var candidates: Array[int] = []
	for i in random_splashes.size():
		if not _recent.has(i):
			candidates.append(i)
	if candidates.is_empty():
		candidates.append(_rng.randi_range(0, random_splashes.size() - 1))

	var idx: int = candidates[_rng.randi_range(0, candidates.size() - 1)]

	_recent.push_back(idx)
	while _recent.size() > window:
		_recent.pop_front()

	return random_splashes[idx]


## 8 spaces of breathing room on each side of every message.
const _PAD := "        "


func _apply_text(message: String, animate: bool = true) -> void:
	var padded := _PAD + message + _PAD

	if not animate or fade_time <= 0.0:
		text = padded
		modulate.a = 1.0
		return

	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, fade_time)
	_tween.tween_callback(func() -> void: text = padded)
	_tween.tween_property(self, "modulate:a", 1.0, fade_time)
