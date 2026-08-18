class_name InventoryTooltipButton
extends Button


static func safe_item_name(item_id: int) -> String:
	var item_name := ItemRegistry.get_item_name(item_id).strip_edges()
	return item_name if not item_name.is_empty() else "Item"


func _make_custom_tooltip(for_text: String) -> Object:
	if for_text.strip_edges().is_empty():
		return null

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.042, 0.055, 0.96)
	panel_style.border_color = Color(0.30, 0.36, 0.46, 0.95)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 10
	panel_style.content_margin_top = 8
	panel_style.content_margin_right = 10
	panel_style.content_margin_bottom = 8
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	panel_style.shadow_size = 4
	panel.add_theme_stylebox_override("panel", panel_style)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 3)
	panel.add_child(content)

	var first_line_end := for_text.find("\n")
	var title_text := for_text
	var detail_text := ""
	if first_line_end >= 0:
		title_text = for_text.substr(0, first_line_end)
		detail_text = for_text.substr(first_line_end + 1).strip_edges()

	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = title_text
	title.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	title.add_theme_font_size_override("font_size", 16)
	content.add_child(title)

	if not detail_text.is_empty():
		var details := Label.new()
		details.mouse_filter = Control.MOUSE_FILTER_IGNORE
		details.text = detail_text
		details.add_theme_color_override("font_color", Color(0.64, 0.70, 0.80))
		details.add_theme_font_size_override("font_size", 13)
		content.add_child(details)

	return panel
