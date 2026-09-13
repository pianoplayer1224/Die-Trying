#!/usr/bin/env python3
"""Die Trying — terminal edition.

Port of the Godot game in die-trying/:
  rules        <- scripts/main.gd
  state        <- scripts/game_state.gd
  splash text  <- scripts/label_splash.gd
  roll anim    <- scripts/dice.gd
  help text    <- scenes/help.tscn

Run:  python3 die_trying.py
"""

import math
import os
import random
import sys
import textwrap
import time
from dataclasses import dataclass, field
from typing import Optional

# =========================================================
# CONFIG — same tables as main.gd. d2 is level 0 and free.
# =========================================================
DICE_TIERS = [
    # (display name, faces, cost)
    ("d2", 2, 0),
    ("d4", 4, 25),
    ("d6", 6, 75),
    ("d8", 8, 200),
    ("d10", 10, 500),
    ("d12", 12, 1200),
    ("d20", 20, 6000),
]

SPEED_LEVELS = [
    # (roll duration in seconds, cost)
    (3.0, 0),
    (2.6, 50),
    (2.2, 100),
    (1.8, 200),
    (1.4, 500),
    (1.0, 1000),
    (0.8, 2000),
    (0.6, 5000),
    (0.4, 8000),
]

MONEY_MULT_LEVELS = [
    # (multiplier, cost)
    (1.0, 0),
    (1.25, 40),
    (1.5, 120),
    (2.0, 300),
    (3.0, 800),
    (4.0, 2000),
]

MATCH_MULT_LEVELS = [
    # (starting multiplier on a double, cost)
    (2.0, 0),
    (3.0, 20),
    (4.0, 50),
    (5.0, 100),
    (6.0, 250),
]

GOAL = 500
BUST_VALUE = 1

# Roll animation (dice.gd): tick_count faces, each delay up to
# `slowdown` times longer than the first, summing to roll_duration.
TICK_COUNT = 12
SLOWDOWN = 6.0

WIDTH = 50
BAR_WIDTH = 20


def _num(v: float) -> str:
    """GDScript String.num(): 2.0 -> "2", 2.6 -> "2.6"."""
    return f"{v:g}"


# Upgrade menu key -> (shop title, menu label, GameState attribute,
# [(display value, cost), ...]). The dice table is normalized to the
# same shape, so one buy() covers buy_die_upgrade() and
# _buy_from_table() from main.gd.
UPGRADES = {
    "2": ("Dice", "Upgrade Dice", "die_level",
          [(name, cost) for name, _faces, cost in DICE_TIERS]),
    "3": ("Speed", "Upgrade Speed", "speed_level",
          [(_num(d) + "s", cost) for d, cost in SPEED_LEVELS]),
    "4": ("Money Mult", "Upgrade Money Mult", "money_mult_level",
          [("x" + _num(m), cost) for m, cost in MONEY_MULT_LEVELS]),
    "5": ("Match Bonus", "Upgrade Match Bonus", "match_mult_level",
          [("x" + _num(m), cost) for m, cost in MATCH_MULT_LEVELS]),
}

# =========================================================
# TEXT — splash pool and milestones from label_splash.gd
# =========================================================
NO_REPEAT_WINDOW = 5

RANDOM_SPLASHES = [
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
    "Simulation for the Nation!",
    "Remember the 3-2-1 Rule for File Backups!",
    "seal",
    "Visit sealnet.xyz",
    "FILTERED.",
    "Mark 83 1,000 lb ballute-type retarded bomb",
    "Decisions, decisions...",
    "sudo rm -rf --no-preserve-root",
    "FROGE BOGEUS",
    "7EAM!",
    "1f986_duck",
    "🦆",
    "Squawk 7700, Contact Guard on 121.5",
    "You are meant to be doing Maths, aren't you?",
    "Imagine having a Fancy Ass Calculator. I bet you don't even use it for Graphing.'",
    "Get the FX-CG100 Graphing Calculator from casio.com for only £139.99! Never mind, it's sold out.",
    "'It is mathematically proven that on average your partner has more partners than you'",
    "'We are two parts of a song. He is the music, and i am the words' -From some book",
    "'If god would have wanted you to win he wouldn't have created me'",

]

