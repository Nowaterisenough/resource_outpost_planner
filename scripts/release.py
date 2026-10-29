"""Prepare a patch release from main; publish the same tested archive to both portals."""

import argparse
from datetime import date
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib import error, parse, request
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\Z")
SEPARATOR = "-" * 99
spec = importlib.util.spec_from_file_location("package_mod", ROOT / "scripts/package-mod.py")
package_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package_mod)


class ReleaseError(Exception):
    pass


def run(*args, cwd=ROOT, binary=False):
    result = subprocess.run(args, cwd=cwd, capture_output=True)
    if result.returncode:
        # gh/git can include credential or signed URL details in errors; do not echo them.
        raise ReleaseError(f"{args[0]} {args[1]} failed (exit {result.returncode})")
    return result.stdout if binary else result.stdout.decode().strip()


def git(root, *args):
    return run("git", *args, cwd=root)


def version_tuple(version):
    if not VERSION.fullmatch(version):
        raise ReleaseError("Version must be three non-negative integers, for example 1.10.4")
    return tuple(map(int, version.split(".")))


def release_notes(changelog, version):
    sections = re.split(r"(?m)^-{10,}\s*$", changelog)
    sections = [s.strip() for s in sections if s.strip()]
    if not sections or sections[0].splitlines()[0] != f"Version: {version}":
        raise ReleaseError("The first changelog entry must match info.json")
    lines = sections[0].splitlines()
    if len(lines) < 4 or not lines[1].startswith("Date: "):
        raise ReleaseError("The latest changelog needs a date and release notes")
    try:
        date.fromisoformat(lines[1][6:])
    except ValueError as exc:
        raise ReleaseError("Invalid changelog date") from exc
    if not any(line.startswith("    - ") for line in lines):
        raise ReleaseError("The latest changelog must contain at least one bullet")
    notes = [f"## {version}", "", lines[1], ""]
    for line in lines[2:]:
        if line.startswith("  ") and not line.startswith("    ") and line.endswith(":"):
            notes.extend([f"### {line.strip()[:-1]}", ""])
        else:
            notes.append(line[4:] if line.startswith("    ") else line)
    return "\n".join(notes).rstrip() + "\n"


def next_release(root):
    info = json.loads((root / "info.json").read_text(encoding="utf-8-sig"))
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", info["name"]):
        raise ReleaseError("Invalid mod name")
    current = version_tuple(info["version"])
    source = git(root, "rev-parse", "HEAD")
    tags = [t for t in git(root, "tag", "--merged", source, "--list", "v*").splitlines()
            if VERSION.fullmatch(t[1:])]
    previous = max(tags, key=lambda t: version_tuple(t[1:])) if tags else None
    if previous and current <= version_tuple(previous[1:]):
        major, minor, patch = version_tuple(previous[1:])
        info["version"] = f"{major}.{minor}.{patch + 1}"
    changelog = (root / "changelog.txt").read_text(encoding="utf-8-sig")
    top = re.search(r"(?m)^Version: (.+)$", changelog)
    if not top or top[1] != info["version"]:
        revision = f"{previous}..{source}" if previous else source
        subjects = git(root, "log", "--reverse", "--format=%h %s", revision).splitlines()
        groups = {"Features": [], "Bugfixes": [], "Optimizations": [], "Changes": []}
        for entry in subjects:
            subject = entry.split(" ", 1)[1]
            kind = subject.split(":", 1)[0].split("(", 1)[0]
            category = {"feat": "Features", "fix": "Bugfixes", "perf": "Optimizations"}.get(kind, "Changes")
            groups[category].append(entry)
        if not subjects:
            raise ReleaseError("No changes since the previous release")
        # Source date is stable when a failed run is retried on a different day.
        header = [SEPARATOR, f"Version: {info['version']}", f"Date: {git(root, 'show', '-s', '--format=%cs', source)}"]
        for category, entries in groups.items():
            if entries:
                header.extend([f"  {category}:", *(f"    - {entry}" for entry in entries)])
        changelog = "\n".join(header) + "\n" + changelog
    notes = release_notes(changelog, info["version"])
    return info, changelog, notes, source


