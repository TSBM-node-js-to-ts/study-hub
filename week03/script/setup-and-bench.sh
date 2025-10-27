#!/usr/bin/env bash
set -euo pipefail

# ===== Settings =====
YARN_VER="4.3.1"
PNPM_VER="9.12.0"
NPM_VER="10.9.0"
ROOT="$(pwd)"
RESULT_DIR="$ROOT/_bench_results"
mkdir -p "$RESULT_DIR"

say() { echo -e "\033[1;36m$*\033[0m"; }

# ----- helpers -----
mk_small() {
  mkdir -p small && cd small
  cat > package.json <<'JSON'
{
  "name": "small-app",
  "private": true,
  "version": "1.0.0",
  "type": "module",
  "scripts": { "build": "echo build", "test": "echo test" },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {
    "typescript": "^5.6.2",
    "eslint": "^9.9.0",
    "jest": "^29.7.0"
  }
}
JSON
  cd "$ROOT"
}

mk_medium() {
  mkdir -p medium && cd medium
  cat > package.json <<'JSON'
{
  "name": "medium-app",
  "private": true,
  "version": "1.0.0",
  "type": "module",
  "scripts": { "build": "echo build", "test": "echo test" },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "zustand": "^4.5.2",
    "axios": "^1.7.7"
  },
  "devDependencies": {
    "typescript": "^5.6.2",
    "eslint": "^9.9.0",
    "jest": "^29.7.0",
    "@storybook/react": "^8.2.6",
    "cypress": "^13.13.2",
    "vite": "^5.4.6"
  }
}
JSON
  cd "$ROOT"
}

mk_monorepo() {
  mkdir -p monorepo && cd monorepo
  cat > package.json <<'JSON'
{
  "name": "mono",
  "private": true,
  "version": "1.0.0",
  "workspaces": ["packages/*"],
  "type": "module",
  "scripts": { "build": "echo root", "test": "echo root" }
}
JSON

  mkdir -p packages/ui packages/app
  cat > packages/ui/package.json <<'JSON'
{
  "name": "@mono/ui",
  "version": "0.0.1",
  "main": "index.js",
  "type": "module",
  "dependencies": {
    "react": "^18.3.1"
  }
}
JSON

  cat > packages/app/package.json <<'JSON'
{
  "name": "@mono/app",
  "version": "0.0.1",
  "private": true,
  "type": "module",
  "dependencies": {
    "@mono/ui": "0.0.1",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "axios": "^1.7.7"
  },
  "devDependencies": {
    "typescript": "^5.6.2",
    "eslint": "^9.9.0"
  }
}
JSON
  cd "$ROOT"
}

size_of() { du -sk "$1" 2>/dev/null | awk '{print $1}'; }

clean_all() {
  rm -rf node_modules package-lock.json yarn.lock pnpm-lock.yaml .pnp.cjs .yarn/cache .yarn/install-state.gz
  npm cache clean --force >/dev/null 2>&1 || true
  yarn cache clean >/dev/null 2>&1 || true
  local store
  store=$(pnpm store path 2>/dev/null || echo "")
  [ -n "$store" ] && [ -d "$store" ] && rm -rf "$store" || true
}