MILESTONES = {
    "rolls": {
        10: "Ten rolls. A promising start.",
        50: "Fifty rolls now.",
        100: "One hundred rolls. Hope you're having fun!",
        250: "250 rolls. This is a lifestyle now.",
        500: "500 rolls. Seek help.",
        1000: "1000 rolls. Seek help, urgently.",
        5000: "5000 rolls. Please stop.",
    },
    "busts": {
        1: "Your first wipe. It won't be your last.",
        5: "Five wipes. The die is just being honest.",
        10: "Ten wipes. Have you considered not rolling ones?",
        25: "25 wipes. That's dedication. Or denial.",
        50: "50 wipes. The one is your most loyal face.",
        100: "100 wipes. Damn, you are unlucky.",
    },
    "earned": {
        100: "First $100 earned. Get yourself something nice.",
        500: "$500 lifetime earnings. The dice are paying rent.",
        1000: "$1,000 earned. The economy fears you.",
        5000: "$5,000 earned. Statistically inevitable, still impressive.",
        10000: "$10,000 earned. Consider diversifying into more dice.",
        20000: "$20,000 lifetime earnings. You Won Capitalism.",
    },
    "spent": {
        100: "$100 spent. Investing in yourself.",
        500: "$500 spent. The upgrade shop thanks you.",
        2000: "$2,000 spent. All purchases are final.",
        5000: "$5,000 spent. No refunds!",
        10000: "$10,000 spent. Money can, in fact, buy happiness.",
        28530: "You really just bought everything in the store, didn't you?",
    },
    # Keys are SECONDS of playtime.
    "playtime": {
        60: "One whole minute of playtime.",
        300: "Five minutes. The dice appreciate your company.",
        600: "Ten minutes. Optimal play suggests you're about halfway.",
        1200: "Twenty minutes. Interesting strategic choices were made.",
        1800: "Thirty minutes. The dice aren't going anywhere. Neither are you.",
    },
}

HELP_LINES = [
    "HOW TO PLAY:",
    "Roll the die to progress towards the goal (500) and",
    "earn money equal to the number you roll.",
    "",
    "But, roll a 1 and your progress gets WIPED.",
    "",
    "Roll the same number twice in a row to start a",
    "MATCH STREAK. Each roll in the streak earns bonus",
    "money. The streak ends if you roll a 1, or roll a",
    "different number.",
    "",
    "Upgrade your dice, earn money, and get gambling!",
    "",
    "UPGRADES:",
    "  Dice        - more faces: higher rolls, rarer 1s.",
    "  Speed       - shorter roll animation.",
    "  Money Mult  - multiplies all money earned.",
    "  Match Bonus - raises the streak's starting",
    "                multiplier AND how much each",
    "                extra match adds.",
]

# The "your did it" star from the win sprite, as ASCII.
WIN_ART = [
    "           /\\",
    "          /  \\",
    "_________/    \\_________",
    "\\                      /",
    "  \\                  /",
    "    \\ your did it  /",
    "   /                \\",
    "  /        /\\        \\",
    " /       /    \\       \\",
    "/______/        \\______\\",
]


# =========================================================
# STATE — game_state.gd
# =========================================================
@dataclass
class GameState:
    money: int = 0
    progress: int = 0
    best_run: int = 0

    die_level: int = 0
    speed_level: int = 0
    money_mult_level: int = 0
    match_mult_level: int = 0

    last_roll: int = 0          # 0 = "no previous roll"
    match_length: int = 0
    last_earnings: int = 0

    # Lifetime stats (feed the splash milestones and the win screen).
    total_rolls: int = 0
    bust_count: int = 0
    total_earned: int = 0
    total_spent: int = 0
    start_time: float = field(default_factory=time.monotonic)
    won_at: Optional[float] = None   # set on win; stops the playtime clock

    @property
    def game_won(self) -> bool:
        return self.won_at is not None

    @property
    def playtime(self) -> float:
        end = self.won_at if self.won_at is not None else time.monotonic()
        return end - self.start_time

    def reset(self) -> None:
        """Wipe everything back to a fresh game."""
        self.__dict__.update(vars(GameState()))


