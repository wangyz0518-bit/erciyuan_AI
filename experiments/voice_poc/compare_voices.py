"""Desktop-only Qwen / CosyVoice comparison. Secrets and audio stay in .voice-local."""

import argparse
import base64
import csv
import hashlib
import html
import json
import math
import os
from pathlib import Path
import random
import re
import shutil
import threading
import time
import uuid
import wave

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[2]
MODELS = {"plus": "cosyvoice-v3.5-plus", "flash": "cosyvoice-v3.5-flash"}
PRICES = {"plus": 1.5, "flash": 0.8}
STYLES = {
    "calm": "用普通话自然交谈，语气平静，保持日常语速。",
    "happy": "用普通话带着轻微笑意交谈，开心但不过分兴奋，保持日常语速。",
    "comfort": "用普通话温柔耐心地安慰朋友，保持日常语速，不拖长字音。",
    "puzzled": "用普通话轻声询问，带一点迟疑和疑惑，保持日常语速。",
}
REFERENCE_TEXT = "你好，今天我们可以一起聊聊最近发生的事情。窗边的阳光很暖，我刚刚整理好了桌上的书，也准备了一杯水。你可以慢慢说，我会认真听。"


def save_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def billable_characters(text):
    # Model Studio's documented Han character rule; other Unicode code points count once.
    return sum(2 if (0x3400 <= ord(c) <= 0x4DBF or 0x4E00 <= ord(c) <= 0x9FFF
                     or 0xF900 <= ord(c) <= 0xFAFF or 0x20000 <= ord(c) <= 0x323AF) else 1
               for c in text)


def read_cases(path):
    with Path(path).open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    if not rows or any(not r.get("text", "").strip() or r.get("style") not in STYLES for r in rows):
        raise InputError("Cases require nonempty text and calm/happy/comfort/puzzled style.")
    return rows


def quantile(values, q):
    ordered = sorted(values)
    return ordered[math.ceil(len(ordered) * q) - 1] if ordered else None


def credentials():
    key = os.environ.get("DASHSCOPE_API_KEY", "").strip()
    workspace = os.environ.get("DASHSCOPE_WORKSPACE_ID", "").strip()
    if not key or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,127}", workspace):
        raise InputError("Configure the Beijing DashScope API key and workspace ID locally first.")
    return key, workspace


def safe_error(error):
    # Never put HTTP headers, SDK exception bodies, keys or workspace URLs into logs.
    if isinstance(error, (ExperimentError, InputError)):
        return str(error)
    return type(error).__name__ + ": details omitted; check local configuration and service availability."


class ExperimentError(RuntimeError):
    pass


class InputError(ValueError):
    """Safe local validation message; never include credential values."""
    pass


