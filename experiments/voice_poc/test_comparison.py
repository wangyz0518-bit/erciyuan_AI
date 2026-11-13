"""Offline checks for paid-call boundaries and stream framing; no API calls."""

import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import compare_voices as c


class SocketFixture:
    def __init__(self, events):
        self.events, self.sent, self.closed = list(events), [], False

    def send(self, text):
        self.sent.append(json.loads(text))

    def recv(self):
        next_event = self.events.pop(0)
        if isinstance(next_event, bytes):
            return next_event
        return json.dumps({"header": {"event": next_event, "task_id": self.sent[-1]["header"]["task_id"]},
                           "payload": {"usage": {"characters": 4}}})

    def settimeout(self, value):
        pass

    def close(self):
        self.closed = True


class StreamTests(unittest.TestCase):
    def cloud(self, events):
        socket = SocketFixture(events)
        return c.CloudVoice("cosyvoice-v3.5-plus", "example", "secret", "workspace",
                            socket_factory=lambda *a, **k: socket), socket

    def test_ack_before_text_and_split_pcm_sample(self):
        voice, socket = self.cloud(["task-started", b"\x01", b"\x00\x02\x00", "task-finished"])
        received = []
        pcm, metrics = voice.generate("你好", "平静", 21, received.append)
        self.assertEqual(pcm, b"\x01\x00\x02\x00")
        self.assertEqual(received, [b"\x01", b"\x00\x02\x00"])
        self.assertEqual([p["header"]["action"] for p in socket.sent], ["run-task", "continue-task", "finish-task"])
        self.assertEqual(metrics["provider_characters"], 4)
        self.assertFalse(metrics["connection_reused"])
        socket.events = ["task-started", b"\x01\x00", "task-finished"]
        self.assertTrue(voice.generate("你好", "平静", 21, lambda _: None)[1]["connection_reused"])

    def test_failure_stops_before_text_without_retry(self):
        voice, socket = self.cloud(["task-failed"])
        with self.assertRaises(c.ExperimentError):
            voice.generate("你好", "平静", 21, lambda _: None)
        self.assertEqual(len(socket.sent), 1)
        self.assertTrue(socket.closed)
        self.assertIsNone(voice.ws)

    def test_truncated_audio_is_rejected_and_connection_closed(self):
        voice, socket = self.cloud(["task-started", b"\x01", "task-finished"])
        with self.assertRaises(c.ExperimentError):
            voice.generate("你好", "平静", 21, lambda _: None)
        self.assertTrue(socket.closed)

    def test_cloud_error_keeps_code_but_hides_private_message(self):
        voice, socket = self.cloud([])
        socket.recv = lambda: json.dumps({"header": {"event": "task-failed",
            "task_id": socket.sent[-1]["header"]["task_id"], "error_code": "InternalError",
            "error_message": "internal failure Authorization: Bearer secret voice-id private"}})
        with self.assertRaises(c.ExperimentError) as caught:
            voice.generate("你好", "平静", 21, lambda _: None)
        self.assertIn("code=InternalError", str(caught.exception))
        self.assertNotIn("secret", str(caught.exception))
        self.assertNotIn("private", str(caught.exception))
        self.assertTrue(socket.closed)

    def test_wrong_task_cannot_be_mixed_into_current_audio(self):
        voice, socket = self.cloud([])
        socket.recv = lambda: json.dumps({"header": {"event": "task-started", "task_id": "wrong-task"}})
        with self.assertRaises(c.ExperimentError):
            voice.generate("你好", "平静", 21, lambda _: None)
        self.assertTrue(socket.closed)

    def test_key_only_stream_uses_official_beijing_endpoint(self):
        with patch.dict("os.environ", {"DASHSCOPE_API_KEY": "secret", "DASHSCOPE_WORKSPACE_ID": ""}):
            key, workspace = c.credentials()
        socket = SocketFixture(["task-started", b"\x01\x00", "task-finished"])
        connections = []
        def connect(url, **kwargs):
            connections.append((url, kwargs))
            return socket
        voice = c.CloudVoice("cosyvoice-v3.5-plus", "example", key, workspace, socket_factory=connect)
        voice.generate("你好", "平静", 21, lambda _: None)
        self.assertEqual(connections[0][0], "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
        self.assertEqual(connections[0][1]["header"], ["Authorization: Bearer secret"])

    def test_key_only_enrollment_uses_default_endpoint(self):
        with patch("requests.post") as post:
            post.return_value.ok = True
            post.return_value.json.return_value = {"output": {"status": "OK"}}
            c.enrollment_request("secret", "", {"action": "query_voice", "voice_id": "saved"})
        self.assertEqual(post.call_args.args[0], "https://dashscope.aliyuncs.com/api/v1/services/audio/tts/customization")


class BoundaryTests(unittest.TestCase):
    def test_budget_gate_precedes_credentials_and_output_creation(self):
        with tempfile.TemporaryDirectory() as folder:
            args = SimpleNamespace(cases=Path(__file__).with_name("screening-cases.csv"), limit=None,
                repeats=100, order_seed=31, backend="plus", max_cost_cny=.01, output=Path(folder) / "output")
            with patch.object(c, "credentials", side_effect=AssertionError("credentials must not be read")):
                with self.assertRaises(ValueError):
                    c.run(args)
            self.assertFalse(args.output.exists())

    def test_workspace_cannot_redirect_key_to_another_domain(self):
        with patch.dict("os.environ", {"DASHSCOPE_API_KEY": "secret", "DASHSCOPE_WORKSPACE_ID": "host.example/path"}):
            with self.assertRaises(ValueError):
                c.credentials()

    def test_key_only_voice_manifest_cannot_cross_credentials(self):
        self.assertNotEqual(c.scope_fingerprint("key-one", ""), c.scope_fingerprint("key-two", ""))
        self.assertEqual(c.scope_fingerprint("key-one", "workspace"), c.hashlib.sha256(b"workspace").hexdigest())

    def test_exception_logs_do_not_include_secrets(self):
        self.assertNotIn("secret-key", c.safe_error(RuntimeError("Authorization: Bearer secret-key")))

    def test_summary_excludes_reconnected_cold_requests_and_preserves_failed_attempt(self):
        records = [dict(position=1, backend="flash", wav="a.wav", connection_reused=False,
                        first_audio_seconds=10, provider_characters=20),
                   dict(position=2, backend="flash", wav="b.wav", connection_reused=True,
                        first_audio_seconds=1, provider_characters=30),
                   dict(position=3, backend="flash", error="failed"),
                   dict(position=4, backend="flash", wav="c.wav", connection_reused=False,
                        first_audio_seconds=20, provider_characters=10)]
        result = c.summarize(records, None)
        self.assertEqual(result["attempted"], 4)
        self.assertEqual(result["successful"], 3)
        self.assertEqual(result["warm_count"], 1)
        self.assertEqual(result["warm"]["first_audio_seconds"]["p95"], 1)
        self.assertEqual(result["provider_usage_reported_count"], 3)
        self.assertEqual(result["provider_metered_characters"], 60)

    def test_billing_handles_han_and_punctuation(self):
        self.assertEqual(c.billable_characters("中A文123"), 8)
        self.assertEqual(c.billable_characters("中文。"), 5)
        self.assertTrue(all(c.billable_characters(s) <= 100 for s in c.STYLES.values()))

    def test_enrollment_resumes_without_creating_new_voices(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            reference = folder / "reference.wav"
            c.write_wav(reference, b"\x01\x00" * 240000)
            manifest = folder / "voices.json"
            c.save_json(manifest, {"reference_sha256": c.sha256(reference),
                "workspace_sha256": c.hashlib.sha256(b"workspace").hexdigest(),
                "voices": {model: model + "-saved" for model in c.MODELS.values()}})
            calls = []
            def fake_request(key, workspace, payload):
                calls.append(payload)
                return {"status": "OK"}
            with patch.object(c, "credentials", return_value=("secret", "workspace")), \
                 patch.object(c, "enrollment_request", side_effect=fake_request):
                c.enroll(SimpleNamespace(reference=reference, output=manifest))
            self.assertEqual([x["action"] for x in calls], ["query_voice", "query_voice"])

    def test_playback_does_not_count_leading_silence_as_first_voice(self):
        player = c.Playback(False)
        player.enabled = True
        player.started = 10
        player.pending = bytearray(b"\0\0" * 40 + b"\xff\x7f" + b"\0\0" * 39)
        player.done = True
        class Finished(Exception):
            pass
        player.sd = SimpleNamespace(CallbackStop=Finished)
        output = bytearray(160)
        with patch.object(c.time, "perf_counter", return_value=12):
            with self.assertRaises(Finished):
                player.callback(output, 80, SimpleNamespace(outputBufferDacTime=101, currentTime=100),
                                SimpleNamespace(output_underflow=False))
        self.assertAlmostEqual(player.first_dac, 3 + 40 / 24000)
        self.assertEqual(player.starved_frames, 0)


if __name__ == "__main__":
    unittest.main()
