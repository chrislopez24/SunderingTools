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


def test_toc_no_missing_embeds_and_new_entrypoints():
    toc = (ROOT / "SunderingTools.toc").read_text(encoding="utf-8")
    assert "Libs\\LibStub\\LibStub.lua" not in toc
    assert "Libs\\CallbackHandler-1.0\\CallbackHandler-1.0.lua" not in toc
    assert "@project-version@" in toc
    assert "Modules\\InterruptTracker.lua" in toc
    assert "Modules\\BloodlustSound.lua" in toc


def test_release_workflow_uses_packager():
    workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
    assert "BigWigsMods/packager" in workflow


def test_required_runtime_files_are_tracked_in_git():
    tracked = git_tracked_files()
    required = {
        "SunderingTools.lua",
        "Settings.lua",
        "SunderingTools.toc",
        "Modules/InterruptTracker.lua",
        "Modules/BloodlustSound.lua",
        "sounds/pedrolust.mp3",
    }
    assert required <= tracked
