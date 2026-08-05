#!/usr/bin/env python3
# Install a website as a Chromium web app with its own user-data directory.

import argparse
import fcntl
import json
import os
import re
import select
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path
from urllib.parse import urljoin

DATA_HOME = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")
APPLICATIONS = DATA_HOME / "applications"
CHROMIUM_DEFAULT_DIR = Path.home() / ".config" / "chromium"
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/150.0.0.0 Safari/537.36"
)

# PWA.install is only handed to DevTools clients that pass Chromium's
# AllowUnsafeOperations gate, which excludes --remote-debugging-port.
# The pipe transport (CDP over fd 3/4, NUL-delimited JSON) is the only way in.
LAUNCH_FLAGS = [
    "--remote-debugging-pipe",
    "--no-first-run",
    "--no-default-browser-check",
    "--no-startup-window",
]


class CdpError(Exception):
    pass


def die(message):
    sys.exit(f"Error: {message}")


def slugify(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def data_dir_for(slug):
    return Path.home() / ".config" / f"chromium-{slug}"


def profile_in_use(data_dir):
    """A second Chromium on the same profile hands off to the running one and
    exits, taking the DevTools pipe with it."""
    try:
        lock = os.readlink(data_dir / "SingletonLock")
    except OSError:
        return False
    pid = lock.rsplit("-", 1)[-1]
    return pid.isdigit() and Path(f"/proc/{pid}").exists()


class Chromium:
    """A Chromium instance driven over the DevTools pipe transport."""

    def __init__(self, data_dir):
        self.data_dir = data_dir
        self._buffer = b""
        self._last_id = 0

    def __enter__(self):
        chromium = shutil.which("chromium")
        if not chromium:
            die("chromium not found on PATH")
        if profile_in_use(self.data_dir):
            die(f"Chromium is already running on {self.data_dir}; close that window first")

        to_child_r, to_child_w = os.pipe()
        from_child_r, from_child_w = os.pipe()
        # os.pipe() hands back low descriptors, so move our own ends out of the
        # way before putting the child's ends on fd 3 and 4.
        self._write_fd = fcntl.fcntl(to_child_w, fcntl.F_DUPFD, 10)
        self._read_fd = fcntl.fcntl(from_child_r, fcntl.F_DUPFD, 10)
        os.close(to_child_w)
        os.close(from_child_r)
        os.dup2(to_child_r, 3, inheritable=True)
        os.dup2(from_child_w, 4, inheritable=True)
        os.set_inheritable(3, True)
        os.set_inheritable(4, True)
        for fd in (to_child_r, from_child_w):
            if fd not in (3, 4):
                os.close(fd)

        self.proc = subprocess.Popen(
            [chromium, f"--user-data-dir={self.data_dir}", *LAUNCH_FLAGS],
            pass_fds=(3, 4),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        os.close(3)
        os.close(4)
        return self

    def __exit__(self, *_):
        try:
            self.call("Browser.close", timeout=20)
            self.proc.wait(timeout=20)
        except Exception:
            self.proc.kill()
        os.close(self._write_fd)
        os.close(self._read_fd)
        return False

    def call(self, method, params=None, timeout=180):
        self._last_id += 1
        message = {"id": self._last_id, "method": method}
        if params:
            message["params"] = params
        os.write(self._write_fd, json.dumps(message).encode() + b"\0")
        while True:
            reply = self._receive(timeout)
            if reply.get("id") != message["id"]:
                continue
            if "error" in reply:
                raise CdpError(reply["error"].get("message", json.dumps(reply["error"])))
            return reply.get("result", {})

    def _receive(self, timeout):
        while b"\0" not in self._buffer:
            ready, _, _ = select.select([self._read_fd], [], [], timeout)
            if not ready:
                raise CdpError(f"timed out after {timeout}s waiting for Chromium")
            chunk = os.read(self._read_fd, 65536)
            if not chunk:
                raise CdpError("Chromium closed the DevTools pipe")
            self._buffer += chunk
        raw, self._buffer = self._buffer.split(b"\0", 1)
        return json.loads(raw)


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read().decode(errors="replace")


def resolve_manifest_id(url):
    """Chromium keys web apps by manifest id, which defaults to start_url."""
    try:
        html = fetch(url)
    except Exception as error:
        print(f"! could not fetch {url}: {error}")
        return None
    for tag in re.findall(r"<link\b[^>]*>", html, re.I):
        if not re.search(r"""rel\s*=\s*["']?[^"'>]*\bmanifest\b""", tag, re.I):
            continue
        href = re.search(r"""href\s*=\s*["']([^"']+)""", tag, re.I)
        if not href:
            continue
        manifest_url = urljoin(url, href.group(1))
        try:
            manifest = json.loads(fetch(manifest_url))
        except Exception as error:
            print(f"! could not read manifest {manifest_url}: {error}")
            return None
        identifier = manifest.get("id") or manifest.get("start_url")
        return urljoin(manifest_url, identifier) if identifier else None
    return None


def manifest_id_from_error(message):
    """The id mismatch error names the id Chromium expected; reuse it."""
    match = re.search(r"does not match input url or app id (\S+)", message)
    return match.group(1).rstrip(".") if match else None


def read_desktop_file(entry):
    # $HOME/.local/share/applications collects entries from all sorts of
    # installers: some are not valid UTF-8, some are dangling symlinks.
    try:
        return entry.read_text(errors="replace")
    except OSError:
        return ""


def read_entry(entry):
    fields = {}
    for line in read_desktop_file(entry).splitlines():
        key, _, value = line.partition("=")
        fields.setdefault(key, value)
    return fields


def find_entry(slug):
    data_dir = str(data_dir_for(slug))
    for entry in sorted(APPLICATIONS.glob("*.desktop")):
        text = read_desktop_file(entry)
        if f"X-Webapp-Slug={slug}" in text or f"--user-data-dir={data_dir}" in text:
            return entry
    return None


def patch_entry(entry, slug, manifest_id=None, url=None):
    """Chromium writes StartupWMClass=crx_<id>, but an app window reports its own
    entry basename as the Wayland app_id, and that is what Hyprland matches on."""
    wm_class = entry.stem
    known = read_entry(entry)
    extra = {
        "X-Webapp-Slug": slug,
        "X-Webapp-ManifestId": manifest_id or known.get("X-Webapp-ManifestId", ""),
        "X-Webapp-Url": url or known.get("X-Webapp-Url", ""),
    }

    lines = []
    has_wm_class = False
    for line in read_desktop_file(entry).splitlines():
        if line.startswith("Exec="):
            line = line.replace(f" --class=WebApp-{slug}", "")
        elif line.startswith("StartupWMClass="):
            line = f"StartupWMClass={wm_class}"
            has_wm_class = True
        elif line.split("=", 1)[0] in extra:
            continue
        lines.append(line)
    if not has_wm_class:
        lines.append(f"StartupWMClass={wm_class}")
    lines += [f"{key}={value}" for key, value in extra.items() if value]
    entry.write_text("\n".join(lines) + "\n")


def refresh_desktop_database():
    if shutil.which("update-desktop-database"):
        subprocess.run(
            ["update-desktop-database", str(APPLICATIONS)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def install(args):
    slug = args.slug or slugify(args.name)
    if not slug:
        die(f"cannot derive a slug from {args.name!r}; pass --slug")

    data_dir = data_dir_for(slug)
    if data_dir.resolve() == CHROMIUM_DEFAULT_DIR.resolve():
        die("refusing to use Chromium's own user-data directory")

    existing = find_entry(slug)
    if existing and not args.force:
        die(f"{slug} is already installed ({existing.name}); pass --force to reinstall")

    manifest_id = args.manifest_id or resolve_manifest_id(args.url) or args.url
    print(f"→ manifest id: {manifest_id}")

    data_dir.mkdir(parents=True, exist_ok=True)
    data_dir.chmod(0o700)
    APPLICATIONS.mkdir(parents=True, exist_ok=True)
    before = set(APPLICATIONS.glob("*.desktop"))

    print(f"→ installing into {data_dir}")
    with Chromium(data_dir) as browser:
        params = {"manifestId": manifest_id, "installUrlOrBundleUrl": args.url}
        try:
            browser.call("PWA.install", params)
        except CdpError as error:
            retry = manifest_id_from_error(str(error))
            if not retry:
                die(f"PWA.install failed: {error}")
            print(f"→ retrying with manifest id {retry}")
            manifest_id = retry
            params["manifestId"] = retry
            try:
                browser.call("PWA.install", params)
            except CdpError as retry_error:
                die(f"PWA.install failed: {retry_error}")

        # Apps installed this way open in a browser tab; only the in-browser
        # install path defaults to a standalone window.
        try:
            browser.call(
                "PWA.changeAppUserSettings",
                {"manifestId": manifest_id, "displayMode": "standalone"},
            )
        except CdpError as error:
            print(f"! could not set standalone display mode ({error});")
            print("  the app will open as a browser tab")

    created = sorted(set(APPLICATIONS.glob("*.desktop")) - before)
    entry = created[0] if created else find_entry(slug)
    if not entry:
        die(f"Chromium installed the app but wrote no launcher entry in {APPLICATIONS}")

    patch_entry(entry, slug, manifest_id, args.url)
    refresh_desktop_database()
    print(f"→ {entry.name} (window class {entry.stem})")

    if args.launch and shutil.which("gtk-launch"):
        subprocess.Popen(
            ["gtk-launch", entry.stem],
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        print("→ launched; sign in to the site, and skip any Chromium/Google sync prompt")
    print(f"   verify with chrome://version → Profile Path should be {data_dir}/Default")


def list_apps(_args):
    found = False
    for entry in sorted(APPLICATIONS.glob("*.desktop")):
        fields = read_entry(entry)
        slug = fields.get("X-Webapp-Slug")
        if not slug:
            continue
        found = True
        data_dir = data_dir_for(slug)
        size = subprocess.run(
            ["du", "-sh", str(data_dir)],
            capture_output=True,
            text=True,
        ).stdout.split("\t")[0] or "?"
        print(f"{slug}\t{fields.get('Name', '?')}\t{fields.get('X-Webapp-Url', '?')}")
        print(f"\t{data_dir} ({size.strip()})")
    if not found:
        print("No web apps installed.")


def remove(args):
    entry = find_entry(args.slug)
    if not entry:
        die(f"no web app found for slug {args.slug!r}")
    fields = read_entry(entry)
    manifest_id = fields.get("X-Webapp-ManifestId")
    data_dir = data_dir_for(args.slug)

    if manifest_id and data_dir.is_dir():
        print(f"→ uninstalling {manifest_id}")
        try:
            with Chromium(data_dir) as browser:
                browser.call("PWA.uninstall", {"manifestId": manifest_id})
        except CdpError as error:
            print(f"! Chromium could not uninstall it ({error}); removing the entry anyway")
    entry.unlink(missing_ok=True)
    refresh_desktop_database()
    print(f"→ removed {entry.name}")

    if args.purge:
        answer = input(f"Delete {data_dir} and its logins? [y/N] ").strip().lower()
        if answer == "y":
            shutil.rmtree(data_dir, ignore_errors=True)
            print(f"→ deleted {data_dir}")
        else:
            print(f"→ kept {data_dir}")
    elif data_dir.is_dir():
        print(f"   profile kept at {data_dir} (pass --purge to delete it)")


def fix_class(args):
    entry = find_entry(args.slug)
    if not entry:
        die(f"no web app found for slug {args.slug!r}")
    patch_entry(entry, args.slug)
    refresh_desktop_database()
    print(f"→ {entry.name} now reports window class {entry.stem}")


def main():
    parser = argparse.ArgumentParser(
        description="Install a website as a Chromium web app with its own user-data directory."
    )
    commands = parser.add_subparsers(dest="command", required=True)

    add = commands.add_parser("add", help="install a web app")
    add.add_argument("name")
    add.add_argument("url")
    add.add_argument("--slug", help="override the slug derived from the name")
    add.add_argument("--manifest-id", help="skip manifest lookup and use this id")
    add.add_argument("--force", action="store_true", help="reinstall if already present")
    add.add_argument("--no-launch", dest="launch", action="store_false", help="do not open it afterwards")
    add.set_defaults(func=install)

    listing = commands.add_parser("list", help="list installed web apps")
    listing.set_defaults(func=list_apps)

    removal = commands.add_parser("remove", help="uninstall a web app")
    removal.add_argument("slug")
    removal.add_argument("--purge", action="store_true", help="also delete the profile directory")
    removal.set_defaults(func=remove)

    fix = commands.add_parser("fix-class", help="re-apply the window class to an existing entry")
    fix.add_argument("slug")
    fix.set_defaults(func=fix_class)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
