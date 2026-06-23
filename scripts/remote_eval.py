#!/usr/bin/env python3
import argparse
import json
import os
import statistics
import subprocess
import sys
import time
from pathlib import Path


DEFAULT_MODELS = "mimo-v2.5,mimo-v2-omni"
TEST_FILTER = "TranscriptPostProcessorTests/testRemoteEvalSuiteAgainstConfiguredProvider"


def parse_args():
    parser = argparse.ArgumentParser(description="Run Tsutae remote transcript evals across text models.")
    parser.add_argument(
        "--models",
        default=os.environ.get("TSUTAE_REMOTE_EVAL_MODELS", DEFAULT_MODELS),
        help="Comma-separated model list. Defaults to mimo-v2.5,mimo-v2-omni.",
    )
    parser.add_argument(
        "--out",
        default="out/remote-eval",
        help="Directory for JSONL results and summary files.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail a model run when semantic eval cases fail.",
    )
    parser.add_argument(
        "--summary",
        default=None,
        help="Optional markdown summary path. Defaults to <out>/summary.md.",
    )
    return parser.parse_args()


def repo_root():
    return Path(__file__).resolve().parents[1]


def sanitize_filename(value):
    return "".join(char if char.isalnum() or char in "._-" else "-" for char in value)


def percentile(values, fraction):
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round((len(ordered) - 1) * fraction)))
    return ordered[index]


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


def run_model(model, output_path, strict):
    root = repo_root()
    package_dir = root / "Packages" / "TsutaeCore"
    env = os.environ.copy()
    env["TSUTAE_RUN_REMOTE_EVAL"] = "1"
    env["TSUTAE_REMOTE_EVAL_MODEL"] = model
    env["TSUTAE_REMOTE_EVAL_RESULTS"] = str(output_path)
    if strict:
        env["TSUTAE_REMOTE_EVAL_STRICT"] = "1"
    else:
        env.pop("TSUTAE_REMOTE_EVAL_STRICT", None)

    command = ["swift", "test", "--filter", TEST_FILTER]
    started = time.time()
    print(f"\n== {model} ==")
    process = subprocess.Popen(
        command,
        cwd=str(package_dir),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    captured = []
    assert process.stdout is not None
    for line in process.stdout:
        captured.append(line)
        print(line, end="")
    exit_code = process.wait()
    elapsed = time.time() - started
    return {
        "model": model,
        "exit_code": exit_code,
        "elapsed_seconds": elapsed,
        "records": load_records(output_path),
        "log": "".join(captured),
    }


def summarize_model(result):
    records = result["records"]
    latencies = [float(record.get("elapsedMs", 0.0)) for record in records]
    passed = sum(1 for record in records if record.get("passed"))
    total = len(records)
    return {
        "model": result["model"],
        "exit_code": result["exit_code"],
        "passed": passed,
        "total": total,
        "pass_rate": (passed / total) if total else 0.0,
        "total_ms": sum(latencies),
        "p50_ms": statistics.median(latencies) if latencies else 0.0,
        "p95_ms": percentile(latencies, 0.95),
        "max_ms": max(latencies) if latencies else 0.0,
    }


def markdown_summary(results):
    summaries = [summarize_model(result) for result in results]
    lines = [
        "# Tsutae Remote Transcript Eval",
        "",
        "| Model | Pass | Total ms | p50 ms | p95 ms | Max ms | Exit |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for item in summaries:
        lines.append(
            "| {model} | {passed}/{total} | {total_ms:.0f} | {p50_ms:.0f} | {p95_ms:.0f} | {max_ms:.0f} | {exit_code} |".format(
                **item
            )
        )

    lines.extend(["", "## Cases", ""])
    for result in results:
        lines.append(f"### {result['model']}")
        lines.append("")
        lines.append("| Case | Task | Pass | ms | Failures |")
        lines.append("| --- | --- | ---: | ---: | --- |")
        for record in result["records"]:
            failures = "; ".join(record.get("failures", []))
            lines.append(
                "| {id} | {task} | {passed} | {elapsed:.0f} | {failures} |".format(
                    id=record.get("id", ""),
                    task=record.get("task", ""),
                    passed="yes" if record.get("passed") else "no",
                    elapsed=float(record.get("elapsedMs", 0.0)),
                    failures=failures.replace("\n", " "),
                )
            )
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main():
    args = parse_args()
    models = [model.strip() for model in args.models.split(",") if model.strip()]
    if not models:
        print("No models provided.", file=sys.stderr)
        return 2

    root = repo_root()
    output_dir = (root / args.out).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    results = []
    for model in models:
        output_path = output_dir / f"{sanitize_filename(model)}.jsonl"
        results.append(run_model(model, output_path, args.strict))

    summary = markdown_summary(results)
    summary_path = Path(args.summary).resolve() if args.summary else output_dir / "summary.md"
    summary_path.write_text(summary, encoding="utf-8")
    print("\n== Summary ==")
    print(summary)
    print(f"Summary written to {summary_path}")

    if args.strict and any(result["exit_code"] != 0 for result in results):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
