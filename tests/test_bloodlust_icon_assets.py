from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_bloodlust_pedro_icon_asset_exists():
    assert (ROOT / "assets" / "art" / "pedro.tga").exists()


def test_minimap_logo_asset_exists():
    assert (ROOT / "assets" / "icons" / "logo-minimap.tga").exists()
