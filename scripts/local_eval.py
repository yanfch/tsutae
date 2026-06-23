#!/usr/bin/env python3
import json
import os
import statistics
import subprocess
import sys
import time
from pathlib import Path


TEST_FILTER = "TranscriptPostProcessorTests/testRuleEvalSuiteQuality"


def repo_root():
    return Path(__file__).resolve().parents[1]


def load_records(path):
    records = []
    if not path.exists():
        return records
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    return records


def percentile(values, fraction):
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round((len(ordered) - 1) * fraction)))
    return ordered[index]


def markdown_summary(records, elapsed_seconds):
    latencies = [float(record.get("elapsedMs", 0.0)) for record in records]
    passed = sum(1 for record in records if record.get("passed"))
    total = len(records)
    lines = [
        "# Tsutae Local Transcript Eval",
        "",
        f"- Cases: {passed}/{total}",
        f"- Runner elapsed: {elapsed_seconds:.1f}s",
        f"- Total processing: {sum(latencies):.1f}ms",
        f"- p50: {(statistics.median(latencies) if latencies else 0.0):.2f}ms",
        f"- p95: {percentile(latencies, 0.95):.2f}ms",
        "",
        "| Case | Category | Pass | ms | Failures |",
        "| --- | --- | ---: | ---: | --- |",
    ]
    for record in records:
        failures = "; ".join(record.get("failures", []))
        lines.append(
            "| {id} | {category} | {passed} | {elapsed:.2f} | {failures} |".format(
                id=record.get("id", ""),
                category=record.get("category", ""),
                passed="yes" if record.get("passed") else "no",
                elapsed=float(record.get("elapsedMs", 0.0)),
                failures=failures.replace("\n", " "),
            )
        )
    return "\n".join(lines).rstrip() + "\n"


def main():
    root = repo_root()
    package_dir = root / "Packages" / "TsutaeCore"
    output_dir = root / "out" / "local-eval"
    output_dir.mkdir(parents=True, exist_ok=True)
    records_path = output_dir / "rules-dictionary.jsonl"
    summary_path = output_dir / "summary.md"

    env = os.environ.copy()
    env["TSUTAE_LOCAL_EVAL_RESULTS"] = str(records_path)

    started = time.time()
    process = subprocess.run(
        ["swift", "test", "--filter", TEST_FILTER],
        cwd=str(package_dir),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    elapsed = time.time() - started
    print(process.stdout, end="")

    records = load_records(records_path)
    summary = markdown_summary(records, elapsed)
    summary_path.write_text(summary, encoding="utf-8")
    print("\n== Summary ==")
    print(summary)
    print(f"Records written to {records_path}")
    print(f"Summary written to {summary_path}")
    return process.returncode


if __name__ == "__main__":
    raise SystemExit(main())