measure_sizes() {
  local nm_size files lock npm_cache yarn_cache pnpm_store lockfile=""
  nm_size=$( [ -d node_modules ] && size_of node_modules || echo 0 )
  files=$( [ -d node_modules ] && find node_modules -print 2>/dev/null | wc -l || echo 0 )
  [ -f package-lock.json ] && lockfile=package-lock.json
  [ -f yarn.lock ] && lockfile=yarn.lock
  [ -f pnpm-lock.yaml ] && lockfile=pnpm-lock.yaml
  [ -f .pnp.cjs ] && lockfile=".pnp.cjs"
  lock=$([ -n "$lockfile" ] && size_of "$lockfile" || echo 0)

  local npm_cache_dir yarn_cache_dir pnpm_store_dir
  npm_cache_dir=$(npm config get cache 2>/dev/null || echo "")
  yarn_cache_dir=$(yarn cache dir 2>/dev/null || echo "")
  pnpm_store_dir=$(pnpm store path 2>/dev/null || echo "")

  npm_cache=$([ -n "$npm_cache_dir" ] && [ -d "$npm_cache_dir" ] && size_of "$npm_cache_dir" || echo 0)
  yarn_cache=$([ -n "$yarn_cache_dir" ] && [ -d "$yarn_cache_dir" ] && size_of "$yarn_cache_dir" || echo 0)
  pnpm_store=$([ -n "$pnpm_store_dir" ] && [ -d "$pnpm_store_dir" ] && size_of "$pnpm_store_dir" || echo 0)

  echo "$nm_size,$files,$lock,$npm_cache,$yarn_cache,$pnpm_store"
}

bench_one() {
  local proj=$1
  local tool=$2
  local install_cmd=$3
  local ci_cmd=$4

  say "==> [$proj][$tool] Cold install"
  (cd "$proj" && clean_all && hyperfine --warmup 0 --show-output "$install_cmd" \
     --export-json "$RESULT_DIR/${proj}_${tool}_cold.json")

  # sizes (after cold)
  pushd "$proj" >/dev/null
    IFS=',' read -r NM FILES LOCK NPM_C YARN_C PNPM_S < <(measure_sizes)
  popd >/dev/null

  echo "project,tool,scenario,node_modules_kb,files,lock_kb,npm_cache_kb,yarn_cache_kb,pnpm_store_kb" \
    > "$RESULT_DIR/header.csv" 2>/dev/null || true
  echo "$proj,$tool,cold,$NM,$FILES,$LOCK,$NPM_C,$YARN_C,$PNPM_S" \
    >> "$RESULT_DIR/results.csv"

  say "==> [$proj][$tool] Warm install"
  (cd "$proj" && hyperfine --warmup 1 --show-output "$install_cmd" \
     --export-json "$RESULT_DIR/${proj}_${tool}_warm.json")

  say "==> [$proj][$tool] CI install"
  (cd "$proj" && hyperfine --warmup 0 --show-output "$ci_cmd" \
     --export-json "$RESULT_DIR/${proj}_${tool}_ci.json")
}

# ===== Start =====
say "[1/4] Create projects"
mk_small
mk_medium
mk_monorepo

say "[2/4] Pin package managers via Corepack"
corepack enable
corepack prepare "npm@${NPM_VER}" --activate
corepack prepare "yarn@${YARN_VER}" --activate
corepack prepare "pnpm@${PNPM_VER}" --activate

# Yarn Berry(PnP) 강제
for P in small medium monorepo; do
  cat > "$P/.yarnrc.yml" <<YML
nodeLinker: pnp
YML
done

say "[3/4] Run benchmarks"

# small
bench_one small "npm"  "npm install"             "npm ci"
bench_one small "yarn" "yarn install"            "yarn install --immutable"
bench_one small "pnpm" "pnpm install"            "pnpm install --frozen-lockfile"

# medium
bench_one medium "npm"  "npm install"            "npm ci"
bench_one medium "yarn" "yarn install"           "yarn install --immutable"
bench_one medium "pnpm" "pnpm install"           "pnpm install --frozen-lockfile"

# monorepo
bench_one monorepo "npm"  "npm install"          "npm ci"
bench_one monorepo "yarn" "yarn install"         "yarn install --immutable"
bench_one monorepo "pnpm" "pnpm install"         "pnpm install --frozen-lockfile"

say "[4/4] Done. See results in: $RESULT_DIR/"
echo "• *_cold.json / *_warm.json / *_ci.json: hyperfine 시간 결과"
echo "• results.csv: node_modules/캐시/락파일 크기 요약 (KB)"