class CloudVoice:
    def __init__(self, model, voice, key, workspace, socket_factory=None):
        import websocket
        self.model, self.voice, self.key, self.workspace = model, voice, key, workspace
        self.factory = socket_factory or websocket.create_connection
        self.ws = None

    def close(self):
        if self.ws is not None:
            self.ws.close()
            self.ws = None

    def generate(self, text, instruction, seed, on_audio):
        started = time.perf_counter()
        connected = self.ws is not None
        if self.ws is None:
            self.ws = self.factory(
                f"wss://{self.workspace}.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference",
                header=[f"Authorization: Bearer {self.key}"], timeout=20,
            )
        connect_seconds = time.perf_counter() - started
        task_id = uuid.uuid4().hex
        def send(action, payload):
            self.ws.send(json.dumps({"header": {"action": action, "task_id": task_id,
                                               "streaming": "duplex"}, "payload": payload}, ensure_ascii=False))
        send("run-task", {
            "task_group": "audio", "task": "tts", "function": "SpeechSynthesizer",
            "model": self.model, "input": {}, "parameters": {
                "text_type": "PlainText", "voice": self.voice, "format": "pcm",
                "sample_rate": 24000, "rate": 1.0, "pitch": 1.0,
                "instruction": instruction, "seed": seed, "language_hints": ["zh"],
            },
        })
        acknowledged = False
        first_audio = None
        chunks = []
        usage = None
        try:
            while True:
                remaining = 90 - (time.perf_counter() - started)
                if remaining <= 0:
                    raise ExperimentError("Synthesis exceeded the 90 second deadline; no automatic retry.")
                self.ws.settimeout(min(20, remaining))
                packet = self.ws.recv()
                if not packet:
                    raise ExperimentError("Connection closed before task-finished; no automatic retry.")
                if isinstance(packet, bytes):
                    if not acknowledged:
                        raise ExperimentError("Audio arrived before task-started.")
                    if first_audio is None:
                        first_audio = time.perf_counter() - started
                    chunks.append(packet)
                    on_audio(packet)
                    continue
                event = json.loads(packet)
                header = event.get("header", {})
                if header.get("task_id") != task_id:
                    raise ExperimentError("Unexpected task ID in server response.")
                kind = header.get("event")
                if kind == "task-failed":
                    raise ExperimentError("Cloud task failed; no automatic retry. Check access, quota and voice binding.")
                usage = event.get("payload", {}).get("usage", {}).get("characters", usage)
                if kind == "task-started":
                    if acknowledged:
                        raise ExperimentError("Duplicate task-started event.")
                    acknowledged = True
                    send("continue-task", {"input": {"text": text}})
                    send("finish-task", {"input": {}})
                elif kind == "task-finished":
                    if not acknowledged or not chunks:
                        raise ExperimentError("Task finished without valid audio.")
                    break
            pcm = b"".join(chunks)
            if len(pcm) % 2:
                raise ExperimentError("PCM stream ended with an incomplete 16-bit sample.")
            return pcm, dict(
                first_audio_seconds=first_audio, generation_seconds=time.perf_counter() - started,
                connection_reused=connected, connection_seconds=connect_seconds,
                output_streaming=True, input_streaming=False, provider_characters=usage,
                audio_chunks=len(chunks), sample_rate=24000,
            )
        except BaseException:
            self.close()
            raise


