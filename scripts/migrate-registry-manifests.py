"""Convert legacy registry moon.mod.json metadata for the current Moon toolchain."""

from __future__ import annotations

import json
import os
import re
from pathlib import Path


def migrate(root: Path) -> None:
    migrated = 0
    for manifest in root.rglob("moon.mod.json"):
        data = json.loads(manifest.read_text(encoding="utf-8"))
        target = manifest.with_name("moon.mod")
        imports = data.get("deps", {})
        lines = [f'name = "{data["name"]}"']
        if data.get("version"):
            lines.append(f'\nversion = "{data["version"]}"')
        if imports:
            lines.extend(["\nimport {"])
            lines.extend(f'  "{name}@{version}",' for name, version in imports.items())
            lines.append("}")
        if data.get("preferred-target"):
            lines.append(f'\npreferred_target = "{data["preferred-target"]}"')
        if data.get("source"):
            lines.append(f'\nsource = "{data["source"]}"')
        target.write_text("\n".join(lines) + "\n", encoding="utf-8")
        manifest.unlink()
        migrated += 1
    css = root / "mizchi" / "css" / "src"
    if css.exists():
        for source in css.rglob("*"):
            if source.suffix in {".mbt", ".mbti"}:
                text = source.read_text(encoding="utf-8")
                rewritten = re.sub(r"\bFloat\b", "CssFloat", text)
                if rewritten != text:
                    source.write_text(rewritten, encoding="utf-8")
    print(f"migrated {migrated} registry manifests")


if __name__ == "__main__":
    migrate(Path(os.environ.get("MOONCAKES_DIR", ".mooncakes")))
