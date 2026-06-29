import json
import shutil
import sys
import zipfile
from pathlib import Path


EXCLUDES = {
    ".git",
    ".github",
    ".tmp",
    ".vscode",
    "build",
    "devtools",
    "__pycache__",
    "package_mod.bat",
}


def build(copy_to_mods=True):
    repo_root = Path(__file__).resolve().parent.parent
    info = json.loads((repo_root / "info.json").read_text(encoding="utf-8"))
    mod_name = info["name"]
    version = info["version"]
    folder_name = f"{mod_name}_{version}"
    build_dir = repo_root / "build"
    stage_dir = build_dir / folder_name
    zip_path = build_dir / f"{folder_name}.zip"

    if build_dir.exists():
        shutil.rmtree(build_dir)

    stage_dir.mkdir(parents=True, exist_ok=True)

    for item in repo_root.iterdir():
        if item.name in EXCLUDES:
            continue

        destination = stage_dir / item.name
        if item.is_dir():
            shutil.copytree(
                item,
                destination,
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
            )
        else:
            shutil.copy2(item, destination)

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(stage_dir.rglob("*")):
            archive_name = path.relative_to(build_dir).as_posix()
            archive.write(path, archive_name)

    print(f"Built ZIP: {zip_path}")

    if copy_to_mods:
        mods_dir = Path.home() / "AppData" / "Roaming" / "Factorio" / "mods"
        if not mods_dir.exists():
            raise RuntimeError(f"Factorio mods directory not found: {mods_dir}")
        target = mods_dir / zip_path.name
        shutil.copy2(zip_path, target)
        print(f"Copied ZIP to: {target}")


if __name__ == "__main__":
    try:
        copy_to_mods = "--no-copy" not in sys.argv
        build(copy_to_mods=copy_to_mods)
    except Exception as exc:  # pragma: no cover - devtool path
        print(str(exc), file=sys.stderr)
        sys.exit(1)
