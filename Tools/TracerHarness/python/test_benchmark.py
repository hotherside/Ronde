import math
import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))

from benchmark import ValidationError, score  # noqa: E402


def reference(frames, *, width=1000, height=1000):
    return {
        "schemaVersion": "1.0",
        "clipId": "synthetic-test",
        "sourceHash": "sha256:synthetic-test",
        "width": width,
        "height": height,
        "coordinateOrigin": "top-left",
        "coordinateSpace": "normalized",
        "frames": frames,
    }


def prediction(frames, *, candidates=None, mode="automatic", prompts=0, corrections=0, width=1000, height=1000):
    payload = {
        "schemaVersion": "1.0",
        "clipId": "synthetic-test",
        "sourceHash": "sha256:synthetic-test",
        "width": width,
        "height": height,
        "coordinateOrigin": "top-left",
        "coordinateSpace": "normalized",
        "mode": mode,
        "promptCount": prompts,
        "correctionCount": corrections,
        "frames": frames,
    }
    if candidates is not None:
        payload["candidates"] = candidates
    return payload


class BenchmarkScoringTests(unittest.TestCase):
    def test_provenance_visibility_absent_and_uncertain_are_separate(self):
        labels = reference(
            [
                {"timestamp": 0.0, "visibility": "not_launched", "reviewStatus": "human-verified"},
                {"timestamp": 0.1, "x": 0.20, "y": 0.20, "visibility": "visible", "reviewStatus": "human-verified", "uncertaintyPx": 2},
                {"timestamp": 0.2, "x": 0.40, "y": 0.40, "visibility": "visible", "reviewStatus": "agent-reviewed", "uncertaintyPx": 4},
                {"timestamp": 0.3, "visibility": "occluded", "reviewStatus": "agent-reviewed"},
                {"timestamp": 0.4, "x": 0.60, "y": 0.60, "visibility": "visible", "reviewStatus": "proposal"},
                {"timestamp": 0.5, "visibility": "uncertain", "reviewStatus": "proposal"},
                {"timestamp": 0.8, "x": 0.70, "y": 0.70, "visibility": "visible", "reviewStatus": "unreviewed"},
                {"timestamp": 1.4, "x": 0.75, "y": 0.75, "visibility": "visible", "reviewStatus": "unreviewed"},
                {"timestamp": 1.6, "x": 0.80, "y": 0.80, "visibility": "visible", "reviewStatus": "human-verified"},
            ]
        )
        predictions = prediction(
            [
                {"timestamp": 0.001, "x": 0.01, "y": 0.01},  # explicit not-launched false prediction
                {"timestamp": 0.101, "x": 0.20, "y": 0.20},
                {"timestamp": 0.201, "x": 0.405, "y": 0.40},
                {"timestamp": 0.301, "x": 0.01, "y": 0.01},  # explicit occluded false prediction
                {"timestamp": 0.501, "x": 0.01, "y": 0.01},  # uncertain must be excluded
                {"timestamp": 1.601, "x": 0.80, "y": 0.80},
            ],
            mode="assisted",
            prompts=2,
            corrections=1,
        )
        report = score(labels, predictions, tolerance_ms=5, hit_tolerance_px=10)

        self.assertEqual(report["prediction"], {"mode": "assisted", "promptCount": 2, "correctionCount": 1})
        self.assertEqual(report["visible"]["matchedVisibleFrames"], 3)
        self.assertAlmostEqual(report["visible"]["coverage"]["overallVisible"], 3 / 6)
        self.assertEqual(report["visible"]["coverage"]["reviewedSubset"], 1.0)
        self.assertEqual(report["visible"]["missingVisibleFrames"], 3)
        self.assertAlmostEqual(report["visible"]["longestMissingInterval"]["durationSeconds"], 0.6)
        self.assertEqual(
            report["visible"]["localisationHitsWithinTolerance"]["absolutePixelTolerance"]["coverageReviewedVisible"], 1.0
        )
        self.assertEqual(report["visible"]["onTimeButWrong"]["absolutePixelTolerance"]["count"], 0)
        self.assertEqual(report["explicitAbsent"]["falsePredictions"], 2)
        self.assertEqual(report["explicitAbsent"]["uncertainFramesExcluded"], 1)
        self.assertEqual(report["referenceProvenance"]["statusCounts"]["human-verified"], 3)

    def test_matching_uses_source_pts_and_does_not_interpolate_across_gap(self):
        labels = reference(
            [
                {"timestamp": 0.0, "x": 0.1, "y": 0.1, "visibility": "visible", "reviewStatus": "human-verified"},
                {"timestamp": 0.5, "x": 0.2, "y": 0.2, "visibility": "visible", "reviewStatus": "human-verified"},
                {"timestamp": 1.5, "x": 0.3, "y": 0.3, "visibility": "visible", "reviewStatus": "human-verified"},
            ]
        )
        predictions = prediction(
            [
                {"timestamp": 0.001, "x": 0.1, "y": 0.1},
                {"timestamp": 1.501, "x": 0.3, "y": 0.3},
            ]
        )
        report = score(labels, predictions, tolerance_ms=10, hit_tolerance_px=1)
        self.assertEqual(report["matching"]["interpolation"], False)
        self.assertEqual(report["visible"]["matchedVisibleFrames"], 2)
        self.assertAlmostEqual(
            report["visible"]["localisationHitsWithinTolerance"]["absolutePixelTolerance"]["coverageReviewedVisible"], 2 / 3
        )
        self.assertEqual(report["visible"]["onTimeButWrong"]["absolutePixelTolerance"]["count"], 0)
        self.assertAlmostEqual(report["visible"]["longestMissingInterval"]["durationSeconds"], 0.0)

    def test_matching_maximises_monotonic_cardinality_before_timestamp_nearness(self):
        labels = reference(
            [
                {"timestamp": 0.000, "x": 0.1, "y": 0.1, "visibility": "visible", "reviewStatus": "agent-reviewed"},
                {"timestamp": 0.010, "x": 0.2, "y": 0.2, "visibility": "visible", "reviewStatus": "agent-reviewed"},
            ]
        )
        predictions = prediction(
            [
                {"timestamp": 0.009, "x": 0.1, "y": 0.1},
                {"timestamp": 0.020, "x": 0.2, "y": 0.2},
            ]
        )
        report = score(labels, predictions, tolerance_ms=15, hit_tolerance_px=1)
        self.assertEqual(report["matching"]["matchedReferenceFrames"], 2)
        self.assertEqual(report["visible"]["matchedVisibleFrames"], 2)
        self.assertEqual(report["matching"]["unmatchedPredictionFrames"], 0)

    def test_duplicate_candidate_groups_keep_monotonic_coverage_and_best_spatial_point(self):
        labels = reference(
            [
                {"timestamp": 0.000, "x": 0.1, "y": 0.1, "visibility": "visible", "reviewStatus": "agent-reviewed"},
                {"timestamp": 0.010, "x": 0.2, "y": 0.2, "visibility": "visible", "reviewStatus": "agent-reviewed"},
            ]
        )
        predictions = prediction(
            [{"timestamp": 0.000, "x": 0.1, "y": 0.1}, {"timestamp": 0.010, "x": 0.2, "y": 0.2}],
            candidates=[
                {"timestamp": 0.009, "x": 0.9, "y": 0.9},
                {"timestamp": 0.009, "x": 0.1, "y": 0.1},
                {"timestamp": 0.020, "x": 0.2, "y": 0.2},
            ],
        )
        report = score(labels, predictions, tolerance_ms=15, hit_tolerance_px=1)
        self.assertEqual(report["candidateRecall"]["matchedCandidateFrames"], 2)
        self.assertEqual(report["candidateRecall"]["candidateHits"], 2)
        self.assertEqual(report["candidateRecall"]["eligibleVisibleFrames"], 2)

    def test_non_visible_labels_break_missing_runs(self):
        labels = reference(
            [
                {"timestamp": 0.0, "x": 0.1, "y": 0.1, "visibility": "visible", "reviewStatus": "agent-reviewed"},
                {"timestamp": 0.033, "x": 0.2, "y": 0.2, "visibility": "visible", "reviewStatus": "agent-reviewed"},
                {"timestamp": 0.067, "visibility": "uncertain", "reviewStatus": "agent-reviewed"},
                {"timestamp": 2.0, "x": 0.3, "y": 0.3, "visibility": "visible", "reviewStatus": "agent-reviewed"},
            ]
        )
        report = score(labels, prediction([]), tolerance_ms=1, hit_tolerance_px=5)
        self.assertAlmostEqual(report["visible"]["longestMissingInterval"]["durationSeconds"], 0.033)
        self.assertEqual(report["visible"]["longestMissingInterval"]["frameCount"], 2)
        self.assertEqual(report["visible"]["longestWrongLocalisationInterval"]["absolutePixelTolerance"], None)

    def test_uncertainty_aware_hit_can_differ_from_absolute_tolerance(self):
        labels = reference(
            [{"timestamp": 2.0, "x": 0.50, "y": 0.50, "visibility": "visible", "reviewStatus": "agent-reviewed", "uncertaintyPx": 20}]
        )
        predictions = prediction([{"timestamp": 2.001, "x": 0.515, "y": 0.50}])
        report = score(labels, predictions, tolerance_ms=5, hit_tolerance_px=10)
        hits = report["visible"]["localisationHitsWithinTolerance"]
        self.assertEqual(hits["absolutePixelTolerance"]["hits"], 0)
        self.assertEqual(hits["uncertaintyAware"]["hits"], 1)
        self.assertEqual(hits["absolutePixelTolerance"]["coverageReviewedVisible"], 0.0)
        self.assertEqual(hits["uncertaintyAware"]["coverageReviewedVisible"], 1.0)
        self.assertEqual(hits["uncertaintyAware"]["acceptedOnlyByUncertainty"], 1)
        self.assertEqual(report["visible"]["onTimeButWrong"]["absolutePixelTolerance"]["count"], 1)
        self.assertEqual(report["visible"]["onTimeButWrong"]["uncertaintyAware"]["count"], 0)
        self.assertEqual(report["visible"]["longestWrongLocalisationInterval"]["absolutePixelTolerance"]["frameCount"], 1)
        self.assertEqual(report["visible"]["longestWrongLocalisationInterval"]["uncertaintyAware"], None)
        self.assertAlmostEqual(report["visible"]["errorsPx"]["medianPx"], 15)

    def test_optional_candidates_report_recall_without_changing_final_track(self):
        labels = reference(
            [
                {"timestamp": 0.0, "x": 0.1, "y": 0.1, "visibility": "visible", "reviewStatus": "agent-reviewed"},
                {"timestamp": 0.1, "x": 0.2, "y": 0.2, "visibility": "visible", "reviewStatus": "agent-reviewed"},
            ]
        )
        predictions = prediction(
            [{"timestamp": 0.0, "x": 0.1, "y": 0.1}],
            candidates=[{"timestamp": 0.0, "x": 0.1, "y": 0.1}, {"timestamp": 0.1, "x": 0.9, "y": 0.9}],
        )
        report = score(labels, predictions, tolerance_ms=1, hit_tolerance_px=5)
        self.assertTrue(report["candidateRecall"]["available"])
        self.assertEqual(report["candidateRecall"]["candidateHits"], 1)
        self.assertEqual(report["candidateRecall"]["eligibleVisibleFrames"], 2)

    def test_candidate_recall_uses_best_candidate_at_a_timestamp(self):
        labels = reference(
            [{"timestamp": 0.0, "x": 0.25, "y": 0.25, "visibility": "visible", "reviewStatus": "agent-reviewed"}]
        )
        predictions = prediction(
            [{"timestamp": 0.0, "x": 0.90, "y": 0.90}],
            candidates=[
                {"timestamp": 0.0, "x": 0.90, "y": 0.90},
                {"timestamp": 0.0, "x": 0.25, "y": 0.25},
            ],
        )
        report = score(labels, predictions, tolerance_ms=1, hit_tolerance_px=5)
        self.assertEqual(report["visible"]["matchedVisibleFrames"], 1)
        self.assertEqual(report["candidateRecall"]["matchedCandidateFrames"], 1)
        self.assertEqual(report["candidateRecall"]["candidateHits"], 1)

    def test_nan_and_non_monotonic_source_pts_are_rejected(self):
        labels = reference([{"timestamp": float("nan"), "x": 0.1, "y": 0.1, "visibility": "visible", "reviewStatus": "human-verified"}])
        with self.assertRaises(ValidationError):
            score(labels, prediction([]))

        valid_labels = reference(
            [{"timestamp": 1.0, "x": 0.1, "y": 0.1, "visibility": "visible", "reviewStatus": "human-verified"}]
        )
        duplicate_prediction = prediction(
            [
                {"timestamp": 1.0, "x": 0.1, "y": 0.1},
                {"timestamp": 1.0, "x": 0.1, "y": 0.1},
            ]
        )
        with self.assertRaises(ValidationError):
            score(valid_labels, duplicate_prediction)

        wrong_source = prediction([{"timestamp": 1.0, "x": 0.1, "y": 0.1}])
        wrong_source["sourceHash"] = "sha256:different-source"
        with self.assertRaises(ValidationError):
            score(valid_labels, wrong_source)

        with self.assertRaises(ValidationError):
            score(
                valid_labels,
                prediction(
                    [{"timestamp": 0.2, "x": 0.1, "y": 0.1}],
                    candidates=[{"timestamp": 0.3, "x": 0.1, "y": 0.1}, {"timestamp": 0.1, "x": 0.1, "y": 0.1}],
                ),
            )

        labels = reference(
            [
                {"timestamp": 1.0, "x": 0.1, "y": 0.1, "visibility": "visible", "reviewStatus": "human-verified"},
                {"timestamp": 1.0, "x": 0.2, "y": 0.2, "visibility": "visible", "reviewStatus": "human-verified"},
            ]
        )
        with self.assertRaises(ValidationError):
            score(labels, prediction([]))

    def test_pixel_error_uses_source_dimensions(self):
        labels = reference(
            [{"timestamp": 0.0, "x": 0.5, "y": 0.5, "visibility": "visible", "reviewStatus": "human-verified"}],
            width=200,
            height=100,
        )
        predictions = prediction([{"timestamp": 0.0, "x": 0.55, "y": 0.6}], width=200, height=100)
        report = score(labels, predictions, tolerance_ms=0, hit_tolerance_px=14.15)
        self.assertTrue(math.isclose(report["visible"]["errorsPx"]["maxPx"], math.hypot(10, 10)))
        self.assertEqual(report["visible"]["localisationHitsWithinTolerance"]["absolutePixelTolerance"]["hits"], 1)

    def test_prediction_report_preserves_allowlisted_provenance_only(self):
        labels = reference(
            [{"timestamp": 0.0, "x": 0.1, "y": 0.1, "visibility": "visible", "reviewStatus": "agent-reviewed"}]
        )
        predictions = prediction([{"timestamp": 0.0, "x": 0.1, "y": 0.1}])
        predictions.update(
            {
                "sourceRevision": "7a6bd012",
                "sourceHashes": {"Swift/Tracker.swift": "e" * 64},
                "modelSHA256": "a" * 64,
                "modelHashScope": "specification-only",
                "sourceModelBundleSHA256": "b" * 64,
                "sourceModelWeightSHA256": "c" * 64,
                "variant": "controlled-impact::daylight",
                "replay": {
                    "algorithm": "seeded-candidate-replay",
                    "codeSHA256": "d" * 64,
                    "candidatePoolSHA256": "e" * 64,
                    "privatePath": "/private/review/replay.json",
                },
                "assistance": {
                    "pointSeed": {"x": 0.3, "y": 0.4},
                    "privatePath": "/private/review/assistance.json",
                },
            }
        )
        report = score(labels, predictions, tolerance_ms=1, hit_tolerance_px=1)
        reported = report["prediction"]
        self.assertEqual(reported["sourceRevision"], "7a6bd012")
        self.assertEqual(reported["sourceHashes"], {"Swift/Tracker.swift": "e" * 64})
        self.assertEqual(reported["modelSHA256"], "a" * 64)
        self.assertEqual(reported["replay"], {"algorithm": "seeded-candidate-replay", "codeSHA256": "d" * 64, "candidatePoolSHA256": "e" * 64})
        self.assertNotIn("assistance", reported)


if __name__ == "__main__":
    unittest.main()