def prepare(root, output):
    info, changelog, notes, source = next_release(root)
    original = {p: (root / p).read_bytes() for p in ("info.json", "changelog.txt")}
    info_text = json.dumps(info, ensure_ascii=False, indent=2) + "\n"
    output.mkdir(parents=True, exist_ok=True)
    # Package the prospective version without leaving local source edits behind.
    try:
        (root / "info.json").write_text(info_text)
        (root / "changelog.txt").write_text(changelog)
        archive = package_mod.package(root, output)
    finally:
        for p, data in original.items():
            (root / p).write_bytes(data)
    data = archive.read_bytes()
    manifest = dict(name=info["name"], title=info["title"], version=info["version"],
                    tag="v" + info["version"], source_commit=source, archive=archive.name,
                    sha256=hashlib.sha256(data).hexdigest(), sha1=hashlib.sha1(data).hexdigest())
    (output / "info.json").write_text(info_text)
    (output / "changelog.txt").write_text(changelog)
    (output / "notes.md").write_text(notes)
    (output / "SHA256SUMS").write_text(f"{manifest['sha256']}  {archive.name}\n")
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared {manifest['tag']} from {source[:12]}: {archive.name}")
    return manifest


def verify(root, output):
    m = json.loads((output / "manifest.json").read_text())
    version_tuple(m["version"])
    if m["tag"] != "v" + m["version"] or m["archive"] != f"{m['name']}_{m['version']}.zip":
        raise ReleaseError("Invalid release artifact identity")
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", m["name"]):
        raise ReleaseError("Invalid artifact mod name")
    if git(root, "rev-parse", "HEAD") != m["source_commit"]:
        raise ReleaseError("Release artifact belongs to another source commit")
    data = (output / m["archive"]).read_bytes()
    if hashlib.sha256(data).hexdigest() != m["sha256"] or hashlib.sha1(data).hexdigest() != m["sha1"]:
        raise ReleaseError("Release archive checksum mismatch")
    info = json.loads((output / "info.json").read_text())
    if (info["name"], info["version"]) != (m["name"], m["version"]):
        raise ReleaseError("Release metadata mismatch")
    if (output / "notes.md").read_text() != release_notes((output / "changelog.txt").read_text(), m["version"]):
        raise ReleaseError("Release notes do not match the changelog")
    if (output / "SHA256SUMS").read_text() != f"{m['sha256']}  {m['archive']}\n":
        raise ReleaseError("Release checksum file mismatch")
    with zipfile.ZipFile(output / m["archive"]) as z:
        prefix = f"{m['name']}_{m['version']}/"
        expected_names = {prefix + p.relative_to(root).as_posix() for p in package_mod.source_files(root)}
        names = z.namelist()
        if len(names) != len(set(names)) or set(names) != expected_names:
            raise ReleaseError("Release archive has missing, extra or duplicate files")
        for entry in names:
            if not entry.startswith(prefix) or ".." in Path(entry).parts:
                raise ReleaseError("Invalid archive member path")
            relative = entry[len(prefix):]
            expected = output / relative if relative in ("info.json", "changelog.txt") else root / relative
            if not expected.is_file() or z.read(entry) != expected.read_bytes():
                raise ReleaseError("Packaged source differs from the checked-out source")
        if json.loads(z.read(prefix + "info.json")) != info:
            raise ReleaseError("Packaged info.json mismatch")
    return m


