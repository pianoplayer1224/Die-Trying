# splash.gd — script for the ROOT (CanvasLayer) of splash.tscn.
#
# splash.tscn is registered as an AUTOLOAD named "Splash"
# (Project Settings > Globals > Autoload — autoloads can be scenes,
# not just scripts). Because it lives under /root instead of inside
# the current scene, the label survives every change_scene_to_file():
# the rotation timer keeps counting and the current message stays up
# across menu <-> game transitions.
#
# CanvasLayer with layer = 1 is what keeps it VISIBLE everywhere:
# autoloads sit before the current scene in the tree, so without the
# layer bump any scene with an opaque background would draw on top
# of the label.

extends CanvasLayer

@onready var label: SplashLabel = $SplashLabel
