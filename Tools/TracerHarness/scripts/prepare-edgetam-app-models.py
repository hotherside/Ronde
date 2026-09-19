#!/usr/bin/env python3
"""Prepare the five verified EdgeTAM Core ML resources for a private app build.

This tool is deliberately offline. It verifies the already-built diagnostic app and
its final-build evidence before copying only the resources consumed by
EdgeTAMTrackingService. The output must be outside the repository.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import shutil
import tempfile
from pathlib import Path
from typing import Any, Mapping

MODEL_RESOURCES: dict[str, str] = {
    "image": "edgetam_image_encoder.mlmodelc",
    "attention": "edgetam_variable_memory_attention.mlmodelc",
    "point": "edgetam_sam_heads_fixed_prompt.mlmodelc",
    "noPoint": "edgetam_sam_heads_no_point.mlmodelc",
    "memory": "edgetam_memory_encoder_perceiver_sigmoid_tracking.mlmodelc",
}
CONSTANTS_RESOURCE = "edgetam-constants.json"
LICENSE_RESOURCE = "edgetam-license.txt"
MODEL_VERSION = "EdgeTAM@7711e012a30a2402c4eaab637bdb00a521302c91; float32"
EXPECTED_BUNDLE_ID = "com.ronde.edgetamdiagnostic"
SHA256_LENGTH = 64
CHUNK_SIZE = 1024 * 1024


class PreparationError(RuntimeError):
    """A failed provenance, integrity, or output safety check."""


def _normalise_hash(value: Any, field: str) -> str:
    if not isinstance(value, str):
        raise PreparationError(f"{field} must be a SHA-256 string")
    result = value.strip().lower()
    if result.startswith("sha256:"):
        result = result[7:]
    if len(result) != SHA256_LENGTH or any(character not in "0123456789abcdef" for character in result):
        raise PreparationError(f"{field} must contain a 64-character SHA-256 digest")
    return result


def _file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            while chunk := handle.read(CHUNK_SIZE):
                digest.update(chunk)
    except OSError as error:
        raise PreparationError(f"could not read {path}") from error
    return digest.hexdigest()


def _is_hidden(relative: Path) -> bool:
    return any(part.startswith(".") for part in relative.parts)


def _tree_files(root: Path) -> list[tuple[str, Path]]:
    if not root.is_dir() or root.is_symlink():
        raise PreparationError(f"expected a regular directory: {root}")
    files: list[tuple[str, Path]] = []
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if _is_hidden(relative):
            continue
        if path.is_symlink():
            raise PreparationError(f"symlinks are not allowed in compiled model trees: {path}")
        if path.is_file():
            files.append((relative.as_posix(), path))
        elif not path.is_dir():
            raise PreparationError(f"unsupported model-tree entry: {path}")
    files.sort(key=lambda item: item[0])
    if not files:
        raise PreparationError(f"compiled model tree is empty: {root}")
    return files


def _compiled_tree_digest(root: Path) -> str:
    """Match the Swift service's sorted relative-path/TAB/file-SHA/newline digest."""
    manifest = bytearray()
    for relative, path in _tree_files(root):
        manifest.extend(relative.encode("utf-8"))
        manifest.extend(b"\t")
        manifest.extend(_file_digest(path).encode("ascii"))
        manifest.extend(b"\n")
    return hashlib.sha256(manifest).hexdigest()


def _read_json(path: Path, description: str) -> Mapping[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise PreparationError(f"could not read {description}: {path}") from error
    if not isinstance(value, Mapping):
        raise PreparationError(f"{description} must contain a JSON object")
    return value


def _repo_root() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / "project.yml").is_file() and (parent / "AGENTS.md").is_file():
            return parent
    raise PreparationError("could not determine repository root")


def _outside_repo(path: Path, repo_root: Path, description: str) -> None:
    try:
        path.relative_to(repo_root)
    except ValueError:
        return
    raise PreparationError(f"{description} must be outside the repository: {path}")


