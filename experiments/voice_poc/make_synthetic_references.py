"""Create one short reference per expression using a fixed Qwen preset."""

import argparse
import json
import time
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
from qwen_tts import Qwen3TTSModel

REFERENCE_TEXT = "那我们再看一看吧。"
STYLES = {
    "calm": "用平静自然的普通话说，像日常陈述，语调平稳，吐字清楚。",
    "happy": "带着自然的笑意，明显开心、轻快，语调明亮，像收到好消息后说话。",
    "comfort": "像在安慰有些失落的朋友，声音轻柔温暖，慢一点，留一点停顿。",
    "puzzled": "带着疑惑和不确定，像在试探着问对方，尾音稍稍上扬。",
}
NORMAL_SPEED_COMFORT = (
    "用普通话，像在安慰身边的朋友，语气柔和温暖，保持日常说话的速度，清楚自然地说。"
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--device", choices=["cpu", "cuda:0"], default="cpu")
    parser.add_argument("--normal-speed-comfort", action="store_true")
    args = parser.parse_args()
    if not (args.model_dir / "model.safetensors").is_file():
        parser.error("model-dir must contain the locally downloaded Qwen weights")

    args.output.mkdir(parents=True, exist_ok=False)
    torch.set_num_threads(6)
    started = time.perf_counter()
    model = Qwen3TTSModel.from_pretrained(
        str(args.model_dir.resolve()),
        device_map=args.device,
        dtype=torch.float32 if args.device == "cpu" else torch.bfloat16,
        attn_implementation="sdpa",
        local_files_only=True,
    )
    print(f"Qwen model load: {time.perf_counter() - started:.2f}s", flush=True)
    references = {}
    styles = dict(STYLES)
    if args.normal_speed_comfort:
        styles["comfort"] = NORMAL_SPEED_COMFORT
    for style, instruction in styles.items():
        torch.manual_seed(21)
        started = time.perf_counter()
        wavs, rate = model.generate_custom_voice(
            text=REFERENCE_TEXT, language="Chinese", speaker="Serena",
            instruct=instruction, max_new_tokens=160,
        )
        samples = wavs[0]
        if samples.ndim != 1 or not np.isfinite(samples).all() or not np.any(samples):
            raise ValueError(f"No valid reference for {style}")
        wav_name = f"{style}.wav"
        sf.write(args.output / wav_name, samples, rate, subtype="PCM_16")
        references[style] = dict(
            wav=wav_name, text=REFERENCE_TEXT, speaker="Serena",
            instruction=instruction, duration_seconds=samples.size / rate,
        )
        print(
            f"{style}: {samples.size / rate:.2f}s audio, "
            f"{time.perf_counter() - started:.2f}s generation",
            flush=True,
        )

    (args.output / "references.json").write_text(
        json.dumps(references, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
