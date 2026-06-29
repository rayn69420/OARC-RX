import argparse
import json
import mimetypes
import os
import subprocess
import sys
import uuid
from pathlib import Path
from urllib import error, request


def encode_multipart(fields, files):
    boundary = f"----OarcRxBoundary{uuid.uuid4().hex}"
    body = bytearray()

    for name, value in fields.items():
        body.extend(f"--{boundary}\r\n".encode("utf-8"))
        body.extend(
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(
                "utf-8"
            )
        )
        body.extend(str(value).encode("utf-8"))
        body.extend(b"\r\n")

    for name, file_path in files.items():
        file_name = Path(file_path).name
        content_type = mimetypes.guess_type(file_name)[0] or "application/octet-stream"
        body.extend(f"--{boundary}\r\n".encode("utf-8"))
        body.extend(
            (
                f'Content-Disposition: form-data; name="{name}"; '
                f'filename="{file_name}"\r\n'
            ).encode("utf-8")
        )
        body.extend(f"Content-Type: {content_type}\r\n\r\n".encode("utf-8"))
        body.extend(Path(file_path).read_bytes())
        body.extend(b"\r\n")

    body.extend(f"--{boundary}--\r\n".encode("utf-8"))
    headers = {"Content-Type": f"multipart/form-data; boundary={boundary}"}
    return bytes(body), headers


def post_json(url, fields, headers=None):
    body, multipart_headers = encode_multipart(fields, {})
    req_headers = dict(headers or {})
    req_headers.update(multipart_headers)
    req = request.Request(url, data=body, headers=req_headers, method="POST")
    try:
        with request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} for {url}: {detail}") from exc


def post_file(url, file_field, file_path):
    body, multipart_headers = encode_multipart({}, {file_field: file_path})
    req = request.Request(url, data=body, headers=multipart_headers, method="POST")
    try:
        with request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} for upload: {detail}") from exc


def mod_exists(mod_name):
    try:
        with request.urlopen(f"https://mods.factorio.com/api/mods/{mod_name}") as resp:
            if resp.status == 200:
                return True
    except error.HTTPError as exc:
        if exc.code == 404:
            return False
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"Failed checking mod existence for {mod_name}: HTTP {exc.code} {detail}"
        ) from exc
    return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--zip-path")
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    info = json.loads((repo_root / "info.json").read_text(encoding="utf-8"))
    mod_name = info["name"]
    mod_version = info["version"]
    api_key = os.environ.get("FACTORIO_MOD_PORTAL_API_KEY") or os.environ.get(
        "MOD_UPLOAD_API_KEY"
    )
    if not api_key:
        raise RuntimeError(
            "Missing FACTORIO_MOD_PORTAL_API_KEY or MOD_UPLOAD_API_KEY environment variable."
        )

    if not args.skip_build:
        subprocess.run([str(repo_root / "package_mod.bat")], cwd=repo_root, check=True)

    zip_path = (
        Path(args.zip_path)
        if args.zip_path
        else repo_root / "build" / f"{mod_name}_{mod_version}.zip"
    )
    if not zip_path.exists():
        raise RuntimeError(f"Zip file not found: {zip_path}")

    auth_headers = {"Authorization": f"Bearer {api_key}"}

    if mod_exists(mod_name):
        print(f"Updating existing Mod Portal entry for {mod_name}...")
        init_response = post_json(
            "https://mods.factorio.com/api/v2/mods/releases/init_upload",
            {"mod": mod_name},
            auth_headers,
        )
    else:
        print(f"Publishing new Mod Portal entry for {mod_name}...")
        init_response = post_json(
            "https://mods.factorio.com/api/v2/mods/init_publish",
            {"mod": mod_name},
            auth_headers,
        )

    upload_url = init_response.get("upload_url")
    if not upload_url:
        raise RuntimeError(
            f"Mod Portal did not return upload_url: {json.dumps(init_response, indent=2)}"
        )

    upload_response = post_file(upload_url, "file", zip_path)
    if not upload_response.get("success"):
        raise RuntimeError(
            f"Upload failed: {json.dumps(upload_response, indent=2)}"
        )

    print("Upload successful.")
    print(f"Mod page: https://mods.factorio.com/mod/{mod_name}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # pragma: no cover - devtool path
        print(str(exc), file=sys.stderr)
        sys.exit(1)
