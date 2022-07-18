import fileinput
import os
from pathlib import Path
from typing import List

import requests
from packaging.version import Version

PLUGIN_DIR = '~/GitHub/jetbrains/plugins'


def _parse_file(path: Path) -> List[str]:
    with open(path, "r") as f:
        return [line for line in f]


def _get_line_starting_with(search: str, lines: List[str] = None) -> str:
    for line in lines:
        if line.startswith(search):
            return line


def _get_version_from_prop(search: str, lines: List[str] = None) -> Version:
    txt = _get_line_starting_with(search, lines)
    return Version(txt.split(' = ')[1].strip())


def get_latest_intellij_release() -> Version:
    data = requests.get(url=f'https://data.services.jetbrains.com/products?code=IIU&release.type=release').json()

    versions: List[Version] = []
    for ide in data:
        code = ide['code']
        name = ide['name']

        print(f'Processing releases for {code} -> {name}')
        for release in ide['releases']:
            versions.append(Version(release['version']))

    v = max(versions)
    return v


def _next_plugin_version(
        plugin_version: Version,
        current_platform_version: Version,
        new_platform_version: Version,
) -> Version:
    # Platform: 2022.3.2 -> 2023.1.0
    # Plugin  :    0.2.6 ->    1.0.0
    if new_platform_version.major > current_platform_version.major:
        return Version(f'{plugin_version.major + 1}.0.0')

    # Platform: 2022.1.1 -> 2023.2.0
    # Plugin  :    0.2.6 ->    0.3.0
    if new_platform_version.minor > current_platform_version.minor:
        return Version(f'{plugin_version.major}.{plugin_version.minor + 1}.0')

    # Platform: 2022.3.2 -> 2023.3.3
    # Plugin  :    0.2.6 ->    0.2.7
    if new_platform_version.micro > current_platform_version.micro:
        return Version(f'{plugin_version.major}.{plugin_version.minor}.{plugin_version.micro + 1}')

    return plugin_version


def update_gradle_properties(plugin_path: Path, new_version: Version) -> Version:
    print(f'Updating  [gradle.properties] file...')
    gradle_file = plugin_path / 'gradle.properties'

    lines = _parse_file(gradle_file)

    current_plugin_version = _get_version_from_prop('pluginVersion', lines)
    current_plugin_verifier_ide_versions = _get_version_from_prop('pluginVerifierIdeVersions', lines)
    current_platform_version = _get_version_from_prop('platformVersion', lines)

    if current_platform_version == new_version:
        print(f'Skipping  [gradle.properties] file, versions same ({current_platform_version} == {new_version}).\n')
        return current_platform_version

    next_plugin_version = _next_plugin_version(
        plugin_version=current_plugin_version,
        current_platform_version=current_platform_version,
        new_platform_version=new_version,
    )

    with fileinput.FileInput(gradle_file, inplace=True, backup='.bak') as file:
        for line in file:
            # replace pluginVersion
            line = line.replace(
                f'pluginVersion = {current_plugin_version}',
                f'pluginVersion = {next_plugin_version}'
            )

            # replace pluginVerifierIdeVersions
            line = line.replace(
                f'pluginVerifierIdeVersions = {current_plugin_verifier_ide_versions}',
                f'pluginVerifierIdeVersions = {new_version}'
            )

            # replace platformVersion
            line = line.replace(
                f'platformVersion = {current_platform_version}',
                f'platformVersion = {new_version}'
            )

            print(line, end='')  # the line already has a `\n` char, so omit adding a new one.

    # Delete the backup file
    backup_file = Path(str(gradle_file) + '.bak')
    if backup_file.is_file() and backup_file.exists():
        os.remove(backup_file)

    print(f'Completed [gradle.properties] file.\n')
    return current_platform_version


def update_changelog(plugin_path: Path, new_version: Version) -> None:
    print(f'Updating  [CHANGELOG.md] file...')

    changelog_file = plugin_path / 'CHANGELOG.md'
    upgrade_line = f'- Upgrading IntelliJ to {new_version}\n'

    # Check if the upgrade line already exists in `CHANGELOG.md`
    with open(file=changelog_file, mode='r') as f:
        for line in f:
            if upgrade_line == line:
                print(f'Skipping  [CHANGELOG.md] file, already found "{upgrade_line.strip()}" in file.\n')
                return

    with fileinput.FileInput(changelog_file, inplace=True, backup='.bak') as file:
        changed = False
        for line in file:
            # We always print the existing line...
            print(line, end='')  # the line already has a `\n` char, so omit adding a new one.

            # ...and if we run into the first line with `### Changed`, we add a line item for this version.
            if '### Changed' in line and not changed:
                changed = True
                print(upgrade_line, end='')

    # Delete the backup file
    backup_file = Path(str(changelog_file) + '.bak')
    if backup_file.is_file() and backup_file.exists():
        os.remove(backup_file)

    print(f'Completed [CHANGELOG.md] file.\n')


def _find_github_compatibility_workflow_files(plugin_path: Path) -> List[Path]:
    results: List[Path] = []
    for path in Path(plugin_path).glob('.github/workflows/*'):
        if not path.is_file():
            continue

        with open(path, 'r') as workflow_file:
            if 'uses: ChrisCarini/intellij-platform-plugin-verifier-action' in workflow_file.read():
                results.append(path)
    return results


def update_github_workflow(plugin_path: Path, current_platform_version: Version, new_version: Version) -> None:
    print(f'Updating GitHub workflow files...')

    print(f'Searching for GitHub compatibility workflow files...')
    github_workflow_files = _find_github_compatibility_workflow_files(plugin_path=plugin_path)
    print(f'Found {len(github_workflow_files)} workflow file(s)...')

    for github_workflow_file in github_workflow_files:
        print(f'Updating  [{github_workflow_file}] file...')

        with fileinput.FileInput(github_workflow_file, inplace=True, backup='.bak') as file:
            for line in file:
                # replace IJ Community line
                line = line.replace(
                    f'ideaIC:{current_platform_version}',
                    f'ideaIC:{new_version}',
                )

                # replace IJ Ultimate line
                line = line.replace(
                    f'ideaIU:{current_platform_version}',
                    f'ideaIU:{new_version}',
                )

                print(line, end='')  # the line already has a `\n` char, so omit adding a new one.

        # Delete the backup file
        backup_file = Path(str(github_workflow_file) + '.bak')
        if backup_file.is_file() and backup_file.exists():
            os.remove(backup_file)

        print(f'Completed [{github_workflow_file}] file.')

    print(f'Completed updating GitHub workflow files.')


def main() -> None:
    latest_version = get_latest_intellij_release()

    p = Path(PLUGIN_DIR).expanduser()
    for path in p.glob('*'):
        if not path.is_dir():
            continue
        if 'sample-intellij-plugin' not in str(path.resolve()):
            continue
        print(f'Working on [{path}]...')

        current_platform_version = update_gradle_properties(plugin_path=path, new_version=latest_version)

        update_changelog(plugin_path=path, new_version=latest_version)

        update_github_workflow(
            plugin_path=path,
            current_platform_version=current_platform_version,
            new_version=latest_version,
        )

        # TODO(ChrisCarini) - Where to pickup?
        #   1) Stash changes
        #   2) Pull latest changes
        #   3) Commit upgrade changes
        #   4) Push branch
        #   5) Open PR
        #  (NOTE: All of the above steps can be found (in shell script) in
        #  the `iterate_over_all_ij_plugin_repos.sh` of this repo.


if __name__ == '__main__':
    main()
