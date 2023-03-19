# Copyright 2023 cedar.ai. All rights reserved.
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

def _impl(rctx):
    rctx.file("BUILD.bazel", """
package(default_visibility = ["//visibility:public"])

exports_files(["venv.bzl"])
""")

    rctx.download_and_extract(
        output = "importlib_metadata",
        sha256 = "9e6fafdbf0601a5825c53a842f7bb6928c8e8eb6c46a228199ca02396cf6007a",
        stripPrefix = "importlib_metadata-6.0.0",
        url = "https://github.com/python/importlib_metadata/archive/refs/tags/v6.0.0.tar.gz",
    )

    rctx.file("importlib_metadata/BUILD.bazel", """
package(default_visibility = ["//visibility:public"])

py_library(
    name = "importlib_metadata",
    srcs = glob(["importlib_metadata/*.py"]),
    imports = ["."],
    deps = [
        "@{name}//zipp",
    ],
)
""".format(
        name = rctx.name,
    ))

    rctx.download_and_extract(
        output = "zipp",
        sha256 = "a2e6a09c22d6d36221e2d37f08d9566554f4de9e6e3ed8eb9ddcc0b0440162c0",
        stripPrefix = "zipp-3.15.0",
        url = "https://github.com/jaraco/zipp/archive/refs/tags/v3.15.0.tar.gz",
    )

    rctx.file("zipp/BUILD.bazel", """
package(default_visibility = ["//visibility:public"])

py_library(
    name = "zipp",
    srcs = glob(["zipp/*.py"]),
    imports = ["."],
)
""")

    rctx.template("venv.bzl", rctx.attr._template, {
        "%%NAME%%": rctx.name,
    })

py_venv_repositories = repository_rule(
    implementation = _impl,
    attrs = {
        "_template": attr.label(
            default = ":venv.bzl.tmpl",
        ),
    },
)
