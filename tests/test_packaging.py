from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


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
