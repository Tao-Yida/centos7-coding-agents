# Contributing to Coding Agents on CentOS 7

> We welcome Pull Requests! 🎉

This project aims to be a comprehensive compatibility layer for running any AI coding agent on CentOS 7 (and similar old Linux distributions) using custom glibc.

## Ways to Contribute

### 1. Add a New Coding Agent

The most common contribution is adding support for a new coding agent.

#### Step-by-Step

1. **Fork this repository**
2. **Copy the template:**
   ```bash
   cp scripts/template_with_custom_glibc.sh scripts/your_agent_with_custom_glibc.sh
   ```
3. **Implement the script:**
   - Fill in `AGENT_NAME` and `AGENT_BINARY` with your agent's details
   - Choose the appropriate launch method (see comments in template)
   - Keep the environment save/restore pattern — this is **critical** for system stability
   - Maintain the same validation and error handling style

4. **Update the README:**
   - Add your agent to the [Supported Agents](README.md#supported-agents) table
   - Add a new section following the existing format

5. **Test your script** on a clean CentOS 7 environment

6. **Submit a Pull Request**

### 2. Improve Existing Scripts

- Bug fixes
- Better error messages
- More robust environment handling
- Documentation improvements
- Additional troubleshooting tips

### 3. Report Issues

- Open a GitHub Issue for problems, questions, or suggestions
- Include your CentOS version, agent version, and full error output

## Coding Guidelines

### Script Style

All agent scripts should follow these conventions:

```bash
# 1. Shebang
#!/bin/bash

# 2. Brief header with description and prerequisites
# 3. set -euo pipefail
# 4. Clear section markers (# ─── Section ───)
# 5. Validation with meaningful error messages
# 6. Environment save → minimal setup → launch → restore pattern
# 7. Consistent exit codes
```

### Critical Rules

1. **Do NOT add custom glibc to `LD_LIBRARY_PATH`** — System binaries compiled against glibc 2.17 will crash.
2. **Always restore original environment** — Use the save/restore pattern seen in all existing scripts.
3. **Validate all dependencies** — Check binary existence, glibc linker, and required tools before launching.
4. **Use `set -euo pipefail`** — Fail early with clear error messages.
5. **Handle cleanup on exit** — Temp files should be removed even on error.

### Launch Methods

| Method | When to Use | Example |
|--------|-------------|---------|
| `ld-linux --library-path` | Agent is script-based (Node.js, Python) | Cursor CLI, Kimi Code |
| `patchelf --set-interpreter` | Agent is a compiled binary | OpenCode |

## PR Review Process

1. **All PRs will be reviewed** for:
   - Correct environment handling
   - No dangerous `LD_LIBRARY_PATH` usage
   - Follows existing conventions
   - Documentation updated
2. **Small, focused PRs are preferred** — One agent per PR if possible
3. **Be responsive to feedback** — We may ask for changes

## Questions?

Open an Issue or start a Discussion on GitHub.

Thank you for contributing! 🚀
