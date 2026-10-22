// Exercise the real package wrappers with shell functions only. No build,
// installation, login registration, network access, or application startup.
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { test } = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { scripts, version } = require('../package.json');

function run(name, functions) {
  const result = spawnSync('/bin/bash', ['-c', `${functions}\n${scripts[name]}`], {
    encoding: 'utf8',
    timeout: 5000,
  });
  assert.ifError(result.error);
  return result;
}

test('app build returns the xcodebuild failure through its output filter', () => {
  const result = run('build', 'xcodebuild() { return 42; }; export -f xcodebuild');
  assert.equal(result.status, 42);
});

test('generator errors do not turn into a missing-generator fallback', () => {
  const result = run('prebuild', 'xcodegen() { return 42; }; export -f xcodegen');
  assert.equal(result.status, 42);
  assert.doesNotMatch(result.stdout, /using existing project/);
});

test('all-products build stops when app build fails', () => {
  const result = run('build:all', 'npm() { echo "$2"; if [ "$2" = build ]; then return 42; fi; }; export -f npm');
  assert.equal(result.status, 42);
  assert.equal(result.stdout.trim(), 'build');
});

for (const name of ['install:cli', 'install:tui']) {
  test(`${name} reports copy failure without a success message`, () => {
    const result = run(name, 'mkdir() { return 0; }; cp() { return 42; }; export -f mkdir cp');
    assert.equal(result.status, 42);
    assert.doesNotMatch(result.stdout, /installed/);
    assert.match(result.stderr, /install failed/);
  });

  test(`${name} does not copy when the destination cannot be created`, () => {
    const result = run(name, 'mkdir() { return 43; }; cp() { echo unexpected-copy; return 0; }; export -f mkdir cp');
    assert.equal(result.status, 43);
    assert.doesNotMatch(result.stdout, /unexpected-copy|installed/);
  });

  test(`${name} succeeds when both mocked filesystem operations succeed`, () => {
    const result = run(name, 'mkdir() { return 0; }; cp() { return 0; }; export -f mkdir cp');
    assert.equal(result.status, 0);
    assert.match(result.stdout, /installed/);
  });
}

test('release stops before packaging when signature verification fails', () => {
  const result = run('release', 'npm() { echo "$2"; return 42; }; export -f npm');
  assert.equal(result.status, 42);
  assert.equal(result.stdout.trim(), 'release:verify');
  assert.doesNotMatch(result.stdout, /handoff|released!/);
});

test('reinstall verifies signing before any installation and never uninstalls first', () => {
  const result = run('reinstall', 'npm() { echo "$2"; return 42; }; export -f npm');
  assert.equal(result.status, 42);
  assert.equal(result.stdout.trim(), 'release:verify');
  assert.doesNotMatch(scripts.reinstall, /uninstall/);
});

// These fakes deliberately reject every unlisted operation. No real Git
// mutation, signing, certificate/key access, build, archive, install or network.
const policyMocks = `
git() {
  printf 'git %s\\n' "$*" >> "$MOCK_TRACE"
  case "$1" in
    symbolic-ref) printf '%s\\n' "\${MOCK_BRANCH:-main}" ;;
    status) [ "\${MOCK_STATUS_FAILURE:-0}" = 0 ] || return 12; printf '%s' "\${MOCK_DIRTY:-}" ;;
    verify-commit) return "\${MOCK_COMMIT_STATUS:-0}" ;;
    cat-file) [ "\${MOCK_MISSING_TAG:-0}" = 0 ] || return 13; printf '%s\\n' "\${MOCK_TAG_TYPE:-tag}" ;;
    verify-tag) return "\${MOCK_TAG_STATUS:-0}" ;;
    rev-parse) if [ "$2" = HEAD ]; then echo aabbcc; else echo "\${MOCK_TAG_COMMIT:-aabbcc}"; fi ;;
    *) echo "unexpected Git mutation: $*" >&2; return 99 ;;
  esac
}
codesign() {
  printf 'codesign %s\\n' "$*" >> "$MOCK_TRACE"
  [ "$1" = --verify ] || return 91
  [[ "$*" == *'--deep --strict --test-requirement'* ]] || return 92
  [[ "$5" == '=anchor apple generic '* ]] || return 96
  [[ "$*" == *'anchor apple generic'* ]] || return 93
  [[ "$*" == *'certificate leaf[field.1.2.840.113635.100.6.1.13] exists'* ]] || return 94
  [[ "$*" == *"certificate leaf[subject.OU] = \\\"\${PORTPILOT_RELEASE_TEAM_ID:-RSH5FK4MB6}\\\""* ]] || return 95
  [ "\${MOCK_SIGNATURE:-developer-id}" = developer-id ] || return 1
  [ "\${!#}" != "\${MOCK_FAIL_ARTIFACT:-}" ] || return 1
}
plutil() { printf '%s\\n' "\${MOCK_APP_VERSION:-$MOCK_VERSION}"; }
ditto() {
  printf 'archive %s\\n' "$*" >> "$MOCK_TRACE"
  [ "\${MOCK_ARCHIVE_FAILURE:-0}" = 0 ] || return 47
  printf 'mock archive' > "\${!#}"
}
unexpected_effect() { echo "unexpected external effect: $*" >&2; return 98; }
xcodebuild() { unexpected_effect "$@"; }
swift() { unexpected_effect "$@"; }
xcrun() { unexpected_effect "$@"; }
npm() { unexpected_effect "$@"; }
cp() { unexpected_effect "$@"; }
xattr() { unexpected_effect "$@"; }
security() { unexpected_effect "$@"; }
export -f git codesign plutil ditto unexpected_effect xcodebuild swift xcrun npm cp xattr security
`;

