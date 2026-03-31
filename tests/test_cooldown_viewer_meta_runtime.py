from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_cooldown_viewer_meta_runtime_slice_exists_and_exports_helper():
    source = (ROOT / "Core/CooldownViewerMeta.lua").read_text(encoding="utf-8")

    assert "C_CooldownViewer" in source
    assert "GetCooldownViewerCooldownInfo" in source
    assert "ResolveSpellMetadata" in source
    assert "_G.SunderingToolsCooldownViewerMeta = Meta" in source
