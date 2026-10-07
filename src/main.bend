# mj (my-journal): manages personal journal entries.
#
#   mj -h | --help      prints the help
#   mj -v | --version   prints the version
#   mj new              creates an entry and opens it in $EDITOR
import Base

# Help
# ====

# A release build writes its version here; see .github/workflows/build.yml.
def version() -> String:
  "0.0.0-dev"

# The commands and the sentence describing each. mj's help lists them,
# and a command without its own help inherits its sentence (see help.of).
def commands() -> List<(String & String)>:
  [("new", "create a new entry and open it in your editor")]

# "  <name><padding><about>", with the abouts lined up in one column.
def help.row(name: String, about: String) -> String:
  +n = name
  "  " ++ n ++ String.repeat(" ", Nat.sub(15n, String.length(n))) ++ about

def help.rows(cmds: List<(String & String)>) -> List<&2, String>:
  match cmds:
    case Nil{}:
      Nil{}
    case Con{(name, about), rest}:
      Con{help.row(name, about), help.rows(rest)}

def help() -> String:
  String.join([
    "mj: manage your personal journal entries.",
    "",
    "usage: mj <command> [options]",
    "",
    "commands:",
    String.join(help.rows(commands()), "\n"),
    "",
    "options:",
    help.row("-h, --help", "show this help"),
    help.row("-v, --version", "show the version"),
    "",
    "Entries are stored in $XDG_DATA_HOME/my-journal/entries",
    "(default: ~/.local/share/my-journal/entries)."
  ], "\n")

def help.pick(found: Bool, about: String, next: String) -> String:
  match found:
    case True{}:
      about
    case False{}:
      next

# The sentence describing the command called name.
def help.about(+name: String, cmds: List<(String & String)>) -> String:
  match cmds:
    case Nil{}:
      ""
    case Con{(n, about), rest}:
      help.pick(String.eq(n, name), about, help.about(name, rest))

# The default help of a command, headed by the sentence it inherits from
# mj's help.
def help.of(name: String) -> String:
  +n = name
  String.join([
    "mj " ++ n ++ ": " ++ help.about(n, commands()),
    "",
    "usage: mj " ++ n,
    "",
    "options:",
    help.row("-h, --help", "show this help")
  ], "\n")

def is_help(+arg: String) -> Bool:
  String.eq(arg, "-h") || String.eq(arg, "--help")

def is_version(+arg: String) -> Bool:
  String.eq(arg, "-v") || String.eq(arg, "--version")

# Processes
# =========

def run.exit(ok: Bool, name: String, out: String, err: String) -> IO(String):
  match ok:
    case True{}:
      IO.pure(String, out)
    case False{}:
      IO.die(String, 1, "mj: " ++ name ++ " failed: " ++ err)

def run.check(name: String,
  r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> IO(String):
  match r:
    case Fail{(code, msg)}:
      IO.die(String, 1, "mj: " ++ name ++ ": " ++ msg)
    case Done{(code, (out, err))}:
      run.exit(U32.is_eq(code, 0), name, out, err)

# Runs a program to completion, answering its stdout; dies if it fails.
def run(program: String, args: List<String>, timeout_ms: U32) -> IO(String):
  +p = program
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, String,
    Process.run(p, args, "", 65536, timeout_ms), run.check(p))

def first_line(lines: List<&2, String>) -> String:
  match lines:
    case Nil{}:
      ""
    case Con{line, rest}:
      line

# Time
# ====

# Formats hour and minute as "<hour>.<tenths>", e.g. 7:31 -> "7.5".
def stamp.fmt(minute: Maybe<&2, U32>, day: String, hour: String,
  half: String) -> IO(String):
  match minute:
    case None{}:
      IO.die(String, 1, "mj: could not read the minute from date")
    case Some{m}:
      IO.pure(String,
        day ++ "-" ++ hour ++ "." ++ U32.show(U32.div(m, 6)) ++ "-" ++ half)

def stamp.parse(parts: List<&2, String>) -> IO(String):
  match parts:
    case Con{day, Con{hour, Con{minute, Con{half, Nil{}}}}}:
      stamp.fmt(U32.read(minute), day, hour, half)
    case _:
      IO.die(String, 1, "mj: unexpected output from date")

# The local time as "<Day>-<day>-<Month>-<year>-<hour.tenths>-<AM|PM>".
def stamp() -> IO(String):
  do IO<String>:
    out : String <- run("env",
      ["LC_TIME=C", "date", "+%A-%-d-%B-%Y %-I %-M %p"], 5000)
    stamp.parse(String.split(first_line(String.lines(out)), ' '))

# UUID
# ====

def hex.digit.if(lt: Bool, d: U32) -> Char:
  match lt:
    case True{}:
      Char.from_u32((48 + d : U32))
    case False{}:
      Char.from_u32((87 + d : U32))

def hex.digit(+d: U32) -> Char:
  hex.digit.if((d < 10 : U32), d)

