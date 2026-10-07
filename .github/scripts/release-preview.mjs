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

// semantic-release's last release: the highest v<version> tag on main.
const last = execFileSync("git", ["tag", "--merged", "HEAD", "--list", "v*"], { encoding: "utf8" })
  .split("\n")
  .map((tag) => semver.valid(tag.slice(1)))
  .filter((version) => version && !semver.prerelease(version))
  .sort(semver.rcompare)[0];

// Commits on main since then, which the next release includes whatever this
// PR brings.
const range = last ? [`v${last}..HEAD`] : ["HEAD"];
const unreleased = execFileSync("git", ["log", "--format=%B%x00", ...range], { encoding: "utf8" })
  .split("\0")
  .map((message) => message.trim())
  .filter(Boolean);

const release = (type) => {
  if (!type) return "nothing";
  if (!last) return "**v1.0.0**, the first release";
  return `**v${semver.inc(last, type)}**, a ${type} bump from v${last}`;
};

const prCommits = readFileSync(COMMITS, "utf8")
  .split("\n")
  .filter(Boolean)
  .map((line) => JSON.parse(line));
const squash = release(await bump([...unreleased, BODY ? `${TITLE}\n\n${BODY}` : TITLE]));
const commits = release(await bump([...unreleased, ...prCommits]));

let comment = `Going by [Conventional Commits](${cc}), merging this now releases`;
if (squash === commits) {
  comment += ` ${squash}, however it's merged.`;
  if (squash === "nothing" && TITLE_OK === "true") {
    comment += " If it changes what mj does for users, use `feat` or `fix`.";
  }
} else {
  comment += `:\n\n- squash merge, by the title and description: ${squash}\n- merge or rebase, by the commits: ${commits}`;
}
if (await bump(unreleased)) {
  comment += `\n\nThis counts commits already on main that haven't been released yet.`;
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
