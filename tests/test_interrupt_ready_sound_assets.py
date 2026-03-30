from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_interrupt_ready_sound_assets_exist():
    sounds = ROOT / "sounds"
    assert (sounds / "ready.mp3").exists()
    assert (sounds / "ready2.mp3").exists()
