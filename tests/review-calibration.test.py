import importlib.util
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location('reviews',Path(__file__).parent/'evals/reviews.py')
reviews=importlib.util.module_from_spec(spec)
spec.loader.exec_module(reviews)


class Calibration(unittest.TestCase):
    def predictions(self):
        return [{**reviews.reviewer_input(c),'blocking_lines':c['blocking_lines']} for c in reviews.CASES]

    def test_prompts_do_not_include_expected_verdict(self):
        for case in reviews.CASES:
            self.assertNotIn('blocking_lines',reviews.reviewer_input(case))

    def test_known_correct_classification_is_distinguished_from_everything_is_wrong(self):
        self.assertTrue(reviews.grade(self.predictions())['passed'])
        predictions=self.predictions()
        for prediction in predictions:
            prediction['blocking_lines']=[2]
        result=reviews.grade(predictions)
        self.assertFalse(result['passed'])
        self.assertGreater(result['false_positives'],0)

    def test_approving_everything_misses_seeded_defects(self):
        predictions=self.predictions()
        for prediction in predictions:
            prediction['blocking_lines']=[]
        result=reviews.grade(predictions)
        self.assertEqual(result['false_negatives'],3)
        self.assertFalse(result['passed'])

    def test_changed_candidate_and_missing_case_are_not_passing_evidence(self):
        predictions=self.predictions()
        with self.assertRaises(ValueError): reviews.grade(predictions[:-1])
        predictions[0]['candidate_sha256']='different'
        with self.assertRaises(ValueError): reviews.grade(predictions)


if __name__=='__main__': unittest.main()