# =========================================================
# SPLASH — label_splash.gd, adapted: the terminal only redraws
# after input, so the line rotates per screen instead of every
# 10 seconds. A pending milestone always beats a random line.
# =========================================================
class Splash:
    def __init__(self, rng: Optional[random.Random] = None) -> None:
        self._rng = rng or random.Random()
        self._recent: list = []
        self._pending = ""
        # category -> index of the next threshold not yet crossed.
        # Never rewound, so milestones fire once ever (even after a
        # play-again reset), same as the Godot label.
        self._next_idx = {category: 0 for category in MILESTONES}
        self._thresholds = {c: sorted(m) for c, m in MILESTONES.items()}

    def report(self, category: str, total: float) -> None:
        """Mark every newly-crossed threshold as fired but queue only
        the HIGHEST one. If several categories fire on the same turn,
        the last report() wins."""
        thresholds = self._thresholds[category]
        newest = ""
        while self._next_idx[category] < len(thresholds):
            threshold = thresholds[self._next_idx[category]]
            if total < threshold:
                break
            self._next_idx[category] += 1
            newest = MILESTONES[category][threshold]
        if newest:
            self._pending = newest

    def next(self) -> str:
        if self._pending:
            message, self._pending = self._pending, ""
            return message
        return self._pick_random()

    def _pick_random(self) -> str:
        window = max(0, min(NO_REPEAT_WINDOW, len(RANDOM_SPLASHES) - 1))
        candidates = [i for i in range(len(RANDOM_SPLASHES))
                      if i not in self._recent]
        if not candidates:
            candidates = [self._rng.randrange(len(RANDOM_SPLASHES))]
        idx = self._rng.choice(candidates)
        self._recent.append(idx)
        while len(self._recent) > window:
            self._recent.pop(0)
        return RANDOM_SPLASHES[idx]


# =========================================================
# RULES — main.gd
# =========================================================
def gd_round(x: float) -> int:
    """GDScript round(): halves round away from zero. Python's round()
    is banker's rounding (round(2.5) == 2), which would change payouts."""
    return int(math.floor(abs(x) + 0.5)) * (1 if x >= 0 else -1)


class Game:
    def __init__(self, rng: Optional[random.Random] = None) -> None:
        self.state = GameState()
        self.splash = Splash(rng)
        self.rng = rng or random.Random()

    @property
    def die(self) -> tuple:
        return DICE_TIERS[self.state.die_level]

    @property
    def roll_duration(self) -> float:
        return SPEED_LEVELS[self.state.speed_level][0]

    def match_multiplier(self) -> float:
        s = self.state
        if s.match_length < 2:
            return 1.0
        start = 2.0 + 1.0 * s.match_mult_level
        step = 1.0 + 1.0 * s.match_mult_level
        return start + step * (s.match_length - 2)

    def calculate_earnings(self, value: int) -> int:
        money_mult = MONEY_MULT_LEVELS[self.state.money_mult_level][0]
        return gd_round(value * money_mult * self.match_multiplier())

    def apply_roll(self, value: int) -> bool:
        """Direct port of _apply_roll(). Returns True on win.
        ORDER MATTERS: match_length is updated BEFORE earnings are
        calculated (and reset before earnings on a bust) — this is what
        makes a bust pay out at 1x match multiplier."""
        s = self.state
        if value == BUST_VALUE:
            s.best_run = max(s.best_run, s.progress)
            s.progress = 0
            s.match_length = 0
            s.last_roll = 0
            s.last_earnings = self.calculate_earnings(value)
            s.money += s.last_earnings
            return False

        if s.last_roll == value:
            s.match_length += 1
        else:
            s.match_length = 1
        s.last_roll = value

        s.last_earnings = self.calculate_earnings(value)
        s.money += s.last_earnings

        s.progress += value
        s.best_run = max(s.best_run, s.progress)

        return s.progress >= GOAL

    def on_roll_done(self, value: int) -> list:
        """_on_dice_roll_done(): apply the roll, update lifetime stats and
        milestones, and return the Content lines for this roll."""
        s = self.state
        progress_before = s.progress
        won = self.apply_roll(value)

        s.total_rolls += 1
        s.total_earned += s.last_earnings
        if value == BUST_VALUE:
            s.bust_count += 1
        self.splash.report("rolls", s.total_rolls)
        self.splash.report("earned", s.total_earned)
        self.splash.report("busts", s.bust_count)

        name = self.die[0]
        if value == BUST_VALUE:
            lines = [f"Rolled a 1 on the {name}.  +${s.last_earnings:,}"]
            if progress_before > 0:
                lines.append(f"BUST! Progress wiped (-{progress_before:,}).")
            else:
                lines.append("BUST! ...luckily there was nothing to lose.")
        else:
            lines = [f"Rolled a {value} on the {name}!  "
                     f"+{value} progress, +${s.last_earnings:,}"]
            if s.match_length >= 2:
                lines.append(f"MATCH x{s.match_length} "
                             f"(x{_num(self.match_multiplier())} $)")

        if won:
            s.won_at = time.monotonic()
        return lines

    def buy(self, key: str) -> str:
        """Generic buy for all four upgrades. Returns the shop message."""
        title, _label, attr, rows = UPGRADES[key]
        s = self.state
        level = getattr(s, attr)
        if level + 1 >= len(rows):
            return f"{title} already MAXED ({rows[level][0]})."
        new_value, cost = rows[level + 1]
        if s.money < cost:
            return (f"Not enough money for {title}: need ${cost:,} "
                    f"(you have ${s.money:,}).")
        s.money -= cost
        setattr(s, attr, level + 1)
        s.total_spent += cost
        self.splash.report("spent", s.total_spent)
        return f"{title} upgraded: {rows[level][0]} -> {new_value}  (-${cost:,})"

    def report_playtime(self) -> None:
        self.splash.report("playtime", self.state.playtime)