function policyFixture(t, overrides = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'portpilot-release-policy-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const app = path.join(dir, 'PortPilot.app');
  fs.mkdirSync(app);
  const cli = path.join(dir, 'portpilot');
  const tui = path.join(dir, 'portpilot-tui');
  fs.writeFileSync(cli, 'synthetic executable fixture', { mode: 0o700 });
  fs.writeFileSync(tui, 'synthetic executable fixture', { mode: 0o700 });
  return {
    ...process.env,
    PORTPILOT_RELEASE_TEAM_ID: 'RSH5FK4MB6',
    PORTPILOT_APP_PATH: app,
    PORTPILOT_CLI_PATH: cli,
    PORTPILOT_TUI_PATH: tui,
    PORTPILOT_RELEASE_DIR: path.join(dir, 'handoff'),
    MOCK_TRACE: path.join(dir, 'trace'),
    MOCK_VERSION: version,
    ...overrides,
  };
}

function runPolicy(script, env, args = []) {
  const result = spawnSync('/bin/bash', ['-c', `${policyMocks}\nbash "$@"`, '--', path.join(__dirname, script), ...args], {
    cwd: path.join(__dirname, '..'),
    env,
    encoding: 'utf8',
    timeout: 5000,
  });
  assert.ifError(result.error);
  return result;
}

for (const [name, overrides, message] of [
  ['non-main branch', { MOCK_BRANCH: 'feature/review' }, /audited main/],
  ['dirty source', { MOCK_DIRTY: ' M package.json' }, /clean/],
  ['failed status read', { MOCK_STATUS_FAILURE: '1' }, /status is unavailable/],
  ['unsigned or untrusted commit', { MOCK_COMMIT_STATUS: '1' }, /HEAD must have/],
  ['missing tag', { MOCK_MISSING_TAG: '1' }, /signed tag .* missing/],
  ['lightweight tag', { MOCK_TAG_TYPE: 'commit' }, /annotated signed tag/],
  ['unsigned or untrusted tag', { MOCK_TAG_STATUS: '1' }, /tag .* signature|must have a verifiable/],
  ['tag on another commit', { MOCK_TAG_COMMIT: 'different' }, /must point to HEAD/],
  ['invalid public team setting', { PORTPILOT_RELEASE_TEAM_ID: 'not-a-team' }, /ten-character/],
  ['stale app version', { MOCK_APP_VERSION: '0.0.0' }, /version does not match/],
]) {
  test(`release refuses ${name} before packaging`, (t) => {
    const env = policyFixture(t, overrides);
    const result = runPolicy('create_release.sh', env);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, message);
    assert.equal(fs.existsSync(env.PORTPILOT_RELEASE_DIR), false);
  });
}

for (const signature of ['unsigned', 'ad-hoc', 'apple-development', 'wrong-team', 'damaged']) {
  test(`both direct release paths reject ${signature} code`, (t) => {
    const env = policyFixture(t, { MOCK_SIGNATURE: signature });
    for (const script of ['create_release.sh', 'release_signed_macos.sh']) {
      const result = runPolicy(script, env);
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /Developer ID Application signature/);
      assert.equal(fs.existsSync(env.PORTPILOT_RELEASE_DIR), false);
    }
  });
}

