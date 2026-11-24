# -n --rawfile files LIST (git ls-files, one path per line) --argjson pkg PACKAGE_JSON|null
# Output: inventory of the repository (spec project-context: Bản kê repo). Pure and sorted, so the
# same commit always gives the same result.
def top: if test("/") then split("/")[0] else "." end;
def base: split("/") | last;
def ext: base | if test("^[^.].*\\.[^.]+$") then (split(".") | last | ascii_downcase) else "" end;
def is_doc:
  (ext | IN("md", "markdown", "txt", "rst", "adoc"))
  or (base | ascii_upcase | test("^(LICENSE|LICENCE|COPYING|NOTICE|CHANGELOG|AUTHORS|CONTRIBUTORS)(\\..*)?$"))
  or startswith("docs/");
def is_github: startswith(".github/");
def is_root_dotfile: (test("/") | not) and startswith(".");
def manifests: ["package.json", "go.mod", "Cargo.toml", "pyproject.toml", "requirements.txt", "Pipfile", "setup.py",
                "Gemfile", "pom.xml", "build.gradle", "build.gradle.kts", "composer.json", "mix.exs", "pubspec.yaml",
                "Package.swift", "deno.json", "bun.lockb"];
def is_ci:
  startswith(".github/workflows/") or startswith(".circleci/") or startswith(".buildkite/")
  or IN(".gitlab-ci.yml", "Jenkinsfile", "azure-pipelines.yml", ".travis.yml", "bitbucket-pipelines.yml");
def test_dir_names: ["test", "tests", "__tests__", "spec", "specs", "e2e", "testing"];

[$files | split("\n")[] | select(length > 0)] | sort as $all
| ($all | map(select((is_github or is_doc or is_root_dotfile) | not))) as $code
| { files: ($all | length),
    has_code: (($code | length) > 0),
    top_dirs: ($all | group_by(top) | map({name: (.[0] | top), files: length}) | sort_by(-.files, .name)),
    extensions: ($all | map(ext) | map(select(. != "")) | group_by(.) | map({ext: .[0], files: length}) | sort_by(-.files, .ext)),
    manifests: [$all[] | select(base as $b | manifests | index($b))],
    package_scripts: (if ($pkg | type) == "object" then ($pkg.scripts // {}) else {} end),
    ci: [$all[] | select(is_ci)],
    test_dirs: ([$all[] | split("/") | .[:-1] as $d
                 | range(0; $d | length) as $i | select(test_dir_names | index($d[$i])) | $d[:$i + 1] | join("/")]
                | unique),
    docs: ([$all[] | select(is_doc and (is_github | not))] | .[:50]),
    docs_total: ([$all[] | select(is_doc and (is_github | not))] | length) }
