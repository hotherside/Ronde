#!/usr/bin/env python3
"""Offline policy and binary-mask comparison for native adaptive EdgeTAM evidence.

This tool consumes only saved diagnostics. It does not invoke models or read
reference labels. Inputs and output must live outside the repository.
"""
from __future__ import annotations
import argparse, hashlib, json, os, tempfile
from pathlib import Path
from PIL import Image

REPO = Path(__file__).resolve().parents[3]

def external(value: str | Path) -> Path:
    path = Path(value).expanduser().resolve()
    if path == REPO or REPO in path.parents:
        raise ValueError('diagnostic inputs and output must be outside the repository')
    return path

def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda: handle.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()

def load(path: Path) -> dict:
    return json.loads(path.read_text())

def crop(value: dict | list | None) -> tuple[int, int, int, int] | None:
    if value is None:
        return None
    if isinstance(value, list):
        return tuple(value)
    return (value['x'], value['y'], value['width'], value['height'])

def pixels(path: str, native: bool, expected_size: int = 512 * 512) -> list[bool]:
    raw = Path(path).read_bytes()
    if native:
        if len(raw) != expected_size:
            raise ValueError('native mask has unexpected byte length')
        return [value != 0 for value in raw]
    with Image.open(Path(path)) as image:
        if image.size != (512, 512):
            raise ValueError('CPU mask dimensions are not 512 square')
        return [value != 0 for value in image.convert('L').getdata()]

def mask_metrics(native_path: str, cpu_path: str) -> dict:
    left = pixels(native_path, native=True)
    right = pixels(cpu_path, native=False)
    intersection = sum(a and b for a, b in zip(left, right))
    union = sum(a or b for a, b in zip(left, right))
    return {
        'iou': 1.0 if union == 0 else intersection / union,
        'xorPixels': sum(a != b for a, b in zip(left, right)),
        'binaryIdentical': left == right,
        'nativeForegroundPixels': sum(left),
        'cpuForegroundPixels': sum(right),
    }

def close(left: float | None, right: float | None, epsilon: float = 1e-9) -> bool:
    return left is not None and right is not None and abs(left - right) <= epsilon

def map_native_canonical(native: dict) -> dict[int, dict]:
    index_map = native['intervalSourceFrameIndices']
    canonical = {}
    for item in native['result']['canonical']:
        local = item['index']
        if not 0 <= local < len(index_map):
            raise ValueError('native canonical index is outside its source index map')
        source_index = index_map[local]
        if source_index in canonical:
            raise ValueError('native emits a duplicate canonical source index')
        canonical[source_index] = item
    return canonical

def cpu_diagnostics(cpu: dict) -> dict[tuple[str, int, int], dict]:
    diagnostics = {}
    for item in cpu.get('initialReverseSeedMasks', []):
        diagnostics[('initial-reverse', item['sourceFrameIndex'], item['segmentId'])] = item
    for transition in cpu.get('automaticTransitions', []):
        item = transition['newSeedMask']
        diagnostics[('transition', item['sourceFrameIndex'], item['segmentId'])] = item
    return diagnostics

def native_diagnostics(native: dict) -> dict[tuple[str, int, int], dict]:
    return {(item['kind'], item['sourceFrameIndex'], item['segmentID']): item
            for item in native['observedMasks'] if item['kind'] != 'canonical'}

