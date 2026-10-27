# Contributing to AgensGraph

Thank you for your interest in contributing to AgensGraph! We welcome
contributions of all kinds: bug reports, feature ideas, documentation
improvements, tests, and code.

This document explains how to get involved. Please read it before opening an
issue or pull request.

## Code of Conduct

Everyone participating in the AgensGraph community is expected to follow our
[Code of Conduct](CODE_OF_CONDUCT.md). Please be respectful and constructive in
all project spaces.

## Security Vulnerabilities

Please do not report security vulnerabilities through public GitHub issues.
Email <inquiry@skaiworldwide.com> instead, with "AgensGraph security" in the
subject line. See [SECURITY.md](SECURITY.md) for what to include.

## Ways to Contribute

- **Ask a question or start a discussion**: use
  [GitHub Discussions](https://github.com/skaiworldwide-oss/agensgraph/discussions)
  (the Q&A category for questions, Ideas for proposals).
- **Report a bug**: open an
  [issue](https://github.com/skaiworldwide-oss/agensgraph/issues) (see below).
- **Suggest a feature**: open an issue describing the use case.
- **Improve documentation**: fixes to typos, unclear explanations, and examples
  are always welcome. The manual sources live in `doc/src/sgml/agensgraph.sgml`
  and `doc/src/sgml/ref/cypher_*.sgml`.
- **Submit code**: bug fixes, new features, tests, and performance improvements.

If you are new to the project, look for issues labeled
[`help wanted`](https://github.com/skaiworldwide-oss/agensgraph/labels/help%20wanted).

## Reporting Bugs

Before opening a new issue, please search existing issues to avoid duplicates.
A good bug report includes:

- AgensGraph version (`SELECT version();`) and how it was installed (source,
  package, Docker)
- Operating system and version
- Steps to reproduce, ideally a minimal SQL/Cypher script
- Expected behavior and actual behavior
- Relevant log output or error messages

AgensGraph is based on PostgreSQL. If you can reproduce the problem on plain
PostgreSQL without any AgensGraph-specific features, it is likely an upstream
PostgreSQL issue and may be better reported to the
[PostgreSQL project](https://www.postgresql.org/account/submitbug/).

## Suggesting Features

Open an issue (or an Ideas discussion) describing:

- The problem or use case you are trying to solve
- Your proposed solution, including example queries if relevant
- Alternatives you have considered

For larger changes, please discuss the idea in an issue first before starting
work, so we can agree on the approach.

## Development Setup

### Building from Source

1. Clone the repository:

   ```sh
   git clone https://github.com/skaiworldwide-oss/agensgraph.git
   cd agensgraph
   ```

2. Install dependencies (example for Ubuntu; see [INSTALL.md](../INSTALL.md)
   for other platforms):

   ```sh
   sudo apt-get install build-essential libreadline-dev zlib1g-dev flex bison libipc-run-perl
   ```

   `libipc-run-perl` is only needed for the TAP tests.

3. Configure, build, and install:

   ```sh
   ./configure --prefix=$(pwd) --enable-debug --enable-cassert --enable-tap-tests
   make install
   export PATH=$(pwd)/bin:$PATH
   export LD_LIBRARY_PATH=$(pwd)/lib:$LD_LIBRARY_PATH
   ```

   `--enable-debug` and `--enable-cassert` are recommended for development and
   are what CI uses.

### Running Tests

Please run the regression tests before submitting a pull request:

```sh
make check          # core regression suite, including the cypher_* tests
make check-world    # everything CI runs, including contrib and TAP tests
```

CI runs `make check-world` on every push and pull request
([regression.yml](workflows/regression.yml)).

If you fix a bug or add a feature, please add or update regression tests that
cover the change. The Cypher tests live in `src/test/regress/sql/cypher_*.sql`
with expected output in `src/test/regress/expected/`.

## Submitting Pull Requests

1. Fork the repository and create a branch from `main`.
2. Use a descriptive branch name, e.g. `fix/cypher-merge-crash` or
   `feature/shortest-path-option`.
3. Make your changes in small, focused commits.
4. Make sure the code builds without new warnings and all tests pass.
5. Update documentation if your change affects user-facing behavior.
6. Open a pull request, describe what changed and why, and link any related
   issues (e.g., `Fixes #123`).

### Commit Messages

- Start the subject line with a type prefix, as in the existing history:
  `fix:`, `feat:`, `docs:`, `test:`, `chore:`
- Write the rest of the subject line in the imperative mood, in lowercase,
  e.g. `fix: reset every graph write counter for a write with RETURN`
- Keep the subject line under about 72 characters
- Explain what and why in the body when the change is not trivial

### Coding Style

AgensGraph follows the PostgreSQL coding conventions. In particular:

- Use tabs for indentation (tab width 4); see `.editorconfig`
- Follow the existing style of the surrounding code
- Keep changes to upstream PostgreSQL code minimal and clearly marked where
  possible

### Review Process

A maintainer will review your pull request. We may ask for changes before
merging; this is a normal part of the process. If your pull request has not
received a response, feel free to leave a polite comment on it.

## License

AgensGraph is licensed under the [Apache License 2.0](../LICENSE); see also
[NOTICE](../NOTICE). Portions derived from PostgreSQL remain under the
PostgreSQL License ([COPYRIGHT](../COPYRIGHT)).

There is no separate Contributor License Agreement. By submitting a
contribution, you agree that it is licensed under the Apache License 2.0, as
described in Section 5 of that license.

## Contact

For general questions, please use GitHub Discussions or Issues so others can
benefit from the answers. For matters that cannot be discussed publicly,
contact us at <inquiry@skaiworldwide.com>.

Thank you for helping make AgensGraph better!
