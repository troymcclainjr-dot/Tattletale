"""Source contracts that can run without launching Godot.

Runtime storage and input assertions live in city_player_phone_smoke_runner.gd.
These checks cover integration omissions and accidental external export surfaces.
"""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
PHONE = ROOT / "godot/scripts/city/city_player_phone.gd"
GALLERY = ROOT / "godot/scripts/city/city_phone_gallery.gd"
PHONE_UI = ROOT / "godot/scripts/city/city_phone_ui.gd"
CONTEXT = ROOT / "godot/scripts/city/city_photo_context.gd"
ICONS = ROOT / "godot/scripts/city/city_ui_icons.gd"
MINIMAP = ROOT / "godot/scripts/city/city_minimap.gd"
OVERLAY = ROOT / "godot/scripts/city/city_map_overlay.gd"
GEOMETRY = ROOT / "godot/scripts/city/city_map_geometry.gd"


class PhoneSourceContract(unittest.TestCase):
    def test_phone_has_no_external_export_surface(self):
        source = "".join(p.read_text(encoding="utf-8") for p in (PHONE, GALLERY, PHONE_UI, CONTEXT))
        for forbidden in ("OS.shell_open", "OS.execute", "clipboard_set", "globalize_path", "user://photos"):
            self.assertNotIn(forbidden, source)
        self.assertIn('const DIRECTORY := "user://phone_gallery"', source)

    def test_contacts_resolve_existing_authored_people(self):
        data = json.loads((ROOT / "godot/assets/data/pen_lucy_residents.json").read_text(encoding="utf-8"))
        residents = data["residents"]
        self.assertEqual(len(residents), 40)
        self.assertEqual(len({p["id"] for p in residents}), len(residents))
        for person in residents:
            self.assertTrue(person["name"])
            self.assertTrue(person["street"])
        self.assertIn('res://assets/data/pen_lucy_residents.json', PHONE.read_text(encoding="utf-8"))

    def test_referenced_scripts_exist(self):
        for path in (PHONE, GALLERY, PHONE_UI, CONTEXT, ICONS, MINIMAP, OVERLAY, GEOMETRY):
            source = path.read_text(encoding="utf-8")
            for relative in re.findall(r'(?:preload|load)\("res://([^\"]+)"\)', source):
                self.assertTrue((ROOT / "godot" / relative).is_file(), relative)

    def test_inspector_debug_capture_remains_separate(self):
        source = PHONE.read_text(encoding="utf-8")
        self.assertNotIn("KEY_F8", source)
        inspector = (ROOT / "godot/scripts/city/city_inspector.gd").read_text(encoding="utf-8")
        self.assertIn("KEY_F8", inspector)

    def test_phone_retains_world_only_exposure_and_prop(self):
        source = PHONE.read_text(encoding="utf-8")
        self.assertIn("camera.cull_mask = source.cull_mask & ~VIEWMODEL_LAYER", source)
        self.assertIn('"HeldPhoneAndHand"', source)
        self.assertIn("await RenderingServer.frame_post_draw", source)

    def test_pointer_writes_are_guarded_for_validation(self):
        source = PHONE.read_text(encoding="utf-8")
        writes = re.findall(r"^\s*Input\.mouse_mode\s*=(?!=).*$", source, re.MULTILINE)
        self.assertEqual(len(writes), 1, "all pointer changes must pass through the guard")
        guard = source.split("func _set_pointer_mode(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn('DisplayServer.get_name() == "headless"', guard)
        self.assertIn('level.get("offscreen_validation")', guard)
        self.assertLess(guard.index("return"), guard.index("Input.mouse_mode = mode"))
        for path in (PHONE_UI, CONTEXT, ICONS):
            self.assertNotIn("Input.mouse_mode", path.read_text(encoding="utf-8"))

    def test_trusted_photo_hook_is_emitted_only_after_storage(self):
        source = PHONE.read_text(encoding="utf-8")
        self.assertIn("signal photo_captured(context: Dictionary)", source)
        for method in ("func register_photo_subject_provider(", "func unregister_photo_subject_provider(", "func get_photo_context("):
            self.assertIn(method, source)
        self.assertEqual(source.count("photo_captured.emit("), 1)
        commit = source.split("func commit_photo(", 1)[1].split("\nfunc ", 1)[0]
        self.assertLess(commit.index("if bool(result.ok)"), commit.index("photo_captured.emit("))
        capture = source.split("func _capture(", 1)[1].split("\nfunc ", 1)[0]
        # Subjects are resolved from the live pose before the GPU readback.
        self.assertLess(capture.index("build_photo_context()"), capture.index("await RenderingServer.frame_post_draw"))
        stored = source.split("func get_photo_context(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn('copy["trusted"] = false', stored)

    def test_photo_context_uses_world_queries_not_pixels(self):
        source = CONTEXT.read_text(encoding="utf-8")
        self.assertIn("intersect_ray", source)
        self.assertIn("is_position_behind", source)
        for forbidden in ("get_image", "get_texture", "Image."):
            self.assertNotIn(forbidden, source)
        for bound in ("MAX_SUBJECTS", "MAX_RAYS", "MAX_CANDIDATES"):
            self.assertRegex(source, rf"const {bound} := \d+")

    def test_phone_keeps_modal_keys(self):
        source = PHONE.read_text(encoding="utf-8")
        handler = source.split("func handle_input(", 1)[1].split("\nfunc ", 1)[0]
        for key in ("KEY_P", "KEY_1", "KEY_2", "KEY_3", "KEY_4", "KEY_5", "KEY_ENTER", "KEY_ESCAPE", "KEY_BACKSPACE", "KEY_F5", "KEY_M", "KEY_F6"):
            self.assertIn(key, handler)
        self.assertNotIn("get_tree().paused =", source, "the world keeps simulating while the phone is up")
        self.assertNotIn("Time.get_datetime_string_from_system(", source.split("func game_clock(", 1)[1].split("\nfunc ", 1)[0])


class MapSourceContract(unittest.TestCase):
    def test_symbols_are_vector_shapes_not_glyphs(self):
        icons = ICONS.read_text(encoding="utf-8")
        for forbidden in ("draw_string", "Font", "load(", "Texture"):
            self.assertNotIn(forbidden, icons)
        self.assertIn("canvas_item_add_triangle_array", icons)
        minimap = MINIMAP.read_text(encoding="utf-8")
        self.assertNotIn("fallback_font", minimap)
        self.assertNotIn("↑", minimap)
        self.assertNotIn("draw_circle(", minimap, "map symbols go through the shared triangle batch")

    def test_place_names_are_not_drawn_per_place(self):
        draw = MINIMAP.read_text(encoding="utf-8").split("func _draw(", 1)[1].split("\nfunc ", 1)[0]
        captions = re.findall(r"_caption\(", draw)
        self.assertLessEqual(len(captions), 2, "only the hover/selection name and inspector camera tag")
        self.assertNotIn('business.get("name"', draw)
        self.assertNotIn('"DESTINATION"', draw)

    def test_courts_are_muted_blue_green_and_batching_stays(self):
        geometry = GEOMETRY.read_text(encoding="utf-8")
        self.assertNotIn("a18745", geometry)
        self.assertIn("Icons.SPORTS_COURT", geometry)
        for retained in ("_batch_polygons(buildings)", "_batch_polygons(courts)", "draw_mesh("):
            self.assertIn(retained, geometry)
        overlay = OVERLAY.read_text(encoding="utf-8")
        self.assertNotIn("Ochre", overlay)
        self.assertIn("Sports court", overlay)


if __name__ == "__main__":
    unittest.main(verbosity=2)
