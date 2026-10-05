"""Turns the .env.<environment>.local files into Kubernetes Secrets, straight into the cluster.

    uv run python scripts/secrets.py staging                      # namespace likho-staging
    uv run python scripts/secrets.py production --context prod    # a named kubectl context
    uv run python scripts/secrets.py staging --namespace likho --allow-placeholders   # the local cluster

Reads, from the sibling checkouts (the D:\\likho layout), the files that likho-infra's
make-env-secrets.py wrote:

    likho-infra/.env.<env>.local      -> Secret likho-stack-secrets (the databases, S3, Meilisearch)
                                         Secret likho-stack-s3      (SeaweedFS's s3.json, same keys)
    likho-api/.env.<env>.local        -> Secret likho-api-secrets
    likho-media/.env.<env>.local      -> Secret likho-media-secrets
    likho-transcription/.env.<env>.local -> Secret likho-transcription-secrets
    likho-language/.env.<env>.local   -> Secret likho-language-secrets
    likho-search/.env.<env>.local     -> Secret likho-search-secrets
    likho-connector-ameyo/.env.<env>.local -> Secret likho-connector-ameyo-secrets
    likho-insights/.env.<env>.local   -> Secret likho-insights-secrets

With GHCR_USER and GHCR_TOKEN in the environment (a GitHub token with read:packages), also
the pull secret ghcr-pull for the private images. Nothing is written to disk and no value is
printed: the manifests go to `kubectl apply` on its standard input. A value still reading
CHANGE-ME (the public domain, the first admin's email) stops the script unless
--allow-placeholders is given, which the local cluster does because it overrides them.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SERVICES = (
    "likho-api",
    "likho-media",
    "likho-transcription",
    "likho-language",
    "likho-search",
    "likho-connector-ameyo",
    "likho-insights",
)
ENVIRONMENTS = ("staging", "production")


def parse_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key.strip()] = value
    return values


def secret(name: str, namespace: str, data: dict[str, str], kind: str = "Opaque") -> dict:
    return {
        "apiVersion": "v1",
        "kind": "Secret",
        "type": kind,
        "metadata": {
            "name": name,
            "namespace": namespace,
            "labels": {"app.kubernetes.io/part-of": "likho", "app.kubernetes.io/managed-by": "likho-deploy-secrets"},
        },
        "stringData": data,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("environment", choices=ENVIRONMENTS)
    parser.add_argument("--namespace", help="default: likho-<environment>")
    parser.add_argument("--context", help="kubectl context (default: the current one)")
    parser.add_argument("--allow-placeholders", action="store_true", help="accept CHANGE-ME values")
    parser.add_argument("--dry-run", action="store_true", help="only list what would be applied")
    args = parser.parse_args()
    env = args.environment
    namespace = args.namespace or f"likho-{env}"

    files = {"likho-infra": ROOT / "likho-infra" / f".env.{env}.local"}
    files.update({service: ROOT / service / f".env.{env}.local" for service in SERVICES})
    missing = [p for p in files.values() if not p.exists()]
    if missing:
        print("missing (run likho-infra/scripts/make-env-secrets.py first):")
        for p in missing:
            print(f"  {p}")
        return 1

    manifests = []
    for repo, path in files.items():
        values = parse_env(path)
        placeholders = [k for k, v in values.items() if "CHANGE-ME" in v]
        if placeholders and not args.allow_placeholders:
            print(f"{path}: still CHANGE-ME: {', '.join(placeholders)} (fill them in, or --allow-placeholders)")
            return 1
        if repo == "likho-infra":
            manifests.append(secret("likho-stack-secrets", namespace, values))
            s3 = {
                "identities": [
                    {
                        "name": values["S3_ACCESS_KEY"],
                        "credentials": [{"accessKey": values["S3_ACCESS_KEY"], "secretKey": values["S3_SECRET_KEY"]}],
                        "actions": ["Admin", "Read", "Write", "List", "Tagging"],
                    }
                ]
            }
            manifests.append(secret("likho-stack-s3", namespace, {"s3.json": json.dumps(s3, indent=2)}))
        else:
            manifests.append(secret(f"{repo}-secrets", namespace, values))

    user, token = os.environ.get("GHCR_USER"), os.environ.get("GHCR_TOKEN")
    if user and token:
        auth = base64.b64encode(f"{user}:{token}".encode()).decode()
        config = {"auths": {"ghcr.io": {"username": user, "password": token, "auth": auth}}}
        manifests.append(
            secret("ghcr-pull", namespace, {".dockerconfigjson": json.dumps(config)}, kind="kubernetes.io/dockerconfigjson")
        )

    for m in manifests:
        print(f"{m['metadata']['name']}: {', '.join(sorted(m['stringData']))}")
    if args.dry_run:
        return 0

    command = ["kubectl", "apply", "-f", "-"]
    if args.context:
        command += ["--context", args.context]
    subprocess.run(["kubectl", "create", "namespace", namespace] + (["--context", args.context] if args.context else []),
                   capture_output=True)  # exists already: fine
    result = subprocess.run(command, input=json.dumps({"apiVersion": "v1", "kind": "List", "items": manifests}),
                            text=True, capture_output=True)
    print(result.stdout.strip())
    if result.returncode != 0:
        print(result.stderr.strip())
        return result.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
