"""Recorded real Simulator acceptance matrix, independent of an installed Xcode."""
import csv
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
MATRIX=ROOT/'docs/APL_IOS_HOME_BANNER_QA_MATRIX_2026-10-30.csv'
COLUMNS=(
    'se3_empty_90pt',
    'se3_connected_90pt',
    'se3_connecting_90pt',
    'mini_connected_90pt',
    'promax_connected_90pt',
    'se2_dark_a11y_medium_empty_100pt',
    'se2_dark_a11y_medium_connected_100pt',
)


def test_every_shipped_ios_language_has_real_simulator_qa_result():
    locales=json.loads((ROOT/'mobile/ios/ios-locales.json').read_text(encoding='utf-8'))['languages']
    with MATRIX.open(encoding='utf-8',newline='') as file:
        records=list(csv.DictReader(file))
    assert len(locales)==50 and len(records)==50
    assert [row['language'] for row in records]==locales
    for row in records:
        assert all(row[column]=='PASS' for column in COLUMNS),row
        assert float(row['min_clearance_standard_pt'])>=0
        assert float(row['min_clearance_a11y_medium_pt'])>=0
