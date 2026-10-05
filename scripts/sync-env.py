"""Copies each service's committed settings into the chart's values for an environment.

    uv run python scripts/sync-env.py staging
    uv run python scripts/sync-env.py production

Reads ../<service>/.env.<environment> (the sibling checkouts of the D:\\likho layout) and writes
environments/<environment>/env.yaml: the `config` of every service, which the chart turns into
the ConfigMap <service>-env. The .env files stay the source of truth; this file is committed so
the chart can be rendered and checked without the other repositories. Secrets never pass
through here: those are the .env.<environment>.local files, handled by scripts/secrets.py.
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
ROOT = HERE.parent
SERVICES = (
    "likho-api",
    "likho-media",
    "likho-transcription",
    "likho-language",
    "likho-search",
    "likho-connector-ameyo",
    "likho-insights",
    "likho-analytics",
)
ENVIRONMENTS = ("staging", "production")


def parse_env(path: Path) -> dict[str, str]:
    """KEY=value lines; blank lines and # comments skipped; an inline  # comment dropped."""
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.split("  #", 1)[0].split(" #", 1)[0].strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key.strip()] = value
    return values


def yaml_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in ENVIRONMENTS:
        print(f"usage: {sys.argv[0]} <{'|'.join(ENVIRONMENTS)}>")
        return 2
    env = sys.argv[1]
    lines = [
        f"# Made by scripts/sync-env.py {env} from each repository's .env.{env}. Do not edit here:",
        "# change the .env file in the service's repository and run the script again.",
        "services:",
    ]
    for service in SERVICES:
        source = ROOT / service / f".env.{env}"
        if not source.exists():
            print(f"missing: {source}")
            return 1
        lines.append(f"  {service}:")
        lines.append("    config:")
        for key, value in parse_env(source).items():
            lines.append(f"      {key}: {yaml_string(value)}")
    target = HERE / "environments" / env / "env.yaml"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {target.relative_to(HERE)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
