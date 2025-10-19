#!/usr/bin/env python3
from __future__ import annotations

import argparse
import logging
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Iterable, Optional
from urllib.error import URLError
from urllib.request import urlopen

DEFAULT_MIRROR = "https://mirror.ctan.org/systems/texlive/tlnet"
DEFAULT_ARCHIVE_MIRROR = "ftp://tug.org/historic/systems/texlive"
DEFAULT_ARCHIVE_NAME = "install-tl-unx.tar.gz"
DEFAULT_CACHE_BUSTER = "0"
SYMLINK_DESTINATION = Path("/usr/local/bin")
KNOWN_TEXLIVE_ROOTS = (
    Path("/usr/local/texlive"),
    Path("/opt/texlive"),
)


def configure_logging(verbose: bool) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=level, format="%(levelname)s: %(message)s")


def append_cache_buster(url: str, token: str) -> str:
    if not token or token == "0":
        return url
    return f"{url}{'&' if '?' in url else '?'}ts={token}"


def download_installer(version: str, archive_name: str, mirror: str, archive_mirror: str, cache_buster: str, output: Optional[Path]) -> None:
    output_path = output or Path(archive_name)
    if version == "latest":
        base = mirror.rstrip("/")
        url = f"{base}/{archive_name}"
    else:
        base = archive_mirror.rstrip("/")
        url = f"{base}/{version}/tlnet-final/{archive_name}"

    url = append_cache_buster(url, cache_buster)
    logging.info("Downloading installer: %s", url)

    try:
        with urlopen(url) as response, output_path.open("wb") as target:
            shutil.copyfileobj(response, target)
    except URLError as exc:
        logging.error("Failed to download installer from %s: %s", url, exc)
        raise SystemExit(1) from exc

    logging.info("Downloaded installer to %s", output_path)


def run_subprocess(args: Iterable[str], *, cwd: Optional[Path] = None, check: bool = True, env: Optional[dict[str, str]] = None, suppress_output: bool = False) -> subprocess.CompletedProcess:
    stdout = subprocess.PIPE if suppress_output else None
    stderr = subprocess.PIPE if suppress_output else None
    try:
        result = subprocess.run(
            list(args),
            cwd=str(cwd) if cwd else None,
            check=check,
            env=env,
            stdout=stdout,
            stderr=stderr,
            text=True,
        )
        if suppress_output and result.stdout:
            logging.debug(result.stdout.strip())
        if suppress_output and result.stderr:
            logging.debug(result.stderr.strip())
        return result
    except subprocess.CalledProcessError as exc:
        if suppress_output and exc.stdout:
            logging.debug(exc.stdout.strip())
        if suppress_output and exc.stderr:
            logging.debug(exc.stderr.strip())
        logging.error("Command failed (%s): %s", exc.returncode, " ".join(exc.cmd))
        raise SystemExit(exc.returncode) from exc
    except FileNotFoundError as exc:
        logging.error("Command not found: %s", exc)
        raise SystemExit(1) from exc


def locate_install_tl(workdir: Path) -> Path:
    candidate = workdir / "install-tl"
    if candidate.is_file():
        return candidate
    nested = workdir / "install-tl" / "install-tl"
    if nested.is_file():
        return nested
    logging.error("install-tl script not found in %s", workdir)
    raise SystemExit(1)


def check_path() -> bool:
    try:
        run_subprocess(["tex", "--version"], check=True, suppress_output=True)
        logging.info("TeX binaries detected on PATH")
        return True
    except SystemExit:
        logging.debug("TeX binaries missing from PATH")
        return False


def iter_candidate_bin_dirs() -> Iterable[Path]:
    for root in KNOWN_TEXLIVE_ROOTS:
        if not root.exists():
            continue
        for entry in sorted(root.iterdir(), reverse=True):
            bin_root = entry / "bin"
            if not bin_root.is_dir():
                continue
            for arch_dir in bin_root.iterdir():
                tex_binary = arch_dir / "tex"
                if tex_binary.is_file():
                    yield arch_dir


def bin_dir_from_tlmgr() -> Optional[Path]:
    env = os.environ.copy()
    env.setdefault("PATH", "/usr/local/bin:/usr/bin:/bin")
    try:
        result = run_subprocess(["tlmgr", "conf", "texmf"], check=True, suppress_output=True, env=env)
    except SystemExit:
        return None

    for line in (result.stdout or "").splitlines():
        stripped = line.strip()
        if stripped.startswith("TEXMFROOT"):
            parts = stripped.split(None, 1)
            if len(parts) == 2:
                root = Path(parts[1].strip())
                bin_root = root / "bin"
                if bin_root.is_dir():
                    for candidate in bin_root.iterdir():
                        if (candidate / "tex").is_file():
                            return candidate
    return None


