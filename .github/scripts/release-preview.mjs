// Writes the PR comment saying what release squash-merging this PR would make.
// The squash merge makes the PR title the commit on main, so semantic-release's
// commit analyzer, with the options in .releaserc.yaml, decides from the title
// alone. Reads TITLE, writes the comment to the file named in COMMENT, and runs
// in a checkout of main.
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { analyzeCommits } from "@semantic-release/commit-analyzer";
import semver from "semver";
import { parse } from "yaml";

const { TITLE, COMMENT } = process.env;
const analyzer = "@semantic-release/commit-analyzer";

const { plugins } = parse(readFileSync(".releaserc.yaml", "utf8"));
const entry = plugins.find((p) => (Array.isArray(p) ? p[0] : p) === analyzer);
const options = Array.isArray(entry) ? entry[1] : {};

const bump = await analyzeCommits(options, {
  cwd: process.cwd(),
  commits: [{ hash: "", message: TITLE }],
  logger: { log() {} },
});

// semantic-release's last release: the highest v<version> tag on main.
const last = execFileSync("git", ["tag", "--merged", "HEAD", "--list", "v*"], { encoding: "utf8" })
  .split("\n")
  .map((tag) => semver.valid(tag.slice(1)))
  .filter((version) => version && !semver.prerelease(version))
  .sort(semver.rcompare)[0];

const type = TITLE.match(/^\w+/)[0];
const cc = "[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)";
let comment;
if (!bump) {
  comment = `Squash-merging this releases nothing, as the ${cc} type \`${type}\` doesn't change the version. If it changes what mj does for users, use \`feat\` or \`fix\` instead.`;
} else if (!last) {
  comment = `Going by its ${cc} title, squash-merging this makes the first release, **v1.0.0**.`;
} else {
  comment = `Going by its ${cc} title, squash-merging this now releases **v${semver.inc(last, bump)}**, a ${bump} bump from v${last}.`;
}
writeFileSync(COMMENT, comment + "\n");
console.log(comment);
