// Writes the PR comment saying what release merging this PR would make. A
// squash merge makes the PR's title and description the commit on main (the
// repo's squash settings); a merge or rebase brings the PR's own commits. The
// release also counts main's commits since the last release tag. Each case is
// decided by semantic-release's commit analyzer, with the options in
// .releaserc.yaml.
//
// Reads TITLE, BODY (the PR description), TITLE_OK ("true" if the title is
// conventional) and COMMITS (a file with one JSON-encoded commit message per
// line), writes the comment to the file named in COMMENT, and runs in a
// checkout of main.
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { analyzeCommits } from "@semantic-release/commit-analyzer";
import semver from "semver";
import { parse } from "yaml";

const { TITLE, BODY, TITLE_OK, COMMITS, COMMENT } = process.env;
const analyzer = "@semantic-release/commit-analyzer";
const cc = "https://www.conventionalcommits.org/en/v1.0.0/";

const { plugins } = parse(readFileSync(".releaserc.yaml", "utf8"));
const entry = plugins.find((p) => (Array.isArray(p) ? p[0] : p) === analyzer);
const options = Array.isArray(entry) ? entry[1] : {};

const bump = (messages) =>
  analyzeCommits(options, {
    cwd: process.cwd(),
    commits: messages.map((message) => ({ hash: "", message })),
    logger: { log() {} },
  });

// semantic-release's last release: the highest v<version> tag on main. The
// tag is kept as named, since build metadata such as +build.1 isn't part of
// the parsed version.
const last = execFileSync("git", ["tag", "--merged", "HEAD", "--list", "v*"], { encoding: "utf8" })
  .split("\n")
  .map((tag) => ({ tag, version: semver.valid(tag.slice(1)) }))
  .filter(({ version }) => version && !semver.prerelease(version))
  .sort((a, b) => semver.rcompare(a.version, b.version))[0];

// Commits on main since then, which the next release includes whatever this
// PR brings.
const range = last ? [`${last.tag}..HEAD`] : ["HEAD"];
const unreleased = execFileSync("git", ["log", "--format=%B%x00", ...range], { encoding: "utf8" })
  .split("\0")
  .map((message) => message.trim())
  .filter(Boolean);

// The analyzer's types, lowest first; a set of commits releases the highest
// of its commits' types.
const types = [null, "patch", "minor", "major"];
const higher = (a, b) => types[Math.max(types.indexOf(a), types.indexOf(b))];

const release = (type) => {
  if (!type) return "nothing";
  if (!last) return "nothing until `v0.0.0` is tagged";
  return `**v${semver.inc(last.version, type)}**, a ${type} bump from ${last.tag}`;
};

const prCommits = readFileSync(COMMITS, "utf8")
  .split("\n")
  .filter(Boolean)
  .map((line) => JSON.parse(line));
const base = await bump(unreleased);
const squash = release(higher(base, await bump([BODY ? `${TITLE}\n\n${BODY}` : TITLE])));
const commits = release(higher(base, await bump(prCommits)));

let comment = `Going by [Conventional Commits](${cc}), merging this now releases`;
if (squash === commits) {
  comment += ` ${squash}, however it's merged.`;
  if (squash === "nothing" && TITLE_OK === "true") {
    comment += " If it changes what mj does for users, use `feat` or `fix`.";
  }
} else {
  comment += `:\n\n- squash merge, by the title and description: ${squash}\n- merge or rebase, by the commits: ${commits}`;
}
if (base) {
  comment += `\n\nThis counts commits already on main that haven't been released yet.`;
}
if (!last) {
  comment += `\n\nmain has no \`v*\` tag, so release.yml stops rather than release v1.0.0. Tag main's first commit \`v0.0.0\`.`;
}

if (TITLE_OK !== "true") {
  comment += `

The title isn't a Conventional Commit, so please rename it to \`<type>(<scope>): <summary>\`, e.g. \`fix(install): accept MJ_VERSION without a leading v\`:

- \`feat\`: something new for users (minor)
- \`fix\`: a bug fix (patch)
- \`perf\`: faster or lighter, same behaviour (patch)
- \`refactor\`: restructured code, same behaviour (no release)
- \`docs\`: documentation only (no release)
- \`test\`: tests only (no release)
- \`build\`: build setup or dependencies, e.g. \`mise.toml\` (no release)
- \`ci\`: workflows and CI scripts (no release)
- \`chore\`: other upkeep (no release)
- \`style\`: formatting only (no release)
- \`revert\`: undoes an earlier change (no release)
- add \`!\` after the type, e.g. \`feat!:\`, when users must change how they use mj (major)`;
}

writeFileSync(COMMENT, comment + "\n");
console.log(comment);