def _verify_app(app: Path, evidence: Mapping[str, Any]) -> None:
    if not app.is_dir() or app.is_symlink() or app.suffix != ".app":
        raise PreparationError(f"--app must be a regular .app directory: {app}")
    if evidence.get("status") != "verified-for-device-install":
        raise PreparationError("final-build evidence is not verified-for-device-install")
    if evidence.get("strictCodeSignVerified") is not True:
        raise PreparationError("final-build evidence does not verify strict code signing")
    if evidence.get("bundleID") != EXPECTED_BUNDLE_ID:
        raise PreparationError("final-build evidence bundleID is not the EdgeTAM diagnostic app")

    info_path = app / "Info.plist"
    try:
        info = plistlib.loads(info_path.read_bytes())
    except (OSError, plistlib.InvalidFileException, ValueError) as error:
        raise PreparationError(f"could not read diagnostic app Info.plist: {info_path}") from error
    if info.get("CFBundleIdentifier") != EXPECTED_BUNDLE_ID:
        raise PreparationError("diagnostic app bundle identifier does not match final-build evidence")
    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or not executable_name:
        raise PreparationError("diagnostic app has no executable name")
    executable = app / executable_name
    expected_executable = evidence.get("executableSHA256")
    if expected_executable is not None:
        actual_executable = _file_digest(executable)
        if actual_executable != _normalise_hash(expected_executable, "executableSHA256"):
            raise PreparationError("diagnostic app executable does not match final-build evidence")


def _expected_model_hashes(evidence: Mapping[str, Any]) -> dict[str, str]:
    values = evidence.get("compiledModelSHA256")
    if not isinstance(values, Mapping) or set(values) != set(MODEL_RESOURCES):
        raise PreparationError("final-build evidence compiledModelSHA256 keys do not match the five service components")
    return {key: _normalise_hash(values[key], f"compiledModelSHA256.{key}") for key in MODEL_RESOURCES}


def _expected_constants_hash(evidence: Mapping[str, Any]) -> str:
    return _normalise_hash(evidence.get("constantsSHA256"), "constantsSHA256")


def _copy_tree_without_hidden(source: Path, destination: Path) -> None:
    if destination.exists() or destination.is_symlink():
        raise PreparationError(f"staging destination already exists: {destination}")
    destination.mkdir(parents=True)
    for relative, source_file in _tree_files(source):
        destination_file = destination / relative
        destination_file.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source_file, destination_file)
        shutil.copystat(source_file, destination_file, follow_symlinks=False)


