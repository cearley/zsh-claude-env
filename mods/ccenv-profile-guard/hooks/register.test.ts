import { expect, test } from 'claude-code/testing';

const HOME = '/Users/x';

function run(stdout: string, exitCode = 0) {
  return { value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } };
}

function stat(realPath: string) {
  return { value: { kind: 'dir' as const, size: 0, mtimeMs: 0, isLink: false, realPath } };
}

function mockEnv(on: Parameters<typeof test>[1] extends never ? never : any, activeConfigDir: string, ccenvRoot?: string) {
  // Nothing sits beneath tool.check in a test; this stands in for "no rule,
  // mode or other hook made a decision" -- the real engine's own default
  // once our hook calls next(e) without deciding.
  on('tool.check', () => ({ decision: 'allow' }));

  on('process.run', (_: unknown, e: { argv: readonly string[] }) => {
    const [cmd, arg] = e.argv;
    if (cmd !== 'printenv') throw new Error(`unexpected argv ${JSON.stringify(e.argv)}`);
    if (arg === 'CLAUDE_CONFIG_DIR') return run(`${activeConfigDir}\n`);
    if (arg === 'HOME') return run(`${HOME}\n`);
    if (arg === 'CCENV_ROOT') return ccenvRoot ? run(`${ccenvRoot}\n`) : run('', 1);
    throw new Error(`unexpected printenv ${arg}`);
  });
}

function mockRegistry(on: any, profiles: Record<string, string>, extraStats: Record<string, string> = {}) {
  on('fs.list', (_: unknown, e: { path: string }) => {
    if (e.path !== `${HOME}/.ccenv/profiles`) throw new Error(`unexpected list ${e.path}`);
    return { value: Object.keys(profiles).map((name) => ({ name, kind: 'other', size: 0, mtimeMs: 0, isLink: true })) };
  });
  on('fs.stat', (_: unknown, e: { path: string }) => {
    for (const [name, realPath] of Object.entries(profiles)) {
      if (e.path === `${HOME}/.ccenv/profiles/${name}`) return stat(realPath);
    }
    if (e.path === `${HOME}/.claude`) return stat(`${HOME}/.claude`);
    if (e.path in extraStats) return stat(extraStats[e.path]);
    // Anything already shaped like a real path (our own fallback case) resolves to itself.
    return stat(e.path);
  });
}

test('asks when Read targets a different registered profile\'s file', async ($, on) => {
  mockEnv(on, `${HOME}/.claude-personal`);
  mockRegistry(on, { personal: `${HOME}/.claude-personal`, work: `${HOME}/.claude-work` });

  const result = await $.tool.check({ tool: 'Read', input: { file_path: `${HOME}/.claude-work/settings.json` } });

  expect(result.decision).toBe('ask');
  expect(result.reason).toContain('work');
});

test('stays silent on a same-profile Edit', async ($, on) => {
  mockEnv(on, `${HOME}/.claude-personal`);
  mockRegistry(on, { personal: `${HOME}/.claude-personal`, work: `${HOME}/.claude-work` });

  const result = await $.tool.check({ tool: 'Edit', input: { file_path: `${HOME}/.claude-personal/settings.json` } });

  expect(result.decision).toBe('allow');
});

test('recognizes the bare, unregistered default profile', async ($, on) => {
  mockEnv(on, `${HOME}/.claude-work`);
  mockRegistry(on, { work: `${HOME}/.claude-work` });

  const result = await $.tool.check({ tool: 'Edit', input: { file_path: `${HOME}/.claude/CLAUDE.md` } });

  expect(result.decision).toBe('ask');
  expect(result.reason).toContain('default');
});

test('a hand-set, unregistered session dir still flags a known profile\'s file', async ($, on) => {
  // No session identity must not silently become no checking.
  mockEnv(on, '/tmp/scratch-claude-dir');
  mockRegistry(on, { work: `${HOME}/.claude-work` });

  const result = await $.tool.check({ tool: 'Write', input: { file_path: `${HOME}/.claude-work/settings.json` } });

  expect(result.decision).toBe('ask');
});

test('does not false-positive on a profile-name prefix collision', async ($, on) => {
  // ~/.claude-work vs ~/.claude-work-backup on a path-separator boundary.
  mockEnv(on, `${HOME}/.claude-work`);
  mockRegistry(on, { work: `${HOME}/.claude-work` });

  const result = await $.tool.check({
    tool: 'Read',
    input: { file_path: `${HOME}/.claude-work-backup/settings.json` },
  });

  expect(result.decision).toBe('allow');
});

test('Bash: extracts a candidate path and asks across profiles', async ($, on) => {
  mockEnv(on, `${HOME}/.claude-personal`);
  mockRegistry(on, { personal: `${HOME}/.claude-personal`, work: `${HOME}/.claude-work` });

  const result = await $.tool.check({
    tool: 'Bash',
    input: { command: `cat ${HOME}/.claude-work/settings.json` },
  });

  expect(result.decision).toBe('ask');
});

test('Bash: an unrelated command is left alone', async ($, on) => {
  mockEnv(on, `${HOME}/.claude-personal`);
  mockRegistry(on, { personal: `${HOME}/.claude-personal` });

  const result = await $.tool.check({ tool: 'Bash', input: { command: 'git status' } });

  expect(result.decision).toBe('allow');
});
