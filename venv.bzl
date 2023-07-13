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

PYTHON_TOOLCHAIN_TYPE = "@bazel_tools//tools/python:toolchain_type"

def _py_venv_deps_impl(ctx):
    toolchain_depset = ctx.toolchains[PYTHON_TOOLCHAIN_TYPE].py3_runtime.files or depset()
    toolchain_files = {f: None for f in toolchain_depset.to_list()}

    imports = []
    for dep in ctx.attr.deps:
        if PyInfo not in dep:
            continue
        imports.extend([i for i in dep[PyInfo].imports.to_list() if i not in imports])

    deps = depset(transitive = [dep[DefaultInfo].default_runfiles.files for dep in ctx.attr.deps])
    data = depset(transitive = [data[DefaultInfo].files for data in ctx.attr.data])
    out = ctx.outputs.output

    files = []
    for dep in deps.to_list() + data.to_list():
        # Skip files that are provided by the python toolchain.
        # They don't need to be in the venv.
        if dep in toolchain_files:
            continue

        typ = "S" if dep.is_source else "G"
        files.append({"t": typ, "p": dep.short_path})

    doc = {
        "workspace": ctx.workspace_name,
        "imports": imports,
        "files": files,
        "commands": ctx.attr.commands,
        "always_link": ctx.attr.always_link,
    }
    ctx.actions.write(out, json.encode(doc))

    return [DefaultInfo(files = depset(direct = [out]))]

_py_venv_deps = rule(
    implementation = _py_venv_deps_impl,
    attrs = {
        "deps": attr.label_list(),
        "data": attr.label_list(),
        "commands": attr.string_list(),
        "always_link": attr.bool(),
        "output": attr.output(),
    },
    toolchains = [PYTHON_TOOLCHAIN_TYPE],
)

def py_venv(name, deps = None, data = None, extra_pip_commands = None, always_link = False, venv_location = None, **kwargs):
    deps = deps or []
    extra_pip_commands = extra_pip_commands or []

    deps_name = "_" + name + "_deps"
    out_name = deps_name + ".json"
    out_label = ":" + out_name
    _py_venv_deps(
        name = deps_name,
        deps = deps,
        data = data,
        commands = extra_pip_commands,
        always_link = always_link,
        output = out_name,
        **kwargs,
    )

    env = {
        "BUILD_ENV_INPUT": "$(location " + out_label + ")",
    }

    if venv_location:
        env.update({"VENV_LOCATION": venv_location})

    py_binary(
        name = name,
        srcs = ["@rules_pyvenv//:build_env.py"],
        deps = ["@rules_pyvenv//vendor/importlib_metadata"],
        data = [out_label] + deps + data,
        main = "@rules_pyvenv//:build_env.py",
        env = env,
        **kwargs,
    )
