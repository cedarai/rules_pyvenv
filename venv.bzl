# Copyright 2021 cedar.ai. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("@rules_python//python:defs.bzl", "py_binary")
load("@rules_pyvenv_deps//:requirements.bzl", "requirement")

def _py_venv_deps_impl(ctx):
    imports = []
    for dep in ctx.attr.deps:
        if PyInfo not in dep:
            continue
        imports.extend([i for i in dep[PyInfo].imports.to_list() if i not in imports])

    deps = depset(transitive = [dep[DefaultInfo].default_runfiles.files for dep in ctx.attr.deps])
    out = ctx.outputs.output

    files = []
    for dep in deps.to_list():
        if dep.is_directory:
            continue
        typ = "S" if dep.is_source else "G"
        files.append({"t": typ, "p": dep.short_path})

    doc = {
        "imports": list(imports),
        "files": files,
        "commands": ctx.attr.commands,
    }
    ctx.actions.write(out, json.encode(doc))

    return [DefaultInfo(files = depset(direct = [out]))]

_py_venv_deps = rule(
    implementation = _py_venv_deps_impl,
    attrs = {
        "deps": attr.label_list(),
        "commands": attr.string_list(),
        "output": attr.output(),
    },
)

def py_venv(name, deps = None, extra_pip_commands = None):
    deps = deps or []
    extra_pip_commands = extra_pip_commands or []

    deps_name = "_" + name + "_deps"
    out_name = deps_name + ".txt"
    out_label = ":" + out_name
    _py_venv_deps(
        name = deps_name,
        deps = deps,
        commands = extra_pip_commands,
        output = out_name,
    )

    py_binary(
        name = name,
        srcs = ["@rules_pyvenv//:build_env.py"],
        deps = [requirement("entrypoints")],
        data = [out_label] + deps,
        main = "@rules_pyvenv//:build_env.py",
        env = {
            "BUILD_ENV_INPUT": "$(location " + out_label + ")",
        },
    )