class NoRedirect(request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Factorio:
    def __init__(self, key):
        self.key = key
        self.opener = request.build_opener(NoRedirect())

    def json(self, url, data=None, headers=None):
        try:
            with self.opener.open(request.Request(url, data=data, headers=headers or {}), timeout=60) as response:
                result = json.load(response)
        except error.HTTPError as exc:
            raise ReleaseError(f"Factorio API returned HTTP {exc.code}") from None
        except (error.URLError, TimeoutError, ValueError):
            raise ReleaseError("Factorio API request failed; retry to reconcile publication state") from None
        if result.get("error"):
            raise ReleaseError("Factorio API rejected the request")
        return result

    def exists(self, m):
        result = self.json(f"https://mods.factorio.com/api/mods/{m['name']}/full")
        release = next((r for r in result.get("releases", []) if r["version"] == m["version"]), None)
        if release and (release.get("sha1") != m["sha1"] or release.get("file_name") != m["archive"]):
            raise ReleaseError("Factorio version already exists with different contents; refusing to overwrite")
        return release is not None

    def upload(self, m, archive):
        boundary = uuid.uuid4().hex
        init = self.json("https://mods.factorio.com/api/v2/mods/releases/init_upload",
                         parse.urlencode({"mod": m["name"]}).encode(),
                         {"Authorization": "Bearer " + self.key, "Content-Type": "application/x-www-form-urlencoded"})
        url = init.get("upload_url", "")
        destination = parse.urlsplit(url)
        if (destination.scheme != "https" or not destination.hostname
                or not (destination.hostname == "factorio.com" or destination.hostname.endswith(".factorio.com"))
                or destination.username or destination.password or destination.port not in (None, 443)):
            raise ReleaseError("Unexpected Factorio upload destination")
        body = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{archive.name}"\r\n'
                'Content-Type: application/zip\r\n\r\n').encode() + archive.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
        # The signed upload URL does not need the account API key.
        result = self.json(url, body, {"Content-Type": f"multipart/form-data; boundary={boundary}"})
        if result.get("success") is not True:
            raise ReleaseError("Factorio did not confirm upload success")
        for delay in (0, 2, 4):
            time.sleep(delay)
            if self.exists(m):
                return
        raise ReleaseError("Factorio upload not yet visible; rerun to verify without duplicate upload")


class GitHub:
    def __init__(self, repository):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
            raise ReleaseError("Invalid GITHUB_REPOSITORY")
        self.repository = repository

    def release(self, tag):
        result = subprocess.run(["gh", "api", f"repos/{self.repository}/releases/tags/{tag}"], capture_output=True)
        if result.returncode:
            if b"(HTTP 404)" in result.stderr:
                return None
            raise ReleaseError("Could not read GitHub release state")
        return json.loads(result.stdout)

    def asset_matches(self, asset, path):
        expected = hashlib.sha256(path.read_bytes()).hexdigest()
        if asset.get("digest"):
            return asset["digest"] == "sha256:" + expected
        data = run("gh", "api", f"repos/{self.repository}/releases/assets/{asset['id']}",
                   "-H", "Accept: application/octet-stream", binary=True)
        return hashlib.sha256(data).hexdigest() == expected

    def create_draft(self, m, commit, notes):
        run("gh", "release", "create", m["tag"], "--repo", self.repository, "--verify-tag", "--draft",
            "--title", f"{m['title']} {m['version']}", "--target", commit, "--notes-file", str(notes))
        return self.release(m["tag"])

    def upload(self, tag, path):
        run("gh", "release", "upload", tag, str(path), "--repo", self.repository)

    def publish(self, tag):
        release = self.release(tag)
        # Semver selection prevents a retried older draft from becoming the latest release.
        run("gh", "api", f"repos/{self.repository}/releases/{release['id']}",
            "--method", "PATCH", "-F", "draft=false", "-f", "make_latest=legacy")


def existing_release_commit(root, output, m):
    """Validate a retry against the immutable release tag, without mutating anything."""
    existing = git(root, "tag", "--list", m["tag"])
    if existing:
        commit = git(root, "rev-parse", m["tag"] + "^{commit}")
        if commit != m["source_commit"]:
            if git(root, "rev-parse", commit + "^") != m["source_commit"]:
                raise ReleaseError("Release tag belongs to another push")
            changed = git(root, "diff", "--name-only", m["source_commit"], commit).splitlines()
            if set(changed) - {"info.json", "changelog.txt"}:
                raise ReleaseError("Release tag changes code beyond version metadata")
        for path in ("info.json", "changelog.txt"):
            if run("git", "show", f"{commit}:{path}", cwd=root, binary=True) != (output / path).read_bytes():
                raise ReleaseError("Release tag metadata differs from the tested artifact")
        return commit
    return None


