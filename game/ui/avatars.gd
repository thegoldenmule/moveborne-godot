class_name MbAvatars
extends RefCounted

## The preset avatar set: 12 occult-arcade skull glyphs generated via the artgen
## pipeline (icon-flat, violet line art on black, background stripped) and saved
## into res://assets/generated/icons/. The Profiles snap stores only an avatar_id
## string (the filename stem); this catalog maps it to the local texture, so there
## is no image upload/storage path. An unknown/empty id renders the default sigil.

const DIR := "res://assets/generated/icons/"

const IDS: Array[String] = [
	"skull_avatar_01", "skull_avatar_02", "skull_avatar_03", "skull_avatar_04",
	"skull_avatar_05", "skull_avatar_06", "skull_avatar_07", "skull_avatar_08",
	"skull_avatar_09", "skull_avatar_10", "skull_avatar_11", "skull_avatar_12",
]


## The default avatar_id used when a profile has none yet.
static func default_id() -> String:
	return IDS[0]


## Normalize an arbitrary stored avatar_id to a known one (default sigil if the
## id is empty or no longer in the set).
static func resolve_id(avatar_id: String) -> String:
	return avatar_id if IDS.has(avatar_id) else default_id()


## Texture for an avatar_id, or null if it can't be loaded (caller draws a
## fallback). Resolves unknown/empty ids to the default first.
static func texture(avatar_id: String) -> Texture2D:
	# A GenTexture ref (.tres) — a drop-in Texture2D over the pooled, scalable SVG.
	var path := DIR + resolve_id(avatar_id) + ".tres"
	if ResourceLoader.exists(path):
		return load(path)
	return null