# =========================================================
# SAVING — same 10-character code as the calculator edition
# =========================================================
# The code format is identical to calc/dtsave.py, so a code from the
# calculator loads here and vice versa. Ten base64 characters, six bits
# each, packed as a bit stream:
#   levels 11 | progress 9 | money 16 | rolls 13 | wipes 11 = 60 bits
# Spending is the sum of the costs of the levels owned and earnings are
# money + spending, so neither is stored. There is no room for a
# checksum; loads are sanity-checked instead (levels in range, wipes no
# greater than rolls, no money before the first roll).
#
# Unlike the calculator, this version can write files, so it also
# auto-saves to SAVE_FILE and resumes from it without any typing. The
# file keeps playtime and best run too, which do not fit in the code.
ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-."
WIDTHS = [11, 9, 16, 13, 11]
LIMITS = [1889, 511, 65535, 8191, 2047]
CODE_LEN = 10
SAVE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "die_trying.save")


def _emit(vals: list, widths: list) -> str:
    out = ""
    acc = n = 0
    for value, width in zip(vals, widths):
        acc = (acc << width) | value
        n += width
        while n >= 6:
            n -= 6
            out += ALPHABET[(acc >> n) & 63]
            acc &= (1 << n) - 1
    if n:
        out += ALPHABET[(acc << (6 - n)) & 63]
    return out


def _read(s: str, widths: list):
    """Field values, or None if a character is not in the alphabet."""
    vals, acc, n, pos = [], 0, 0, 0
    for width in widths:
        while n < width:
            if pos >= len(s):
                return None
            i = ALPHABET.find(s[pos])
            if i < 0:
                return None
            pos += 1
            acc = (acc << 6) | i
            n += 6
        n -= width
        vals.append((acc >> n) & ((1 << width) - 1))
        acc &= (1 << n) - 1
    return vals


def _clamp(v: int, hi: int) -> int:
    return 0 if v < 0 else min(v, hi)


def grouped(code: str) -> str:
    """Two blocks of five: easier to read out and type back."""
    return code[:5] + " " + code[5:]


def spent_from_levels(state: GameState) -> int:
    """Every purchase is recorded in the levels, so spending is derivable."""
    total = 0
    for _title, _label, attr, rows in UPGRADES.values():
        for i in range(getattr(state, attr) + 1):
            total += rows[i][1]
    return total