def _copy_file(source: Path, destination: Path) -> None:
    if destination.exists() or destination.is_symlink():
        raise PreparationError(f"staging destination already exists: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    shutil.copystat(source, destination, follow_symlinks=False)


def _validate_existing_tree(path: Path, expected_digest: str, description: str) -> None:
    if path.is_symlink() or not path.is_dir():
        raise PreparationError(f"existing {description} is not a regular directory: {path}")
    actual = _compiled_tree_digest(path)
    if actual != expected_digest:
        raise PreparationError(f"existing {description} differs from the verified source")


def _validate_existing_file(path: Path, expected_digest: str, description: str) -> None:
    if path.is_symlink() or not path.is_file():
        raise PreparationError(f"existing {description} is not a regular file: {path}")
    actual = _file_digest(path)
    if actual != expected_digest:
        raise PreparationError(f"existing {description} differs from the verified source")


def _prepare_output(
    output: Path,
    source_models: Mapping[str, Path],
    model_hashes: Mapping[str, str],
    source_constants: Path,
    constants_hash: str,
    identity_bytes: bytes,
    license_path: Path | None,
) -> None:
    output_exists = output.exists() or output.is_symlink()
    if output.is_symlink() or (output_exists and not output.is_dir()):
        raise PreparationError(f"--output must be a regular directory or a new path: {output}")
    allowed_names = set(MODEL_RESOURCES.values()) | {CONSTANTS_RESOURCE, "edgetam-model-identity.json"}
    if license_path is not None:
        allowed_names.add(LICENSE_RESOURCE)
    if output_exists:
        unexpected = sorted(path.name for path in output.iterdir() if path.name not in allowed_names)
        if unexpected:
            raise PreparationError(f"output contains unexpected files: {', '.join(unexpected)}")

    missing = [
        name for name in [*MODEL_RESOURCES.values(), CONSTANTS_RESOURCE, "edgetam-model-identity.json"]
        if not (output / name).exists()
    ]
    if license_path is not None and not (output / LICENSE_RESOURCE).exists():
        missing.append(LICENSE_RESOURCE)

    if not output_exists:
        output.parent.mkdir(parents=True, exist_ok=True)
        staging: Path | None = Path(tempfile.mkdtemp(prefix=f".{output.name}.staging-", dir=output.parent))
        try:
            for key, name in MODEL_RESOURCES.items():
                _copy_tree_without_hidden(source_models[key], staging / name)
            _copy_file(source_constants, staging / CONSTANTS_RESOURCE)
            (staging / "edgetam-model-identity.json").write_bytes(identity_bytes)
            if license_path is not None:
                _copy_file(license_path, staging / LICENSE_RESOURCE)
            os.replace(staging, output)
            staging = None
        finally:
            if staging is not None and staging.exists():
                shutil.rmtree(staging)
    elif missing:
        staging = Path(tempfile.mkdtemp(prefix=f".{output.name}.staging-", dir=output.parent))
        try:
            for key, name in MODEL_RESOURCES.items():
                if not (output / name).exists():
                    _copy_tree_without_hidden(source_models[key], staging / name)
            if not (output / CONSTANTS_RESOURCE).exists():
                _copy_file(source_constants, staging / CONSTANTS_RESOURCE)
            identity_destination = staging / "edgetam-model-identity.json"
            if not (output / identity_destination.name).exists():
                identity_destination.write_bytes(identity_bytes)
            if license_path is not None and not (output / LICENSE_RESOURCE).exists():
                _copy_file(license_path, staging / LICENSE_RESOURCE)
            for staged in staging.iterdir():
                destination = output / staged.name
                if destination.exists() or destination.is_symlink():
                    raise PreparationError(f"output changed while preparing: {destination}")
                os.replace(staged, destination)
            shutil.rmtree(staging)
            staging = None
        finally:
            if staging is not None and staging.exists():
                shutil.rmtree(staging)

    for key, name in MODEL_RESOURCES.items():
        _validate_existing_tree(output / name, model_hashes[key], name)
    _validate_existing_file(output / CONSTANTS_RESOURCE, constants_hash, CONSTANTS_RESOURCE)
    identity_destination = output / "edgetam-model-identity.json"
    _validate_existing_file(identity_destination, _sha256_bytes(identity_bytes), identity_destination.name)
    if license_path is not None:
        _validate_existing_file(output / LICENSE_RESOURCE, _file_digest(license_path), LICENSE_RESOURCE)


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True, help="verified diagnostic .app")
    parser.add_argument("--evidence", type=Path, required=True, help="final-build-evidence.json")
    parser.add_argument("--output", type=Path, required=True, help="external model output directory")
    parser.add_argument("--license", type=Path, help="optional public LICENSE file to copy")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    repo_root = _repo_root()
    output = args.output.expanduser().resolve()
    _outside_repo(output, repo_root, "--output")
    app = args.app.expanduser().resolve()
    evidence_path = args.evidence.expanduser().resolve()
    license_path = args.license.expanduser().resolve() if args.license else None

    evidence = _read_json(evidence_path, "final-build evidence")
    _verify_app(app, evidence)
    model_hashes = _expected_model_hashes(evidence)
    constants_hash = _expected_constants_hash(evidence)

    source_models: dict[str, Path] = {}
    for key, name in MODEL_RESOURCES.items():
        source = app / name
        source_models[key] = source
        actual = _compiled_tree_digest(source)
        if actual != model_hashes[key]:
            raise PreparationError(f"{name} does not match final-build evidence")
    source_constants = app / CONSTANTS_RESOURCE
    if source_constants.is_symlink() or not source_constants.is_file():
        raise PreparationError(f"diagnostic app is missing {CONSTANTS_RESOURCE}")
    if _file_digest(source_constants) != constants_hash:
        raise PreparationError(f"{CONSTANTS_RESOURCE} does not match final-build evidence")

    if license_path is not None:
        if license_path.is_symlink() or not license_path.is_file():
            raise PreparationError(f"--license must be a regular file: {license_path}")

    identity = {
        "schemaVersion": 1,
        "modelVersion": MODEL_VERSION,
        "constantsResource": CONSTANTS_RESOURCE,
        "constantsSHA256": f"sha256:{constants_hash}",
        "modelResources": MODEL_RESOURCES,
        "expectedCompiledModelSHA256": {
            key: f"sha256:{model_hashes[key]}" for key in MODEL_RESOURCES
        },
    }
    identity_bytes = (json.dumps(identity, indent=2, sort_keys=True) + "\n").encode("utf-8")
    _prepare_output(
        output=output,
        source_models=source_models,
        model_hashes=model_hashes,
        source_constants=source_constants,
        constants_hash=constants_hash,
        identity_bytes=identity_bytes,
        license_path=license_path,
    )
    print(f"Prepared verified EdgeTAM resources at {output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PreparationError as error:
        raise SystemExit(f"error: {error}") from error
