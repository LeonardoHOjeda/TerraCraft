extends TextureRect

@export var world: World
@export var map_size_blocks: int = 512
@export var pixels_per_sample: int = 2

var image: Image
var image_texture: ImageTexture


func _ready() -> void:
	generate_biome_map()


func generate_biome_map() -> void:
	if world == null:
		return

	var samples := map_size_blocks / pixels_per_sample

	image = Image.create(
		samples,
		samples,
		false,
		Image.FORMAT_RGB8
	)

	var half_size := map_size_blocks / 2

	for px in samples:
		for pz in samples:
			var world_x := px * pixels_per_sample - half_size
			var world_z := pz * pixels_per_sample - half_size

			var biome_value := world.biome_noise.get_noise_2d(
				world_x,
				world_z
			)

			var color := get_biome_color(biome_value)

			image.set_pixel(px, pz, color)

	image_texture = ImageTexture.create_from_image(image)
	texture = image_texture


func get_biome_color(value: float) -> Color:
	if value < -0.25:
		return Color(0.85, 0.75, 0.35)

	if value > 0.35:
		return Color(0.15, 0.35, 0.12)

	return Color(0.35, 0.65, 0.25)