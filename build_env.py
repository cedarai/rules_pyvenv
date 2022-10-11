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

import collections
import json
import os
import pathlib
import subprocess
import sys
import textwrap
from typing import Dict, List, Optional
import venv

import entrypoints


EnvFile = collections.namedtuple("EnvFile", ["path", "site_packages_path"])


def console_script(env_path: pathlib.Path, module: str, func: str) -> str:
    return textwrap.dedent(
        f"""\
        #!{env_path / "bin/python3"}
        # -*- coding: utf-8 -*-
        import re
        import sys
        from {module} import {func}
        if __name__ == '__main__':
            sys.argv[0] = re.sub(r'(-script\\.pyw|\\.exe)?$', '', sys.argv[0])
            sys.exit({func}())
        """
    )


def get_site_packages_path(path: str, imports: List[str]) -> Optional[str]:
    if not path.startswith("../"):
        return path

    for imp in imports:
        # Newer versions of rules_python use a site-packages/ prefix, so we also check for that.
        prefixes = [f"../{imp}/site-packages/", f"../{imp}/"]
        for prefix in prefixes:
            if path.startswith(prefix):
                return path[len(prefix) :]

    # External file that didn't match imports. Include but warn.
    parts = path.split("/", maxsplit=2)
    include_path = parts[2]
    print(f"Warning: [{path}] didn't match any imports. Including as [{include_path}]")


def is_external(file_: str) -> bool:
    return file_.startswith("../")


def find_site_packages(env_path: pathlib.Path) -> pathlib.Path:
    lib_path = env_path / "lib"

    # We should find one "pythonX.X" directory in here.
    for child in lib_path.iterdir():
        if child.name.startswith("python"):
            site_packages_path = child / "site-packages"
            if site_packages_path.exists():
                return site_packages_path

    raise Exception("Unable to find site-packages path in venv")


def get_files(build_env_input: Dict) -> List[EnvFile]:
    files = []

    imports = build_env_input["imports"]
    for depfile in build_env_input["files"]:
        # Bucket files into external and workspace groups.
        # Only generated workspace files are kept.
        type_ = depfile["t"]
        path = depfile["p"]

        site_packages_path = get_site_packages_path(path, imports)
        if not site_packages_path:
            continue

        if is_external(path):
            files.append(EnvFile(pathlib.Path(path), pathlib.Path(site_packages_path)))
        elif type_ == "G":
            files.append(EnvFile(pathlib.Path(path), pathlib.Path(site_packages_path)))

    return files


def is_data_file(file: EnvFile) -> bool:
    return file.site_packages_path.parts[0].endswith(".data")


def install_data_file(env_path: pathlib.Path, file: EnvFile) -> None:
    if len(file.site_packages_path.parts) > 2 and file.site_packages_path.parts[1] == "scripts":
        install_included_script(env_path, file.path)


def install_site_file(site_packages_path: pathlib.Path, file: EnvFile) -> None:
    site_path = site_packages_path / file.site_packages_path
    if not site_path.exists():
        site_path.parent.mkdir(parents=True, exist_ok=True)
        site_path.symlink_to(file.path.resolve())


def install_files(env_path: pathlib.Path, files: List[EnvFile]) -> None:
    site_packages_path = find_site_packages(env_path)
    for file in files:
        if is_data_file(file):
            install_data_file(env_path, file)
        else:
            install_site_file(site_packages_path, file)


def generate_console_scripts(env_path: pathlib.Path) -> None:
    site_packages = find_site_packages(env_path)
    bin = env_path / "bin"

    entry_points = entrypoints.get_group_all("console_scripts", [str(site_packages)])
    for ep in entry_points:
        script = bin / ep.name
        if script.exists():
            continue
        script.write_text(console_script(env_path, ep.module_name, ep.object_name), encoding="utf-8")
        script.chmod(0o755)


def install_included_script(env_path: pathlib.Path, script_file: pathlib.Path) -> None:
    script_text = script_file.read_bytes()

    # From pep-491:
    #   Python scripts must appear in scripts and begin with exactly b'#!python' in order to enjoy script wrapper
    #   generation and #!python rewriting at install time. They may have any or no extension.
    if script_text.startswith(b"#!python"):
        shebang = f'#!{env_path / "bin/python3"}'.encode("utf-8")
        script_text = shebang + script_text[len(b"#!python") :]

    script = env_path / "bin" / script_file.name
    script.write_bytes(script_text)
    script.chmod(0o755)


def run_additional_commands(env_path: pathlib.Path, commands: List[str]) -> None:
    lines = [f". {env_path}/bin/activate"]
    for cmd in commands:
        pip_cmd = f"pip --no-input {cmd}"
        # Echo in green what command is being run
        lines.append(fr'echo "\n\033[0;32m> {pip_cmd}\033[0m"')
        lines.append(pip_cmd)

    full_command = ";".join(lines)

    # Prefer using zsh, since on macos (which ships with it), zsh adds support for executing
    # scripts whose shebang lines point to other scripts.
    # If we can't find zsh, use the default and hope for the best.
    shell = None
    for zsh in ["/bin/zsh", "/usr/bin/zsh"]:
        if pathlib.Path(zsh).exists():
            shell = zsh
    ret = subprocess.run(full_command, capture_output=False, shell=True, executable=shell)
    ret.check_returncode()


def main():
    if "BUILD_ENV_INPUT" not in os.environ:
        raise Exception("Missing BUILD_ENV_INPUT environment variable")
    if len(sys.argv) != 2:
        raise Exception(f"Usage: {sys.argv} <venv path>")

    with open(os.environ["BUILD_ENV_INPUT"]) as f:
        build_env_input = json.load(f)

    files = get_files(build_env_input)

    # Hack: fully resolve the current interpreter's known path to get venv to link to the
    # files in their actual location
    sys._base_executable = str(pathlib.Path(sys._base_executable).resolve())

    cwd = os.environ.get("BUILD_WORKING_DIRECTORY", os.getcwd())
    env_path = pathlib.Path(cwd) / pathlib.Path(sys.argv[1])

    builder = venv.EnvBuilder(clear=True, symlinks=True, with_pip=True)
    builder.create(str(env_path))

    install_files(env_path, files)
    generate_console_scripts(env_path)

    extra_commands = build_env_input.get("commands")
    if extra_commands:
        run_additional_commands(env_path, extra_commands)


if __name__ == "__main__":
    main()
