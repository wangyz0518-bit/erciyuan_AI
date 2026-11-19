"""Generate and measure local desktop samples using a reference manifest."""

import argparse
import csv
import json
import math
import random
import time
from pathlib import Path

import numpy as np
import sherpa_onnx
import soundfile as sf


def load_engine(model_dir, vocoder, threads):
    files = {
        "encoder": model_dir / "encoder.int8.onnx",
        "decoder": model_dir / "decoder.int8.onnx",
        "lexicon": model_dir / "lexicon.txt",
        "tokens": model_dir / "tokens.txt",
        "vocoder": vocoder,
    }
    for path in files.values():
        if not path.is_file():
            raise FileNotFoundError(path)
    data_dir = model_dir / "espeak-ng-data"
    if not data_dir.is_dir():
        raise FileNotFoundError(data_dir)

    model = sherpa_onnx.OfflineTtsModelConfig(
        zipvoice=sherpa_onnx.OfflineTtsZipvoiceModelConfig(
            data_dir=str(data_dir), **{name: str(path) for name, path in files.items()}
        ),
        provider="cpu",
        num_threads=threads,
    )
    config = sherpa_onnx.OfflineTtsConfig(model=model)
    if not config.validate():
        raise ValueError("Invalid ZipVoice model configuration")
    return sherpa_onnx.OfflineTts(config)


def load_references(manifest, steps):
    references = {}
    for style, entry in json.loads(manifest.read_text(encoding="utf-8")).items():
        path = manifest.parent / entry["wav"]
        samples, rate = sf.read(path, dtype="float32")
        if samples.ndim != 1 or not samples.size or not np.isfinite(samples).all():
            raise ValueError(f"Expected a nonempty mono reference: {path}")
        if not entry["text"].strip():
            raise ValueError(f"Missing reference transcript: {path}")
        config = sherpa_onnx.GenerationConfig()
        config.reference_audio = samples
        config.reference_sample_rate = rate
        config.reference_text = entry["text"]
        config.num_steps = steps
        config.extra["min_char_in_sentence"] = "30"
        references[style] = config
    return references


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--vocoder", type=Path, required=True)
    parser.add_argument("--references", type=Path, required=True)
    parser.add_argument("--cases", type=Path, required=True, help="CSV with text,style columns")
    parser.add_argument("--output", type=Path, required=True, help="New output directory")
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--steps", type=int, default=4)
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--order-seed", type=int, default=17)
    args = parser.parse_args()
    if min(args.threads, args.steps, args.repeats) < 1:
        parser.error("threads, steps and repeats must be positive")

    references = load_references(args.references, args.steps)
    with args.cases.open(encoding="utf-8-sig", newline="") as case_file:
        cases = list(csv.DictReader(case_file))
    if not cases or any(not c["text"].strip() or c["style"] not in references for c in cases):
        parser.error("cases require nonempty text and a style listed in references")

    schedule = [
        (case_index, repeat)
        for repeat in range(1, args.repeats + 1)
        for case_index in range(len(cases))
    ]
    random.Random(args.order_seed).shuffle(schedule)
    args.output.mkdir(parents=True, exist_ok=False)
    started = time.perf_counter()
    engine = load_engine(args.model_dir, args.vocoder, args.threads)
    load_seconds = time.perf_counter() - started
    print(f"model load: {load_seconds:.3f}s", flush=True)

    records = []
    log_path = args.output / "runs.jsonl"
    with log_path.open("x", encoding="utf-8") as log:
        for position, (case_index, repeat) in enumerate(schedule, 1):
            case = cases[case_index]
            filename = f"{position:03d}.wav"
            record = dict(case, case=case_index + 1, repeat=repeat, position=position)
            try:
                started = time.perf_counter()
                audio = engine.generate(case["text"], references[case["style"]])
                seconds = time.perf_counter() - started
                samples = np.asarray(audio.samples, dtype=np.float32)
                if not samples.size or not np.isfinite(samples).all() or not np.any(samples):
                    raise ValueError("Generation returned empty, invalid or silent audio")
                duration = samples.size / audio.sample_rate
                sf.write(args.output / filename, samples, audio.sample_rate, subtype="PCM_16")
                record.update(
                    wav=filename, generation_seconds=seconds, audio_seconds=duration,
                    sample_rate=audio.sample_rate, rtf=seconds / duration,
                )
            except (RuntimeError, ValueError, OSError) as error:
                record["error"] = str(error)
            log.write(json.dumps(record, ensure_ascii=False) + "\n")
            log.flush()
            records.append(record)

    warm_times = sorted(
        row["generation_seconds"]
        for row in records
        if "wav" in row and row["position"] > 1 and 10 <= len(row["text"]) <= 40
    )
    successful = sum("wav" in row for row in records)
    summary = dict(
        sherpa_onnx=sherpa_onnx.__version__, threads=args.threads, steps=args.steps,
        order_seed=args.order_seed, load_seconds=load_seconds, attempted=len(records),
        successful=successful, first_generation_seconds=records[0].get("generation_seconds"),
        warm_short_count=len(warm_times),
        warm_short_p50_seconds=warm_times[math.ceil(0.50 * len(warm_times)) - 1] if warm_times else None,
        warm_short_p95_seconds=warm_times[math.ceil(0.95 * len(warm_times)) - 1] if warm_times else None,
    )
    result = json.dumps(summary, indent=2)
    (args.output / "summary.json").write_text(result + "\n", encoding="utf-8")
    print(result)
    return int(successful != len(records))


if __name__ == "__main__":
    raise SystemExit(main())
