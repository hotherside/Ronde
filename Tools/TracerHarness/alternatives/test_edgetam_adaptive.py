"""Synthetic crop-boundary regression tests; no models or private media used."""
import unittest

from edgetam_adaptive_adapter import gap_continuation_decision, violating_axis_can_recenter


class AdaptiveCropBoundaryTests(unittest.TestCase):
    def test_clamped_top_ignores_one_pixel_drift_on_central_x_axis(self):
        self.assertFalse(violating_axis_can_recenter(
            257, 80, (1000, 0, 512, 512), (1001, 0, 512, 512)))

    def test_horizontal_violation_can_recenter_while_top_is_clamped(self):
        self.assertTrue(violating_axis_can_recenter(
            390, 80, (1000, 0, 512, 512), (1134, 0, 512, 512)))

    def test_vertical_violation_can_recenter(self):
        self.assertTrue(violating_axis_can_recenter(
            256, 390, (1000, 200, 512, 512), (1000, 334, 512, 512)))

    def test_central_point_does_not_recenter(self):
        self.assertFalse(violating_axis_can_recenter(
            256, 256, (1000, 200, 512, 512), (1000, 200, 512, 512)))


class SourceTimeGapTests(unittest.TestCase):
    def test_default_policy_still_stops_on_first_empty(self):
        self.assertFalse(gap_continuation_decision(1.0, 1.03)["continueSameStateAndCrop"])

    def test_exact_boundary_and_reverse_time(self):
        self.assertTrue(gap_continuation_decision(1.0, 1.2, .20)["continueSameStateAndCrop"])
        self.assertTrue(gap_continuation_decision(1.2, 1.0, .20)["continueSameStateAndCrop"])
        self.assertFalse(gap_continuation_decision(1.0, 1.20001, .20)["continueSameStateAndCrop"])

    def test_irregular_source_times_use_elapsed_time_not_frame_count(self):
        decisions = [gap_continuation_decision(2.0, t, .20)["continueSameStateAndCrop"]
                     for t in (2.01, 2.04, 2.199, 2.205)]
        self.assertEqual(decisions, [True, True, True, False])

    def test_empty_decision_never_recentres_or_emits_coordinates(self):
        decision = gap_continuation_decision(1.0, 1.1, .20)
        self.assertTrue(decision["continueSameStateAndCrop"])
        self.assertFalse(decision["recenter"])
        self.assertFalse(decision["emitPoint"])
        self.assertNotIn("x", decision)
        self.assertNotIn("y", decision)

    def test_empty_initial_prompt_has_no_observed_anchor_for_recovery(self):
        self.assertFalse(gap_continuation_decision(None, 1.0, .20)["continueSameStateAndCrop"])


if __name__ == "__main__":
    unittest.main()