def release_commit(root, output, m):
    """Atomically advance main and create a tag, or reuse this run's immutable tag."""
    existing = existing_release_commit(root, output, m)
    if existing:
        return existing
    remote = git(root, "ls-remote", "origin", "refs/heads/main").split()
    if not remote or remote[0] != m["source_commit"]:
        return None  # A newer push will publish the combined changes; never move main backwards.
    for path in ("info.json", "changelog.txt"):
        (root / path).write_bytes((output / path).read_bytes())
    git(root, "add", "--", "info.json", "changelog.txt")
    if set(git(root, "diff", "--cached", "--name-only").splitlines()) - {"info.json", "changelog.txt"}:
        raise ReleaseError("Unrelated staged files found; refusing to include them in release commit")
    # Always use a child commit: a rerun of the source must not count its own tag as a previous release.
    git(root, "-c", "user.name=github-actions[bot]", "-c", "user.email=41898282+github-actions[bot]@users.noreply.github.com",
        "commit", "--allow-empty", "-m", f"build(release): 发布模组 {m['version']} [skip ci]")
    commit = git(root, "rev-parse", "HEAD")
    git(root, "tag", m["tag"], commit)
    git(root, "push", "--atomic", "origin", "HEAD:refs/heads/main", f"refs/tags/{m['tag']}")
    return commit


def publish(root, output, portal, github):
    m = verify(root, output)
    existing = git(root, "tag", "--list", m["tag"])
    remote = git(root, "ls-remote", "origin", "refs/heads/main").split()
    if not remote:
        raise ReleaseError("Remote main is missing")
    if remote[0] != m["source_commit"]:
        try:
            owned = existing_release_commit(root, output, m) if existing else None
        except ReleaseError:
            owned = None
        if not owned:
            (output / "published.md").write_text("A newer push reached main; this stale run skipped publication.\n")
            print("Skipped stale main push; the latest workflow run will publish.")
            return
    # Validate both existing destinations before any external mutation.
    portal_done = portal.exists(m)
    release = github.release(m["tag"])
    assets = {a["name"]: a for a in (release or {}).get("assets", [])}
    paths = [output / m["archive"], output / "SHA256SUMS"]
    for path in paths:
        if path.name in assets and not github.asset_matches(assets[path.name], path):
            raise ReleaseError("GitHub release asset has different contents; refusing to overwrite")
        if release and not release["draft"] and path.name not in assets:
            raise ReleaseError("Published GitHub release is missing an expected asset")
    commit = release_commit(root, output, m)
    if commit is None:
        (output / "published.md").write_text("A newer push reached main; this stale run skipped publication.\n")
        print("Skipped stale main push; the latest workflow run will publish.")
        return
    if not release:
        release = github.create_draft(m, commit, output / "notes.md")
        if not release:
            raise ReleaseError("GitHub draft creation was not confirmed")
    for path in paths:
        if path.name not in assets:
            github.upload(m["tag"], path)
    if not portal_done:
        portal.upload(m, output / m["archive"])
    if release["draft"]:
        github.publish(m["tag"])
    confirmed = github.release(m["tag"])
    final_assets = {a["name"]: a for a in (confirmed or {}).get("assets", [])}
    if (not confirmed or confirmed["draft"] or not portal.exists(m)
            or any(p.name not in final_assets or not github.asset_matches(final_assets[p.name], p) for p in paths)):
        raise ReleaseError("Publication not confirmed; rerun to reconcile without overwriting assets")
    result = (f"Published **{m['tag']}** at `{commit}`.\n\n"
              f"- [GitHub Release](https://github.com/{github.repository}/releases/tag/{m['tag']})\n"
              f"- [Factorio Mod Portal](https://mods.factorio.com/mod/{m['name']})\n")
    (output / "published.md").write_text(result)
    print(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "publish"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            prepare(ROOT, args.output.resolve())
        else:
            if os.environ.get("GITHUB_REF") != "refs/heads/main":
                raise ReleaseError("Publishing is only permitted from main")
            if not os.environ.get("FACTORIO_API_KEY") or not os.environ.get("GH_TOKEN"):
                raise ReleaseError("FACTORIO_API_KEY and GH_TOKEN are required")
            publish(ROOT, args.output.resolve(), Factorio(os.environ["FACTORIO_API_KEY"]),
                    GitHub(os.environ.get("GITHUB_REPOSITORY", "")))
    except (ReleaseError, OSError, ValueError, KeyError, zipfile.BadZipFile) as exc:
        message = str(exc) if isinstance(exc, ReleaseError) else type(exc).__name__
        print("Release failed: " + message, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
