"""Review calibration: seeded defects versus correct code with optional style changes.

--prompts emits only reviewer inputs. --predictions grades JSON answers from a
reviewer; it never asks the reviewer to grade itself and never calls a model.
The fixture checks defect locations, not the semantic quality of explanations.
"""
import argparse
import hashlib
import json
from pathlib import Path

CASES = [
    {'id':'review-01','request':'total([]) returns 0; preserve the API.',
     'code':'def total(values):\n    return sum(values) if values else None\n','blocking_lines':[2]},
    {'id':'review-02','request':'total([]) returns 0; preserve the API. Naming improvements are optional.',
     'code':'def total(v):\n    return sum(v)\n','blocking_lines':[]},
    {'id':'review-03','request':'smallest returns the smallest value without modifying the input list.',
     'code':'def smallest(values):\n    values.sort()\n    return values[0]\n','blocking_lines':[2]},
    {'id':'review-04','request':'smallest returns the smallest value of a nonempty list without modifying it. Refactoring is optional.',
     'code':'def smallest(values):\n    return sorted(values)[0]\n','blocking_lines':[]},
    {'id':'review-05','request':'take supports None for all items and 0 for no items; preserve input.',
     'code':'def take(values, limit=None):\n    return values[:limit] if limit else values[:]\n','blocking_lines':[2]},
    {'id':'review-06','request':'take supports None for all items and 0 for no items. Do not add unspecified validation.',
     'code':'def take(values, limit=None):\n    return values[:limit]\n','blocking_lines':[]},
]


def reviewer_input(case):
    content = {k:case[k] for k in ('id','request','code')}
    content['candidate_sha256'] = hashlib.sha256(json.dumps(content,sort_keys=True).encode()).hexdigest()
    return content


def grade(predictions):
    if not isinstance(predictions,list):
        raise ValueError('Predictions must be a list')
    answers = {}
    for answer in predictions:
        if not isinstance(answer,dict) or answer.get('id') in answers:
            raise ValueError('Unique case IDs required')
        answers[answer.get('id')] = answer
    if set(answers) != {c['id'] for c in CASES}:
        raise ValueError('Predictions must cover exactly the six cases')
    tp = fp = fn = 0
    for case in CASES:
        answer = answers[case['id']]
        if answer.get('candidate_sha256') != reviewer_input(case)['candidate_sha256']:
            raise ValueError('Evidence refers to a different candidate: '+case['id'])
        lines = answer.get('blocking_lines')
        if not isinstance(lines,list) or any(type(n) is not int or n<1 or n>len(case['code'].splitlines()) for n in lines):
            raise ValueError('blocking_lines must identify candidate lines')
        actual, expected = set(lines), set(case['blocking_lines'])
        tp += len(actual & expected)
        fp += len(actual - expected)
        fn += len(expected - actual)
    return {'kind':'review-calibration','cases':len(CASES),'true_positives':tp,'false_positives':fp,
            'false_negatives':fn,'precision':tp/(tp+fp) if tp+fp else None,
            'recall':tp/(tp+fn) if tp+fn else None,'passed':fp==0 and fn==0,
            'limits':'Small seeded fixtures; locations only, not proof of general reviewer competence.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--prompts',action='store_true')
    group.add_argument('--predictions',type=Path)
    args = parser.parse_args()
    result = [reviewer_input(c) for c in CASES] if args.prompts else grade(json.loads(args.predictions.read_text()))
    print(json.dumps(result,indent=2))