# The n lowest hex digits of w.
def hex.go(n: Nat, +w: U32, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+p:
      hex.go(p, U32.shrn(w, 4n), SCon{hex.digit(U32.and(w, 15)), acc})

def hex(n: Nat, +w: U32) -> String:
  hex.go(n, w, "")

# Lays 128 random bits out as a version 4, variant 1 UUID.
def uuid.show(a: U32, +b: U32, +c: U32, d: U32) -> String:
  version = U32.or(U32.and(b, 4095), 16384)
  variant = U32.or(U32.and(U32.shrn(c, 16n), 16383), 32768)
  hex(8n, a) ++ "-" ++ hex(4n, U32.shrn(b, 16n)) ++ "-" ++ hex(4n, version)
    ++ "-" ++ hex(4n, variant) ++ "-" ++ hex(4n, c) ++ hex(8n, d)

def uuid() -> IO(String):
  do IO<String>:
    a : U32 <- IO.try(U32, IO.random_u32())
    b : U32 <- IO.try(U32, IO.random_u32())
    c : U32 <- IO.try(U32, IO.random_u32())
    d : U32 <- IO.try(U32, IO.random_u32())
    return uuid.show(a, b, c, d)

# Editor
# ======

# The machine's default terminal editor: the first of these on the PATH.
def editor.fallback() -> IO(String):
  do IO<String>:
    out : String <- run("sh", ["-c",
      "command -v editor || command -v nano || command -v vim || command -v vi"],
      5000)
    return first_line(String.lines(out))

def editor.pick.if(empty: Bool, name: String) -> IO(String):
  match empty:
    case True{}:
      editor.fallback()
    case False{}:
      IO.pure(String, name)

def editor.pick(env: Result<&1, &1, U32 & String, String>) -> IO(String):
  match env:
    case Done{+name}:
      editor.pick.if(String.is_empty(name), name)
    case Fail{error}:
      editor.fallback()

def editor() -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, String>, String,
    IO.get_env("EDITOR"), editor.pick)

# Process.run pipes the child's stdio, so the editor is handed the terminal
# through /dev/tty. $1 is unquoted so an EDITOR like "code -w" works.
def editor.open(editor: String, path: String) -> IO(String):
  run("sh", ["-c", "exec $1 \"$2\" </dev/tty >/dev/tty 2>&1", "mj",
    editor, path], 4294967295)

# XDG
# ===

def data_home.fallback() -> IO(String):
  do IO<String>:
    home : String <- IO.try(String, IO.get_env("HOME"))
    return home ++ "/.local/share"

def data_home.if(absolute: Bool, path: String) -> IO(String):
  match absolute:
    case True{}:
      IO.pure(String, path)
    case False{}:
      data_home.fallback()

# $XDG_DATA_HOME, or ~/.local/share when it is unset, empty or relative,
# as the XDG Base Directory spec asks.
def data_home.pick(env: Result<&1, &1, U32 & String, String>) -> IO(String):
  match env:
    case Done{+path}:
      data_home.if(String.starts_with(path, "/"), path)
    case Fail{error}:
      data_home.fallback()

def entries_dir() -> IO(String):
  do IO<String>:
    env : Result<&1, &1, U32 & String, String> <- IO.get_env("XDG_DATA_HOME")
    data : String <- data_home.pick(env)
    return data ++ "/my-journal/entries"

# Commands
# ========

def new.write.done(w: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, r) = w
  do IO<Unit>:
    u : Unit <- IO.pass(Unit, r)
    File.close(f)

def new.write(+dir: String, +name: String) -> IO(Unit):
  +path = dir ++ "/" ++ name ++ ".md"
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    w : File & Result<&1, &1, U32 & String, Unit> <-
      File.write(f, "# " ++ name ++ "\n\n")
    u : Unit <- new.write.done(w)
    e : String <- editor()
    o : String <- editor.open(e, path)
    IO.print(path)

def new.at(+dir: String) -> IO(Unit):
  do IO<Unit>:
    m : String <- run("mkdir", ["-p", "--", dir], 5000)
    when : String <- stamp()
    id : String <- uuid()
    new.write(dir, when ++ "-" ++ id)

# For a command that takes no arguments: -h and --help show its help; any
# other argument is reported, followed by the help.
def args.none.if(is_h: Bool, +n: String, arg: String) -> IO(Unit):
  match is_h:
    case True{}:
      IO.print(help.of(n))
    case False{}:
      IO.die(Unit, 2, "mj " ++ n ++ ": unexpected argument '" ++ arg
        ++ "'\n\n" ++ help.of(n))

def new(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}:
      IO.bind(String, Unit, entries_dir(), dir => new.at(dir))
    case Con{+arg, rest}:
      args.none.if(is_help(arg), "new", arg)

def unknown.kind(option: Bool) -> String:
  match option:
    case True{}:
      "option"
    case False{}:
      "command"

def command.if(is_h: Bool, is_v: Bool, is_new: Bool, +cmd: String,
  rest: List<String>) -> IO(Unit):
  match is_h:
    case True{}:
      IO.print(help())
    case False{}:
      match is_v:
        case True{}:
          IO.print("mj " ++ version())
        case False{}:
          match is_new:
            case True{}:
              new(rest)
            case False{}:
              IO.die(Unit, 2, "mj: unknown "
                ++ unknown.kind(String.starts_with(cmd, "-")) ++ " '" ++ cmd
                ++ "'\n\n" ++ help())

def command(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}:
      IO.print(help())
    case Con{+cmd, rest}:
      command.if(is_help(cmd), is_version(cmd), String.eq(cmd, "new"), cmd,
        rest)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    command(List.tail(&1, String, args))
