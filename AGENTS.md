# Agent / contributor notes

## This repository

- Run Ruby tooling (**bundle**, **rubocop**, **rspec**) via **WSL** with **asdf** (use a login shell, e.g. `wsl bash -lic '…'`).
- **PostgreSQL** is expected in **Docker**; for local tests use **`aswin` / `aswin`** (`TEST_DB_USER`, `TEST_DB_PASSWORD`, or `DATABASE_URL` as appropriate).

More detail and example commands: `.cursor/rules/dev-environment.mdc`.