test('release checks CLI and TUI signatures, not only the app', (t) => {
  const env = policyFixture(t);
  for (const artifact of [env.PORTPILOT_CLI_PATH, env.PORTPILOT_TUI_PATH]) {
    const result = runPolicy('create_release.sh', { ...env, MOCK_FAIL_ARTIFACT: artifact });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Developer ID Application signature/);
    assert.equal(fs.existsSync(env.PORTPILOT_RELEASE_DIR), false);
  }
});

test('release never bumps a version or makes a commit/tag to satisfy policy', (t) => {
  const env = policyFixture(t);
  const result = runPolicy('create_release.sh', env, ['0.0.0']);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /must already match package.json/);
  assert.equal(fs.existsSync(env.MOCK_TRACE), false);
});

test('verified Developer ID artifacts yield only a local, explicitly non-notarized handoff', (t) => {
  const env = policyFixture(t);
  const result = runPolicy('create_release.sh', env);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(fs.readdirSync(env.PORTPILOT_RELEASE_DIR).sort(), [
    'PortPilot-macOS-app.zip', 'RELEASE.txt', 'SHA256SUMS.txt', 'portpilot-macos-cli.zip', 'portpilot-macos-tui.zip',
  ]);
  assert.match(fs.readFileSync(path.join(env.PORTPILOT_RELEASE_DIR, 'RELEASE.txt'), 'utf8'), /Notarization: not performed/);
  const trace = fs.readFileSync(env.MOCK_TRACE, 'utf8');
  assert.equal((trace.match(/^codesign --verify/gm) || []).length, 3);
  assert.doesNotMatch(trace, /^git (commit|tag|push|pull|add)\b|--sign\b|notarytool|stapler/gm);
  assert.match(result.stdout, /No publishing, installation, notarization, commit, or tag/);
});

test('app-only handoff does not need CLI/TUI but still requires signed source and app', (t) => {
  const env = policyFixture(t, { PORTPILOT_RELEASE_TEAM_ID: 'ABCDEFGHIJ' });
  fs.unlinkSync(env.PORTPILOT_CLI_PATH);
  fs.unlinkSync(env.PORTPILOT_TUI_PATH);
  const result = runPolicy('release_signed_macos.sh', env);
  assert.equal(result.status, 0, result.stderr);
  assert.equal((fs.readFileSync(env.MOCK_TRACE, 'utf8').match(/^codesign --verify/gm) || []).length, 1);
  assert.match(fs.readFileSync(path.join(env.PORTPILOT_RELEASE_DIR, 'RELEASE.txt'), 'utf8'), /team: ABCDEFGHIJ/);
});

test('archive failure preserves failure and never reports a successful handoff', (t) => {
  const env = policyFixture(t, { MOCK_ARCHIVE_FAILURE: '1' });
  const result = runPolicy('create_release.sh', env);
  assert.equal(result.status, 47);
  assert.doesNotMatch(result.stdout, /Verified signed local handoff/);
  assert.deepEqual(fs.readdirSync(env.PORTPILOT_RELEASE_DIR), []);
});

test('release:tag verifies an existing signed tag without creating one', (t) => {
  const env = policyFixture(t);
  const result = runPolicy('release_policy.sh', env, ['source']);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /no commit or tag was created/);
  assert.doesNotMatch(fs.readFileSync(env.MOCK_TRACE, 'utf8'), /^git (tag|commit|push)\b/m);
  assert.equal(scripts['release:tag'], 'bash scripts/release_policy.sh source');
});

test('npm publication fails closed and CI has no automatic release publishing authority', () => {
  const result = run('prepublishOnly', '');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /automatic publishing is disabled/);
  const build = fs.readFileSync(path.join(__dirname, '../.github/workflows/build.yml'), 'utf8');
  const publish = fs.readFileSync(path.join(__dirname, '../.github/workflows/npm-publish.yml'), 'utf8');
  assert.doesNotMatch(build, /contents: write|action-gh-release|GITHUB_TOKEN|^  release:/m);
  assert.match(build, /internal-unsigned/);
  assert.doesNotMatch(publish, /npm publish|NPM_TOKEN|^  push:/m);
  assert.match(publish, /permissions: \{\}/);
});