def save_code(state: GameState) -> str:
    levels = ((state.die_level * 9 + state.speed_level) * 6
              + state.money_mult_level) * 5 + state.match_mult_level
    vals = [levels, state.progress, state.money,
            state.total_rolls, state.bust_count]
    return _emit([_clamp(v, hi) for v, hi in zip(vals, LIMITS)], WIDTHS)


def load_code(game: "Game", s: str) -> bool:
    """Validate everything before writing anything, so a bad code leaves
    the game untouched instead of half-loaded."""
    s = s.strip().replace(" ", "")        # tolerates the grouped form
    if len(s) != CODE_LEN:
        return False
    vals = _read(s, WIDTHS)
    if vals is None or vals[0] > LIMITS[0]:
        return False
    if vals[4] > vals[3]:                 # more wipes than rolls
        return False
    if vals[3] == 0 and (vals[1] or vals[2]):   # money before rolling
        return False
    state = game.state
    state.reset()
    levels = vals[0]
    state.match_mult_level = levels % 5
    levels //= 5
    state.money_mult_level = levels % 6
    levels //= 6
    state.speed_level = levels % 9
    state.die_level = levels // 9
    state.progress, state.money = vals[1], vals[2]
    state.total_rolls, state.bust_count = vals[3], vals[4]
    state.best_run = state.progress
    state.total_spent = spent_from_levels(state)
    state.total_earned = state.money + state.total_spent
    for name, total in (("rolls", state.total_rolls),
                        ("busts", state.bust_count),
                        ("earned", state.total_earned),
                        ("spent", state.total_spent)):
        game.splash.report(name, total)   # mark milestones as seen...
    game.splash._pending = ""             # ...without showing them again
    return True


def save_file(game: "Game") -> bool:
    """Code plus the two things it has no room for: playtime and best run."""
    try:
        with open(SAVE_FILE, "w") as f:
            f.write("%s %.1f %d\n" % (save_code(game.state),
                                      game.state.playtime, game.state.best_run))
        return True
    except OSError:
        return False


def load_file(game: "Game") -> bool:
    try:
        with open(SAVE_FILE) as f:
            parts = f.read().split()
    except OSError:
        return False
    if not parts or not load_code(game, parts[0]):
        return False
    if len(parts) > 2:
        try:
            # Shift the clock back so playtime carries on where it left off.
            game.state.start_time = time.monotonic() - float(parts[1])
            game.state.best_run = max(game.state.best_run, int(parts[2]))
        except ValueError:
            pass
    return True


def boot_load(game: "Game") -> str:
    """Returns the first line to show. The save file wins; otherwise offer
    to take a code typed in (a calculator code works here)."""
    if load_file(game):
        return "Save loaded."
    try:
        code = input("Save code (Enter for a new game): ").strip()
    except (EOFError, KeyboardInterrupt):
        return "Welcome to DIE TRYING."
    if not code:
        return "Welcome to DIE TRYING."
    if load_code(game, code):
        save_file(game)
        return "Save code loaded."
    return "Code not recognised - starting a new game."


# =========================================================
# ROLL ANIMATION — dice.gd
# =========================================================
def build_delays(duration: float, tick_count: int = TICK_COUNT,
                 slowdown: float = SLOWDOWN) -> list:
    weights = []
    for i in range(tick_count):
        t = 0.0 if tick_count <= 1 else i / (tick_count - 1)
        weights.append(1.0 + (slowdown - 1.0) * t)
    total = sum(weights)
    return [duration * w / total for w in weights]


def animate_roll(name: str, faces: int, duration: float,
                 rng: random.Random) -> int:
    """Flicker random faces in place, slowing down; the last one shown
    is the result (uniform, same as dice.gd)."""
    face = 1
    for delay in build_delays(duration):
        face = rng.randint(1, faces)
        sys.stdout.write(f"\r  Rolling {name}...  [ {face:>2} ]")
        sys.stdout.flush()
        time.sleep(delay)
    sys.stdout.write("\n")
    return face


# =========================================================
# UI
# =========================================================
def _clear_screen() -> None:
    # Only when drawing to a real terminal — keeps piped output clean.
    if sys.stdout.isatty():
        sys.stdout.write("\033[2J\033[H")


