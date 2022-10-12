# Bazel rules for creating Python virtual environments.
See `example/` for an example.

## Installation
Add the following to your `WORKSPACE`.

(Note: see the releases page for release-specific `WORKSPACE` config)

```
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "rules_pyvenv",
    strip_prefix = "rules_pyvenv-main",
    url = "https://github.com/cedarai/rules_pyvenv/archive/main.tar.gz",
)
```

These rules require a recent version of Python 3.6+ and `rules_python`.
The environment is built using the `venv` library that ships with the Python standard library.
If using the system-provided Python on Debian/Ubuntu, you may need to run
```
apt install python3.8-venv
```

## Example
```
$ cd example
$ bazel run //:venv env
$ . env/bin/activate
```
