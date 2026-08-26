# Nexus IDE — Capabilities

You have direct access to every tool in the development environment.
This is a reference of what you can do. Use it all.

## Editor

- **Read files** — any file, any language, by absolute or project-relative path
- **Edit files** — precise line-level edits, insertions, replacements
- **Create files** — new files and directories anywhere in the project
- **Delete/rename** — file management operations
- **Monaco integration** — syntax highlighting, diagnostics, symbols for 50+ languages

## Search

- **Content search** — `grep -r` / `rg` patterns across the codebase
- **File search** — `find` / `fd` by name, extension, glob
- **Symbol search** — function, class, type definitions
- **Directory exploration** — `tree`, `ls -la`, project structure discovery

## Terminal

- **Execute any command** — builds, tests, scripts, servers, tools
- **Read output** — stdout, stderr, exit codes
- **Background processes** — dev servers, watchers, long-running tasks
- **Interactive debugging** — run debuggers, REPLs, consoles

## Version Control

### Git
- `git status` / `diff` / `log` — repo state
- `git add` / `commit` / `push` — track and share changes
- `git branch` / `checkout` / `merge` / `rebase` — branch management
- `git stash` / `cherry-pick` / `bisect` — advanced workflows
- `git blame` / `log -p` — history investigation

### GitHub (gh CLI)
- `gh pr list` / `view` / `create` / `checks` — pull requests
- `gh pr review` / `comment` / `merge` — PR workflows
- `gh issue list` / `view` / `create` — issue tracking
- `gh run list` / `view` / `watch` — CI/CD status
- `gh release create` / `list` — release management
- `gh api` — raw GitHub API access for anything else

## Build Systems

| Ecosystem | Build | Test | Lint | Format |
|-----------|-------|------|------|--------|
| Rust | `cargo build` | `cargo test` | `cargo clippy` | `cargo fmt` |
| Node/TS | `npm run build` | `npm test` | `eslint .` | `prettier --write .` |
| Flutter | `flutter build` | `flutter test` | `flutter analyze` | `dart format .` |
| Python | `python -m build` | `pytest` | `ruff check .` | `black .` |
| Go | `go build ./...` | `go test ./...` | `golangci-lint run` | `gofmt -w .` |
| Java | `./gradlew build` | `./gradlew test` | — | — |
| C/C++ | `cmake --build build` | `ctest` | `clang-tidy` | `clang-format` |
| Swift | `swift build` | `swift test` | `swiftlint` | `swift-format` |

## Package Managers

- **npm** / **yarn** / **pnpm** / **bun** — Node ecosystem
- **cargo** — Rust crates
- **pip** / **uv** / **poetry** / **pdm** — Python
- **flutter pub** / **dart pub** — Dart/Flutter
- **go get** / **go mod tidy** — Go modules
- **brew** / **apt** / **dnf** — system packages
- **gem** / **bundler** — Ruby

## Framework CLIs

- **React/Next**: `npx next dev`, `npx next build`, `npx next lint`
- **Expo**: `npx expo start`, `npx expo prebuild`, `eas build`
- **Flutter**: `flutter run`, `flutter doctor`, `flutter clean`, `flutter pub get`
- **Rails**: `rails server`, `rails console`, `rails generate`, `rails db:migrate`
- **Django**: `python manage.py runserver`, `manage.py migrate`, `manage.py test`
- **Spring Boot**: `./mvnw spring-boot:run`, `./gradlew bootRun`
- **Vue/Nuxt**: `npx nuxi dev`, `npx vue-cli-service serve`

## Database

- **PostgreSQL**: `psql`, migrations, schema inspection
- **MySQL**: `mysql`, schema management
- **SQLite**: `sqlite3`, local databases
- **MongoDB**: `mongosh`, collection management
- **Redis**: `redis-cli`, cache operations
- **ORM tools**: Prisma, Drizzle, SQLAlchemy, ActiveRecord, GORM

## Docker & Containers

- `docker build` / `run` / `compose up` — container lifecycle
- `docker logs` / `exec` / `inspect` — debugging
- `docker compose` — multi-service environments
- Read `Dockerfile`, `docker-compose.yml`, `.dockerignore`

## Cloud & Deployment

- **Vercel**: `vercel`, `vercel deploy`
- **AWS**: `aws` CLI for S3, Lambda, ECS, CloudFormation
- **GCP**: `gcloud` CLI
- **Azure**: `az` CLI
- **Fly.io**: `fly deploy`, `fly logs`
- **Railway**: `railway up`
- **Kubernetes**: `kubectl`, `helm`

## Debugging & Profiling

- Read stack traces, error messages, crash logs
- `curl` / `httpie` — API testing and debugging
- Memory profiling, performance analysis tools
- Log analysis: `tail -f`, `grep`, structured log parsing

## Your Environment
<!-- Nexus fills this section as it discovers your tools and preferences -->
<!-- Examples: installed CLIs, SSH hosts, project paths, custom scripts, preferred tools -->