def _progress_bar(progress: int) -> str:
    filled = min(BAR_WIDTH, progress * BAR_WIDTH // GOAL)
    return "[" + "#" * filled + "-" * (BAR_WIDTH - filled) + "]"


def render(splash_line: str, content: list, state: GameState) -> None:
    _clear_screen()
    out = ["=" * WIDTH]
    out += [line.center(WIDTH).rstrip()
            for line in textwrap.wrap(splash_line, WIDTH) or [""]]
    out += ["-" * WIDTH]
    out += content or [""]
    out += [
        "-" * WIDTH,
        f"Money:    ${state.money:,}",
        f"Progress: {state.progress} / {GOAL}  {_progress_bar(state.progress)}",
        "=" * WIDTH,
    ]
    print("\n".join(out))


def menu_lines(game: Game) -> list:
    s = game.state
    lines = [f"1. Roll ({game.die[0]})"]
    for key, (_title, label, attr, rows) in UPGRADES.items():
        level = getattr(s, attr)
        if level + 1 >= len(rows):
            lines.append(f"{key}. {label} ({rows[level][0]}) MAXED")
            continue
        new_value, cost = rows[level + 1]
        lines.append(f"{key}. {label} ({rows[level][0]} -> {new_value})  ${cost:,}")
    lines += ["6. Help", "", "0. Exit"]
    return lines


def _format_time(seconds: float) -> str:
    minutes, secs = divmod(int(seconds), 60)
    return f"{minutes}:{secs:02d}"


def win_screen(game: Game) -> bool:
    """Show the win screen. Returns True to play again, False to quit."""
    s = game.state
    pad = " " * ((WIDTH - max(len(row) for row in WIN_ART)) // 2)
    content = [pad + row for row in WIN_ART]
    content += [
        "",
        f"You reached {s.progress} / {GOAL}!",
        f"  Rolls:        {s.total_rolls:,}",
        f"  Wipes:        {s.bust_count:,}",
        f"  Money earned: ${s.total_earned:,}",
        f"  Money spent:  ${s.total_spent:,}",
        f"  Playtime:     {_format_time(s.playtime)}",
    ]
    render(game.splash.next(), content, s)
    while True:
        answer = input("Play again? (y/n) > ").strip().lower()
        if answer in ("y", "yes"):
            s.reset()
            return True
        if answer in ("n", "no"):
            return False


def _setup_terminal() -> None:
    if os.name == "nt":
        os.system("")  # turns on ANSI escape handling in the Windows console
    try:
        # Don't crash on the 🦆 splash in a non-UTF-8 console.
        sys.stdout.reconfigure(errors="replace")
    except (AttributeError, ValueError):
        pass


def main(game: Optional[Game] = None) -> None:
    _setup_terminal()
    fresh = game is None      # a caller-supplied game is already set up
    game = game or Game()
    content = [
        "Welcome to DIE TRYING.",
        f"Reach the goal ({GOAL}) or... die trying.",
        "Pick 1 to roll, 6 for help.",
    ]
    if fresh:
        content[0] = boot_load(game)
    try:
        while True:
            render(game.splash.next(), content, game.state)
            print("\n".join(menu_lines(game)))
            choice = input("> ").strip()
            game.report_playtime()

            if choice == "0":
                break
            elif choice == "1":
                name, faces, _cost = game.die
                value = animate_roll(name, faces, game.roll_duration, game.rng)
                content = game.on_roll_done(value)
                save_file(game)
                if game.state.game_won:
                    if not win_screen(game):
                        break
                    save_file(game)      # the replay starts from scratch
                    content = ["New game started. Good luck!"]
            elif choice in UPGRADES:
                content = [game.buy(choice)]
                save_file(game)
            elif choice == "6":
                # Help is also where the transferable save code lives, so
                # the menu itself stays as it is.
                content = HELP_LINES + [
                    "",
                    "Save code:  " + grouped(save_code(game.state)),
                    "(also saved automatically to die_trying.save)",
                ]
            else:
                content = [f"Invalid input: {choice!r}. Pick 0-6."]
    except (KeyboardInterrupt, EOFError):
        print()


if __name__ == "__main__":
    main()