def compare(native: dict, cpu: dict) -> dict:
    if native['status'] != 'completed':
        raise ValueError('native evidence is not completed')
    source_hash_ok = native['input']['sourceSHA256'] == cpu['sourceHash'].removeprefix('sha256:')
    cache_hash_ok = native['input']['cacheManifestSHA256'] == cpu['fullSourceCacheManifestSHA256']
    pts_hash_ok = native['input']['avPTSManifestSHA256'] == cpu['sourceAVManifestSHA256']
    config_hash_ok = native['input']['configSHA256'] == cpu['configurationSHA256']
    dimensions_ok = native['source']['width'] == cpu['width'] and native['source']['height'] == cpu['height']
    cpu_samples = {item['sourceFrameIndex']: item for item in cpu['samples']}
    native_canonical = map_native_canonical(native)
    interval = native['intervalSourceFrameIndices']
    source_interval_ok = interval == sorted(cpu_samples) and len(interval) == len(set(interval))
    differences = []
    processed_cpu = {index for index, item in cpu_samples.items() if item['processingStatus'] != 'unprocessed_after_direction_stop'}
    if processed_cpu != set(native_canonical):
        differences.append({'kind': 'canonicalProcessedSet', 'cpuCount': len(processed_cpu), 'nativeCount': len(native_canonical)})
    cpu_nonempty = {index for index, item in cpu_samples.items() if item['visible']}
    native_nonempty = {index for index, item in native_canonical.items() if item['visible']}
    if cpu_nonempty != native_nonempty:
        differences.append({'kind': 'nonemptySet', 'cpuCount': len(cpu_nonempty), 'nativeCount': len(native_nonempty)})
    comparisons = []
    for index in sorted(processed_cpu & set(native_canonical)):
        left, right = native_canonical[index], cpu_samples[index]
        expected_status = 'observed_mask' if left['visible'] else 'empty_mask'
        fields_ok = (close(left['timestamp'], right['timestamp']) and left['visible'] == right['visible']
                     and left['direction'] == right['direction'] and left['segmentID'] == right['segmentId']
                     and crop(left['crop']) == crop(right['crop_xywh']) and right['processingStatus'] == expected_status)
        if not fields_ok:
            differences.append({'kind': 'canonicalPolicy', 'sourceFrameIndex': index})
        native_mask = next((item for item in native['observedMasks']
                            if item['kind'] == 'canonical' and item['sourceFrameIndex'] == index), None)
        if native_mask is None or 'rawBinaryMaskPath' not in right:
            differences.append({'kind': 'canonicalMaskMissing', 'sourceFrameIndex': index})
            continue
        metrics = mask_metrics(native_mask['rawBinaryMaskPath'], right['rawBinaryMaskPath'])
        centre_error = None
        if left['visible'] and right['visible']:
            dx = left['centroidX'] - right['x'] * cpu['width']
            dy = left['centroidY'] - right['y'] * cpu['height']
            centre_error = (dx * dx + dy * dy) ** 0.5
        comparisons.append({'sourceFrameIndex': index, 'kind': 'canonical',
                            'maskIoU': metrics['iou'], 'maskXorPixels': metrics['xorPixels'],
                            'binaryIdentical': metrics['binaryIdentical'],
                            'sourceCentreErrorPx': centre_error})
    native_diag, cpu_diag = native_diagnostics(native), cpu_diagnostics(cpu)
    if set(native_diag) != set(cpu_diag):
        differences.append({'kind': 'diagnosticMaskSet', 'cpuCount': len(cpu_diag), 'nativeCount': len(native_diag)})
    for key in sorted(set(native_diag) & set(cpu_diag)):
        left, right = native_diag[key], cpu_diag[key]
        if not (close(left['sourcePTS'], right['timestamp']) and left['direction'] == right['direction']
                and crop(left['crop']) == crop(right['crop_xywh']) and left['visible'] == right['visible']):
            differences.append({'kind': 'diagnosticPolicy', 'sourceFrameIndex': key[1], 'observationKind': key[0]})
        metrics = mask_metrics(left['rawBinaryMaskPath'], right['rawBinaryMaskPath'])
        comparisons.append({'sourceFrameIndex': key[1], 'kind': key[0], 'maskIoU': metrics['iou'],
                            'maskXorPixels': metrics['xorPixels'], 'binaryIdentical': metrics['binaryIdentical'],
                            'sourceCentreErrorPx': None})
    index_map = native['intervalSourceFrameIndices']
    native_segments = [{**item, 'anchorSourceFrameIndex': index_map[item['anchorIndex']]} for item in native['result']['segments']]
    cpu_segments = [{k: item[k] for k in ('segmentId', 'direction', 'crop_xywh', 'anchorTimestamp', 'anchorSourceFrameIndex', 'pointSource')}
                    for item in cpu['segments']]
    segment_policy = [(item['segmentID'], item['direction'], crop(item['crop']), item['anchorTimestamp'], item['anchorSourceFrameIndex'], item['pointSource']) for item in native_segments]
    cpu_segment_policy = [(item['segmentId'], item['direction'], crop(item['crop_xywh']), item['anchorTimestamp'], item['anchorSourceFrameIndex'], item['pointSource']) for item in cpu_segments]
    if segment_policy != cpu_segment_policy:
        differences.append({'kind': 'segments', 'cpuCount': len(cpu_segment_policy), 'nativeCount': len(segment_policy)})
    native_transitions = [(index_map[item['index']], item['timestamp'], item['direction'], crop(item['oldCrop']), crop(item['newCrop']), item['modelDerivedPointX'], item['modelDerivedPointY']) for item in native['result']['transitions']]
    cpu_transitions = [(item['sourceFrameIndex'], item['timestamp'], item['direction'], crop(item['oldCrop']), crop(item['newCrop']), *item['modelDerivedPointPx']) for item in cpu['automaticTransitions']]
    if len(native_transitions) != len(cpu_transitions) or any(
            n[:5] != c[:5] or not close(n[5], c[5]) or not close(n[6], c[6]) for n, c in zip(native_transitions, cpu_transitions)):
        differences.append({'kind': 'transitions', 'cpuCount': len(cpu_transitions), 'nativeCount': len(native_transitions)})
    terminations_ok = native['result']['terminations'] == cpu['directionTermination']
    if not terminations_ok:
        differences.append({'kind': 'terminations'})
    resets_ok = native['result']['automaticReseedCount'] == cpu['automaticReseedCount']
    recovery_ok = native['result']['gapRecoveryCount'] == cpu['gapRecoveryCount']
    if not resets_ok: differences.append({'kind': 'automaticReseedCount'})
    if not recovery_ok: differences.append({'kind': 'gapRecoveryCount'})
    min_iou = min((item['maskIoU'] for item in comparisons), default=0.0)
    max_centre = max((item['sourceCentreErrorPx'] for item in comparisons if item['sourceCentreErrorPx'] is not None), default=0.0)
    discrete = all((source_hash_ok, cache_hash_ok, pts_hash_ok, config_hash_ok, dimensions_ok, source_interval_ok,
                    processed_cpu == set(native_canonical), cpu_nonempty == native_nonempty, resets_ok, recovery_ok,
                    terminations_ok, not any(item['kind'] in ('canonicalPolicy', 'canonicalMaskMissing', 'diagnosticMaskSet', 'diagnosticPolicy', 'segments', 'transitions') for item in differences)))
    return {'sourceHashMatches': source_hash_ok, 'cacheManifestHashMatches': cache_hash_ok,
            'avPTSManifestHashMatches': pts_hash_ok, 'configurationHashMatches': config_hash_ok,
            'sourceDimensionsMatch': dimensions_ok, 'fullSourceIndexAndPTSIntervalMatches': source_interval_ok,
            'canonicalProcessedSetMatches': processed_cpu == set(native_canonical), 'nonemptySetMatches': cpu_nonempty == native_nonempty,
            'automaticReseedCountMatches': resets_ok, 'gapRecoveryCountMatches': recovery_ok,
            'terminationsMatch': terminations_ok, 'discretePolicyPass': discrete,
            'canonicalProcessedCount': len(processed_cpu), 'canonicalNonemptyCount': len(cpu_nonempty),
            'diagnosticMaskCount': len(native_diag), 'minimumRawMaskIoU': min_iou,
            'maximumSourceCentreErrorPx': max_centre, 'rawMaskBinaryExactCount': sum(item['binaryIdentical'] for item in comparisons),
            'rawMaskComparedCount': len(comparisons), 'numericalPass': discrete and min_iou >= 0.9 and max_centre <= 0.5,
            'differences': differences, 'comparisons': comparisons}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--native-evidence', required=True, type=Path)
    parser.add_argument('--cpu-output', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    native_path, cpu_path, output = map(external, (args.native_evidence, args.cpu_output, args.output))
    if output.exists(): raise FileExistsError(f'refuse overwrite: {output}')
    native, cpu = load(native_path), load(cpu_path)
    report = compare(native, cpu)
    report.update({'schemaVersion': 1, 'kind': 'native-adaptive-vs-original-cpu-offline-comparison',
                   'nativeEvidenceSHA256': sha(native_path), 'cpuOutputSHA256': sha(cpu_path),
                   'comparatorSHA256': sha(Path(__file__).resolve()), 'referenceLabelsRead': False})
    output.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=output.parent, prefix='.comparison-', suffix='.tmp')
    with os.fdopen(handle, 'w') as stream:
        json.dump(report, stream, indent=2, sort_keys=True); stream.write('\n'); stream.flush(); os.fsync(stream.fileno())
    os.replace(temporary, output)
    print(json.dumps({'numericalPass': report['numericalPass'], 'discretePolicyPass': report['discretePolicyPass'],
                      'minimumRawMaskIoU': report['minimumRawMaskIoU'], 'maximumSourceCentreErrorPx': report['maximumSourceCentreErrorPx']}))

if __name__ == '__main__': main()