def resolve_texlive_bin_dir() -> Optional[Path]:
    for candidate in iter_candidate_bin_dirs():
        return candidate
    return bin_dir_from_tlmgr()


def tlmgr_path_add(bin_dir: Path) -> bool:
    env = os.environ.copy()
    existing_path = env.get("PATH", "")
    env["PATH"] = f"{bin_dir}:{existing_path}" if existing_path else str(bin_dir)
    try:
        run_subprocess(["tlmgr", "path", "add"], check=False, env=env)
    except SystemExit:
        return False
    return True


def symlink_binaries(bin_dir: Path, destination: Path) -> bool:
    destination.mkdir(parents=True, exist_ok=True)
    success = True
    for binary in bin_dir.iterdir():
        if not binary.is_file():
            continue
        target = destination / binary.name
        try:
            if target.exists() or target.is_symlink():
                target.unlink()
            os.symlink(binary, target)
        except OSError as exc:
            logging.error("Failed to symlink %s -> %s: %s", binary, target, exc)
            success = False
    return success


def run_install(version: str, profile: str, mirror: str, archive_mirror: str, workdir: Path) -> None:
    installer = locate_install_tl(workdir)
    mirror_url = mirror.rstrip("/") + "/"
    args = ["perl", str(installer), f"--profile={profile}", f"--location={mirror_url}"]
    if version != "latest":
        repository = archive_mirror.rstrip("/") + f"/{version}/tlnet-final"
        args.append(f"--repository={repository}")

    logging.info("Running TeXLive installer")
    run_subprocess(args, cwd=workdir)

    if check_path():
        return

    logging.warning("Installer did not configure PATH; attempting tlmgr path add")
    bin_dir = resolve_texlive_bin_dir()
    if not bin_dir:
        logging.error("Could not locate TeXLive binary directory")
        raise SystemExit(1)

    if tlmgr_path_add(bin_dir) and check_path():
        return

    logging.warning("tlmgr path add failed; creating manual symlinks in %s", SYMLINK_DESTINATION)
    if symlink_binaries(bin_dir, SYMLINK_DESTINATION) and check_path():
        return

    logging.error("Failed to make TeXLive binaries available on PATH")
    raise SystemExit(1)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="TeXLive installer helper")
    parser.add_argument("command", choices=["get-installer", "install"], help="Operation to perform")
    parser.add_argument("version", help="TeXLive version to install; use 'latest' for current release")
    parser.add_argument(
        "--mirror",
        default=os.environ.get("TL_MIRROR", DEFAULT_MIRROR),
        help="Primary CTAN mirror for current releases",
    )
    parser.add_argument(
        "--archive-mirror",
        default=os.environ.get("TL_ARCHIVE_MIRROR", DEFAULT_ARCHIVE_MIRROR),
        help="Archive mirror for historic releases",
    )
    parser.add_argument(
        "--archive-name",
        default=os.environ.get("TL_INSTALL_ARCHIVE", DEFAULT_ARCHIVE_NAME),
        help="Installer archive filename",
    )
    parser.add_argument(
        "--cache-buster",
        default=os.environ.get("TL_CACHE_BUSTER", DEFAULT_CACHE_BUSTER),
        help="Token appended to download URLs to bypass Docker cache",
    )
    parser.add_argument(
        "--profile",
        default=os.environ.get("TL_PROFILE", "texlive.profile"),
        help="TeXLive profile used during installation",
    )
    parser.add_argument(
        "--workdir",
        default=os.environ.get("TL_WORKDIR", os.getcwd()),
        help="Working directory containing install-tl files",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Destination path for downloaded installer (get-installer only)",
    )
    parser.add_argument("--verbose", action="store_true", help="Enable verbose logging")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    configure_logging(args.verbose)

    workdir = Path(args.workdir)
    if args.command == "get-installer":
        output = Path(args.output) if args.output else None
        download_installer(
            args.version,
            args.archive_name,
            args.mirror,
            args.archive_mirror,
            args.cache_buster,
            output,
        )
        return 0

    if args.command == "install":
        run_install(args.version, args.profile, args.mirror, args.archive_mirror, workdir)
        return 0

    logging.error("Unknown command: %s", args.command)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
