# Bazel rules for creating Python virtual environments.
See `example/` for an example.

## Installation
Add the following to your `WORKSPACE`.

```
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "rules_pyvenv",
    strip_prefix = "main",
    url = "https://github.com/cedarai/rules_pyvenv/archive/main.tar.gz",
)

load("@rules_pyvenv//:repositories.bzl", rules_pyvenv_repositories = "repositories")
rules_pyvenv_repositories()
```
