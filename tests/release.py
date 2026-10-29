"""Release regressions using local Git remotes and fake publication services only."""

import hashlib
import importlib.util
import json
import os
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("release", ROOT / "scripts/release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def changelog(version):
    return f"{release.SEPARATOR}\nVersion: {version}\nDate: 2026-10-29\n  Changes:\n    - Release notes.\n"


class Portal:
    def __init__(self, events):
        self.events = events
        self.uploaded = None
        self.fail = False

    def exists(self, manifest):
        if self.uploaded and self.uploaded != manifest["sha1"]:
            raise release.ReleaseError("Different portal contents")
        return self.uploaded is not None

    def upload(self, manifest, archive):
        self.events.append("portal-upload")
        if self.fail:
            raise release.ReleaseError("Simulated upload failure")
        self.uploaded = manifest["sha1"]


class GitHub:
    repository = "test/mod"

    def __init__(self, events):
        self.events = events
        self.state = None

    def release(self, tag):
        return self.state

    def asset_matches(self, asset, path):
        return asset["digest"] == "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()

    def create_draft(self, manifest, commit, notes):
        self.events.append("github-draft")
        self.state = {"draft": True, "assets": []}
        return self.state

    def upload(self, tag, path):
        self.events.append("github-upload:" + path.name)
        self.state["assets"].append({"name": path.name, "digest": "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()})

    def publish(self, tag):
        self.events.append("github-publish")
        self.state["draft"] = False


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "source"
        self.origin = self.base / "origin.git"
        self.out = self.base / "out"
        self.root.mkdir()
        release.git(self.root, "init", "--initial-branch=main")
        release.git(self.root, "config", "user.name", "Release test")
        release.git(self.root, "config", "user.email", "test@example.invalid")
        release.git(self.root, "config", "commit.gpgsign", "false")
        release.git(self.root, "config", "tag.gpgsign", "false")
        self.info = {"name": "test-mod", "version": "1.2.3", "title": "Test mod", "factorio_version": "2.0"}
        (self.root / "info.json").write_text(json.dumps(self.info, indent=2) + "\n")
        (self.root / "changelog.txt").write_text(changelog("1.2.3"))
        (self.root / "control.lua").write_text("-- initial source\n")
        (self.root / "gui").mkdir()
        (self.root / "gui/main.lua").write_text("return {}\n")
        (self.root / "LICENSE").write_text("MIT\n")
        self.commit("Initial release")
        release.git(self.root, "tag", "v1.2.3")
        (self.root / "control.lua").write_text("-- faster source\n")
        self.source = self.commit("perf(output): 减少输出等待")
        release.git(self.root, "init", "--bare", str(self.origin))
        release.git(self.root, "remote", "add", "origin", str(self.origin))
        release.git(self.root, "push", "origin", "main", "--tags")
        self.events = []
        self.portal = Portal(self.events)
        self.github = GitHub(self.events)

    def commit(self, subject):
        release.git(self.root, "add", "--all")
        release.git(self.root, "commit", "-m", subject)
        return release.git(self.root, "rev-parse", "HEAD")

    def prepare(self):
        return release.prepare(self.root, self.out)

    def publish(self):
        return release.publish(self.root, self.out, self.portal, self.github)

    def retry_checkout(self):
        release.git(self.root, "checkout", "--detach", self.source)

    def test_patch_release_preserves_checkout_and_packages_only_runtime(self):
        for name in ("secret/key.md", "dist/old.lua", "tests/regression.lua", ".github/workflows/release.yml", "gui/.hidden"):
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("must never ship")
        original = {p: (self.root / p).read_bytes() for p in ("info.json", "changelog.txt")}
        manifest = self.prepare()
        self.assertEqual(manifest["version"], "1.2.4")
        self.assertEqual(manifest["source_commit"], self.source)
        self.assertIn("### Optimizations", (self.out / "notes.md").read_text())
        self.assertIn("减少输出等待", (self.out / "notes.md").read_text())
        for p, data in original.items():
            self.assertEqual((self.root / p).read_bytes(), data)
        with zipfile.ZipFile(self.out / manifest["archive"]) as z:
            self.assertEqual(set(z.namelist()), {"test-mod_1.2.4/" + p for p in
                ("info.json", "changelog.txt", "control.lua", "gui/main.lua", "LICENSE")})
        self.assertEqual(release.verify(self.root, self.out), manifest)

    def test_deterministic_across_mtimes_modes_and_retries(self):
        m1 = self.prepare()
        for p in release.package_mod.source_files(self.root):
            os.utime(p, (10, 10))
            p.chmod(0o755)
        out2 = self.base / "out2"
        m2 = release.prepare(self.root, out2)
        self.assertEqual(m1, m2)
        self.assertEqual((self.out / m1["archive"]).read_bytes(), (out2 / m2["archive"]).read_bytes())

    def test_explicit_version_and_notes_survive_retry_even_without_metadata_diff(self):
        self.info["version"] = "2.0.0"
        (self.root / "info.json").write_text(json.dumps(self.info, indent=2) + "\n")
        (self.root / "changelog.txt").write_text(changelog("2.0.0"))
        self.source = self.commit("feat: major upgrade")
        release.git(self.root, "push", "origin", "main")
        manifest = self.prepare()
        self.assertEqual(manifest["version"], "2.0.0")
        self.publish()
        self.assertEqual(release.git(self.root, "rev-parse", "HEAD^"), self.source)
        self.retry_checkout()
        rerun = release.prepare(self.root, self.base / "rerun")
        self.assertEqual(rerun, manifest)
        self.publish()
        self.assertEqual(self.events.count("github-publish"), 1)

    def test_packaging_failure_restores_source(self):
        original = (self.root / "info.json").read_bytes(), (self.root / "changelog.txt").read_bytes()
        with patch.object(release.package_mod, "package", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                self.prepare()
        self.assertEqual(original, ((self.root / "info.json").read_bytes(), (self.root / "changelog.txt").read_bytes()))

    def test_publish_order_atomic_metadata_push_and_safe_retry(self):
        m = self.prepare()
        self.publish()
        commit = release.git(self.root, "rev-parse", "HEAD")
        self.assertEqual(release.git(self.origin, "rev-parse", "refs/heads/main"), commit)
        self.assertEqual(release.git(self.origin, "rev-parse", m["tag"]), commit)
        self.assertEqual(release.git(self.root, "rev-parse", "HEAD^"), self.source)
        self.assertEqual(set(release.git(self.root, "diff", "--name-only", "HEAD^", "HEAD").splitlines()),
                         {"info.json", "changelog.txt"})
        self.assertIn("[skip ci]", release.git(self.root, "show", "-s", "--format=%s", "HEAD"))
        self.assertLess(self.events.index("github-draft"), self.events.index("portal-upload"))
        self.assertLess(self.events.index("portal-upload"), self.events.index("github-publish"))
        self.retry_checkout()
        events = list(self.events)
        self.publish()
        self.assertEqual(events, self.events)
        self.assertIn("Published **v1.2.4**", (self.out / "published.md").read_text())

    def test_portal_failure_keeps_draft_and_retry_completes(self):
        self.prepare()
        self.portal.fail = True
        with self.assertRaisesRegex(release.ReleaseError, "Simulated"):
            self.publish()
        self.assertTrue(self.github.state["draft"])
        self.assertNotIn("github-publish", self.events)
        self.retry_checkout()
        self.portal.fail = False
        self.publish()
        self.assertEqual(self.events.count("github-draft"), 1)
        self.assertEqual(sum(e.startswith("github-upload:") for e in self.events), 2)
        self.assertFalse(self.github.state["draft"])

    def test_github_publish_failure_reuses_successful_portal_upload(self):
        self.prepare()
        with patch.object(self.github, "publish", side_effect=release.ReleaseError("GitHub unavailable")):
            with self.assertRaises(release.ReleaseError):
                self.publish()
        self.retry_checkout()
        self.publish()
        self.assertEqual(self.events.count("portal-upload"), 1)

    def test_stale_push_skips_even_when_next_version_is_taken(self):
        m = self.prepare()
        (self.root / "control.lua").write_text("-- newer push\n")
        newer = self.commit("fix: newer change")
        release.git(self.root, "tag", m["tag"])
        release.git(self.root, "push", "origin", "main", "--tags")
        self.retry_checkout()
        self.portal.uploaded = "different-release"
        self.publish()
        self.assertEqual(self.events, [])
        self.assertEqual(release.git(self.origin, "rev-parse", "main"), newer)
        self.assertIn("skipped", (self.out / "published.md").read_text())

    def test_remote_push_rejection_has_no_publication_side_effects(self):
        self.prepare()
        hook = self.origin / "hooks/pre-receive"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)
        with self.assertRaises(release.ReleaseError):
            self.publish()
        self.assertEqual(self.events, [])
        self.assertEqual(release.git(self.origin, "rev-parse", "main"), self.source)
        self.assertEqual(release.git(self.origin, "tag", "--list", "v1.2.4"), "")

    def test_different_existing_assets_never_overwritten(self):
        m = self.prepare()
        self.github.state = {"draft": True, "assets": [{"name": m["archive"], "digest": "sha256:wrong"}]}
        with self.assertRaisesRegex(release.ReleaseError, "different contents"):
            self.publish()
        self.assertEqual(self.events, [])
        self.assertEqual(release.git(self.origin, "rev-parse", "main"), self.source)

    def test_tampered_archive_fails_before_publication(self):
        m = self.prepare()
        (self.out / m["archive"]).write_bytes(b"not a valid archive")
        with self.assertRaisesRegex(release.ReleaseError, "checksum mismatch"):
            self.publish()
        self.assertEqual(self.events, [])

    def test_missing_archive_source_rejected_even_with_updated_hashes(self):
        m = self.prepare()
        archive = self.out / m["archive"]
        with zipfile.ZipFile(archive) as z:
            entries = {n: z.read(n) for n in z.namelist() if not n.endswith("control.lua")}
        with zipfile.ZipFile(archive, "w") as z:
            for n, data in entries.items():
                z.writestr(n, data)
        m["sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
        m["sha1"] = hashlib.sha1(archive.read_bytes()).hexdigest()
        (self.out / "manifest.json").write_text(json.dumps(m))
        (self.out / "SHA256SUMS").write_text(f"{m['sha256']}  {m['archive']}\n")
        with self.assertRaisesRegex(release.ReleaseError, "missing, extra or duplicate"):
            self.publish()
        self.assertEqual(self.events, [])

    def test_changed_source_or_notes_rejected(self):
        self.prepare()
        (self.root / "control.lua").write_text("-- untested change\n")
        with self.assertRaisesRegex(release.ReleaseError, "Packaged source"):
            self.publish()
        release.git(self.root, "checkout", "--", "control.lua")
        (self.out / "notes.md").write_text("wrong notes")
        with self.assertRaisesRegex(release.ReleaseError, "notes"):
            self.publish()
        self.assertEqual(self.events, [])

    def test_final_readback_required_for_success(self):
        self.prepare()
        with patch.object(self.github, "publish"):
            with self.assertRaisesRegex(release.ReleaseError, "not confirmed"):
                self.publish()
        self.assertFalse((self.out / "published.md").exists())

    def test_upload_url_validation_and_no_api_key_forwarding(self):
        m = self.prepare()
        client = release.Factorio("fake-test-key")
        for url in ("http://mods.factorio.com/upload", "https://factorio.com.evil.invalid/upload",
                    "https://user@mods.factorio.com/upload", "https://mods.factorio.com:444/upload"):
            with patch.object(client, "json", return_value={"upload_url": url}) as api:
                with self.assertRaises(release.ReleaseError):
                    client.upload(m, self.out / m["archive"])
                self.assertEqual(api.call_count, 1)
        with patch.object(client, "json", side_effect=[{"upload_url": "https://uploads.factorio.com/signed"}, {"success": True}]) as api:
            with patch.object(client, "exists", return_value=True):
                client.upload(m, self.out / m["archive"])
        self.assertEqual(api.call_args_list[0].args[2]["Authorization"], "Bearer fake-test-key")
        self.assertNotIn("Authorization", api.call_args_list[1].args[2])


class GitHubLookupTests(unittest.TestCase):
    def test_published_release_uses_tag_endpoint(self):
        state = {"id": 123, "tag_name": "v1.2.4", "draft": False, "assets": []}
        response = subprocess.CompletedProcess([], 0, json.dumps(state).encode(), b"")
        with patch.object(release.subprocess, "run", return_value=response):
            with patch.object(release, "run") as listing:
                self.assertEqual(release.GitHub("test/mod").release("v1.2.4"), state)
                listing.assert_not_called()

    def test_tag_404_finds_draft_in_paginated_authenticated_listing(self):
        state = {"id": 124, "tag_name": "v1.2.4", "draft": True, "assets": []}
        response = subprocess.CompletedProcess([], 1, b"{}", b"gh: Not Found (HTTP 404)")
        pages = [[{"tag_name": "v1.2.5", "draft": False}], [state]]
        with patch.object(release.subprocess, "run", return_value=response):
            with patch.object(release, "run", return_value=json.dumps(pages)) as listing:
                self.assertEqual(release.GitHub("test/mod").release("v1.2.4"), state)
                listing.assert_called_once_with("gh", "api", "repos/test/mod/releases?per_page=100",
                                                "--paginate", "--slurp")

    def test_tag_404_with_no_matching_draft_is_missing(self):
        response = subprocess.CompletedProcess([], 1, b"{}", b"gh: Not Found (HTTP 404)")
        with patch.object(release.subprocess, "run", return_value=response):
            with patch.object(release, "run", return_value="[[]]"):
                self.assertIsNone(release.GitHub("test/mod").release("v1.2.4"))

    def test_api_failure_is_not_treated_as_missing_release(self):
        response = subprocess.CompletedProcess([], 1, b"{}", b"gh: Service unavailable (HTTP 503)")
        with patch.object(release.subprocess, "run", return_value=response):
            with patch.object(release, "run") as listing:
                with self.assertRaises(release.ReleaseError):
                    release.GitHub("test/mod").release("v1.2.4")
                listing.assert_not_called()


if __name__ == "__main__":
    unittest.main()
