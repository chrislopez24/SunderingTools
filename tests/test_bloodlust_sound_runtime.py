from pathlib import Path

from lupa.lua54 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]


def test_bloodlust_sound_runtime_suite():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        "package.path = package.path .. ';"
        + str(ROOT).replace("\\", "/")
        + "/?.lua;"
        + str(ROOT).replace("\\", "/")
        + "/?/init.lua'"
    )

    lua.execute((ROOT / "tests/modules/test_bloodlust_sound_runtime.lua").read_text(encoding="utf-8"))