class QwenVoice:
    def __init__(self, model_dir, device):
        import torch
        from qwen_tts import Qwen3TTSModel
        if device.startswith("cuda") and not torch.cuda.is_available():
            raise ExperimentError("CUDA is unavailable in this Python environment.")
        self.torch = torch
        torch.set_num_threads(6)
        started = time.perf_counter()
        self.model = Qwen3TTSModel.from_pretrained(
            str(model_dir.resolve()), device_map=device,
            dtype=torch.bfloat16 if device.startswith("cuda") else torch.float32,
            attn_implementation="sdpa", local_files_only=True,
        )
        self.load_seconds = time.perf_counter() - started
        self.runtime = {"torch": torch.__version__, "device": device,
                        "gpu": torch.cuda.get_device_name() if device.startswith("cuda") else None}

    def generate(self, text, instruction, seed, on_audio):
        self.torch.manual_seed(seed)
        started = time.perf_counter()
        wavs, rate = self.model.generate_custom_voice(
            text=text, language="Chinese", speaker="Serena", instruct=instruction,
            max_new_tokens=640, non_streaming_mode=True,
        )
        samples = np.asarray(wavs[0], dtype=np.float32)
        if rate != 24000 or samples.ndim != 1 or not samples.size or not np.isfinite(samples).all():
            raise ExperimentError("Qwen returned invalid audio or an unexpected sample rate.")
        pcm = (np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes()
        elapsed = time.perf_counter() - started
        on_audio(pcm)
        return pcm, dict(first_audio_seconds=elapsed, generation_seconds=elapsed,
                         output_streaming=False, input_streaming=False,
                         audio_chunks=1, sample_rate=rate, runtime=self.runtime)

    def close(self):
        pass


class Playback:
    """Play PCM as it arrives; DAC timestamps are device estimates, not acoustic measurements."""
    def __init__(self, enabled, device=None, rate=24000):
        self.enabled, self.rate = enabled, rate
        self.pending = bytearray()
        self.lock = threading.Lock()
        self.finished = threading.Event()
        self.done, self.running = False, False
        self.first_dac = None
        self.starved_frames = 0
        self.portaudio_underflows = 0
        self.total_bytes = 0
        self.stream = None
        if enabled:
            import sounddevice as sd
            self.sd = sd
            self.stream = sd.RawOutputStream(samplerate=rate, channels=1, dtype="int16",
                device=device, blocksize=480, callback=self.callback,
                finished_callback=self.finished.set, latency="low")

    def callback(self, output, frames, timestamp, status):
        if status.output_underflow:
            self.portaudio_underflows += 1
        with self.lock:
            take = min(frames * 2, len(self.pending))
            take -= take % 2
            block = bytes(self.pending[:take])
            del self.pending[:take]
            done = self.done and not self.pending
            if take < frames * 2 and not self.done:
                self.starved_frames += frames - take // 2
        output[:] = block + b"\0" * (frames * 2 - take)
        if self.first_dac is None and block:
            audible = np.flatnonzero(np.abs(np.frombuffer(block, dtype="<i2").astype(np.int32)) >= 200)
            if len(audible):
                self.first_dac = (time.perf_counter() - self.started
                                  + timestamp.outputBufferDacTime - timestamp.currentTime
                                  + int(audible[0]) / self.rate)
        if done:
            raise self.sd.CallbackStop

    def start_clock(self):
        self.started = time.perf_counter()

    def feed(self, packet):
        if not self.enabled:
            return
        with self.lock:
            self.pending.extend(packet)
            self.total_bytes += len(packet)
            ready = len(self.pending) >= int(self.rate * 2 * 0.12)
        if ready and not self.running:
            self.running = True
            self.stream.start()

    def complete(self):
        if self.enabled:
            with self.lock:
                self.done = True
                pending = bool(self.pending)
            if pending and not self.running:
                self.running = True
                self.stream.start()
            if self.running and not self.finished.wait(self.total_bytes / (2 * self.rate) + 10):
                raise ExperimentError("Playback did not finish within its deadline.")
        return {"playback_enabled": self.enabled, "first_non_silent_dac_estimate_seconds": self.first_dac,
                "playback_starved_seconds": self.starved_frames / self.rate if self.enabled else None,
                "portaudio_underflows": self.portaudio_underflows if self.enabled else None,
                "acoustic_first_sound_seconds": None}

    def close(self):
        if self.stream is not None:
            self.stream.abort()
            self.stream.close()


def write_wav(path, pcm, rate=24000):
    if not pcm or len(pcm) % 2 or not np.any(np.frombuffer(pcm, dtype="<i2")):
        raise ExperimentError("Empty, malformed or silent PCM output.")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(pcm)


def prepare_reference(args):
    args.output.mkdir(parents=True, exist_ok=False)
    engine = QwenVoice(args.model_dir, args.device)
    pcm, metrics = engine.generate(REFERENCE_TEXT, STYLES["calm"], 21, lambda _: None)
    path = args.output / "reference.wav"
    write_wav(path, pcm)
    seconds = len(pcm) / 48000
    manifest = {"origin": "synthetic Qwen3-TTS-12Hz-1.7B-CustomVoice / Serena",
                "text": REFERENCE_TEXT, "instruction": STYLES["calm"],
                "wav": path.name, "sha256": sha256(path), "audio_seconds": seconds,
                "model_load_seconds": engine.load_seconds, "metrics": metrics,
                "human_reference_quality_review": "pending"}
    save_json(args.output / "manifest.json", manifest)
    if not 10 <= seconds <= 30:
        raise ExperimentError("Reference duration is outside 10-30 seconds. Review before cloud enrollment.")
    print(json.dumps({"reference_seconds": seconds, "generation_seconds": metrics["generation_seconds"]}))


def enrollment_request(key, workspace, payload):
    import requests
    response = requests.post(
        f"https://{workspace}.cn-beijing.maas.aliyuncs.com/api/v1/services/audio/tts/customization",
        headers={"Authorization": f"Bearer {key}"}, json={"model": "voice-enrollment", "input": payload},
        timeout=(15, 60),
    )
    if not response.ok:
        raise ExperimentError(f"Voice enrollment HTTP {response.status_code}; response body omitted.")
    data = response.json()
    if "output" not in data:
        raise ExperimentError("Voice enrollment response has no output; no automatic creation retry.")
    return data["output"]


def enroll(args):
    key, workspace = credentials()
    samples, rate = sf.read(args.reference, dtype="float32")
    if samples.ndim != 1 or rate < 16000 or not 10 <= len(samples) / rate <= 30:
        raise InputError("Use a mono 10-30 second WAV with sample rate >=16000 Hz.")
    if not np.isfinite(samples).all() or not np.any(samples) or args.reference.stat().st_size > 10_000_000:
        raise InputError("Invalid or oversized reference.")
    fingerprint = sha256(args.reference)
    workspace_fingerprint = hashlib.sha256(workspace.encode()).hexdigest()
    manifest = {"reference_sha256": fingerprint, "workspace_sha256": workspace_fingerprint, "voices": {}}
    if args.output.exists():
        manifest = json.loads(args.output.read_text(encoding="utf-8"))
        if manifest["reference_sha256"] != fingerprint or manifest["workspace_sha256"] != workspace_fingerprint:
            raise InputError("Existing voice manifest belongs to another reference or workspace; use a new output path.")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    encoded = "data:audio/wav;base64," + base64.b64encode(args.reference.read_bytes()).decode("ascii")
    for alias, model in MODELS.items():
        if model not in manifest["voices"]:
            result = enrollment_request(key, workspace, {"action": "create_voice", "target_model": model,
                "prefix": "dvoicepoc", "audio": encoded, "language_hints": ["zh"],
                "max_prompt_audio_length": 30.0, "enable_volume_normalization": "false"})
            manifest["voices"][model] = result["voice_id"]
            save_json(args.output, manifest)  # Save immediately; a retry must not create duplicate voices.
        voice = manifest["voices"][model]
        for _ in range(60):
            state = enrollment_request(key, workspace, {"action": "query_voice", "voice_id": voice})["status"]
            if state == "OK":
                print(f"{alias}: voice ready (ID stored locally)", flush=True)
                break
            if state != "DEPLOYING":
                raise ExperimentError("Voice deployment failed; the voice ID remains saved locally.")
            time.sleep(1)
        else:
            raise ExperimentError("Voice deployment is still pending; rerun enrollment to query existing IDs.")


def summarize(records, load_seconds):
    success = [r for r in records if "wav" in r]
    warm = [r for r in success if r["position"] > 1]
    result = {"attempted": len(records), "successful": len(success), "model_load_seconds": load_seconds,
              "first_request": success[0] if success and success[0]["position"] == 1 else None,
              "warm_count": len(warm), "human_scores": "pending", "full_chat_latency": "not_measured",
              "acoustic_latency": "not_measured", "warm": {}}
    for key in ("first_audio_seconds", "generation_seconds", "first_non_silent_dac_estimate_seconds", "rtf"):
        vals = [r[key] for r in warm if r.get(key) is not None]
        result["warm"][key] = {"count": len(vals), "p50": quantile(vals, .5), "p95": quantile(vals, .95)}
    result["estimated_cost_cny"] = sum(r.get("estimated_cost_cny", 0) for r in records)
    return result


def run(args):
    cases = read_cases(args.cases)
    if args.limit:
        cases = cases[:args.limit]
    schedule = [(i, repeat) for repeat in range(args.repeats) for i in range(len(cases))]
    random.Random(args.order_seed).shuffle(schedule)
    predicted = sum(billable_characters(cases[i]["text"]) for i, _ in schedule) / 10000 * PRICES.get(args.backend, 0)
    if predicted > args.max_cost_cny:
        raise InputError(f"Estimated synthesis cost {predicted:.4f} CNY exceeds this run's configured budget.")
    engine = None
    load_seconds = None
    if args.backend in MODELS:
        key, workspace = credentials()
        manifest = json.loads(args.voices.read_text(encoding="utf-8"))
        if manifest["workspace_sha256"] != hashlib.sha256(workspace.encode()).hexdigest():
            raise InputError("Voice manifest workspace does not match credentials.")
        voice = manifest["voices"][MODELS[args.backend]]
        if not voice.startswith(MODELS[args.backend] + "-"):
            raise InputError("Voice is not bound to the selected model.")
        engine = CloudVoice(MODELS[args.backend], voice, key, workspace)
    args.output.mkdir(parents=True, exist_ok=False)
    save_json(args.output / "experiment.json", {
        "backend": args.backend, "model": MODELS.get(args.backend, "Qwen3-TTS-12Hz-1.7B-CustomVoice"),
        "cases_sha256": sha256(args.cases), "styles": STYLES,
        "order_seed": args.order_seed, "repeats": args.repeats,
        "estimated_cost_cny": predicted, "price_date": "2026-11-13",
        "reference_sha256": manifest["reference_sha256"] if args.backend in MODELS else None,
        "text_input": "complete text, audio streaming where supported",
        "playback": args.play, "audio_device": args.audio_device,
        "latency_scope": "ready text -> audio receipt / device DAC estimate; excludes LLM and ASR",
    })
    if engine is None:
        engine = QwenVoice(args.model_dir, args.device)
        load_seconds = engine.load_seconds
        print(f"Qwen model loaded in {load_seconds:.2f}s", flush=True)
    records = []
    try:
        with (args.output / "runs.jsonl").open("x", encoding="utf-8") as log:
            for position, (index, repeat) in enumerate(schedule, 1):
                case = cases[index]
                seed = 21 + repeat
                record = dict(case, backend=args.backend, case=index + 1, repeat=repeat + 1,
                              seed=seed, position=position,
                              estimated_cost_cny=billable_characters(case["text"]) / 10000 * PRICES.get(args.backend, 0))
                player = None
                try:
                    player = Playback(args.play, args.audio_device)
                    player.start_clock()
                    pcm, metrics = engine.generate(case["text"], STYLES[case["style"]], seed, player.feed)
                    metrics.update(player.complete())
                    name = f"{position:03d}.wav"
                    write_wav(args.output / name, pcm)
                    duration = len(pcm) / 48000
                    record.update(metrics, wav=name, audio_seconds=duration,
                                  rtf=metrics["generation_seconds"] / duration)
                except Exception as error:
                    record["error"] = safe_error(error)
                finally:
                    if player is not None:
                        player.close()
                records.append(record)
                log.write(json.dumps(record, ensure_ascii=False) + "\n")
                log.flush()
                save_json(args.output / "summary.json", summarize(records, load_seconds))
                print(json.dumps({k: record[k] for k in ("position", "style", "first_audio_seconds", "error") if k in record}), flush=True)
                if "error" in record:
                    raise ExperimentError("Run stopped on first failure; completed samples remain available. No automatic retry.")
    finally:
        engine.close()
    print(json.dumps(summarize(records, load_seconds), ensure_ascii=False), flush=True)


def package(args):
    entries = []
    for folder in args.runs:
        entries.extend((folder, json.loads(line)) for line in (folder / "runs.jsonl").read_text(encoding="utf-8").splitlines())
    entries = [(folder, row) for folder, row in entries if "wav" in row]
    random.Random(args.seed).shuffle(entries)
    args.output.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(args.reference, args.output / "reference.wav")
    answers, public = [], []
    for number, (folder, row) in enumerate(entries, 1):
        name = f"sample-{number:03d}.wav"
        shutil.copyfile(folder / row["wav"], args.output / name)
        public.append({"audio": name, "text": row["text"]})
        answers.append(dict(row, blind_audio=name, source_folder=str(folder.resolve())))
    save_json(args.output.parent / (args.output.name + "-answers.json"), answers)
    with (args.output / "scores.csv").open("x", encoding="utf-8-sig", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["audio", "text", "naturalness_1_to_5", "same_speaker_1_to_5", "expression_guess", "notes"])
        writer.writerows([r["audio"], r["text"], "", "", "", ""] for r in public)
    rows = "\n".join(f'<tr><td>{i}</td><td>{html.escape(r["text"])}</td><td><audio controls preload="none" src="{r["audio"]}"></audio></td></tr>' for i, r in enumerate(public, 1))
    page = '<!doctype html><html lang="zh"><meta charset="utf-8"><title>角色声音盲听</title><style>body{font:16px system-ui;max-width:1100px;margin:32px auto;padding:16px}td{padding:12px;border-bottom:1px solid #ddd}audio{max-width:100%}</style><h1>角色声音盲听</h1><p>先听固定角色参考，再判断每条是否像同一个人。自然度与一致性各打 1–5 分；表达选平静、开心、安慰、疑惑、不确定。请在 scores.csv 中记录，答案另存于上级目录。</p><audio controls src="reference.wav"></audio><p>该参考由 Qwen Serena 合成，并非真人录音。评估的是本角色的跨表达一致性与听感。</p><table>' + rows + '</table></html>'
    (args.output / "index.html").write_text(page, encoding="utf-8")
    print(json.dumps({"blind_samples": len(public), "output": str(args.output.resolve())}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    def local_model(p):
        p.add_argument("--model-dir", type=Path, default=ROOT / ".voice-local/qwen-customvoice")
        p.add_argument("--device", default="cuda:0", choices=["cpu", "cuda:0"])
    p = sub.add_parser("reference")
    local_model(p)
    p.add_argument("--output", type=Path, required=True)
    p.set_defaults(handler=prepare_reference)
    p = sub.add_parser("enroll")
    p.add_argument("--reference", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.set_defaults(handler=enroll)
    p = sub.add_parser("run")
    local_model(p)
    p.add_argument("--backend", required=True, choices=["qwen", "plus", "flash"])
    p.add_argument("--voices", type=Path, default=ROOT / ".voice-local/comparison-voices.json")
    p.add_argument("--cases", type=Path, default=Path(__file__).with_name("screening-cases.csv"))
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--repeats", type=int, default=1)
    p.add_argument("--limit", type=int)
    p.add_argument("--order-seed", type=int, default=31)
    p.add_argument("--max-cost-cny", type=float, default=2.0)
    p.add_argument("--play", action="store_true")
    p.add_argument("--audio-device", type=int)
    p.set_defaults(handler=run)
    p = sub.add_parser("package")
    p.add_argument("--runs", nargs="+", type=Path, required=True)
    p.add_argument("--reference", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--seed", type=int, default=83)
    p.set_defaults(handler=package)
    p = sub.add_parser("devices")
    def devices(_):
        import sounddevice as sd
        print(sd.query_devices())
    p.set_defaults(handler=devices)
    args = parser.parse_args()
    if args.command == "run" and (args.repeats < 1 or args.limit is not None and args.limit < 1 or not math.isfinite(args.max_cost_cny) or args.max_cost_cny <= 0):
        parser.error("repeats, limit and max-cost-cny must be positive finite values")
    try:
        args.handler(args)
    except KeyboardInterrupt:
        print("Cancelled. Partial output remains local; no retry was made.")
        return 130
    except Exception as error:
        print(safe_error(error))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
