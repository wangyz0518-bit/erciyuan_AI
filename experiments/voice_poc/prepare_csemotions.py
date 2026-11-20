"""Extract the four CSEMOTIONS screening references from the pinned first shard."""

import argparse
import io
import json
from pathlib import Path

import pyarrow.parquet as pq
import soundfile as sf

REFERENCES = {
    "calm": (210, "female001_neutral_032.wav", "neutral", 0.80, 3.25, "我们总是在追逐远方。"),
    "happy": (148, "female001_happy_026.wav", "happy", 0.92, 3.08, "今天的阳光如此明媚。"),
    "comfort": (207, "female001_neutral_03.wav", "neutral", 0.22, 3.60, "只要我们不放弃，总会有希望的。"),
    "puzzled": (196, "female001_neutral_02.wav", "neutral", 0.22, 2.50, "你觉得我们能找到答案吗？"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parquet", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    table = pq.read_table(args.parquet)
    args.output.mkdir(parents=True, exist_ok=False)
    manifest = {}
    for style, (index, source, label, start, stop, text) in REFERENCES.items():
        row = table.slice(index, 1).to_pylist()[0]
        if (row["speaker"], row["emotion"], row["audio"]["path"]) != ("female001", label, source):
            raise ValueError(f"Unexpected source metadata for row {index}")
        samples, rate = sf.read(io.BytesIO(row["audio"]["bytes"]), dtype="float32")
        if samples.ndim != 1 or samples.size < round(stop * rate):
            raise ValueError(f"Invalid source audio for row {index}")
        wav = f"{style}.wav"
        sf.write(args.output / wav, samples[round(start * rate):round(stop * rate)], rate, subtype="PCM_16")
        manifest[style] = dict(
            wav=wav, text=text, row=index, start=start, stop=stop,
            speaker=row["speaker"], original_label=label, source_file=source,
        )
    (args.output / "references.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
