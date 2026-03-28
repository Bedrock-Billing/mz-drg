# Contributing to mz-drg

Thank you for considering contributing to mz-drg! This guide will help you get started.

## Getting Started

### Prerequisites

- **Zig 0.16+** — [download](https://ziglang.org/download/)
- **Python 3.11+**
- **uv** (recommended) or **pip**
- **JDK 17+** (only for comparison testing against CMS Java reference)

### Setup

```bash
git clone https://github.com/Bedrock-Billing/mz-drg.git
cd mz-drg

python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

### Running Tests

```bash
# Zig unit tests
cd zig_src && zig build test

# Python tests
python -m pytest tests/ -v
```

## Development Workflow

1. **Fork** the repository and create a feature branch.
2. **Write tests** for any new functionality.
3. **Run the full test suite** before submitting.
4. **Open a pull request** with a clear description of your changes.

## Code Style

- **Python**: Formatted with [ruff](https://docs.astral.sh/ruff/). Run `ruff check . && ruff format .`.
- **Zig**: Follow the standard Zig style guide. Run `zig fmt zig_src/src/`.

## Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — new feature
- `fix:` — bug fix
- `docs:` — documentation changes
- `refactor:` — code restructuring without behavior change
- `test:` — adding or updating tests

## Reporting Issues

- Use the [GitHub issue tracker](https://github.com/Bedrock-Billing/mz-drg/issues).
- Include the DRG version, Python version, and OS.
- Include a minimal code example to reproduce the issue.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
