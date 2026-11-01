#!/usr/bin/env python3
"""Validate actual iOS Home frame probes across VPN state transitions.

Used only with `-aplHomeLayoutProbe` and dummy ad/profile previews in DEBUG.
Requires no real proxy, connectivity, Apple credentials or UI automation.
"""
import argparse
import json
from pathlib import Path

TOLERANCE = 2.0  # points; subpixel layout rounding on Retina devices


def check(paths: list[Path]) -> dict:
    if len(paths) < 2:
        raise ValueError('At least two Home states are required')
    probes = [json.loads(path.read_text(encoding='utf-8')) for path in paths]
    required = ('header', 'banner', 'adStack', 'connection', 'primaryAction', 'profile')
    for path, probe in zip(paths, probes):
        frames = probe.get('frames', {})
        for key in required:
            if key not in frames:
                raise AssertionError(f'{path.name}: missing {key}')
        def bottom(name):
            return frames[name]['y'] + frames[name]['height']
        if abs(bottom('header') - frames['banner']['y']) > TOLERANCE:
            raise AssertionError(f'{path.name}: blank gap between header and banner')
        if 'nativeAd' in frames:
            if abs(bottom('banner') - frames['nativeAd']['y']) > TOLERANCE:
                raise AssertionError(f'{path.name}: blank gap between the two ads')
            if abs(bottom('nativeAd') - bottom('adStack')) > TOLERANCE:
                raise AssertionError(f'{path.name}: native ad is not the last ad in the stack')
        if frames['primaryAction']['height'] < 69.5 or frames['primaryAction']['height'] > 70.5:
            raise AssertionError(f'{path.name}: primary action height changed')
        if frames['connection']['height'] > 70.5:
            raise AssertionError(f'{path.name}: transition caption added height below the button')
        if frames['connection']['y'] < bottom('adStack'):
            raise AssertionError(f'{path.name}: action overlaps ad stack')
        if frames['profile']['y'] < bottom('primaryAction'):
            raise AssertionError(f'{path.name}: profile overlaps primary action')
        if bottom('profile') > probe['height'] + TOLERANCE:
            raise AssertionError(f'{path.name}: profile clipped beneath the bottom tab bar')

    baseline = probes[0]['frames']
    for path, probe in zip(paths[1:], probes[1:]):
        for name in required + ('nativeAd',):
            if name not in baseline or name not in probe['frames']:
                continue
            for axis in ('x', 'y', 'width', 'height'):
                if abs(probe['frames'][name][axis] - baseline[name][axis]) > TOLERANCE:
                    raise AssertionError(f'{path.name}: {name}.{axis} jumped when VPN state changed')
    return {
        'states': len(paths),
        'headerToBannerGap': round(probes[0]['frames']['banner']['y'] -
                                   (baseline['header']['y'] + baseline['header']['height']), 3),
        'buttonHeight': baseline['primaryAction']['height'],
        'buttonY': baseline['primaryAction']['y'],
        'nativeAdPresent': 'nativeAd' in baseline,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('states', nargs='+', type=Path, help='JSON snapshots created by HomeLayoutProbe')
    args = parser.parse_args()
    print(json.dumps(check(args.states), ensure_ascii=False))


if __name__ == '__main__':
    main()
