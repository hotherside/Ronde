import importlib.util
import sys
import unittest
from pathlib import Path

from PIL import Image


SOURCE = Path(__file__).with_name("native_point_tracker.py")
SPEC = importlib.util.spec_from_file_location("native_point_tracker", SOURCE)
assert SPEC and SPEC.loader
TRACKER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = TRACKER
SPEC.loader.exec_module(TRACKER)


class NativePointTrackerTests(unittest.TestCase):
    def test_separated_equal_maxima_select_an_actual_raster_pixel_not_their_midpoint(self):
        response = Image.new("L", (16, 12))
        response.putpixel((2, 3), 200)
        response.putpixel((13, 9), 200)

        # Raster order breaks equal-score ties deterministically. Crucially,
        # (7.5, 6) is not returned because it contains no observed maximum.
        self.assertEqual(TRACKER.maximum_pixel(response), (2, 3, 200))


if __name__ == "__main__":
    unittest.main()
