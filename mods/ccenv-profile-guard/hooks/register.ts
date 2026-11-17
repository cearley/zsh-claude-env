import type { EngineInterface, Register } from 'claude-code';

// Ground truth for "what is this session running as": the engine process's
// own inherited CLAUDE_CONFIG_DIR, not a live re-resolution of ccenv's
// shell>local>global precedence. Those answer different questions: ccenv
// local/global just write a file and never touch a running session's env,
// so a live re-resolution can disagree with what the session is actually
// running as on purpose (e.g. mid-session cwd drift into a directory whose
// .claude-profile names something else).
async function activeConfigDir($: EngineInterface, home: string): Promise<string> {
  const result = await $.process.run(['printenv', 'CLAUDE_CONFIG_DIR']).catch(() => undefined);
  const fromEnv = result?.exitCode === 0 ? result.stdout.trim() : '';
  return fromEnv || `${home}/.claude`;
}

async function homeDir($: EngineInterface): Promise<string> {
  const result = await $.process.run(['printenv', 'HOME']);
  return result.stdout.trim();
}

async function ccenvRoot($: EngineInterface, home: string): Promise<string> {
  const result = await $.process.run(['printenv', 'CCENV_ROOT']).catch(() => undefined);
  const fromEnv = result?.exitCode === 0 ? result.stdout.trim() : '';
  return fromEnv || `${home}/.ccenv`;
}

type Profile = { name: string; realPath: string };

// The registry's own contract (ccenv--resolve.sh's header comment): a
// registered profile is a symlink at $CCENV_ROOT/profiles/<name>, nothing
// else assumed. Resolved to each symlink's real target so a touched path
// is matched against where the profile's files actually live, not against
// naming conventions.
async function registeredProfiles($: EngineInterface, home: string): Promise<Profile[]> {
  const root = await ccenvRoot($, home);
  const entries = await $.fs.list(`${root}/profiles`).catch(() => []);
  const profiles: Profile[] = [];
  for (const entry of entries) {
    if (!entry.isLink) continue;
    const stat = await $.fs.stat(`${root}/profiles/${entry.name}`, { resolve: true }).catch(() => undefined);
    if (stat?.realPath) profiles.push({ name: entry.name, realPath: stat.realPath });
  }
  return profiles;
}

async function realPathOf($: EngineInterface, path: string): Promise<string> {
  const stat = await $.fs.stat(path, { resolve: true }).catch(() => undefined);
  return stat?.realPath ?? path;
}

// Which profile (if any) owns a real path: the bare, unregistered default
// (~/.claude) first -- ccenv never registers it under any name, but a
// session running under it is still a profile identity worth protecting --
// then each registered profile, matched on a path-separator boundary so
// "~/.claude-work" never swallows "~/.claude-work-backup".
function ownerOf(realPath: string, defaultRealPath: string, profiles: Profile[]): string | undefined {
  if (realPath === defaultRealPath || realPath.startsWith(`${defaultRealPath}/`)) {
    return 'default';
  }
  for (const profile of profiles) {
    const prefix = `${profile.realPath}/`;
    if (realPath === profile.realPath || realPath.startsWith(prefix)) {
      return profile.name;
    }
  }
  return undefined;
}

async function crossProfileReason($: EngineInterface, filePath: string, verb: 'reads' | 'touches'): Promise<string | undefined> {
  const home = await homeDir($);
  const [real, activeDir, profiles] = await Promise.all([
    realPathOf($, filePath),
    activeConfigDir($, home),
    registeredProfiles($, home),
  ]);
  const defaultReal = await realPathOf($, `${home}/.claude`);

  const owner = ownerOf(real, defaultReal, profiles);
  if (!owner) return undefined; // nothing we recognize as a profile's file -- out of scope

  const activeReal = await realPathOf($, activeDir);
  // No registry match for the session's own dir (hand-set CLAUDE_CONFIG_DIR,
  // or an unregistered non-default dir) falls back to the literal path as
  // its own identity -- it can never equal a real profile name, so a touch
  // landing inside a *known* profile's dir still gets flagged rather than
  // silently passing just because the session itself has no identity.
  const activeOwner = ownerOf(activeReal, defaultReal, profiles) ?? activeDir;
  if (owner === activeOwner) return undefined;

  return `This ${verb} the "${owner}" profile's file. Active profile's config dir is ${activeDir}.`;
}

// Best-effort, not a shell parser: the first token under a $CLAUDE_CONFIG_DIR-
// style directory (~/.claude*, or $HOME/.claude* once expanded). An
// unrecognized command shape is silently out of scope rather than guessed at.
function extractCandidatePath(command: string, home: string): string | undefined {
  const expanded = command.replaceAll('$HOME', home).replaceAll('${HOME}', home);
  const match = expanded.match(/(^|[\s;&|])(~|\/[^\s;&|'"]*?)\/?\.claude[\w-]*(\/[^\s;&|'"]*)?/);
  if (!match) return undefined;
  const hit = match[0].replace(/^[\s;&|]/, '');
  return hit.startsWith('~') ? home + hit.slice(1) : hit;
}

// Fail-safe posture: a guard that cannot evaluate a call (ccenv missing,
// printenv unavailable, an fs call erroring) asks rather than silently
// clearing it, but never denies -- this guard only ever asks or stays silent.
const FAIL_SAFE = ($: EngineInterface) => ({
  decision: 'ask' as const,
  reason: `${$.plugin.name} couldn't evaluate this call (ccenv/printenv unavailable?) -- review manually.`,
});

export const register: Register = (on) => {
  on('tool.check', { tool: ['Edit', 'Write', 'Read'] }, async ($, e, next) => {
    const input = e.input as { file_path?: string };
    if (!input.file_path) return next(e);
    const reason = await crossProfileReason($, input.file_path, e.tool === 'Read' ? 'reads' : 'touches');
    return reason ? { decision: 'ask', reason } : next(e);
  }).catch(($) => FAIL_SAFE($));

  on('tool.check', { tool: 'Bash' }, async ($, e, next) => {
    const input = e.input as { command?: string };
    const command = input.command ?? '';
    const home = await homeDir($);
    const candidate = extractCandidatePath(command, home);
    if (!candidate) return next(e);
    const reason = await crossProfileReason($, candidate, 'touches');
    return reason ? { decision: 'ask', reason } : next(e);
  }).catch(($) => FAIL_SAFE($));
};
