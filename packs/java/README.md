# java pack — FUTURE (spec-only)

Placeholder pack for Java (Maven / Gradle) projects. **Not yet active** — it has
no commands or hooks. It exists so auto-discovery can report "detected java"
against a real pack id, and so the structure is visible.

To turn this into a working pack, follow ["Authoring a new pack"](../PACK-SPEC.md)
in the pack spec. The `pack.json` here already declares the markers
(`pom.xml` / `build.gradle` / `build.gradle.kts`) and language.
