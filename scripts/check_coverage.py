#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys
from pathlib import Path


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Enforce and ratchet FlowDelta source coverage.")
    parser.add_argument("xcresult", type=Path)
    parser.add_argument(
        "--baseline",
        type=Path,
        default=Path(__file__).resolve().parent / "coverage-baseline.json",
    )
    parser.add_argument("--record-improvements", action="store_true")
    return parser.parse_args()


def load_report(path: Path) -> dict:
    process = subprocess.run(
        ["xcrun", "xccov", "view", "--report", "--json", str(path)],
        check=False,
        capture_output=True,
        text=True,
    )
    if process.returncode:
        raise RuntimeError(process.stderr.strip() or "xccov failed")
    return json.loads(process.stdout)


def source_files(report: dict) -> dict[str, float]:
    result: dict[str, float] = {}
    for target in report.get("targets", []):
        for source in target.get("files", []):
            path = source.get("path", "")
            if "/Sources/FlowDelta" not in path:
                continue
            if any(f"/Sources/{target}/" in path for target in ("FlowDeltaCLI", "FlowDeltaCommandLine", "FlowDeltaReference")):
                continue
            result[path] = float(source.get("lineCoverage", 0)) * 100
    return result


def overall_coverage(files: dict[str, float], report: dict) -> float:
    covered = 0
    executable = 0
    by_path = {
        source.get("path", ""): source
        for target in report.get("targets", [])
        for source in target.get("files", [])
    }
    for path in files:
        source = by_path[path]
        executable += int(source.get("executableLines", 0))
        covered += int(source.get("coveredLines", 0))
    return 100 if executable == 0 else covered * 100 / executable


def main() -> int:
    arguments = parse_arguments()
    report = load_report(arguments.xcresult)
    files = source_files(report)
    if not files:
        print("No FlowDelta library sources found in coverage report", file=sys.stderr)
        return 1
    baseline = json.loads(arguments.baseline.read_text())
    overall = overall_coverage(files, report)
    failures: list[str] = []
    if round(overall, 2) < float(baseline["overall"]):
        failures.append(f"overall {overall:.2f}% < {baseline['overall']:.2f}%")
    for suffix, floor in baseline.get("files", {}).items():
        matches = [coverage for path, coverage in files.items() if path.endswith(suffix)]
        if not matches:
            failures.append(f"missing baseline file {suffix}")
        elif round(matches[0], 2) < float(floor):
            failures.append(f"{suffix} {matches[0]:.2f}% < {float(floor):.2f}%")
    print(f"FlowDelta library coverage: {overall:.2f}% across {len(files)} files")
    for failure in failures:
        print(f"coverage failure: {failure}", file=sys.stderr)
    if failures:
        return 1
    if arguments.record_improvements:
        baseline["overall"] = round(max(float(baseline["overall"]), overall), 2)
        for suffix, floor in list(baseline.get("files", {}).items()):
            match = next(coverage for path, coverage in files.items() if path.endswith(suffix))
            baseline["files"][suffix] = round(max(float(floor), match), 2)
        arguments.baseline.write_text(json.dumps(baseline, indent=2, sort_keys=True) + "\n")
        print(f"Ratchet recorded in {arguments.baseline}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
