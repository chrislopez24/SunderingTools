from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def git_tracked_files() -> set[str]:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files"],
        check=True,
        capture_output=True,
        text=True,
    )
    return set(result.stdout.splitlines())


def test_packaging_files_exist():
    assert (ROOT / ".pkgmeta").exists()
    assert (ROOT / ".github" / "workflows" / "release.yml").exists()


def test_pkgmeta_excludes_development_only_content_from_release_zip():
    pkgmeta = (ROOT / ".pkgmeta").read_text(encoding="utf-8")
    for ignored in (
        ".github",
        "docs",
        "tests",
        "README.md",
        ".gitignore",
    ):
        assert f"  - {ignored}" in pkgmeta


def test_toc_no_missing_embeds_and_new_entrypoints():
    toc = (ROOT / "SunderingTools.toc").read_text(encoding="utf-8")
    assert "Libs\\LibStub\\LibStub.lua" not in toc
    assert "Libs\\CallbackHandler-1.0\\CallbackHandler-1.0.lua" not in toc
    assert "## Version: 0.2.4" in toc
    assert "Modules\\InterruptTrackerModel.lua" in toc
    assert "Modules\\InterruptTracker.lua" in toc
    assert "Modules\\PartyDefensiveTrackerModel.lua" in toc
    assert "Modules\\PartyDefensiveTracker.lua" in toc
    assert "Modules\\DefensiveRaidTrackerModel.lua" in toc
    assert "Modules\\DefensiveRaidTracker.lua" in toc
    assert "Modules\\BloodlustSoundModel.lua" in toc
    assert "Modules\\BloodlustSound.lua" in toc


def test_release_workflow_uses_packager():
    workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
    assert "BigWigsMods/packager" in workflow
    assert "permissions:" in workflow
    assert "contents: write" in workflow
    assert "GITHUB_OAUTH: ${{ secrets.GITHUB_TOKEN }}" in workflow


def test_required_runtime_files_are_tracked_in_git():
    tracked = git_tracked_files()
    required = {
        "SunderingTools.lua",
        "Settings.lua",
        "SunderingTools.toc",
        "Modules/InterruptTrackerModel.lua",
        "Modules/InterruptTracker.lua",
        "Modules/PartyDefensiveTrackerModel.lua",
        "Modules/PartyDefensiveTracker.lua",
        "Modules/DefensiveRaidTrackerModel.lua",
        "Modules/DefensiveRaidTracker.lua",
        "Modules/BloodlustSoundModel.lua",
        "Modules/BloodlustSound.lua",
        "assets/icons/logo-minimap.tga",
        "assets/art/pedro.tga",
        "sounds/pedrolust.mp3",
    }
    assert required <= tracked
