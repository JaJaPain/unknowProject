# CLAUDE.md — Project Rules

## Output Discipline

When writing large documents, research summaries, or plan files, **save incrementally after each logical section**. Never accumulate a full document in a single write — break it into chunks and write/edit the file after each section completes. This prevents hitting the output limit and losing work.

If a response is likely to be long (multi-section plans, changelogs, research findings), explicitly structure the work as: write section 1 → save → write section 2 → save → etc.

## Project Index

Use `PROJECT_MAP.md` as the first-pass navigation index for this codebase. It is a complete file tree listing every file path, class name, and function signature in the project. Before grepping or globbing for a file or function, check PROJECT_MAP.md first — it often gives you the exact path and line context you need in a single read. Use offset/limit to read specific sections since the file is large (~260KB):

- The file is organized as a nested directory tree with 📂 folders and 📄 files
- Each `.gd` script file lists its class name and all function signatures
- Use Grep on PROJECT_MAP.md with a class or function name to jump straight to the right section, then read surrounding lines for context
- Still use Grep/Glob on actual source files when you need line numbers, implementation details, or content not captured in signatures

## Project Overview

- **Engine:** Godot 4.6 (Forward Plus renderer), GDScript
- **Platform:** Windows 11
- **Genre:** Space trading/combat game with procedural generation
