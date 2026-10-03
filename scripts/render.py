"""Renders the product chart for the local cluster into rendered/local/likho.yaml (ignored by git).

    uv run python scripts/render.py local

Skaffold runs this before every deploy (a render hook in skaffold.yaml), then applies the file
with kubectl, putting the images it built into it. Rendering here rather than through Skaffold's
own Helm support keeps Helm 4 and Windows working (Skaffold 2.25 installs a Helm post-renderer
plugin whose manifest Helm 4 cannot read on Windows). The backing services and the real
environments are Helm releases (scripts/local.ps1, scripts/deploy.ps1), not rendered here.
"""

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] != "local":
        print(f"usage: {sys.argv[0]} local")
        return 2
    environments = HERE / "environments"
    out = HERE / "rendered" / "local"
    out.mkdir(parents=True, exist_ok=True)
    command = [
        "helm", "template", "likho", str(HERE / "charts" / "likho"), "--namespace", "likho",
        "-f", str(environments / "staging" / "env.yaml"),
        "-f", str(environments / "local" / "values.yaml"),
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr.strip())
        return result.returncode
    target = out / "likho.yaml"
    target.write_text(result.stdout, encoding="utf-8", newline="\n")
    print(f"wrote {target.relative_to(HERE)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
