"""No SDK, model files, network, or third-party fixtures are used here."""

import io
import json
import stat
import unittest
import zipfile
from unittest.mock import patch

import avatar_zip_preflight as preflight


def make_manifest(**override):
    document = {
        "format": "erciyuan-avatar",
        "formatVersion": "0.1",
        "id": "hero_001",
        "version": "1.0.0",
        "name": "Synthetic Fixture",
        "renderer": "live2d-cubism",
        "runtimeProfile": "native-r5-basic-v1",
        "entry": "model/hero.model3.json",
        "preview": "preview.png",
        "actions": {},
        "expressions": {},
    }
    document.update(override)
    return json.dumps(document).encode("utf-8")


def make_zip(*, manifest=None, extra=None, compression=zipfile.ZIP_STORED):
    archive_bytes = io.BytesIO()
    entries = [
        ("manifest.json", manifest if manifest is not None else make_manifest()),
        ("model/hero.model3.json", b'{"Version":3}'),
        ("preview.png", b"PNG_TEST_BYTES"),
    ]
    entries.extend(extra or [])
    with zipfile.ZipFile(archive_bytes, "w", compression=compression) as archive:
        for name, content in entries:
            archive.writestr(name, content)
    return archive_bytes.getvalue()


class ArchivePreflightTests(unittest.TestCase):
    def inspect(self, contents):
        return preflight.inspect_zip(io.BytesIO(contents))

    def test_valid_package_is_not_extracted(self):
        result = self.inspect(make_zip())
        self.assertEqual(result["id"], "hero_001")
        self.assertEqual(result["version"], "1.0.0")
        self.assertEqual(result["entries"], 3)
        self.assertTrue(result["preflight_only"])

    def test_rejects_parent_path(self):
        with self.assertRaisesRegex(preflight.UnsafeAvatarArchive, "path"):
            self.inspect(make_zip(extra=[("../escape.png", b"BAD")]))

    def test_rejects_windows_backslash(self):
        with self.assertRaisesRegex(preflight.UnsafeAvatarArchive, "path"):
            self.inspect(make_zip(extra=[("model\\escape.png", b"BAD")]))

    def test_rejects_duplicate_names_even_when_case_differs(self):
        with self.assertRaisesRegex(preflight.UnsafeAvatarArchive, "Duplicate"):
            self.inspect(make_zip(extra=[("PREVIEW.PNG", b"OTHER")]))

    def test_rejects_unix_symlink(self):
        link = zipfile.ZipInfo("model/symlink.png")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaisesRegex(preflight.UnsafeAvatarArchive, "Links"):
            self.inspect(make_zip(extra=[(link, b"../../private")]))

    def test_rejects_compression_bomb(self):
        with self.assertRaisesRegex(preflight.UnsafeAvatarArchive, "ratio"):
            self.inspect(
                make_zip(
                    extra=[("model/padding.json", b"0" * 30000)],
                    compression=zipfile.ZIP_DEFLATED,
                )
            )

    def test_rejects_missing_manifest_resource(self):
        with self.assertRaisesRegex(preflight.UnsafeAvatarArchive, "manifest resources"):
            self.inspect(make_zip(manifest=make_manifest(preview="missing.png")))

    def test_rejects_duplicate_json_keys(self):
        data = make_manifest().decode("utf-8").replace(
            '"version": "1.0.0",', '"version": "1.0.0", "version": "1.0.1",'
        )
        with self.assertRaisesRegex(preflight.UnsafeAvatarArchive, "Duplicate JSON"):
            self.inspect(make_zip(manifest=data.encode("utf-8")))

    def test_rejects_bad_version(self):
        with self.assertRaisesRegex(preflight.UnsafeAvatarArchive, "manifest resources"):
            self.inspect(make_zip(manifest=make_manifest(version="../1.0.0")))

    def test_rejects_executable_payload(self):
        with self.assertRaisesRegex(preflight.UnsafeAvatarArchive, "resource type"):
            self.inspect(make_zip(extra=[("run.sh", b"echo bad")]))

    def test_rejects_bad_crc_before_reporting_acceptance(self):
        contents = make_zip()
        self.assertIn(b"PNG_TEST_BYTES", contents)
        damaged = contents.replace(b"PNG_TEST_BYTES", b"PNG_TEST_BYTEX")
        with self.assertRaisesRegex(preflight.UnsafeAvatarArchive, "CRC"):
            self.inspect(damaged)

    def test_rejects_size_above_configured_bounds(self):
        with patch.object(preflight, "MAX_FILE_BYTES", 6):
            with self.assertRaisesRegex(preflight.UnsafeAvatarArchive, "size"):
                self.inspect(make_zip())

    def test_directory_entries_allowed_without_extracting(self):
        result = self.inspect(make_zip(extra=[("extra/", b"")]))
        self.assertEqual(result["entries"], 3)


if __name__ == "__main__":
    unittest.main()
