local script_path = arg[1] or "スピード線.obj2"

local function run_speedline(use_aviutl_noise, fail_aviutl_noise)
    local calls = {
        effects = {},
        loads = {},
        pixelshader_count = 0,
    }

    local obj = {
        w = 1920,
        h = 1080,
        frame = 0,
    }

    function obj.load(kind, value)
        calls.loads[#calls.loads + 1] = { kind, value }
    end

    function obj.effect(...)
        local args = { ... }
        calls.effects[#calls.effects + 1] = args
        if args[1] == "無印ノイズ" and fail_aviutl_noise then
            error("effect not found")
        end
        return true
    end

    function obj.pixelshader()
        calls.pixelshader_count = calls.pixelshader_count + 1
    end

    function obj.draw() end

    local env = setmetatable({
        obj = obj,
        width_track = 300,
        threshold = 20,
        thickness = 80,
        thinness = 0,
        spd = 20,
        blur = 150,
        periodX = 0.1,
        periodY = 6,
        seed = 0,
        color = 0xffffff,
        is_vertical = false,
        invert_alpha = true,
        width_per = false,
        effect_before = false,
        use_aviutl_noise = use_aviutl_noise,
    }, { __index = _G })

    local chunk, load_error
    if _VERSION == "Lua 5.1" then
        chunk, load_error = loadfile(script_path)
        if chunk then
            setfenv(chunk, env)
        end
    else
        chunk, load_error = loadfile(script_path, "t", env)
    end
    assert(chunk, load_error)
    chunk()
    return calls
end

local function find_effect(calls, name)
    for _, args in ipairs(calls.effects) do
        if args[1] == name then
            return args
        end
    end
end

local default_calls = run_speedline(false, false)
assert(find_effect(default_calls, "ノイズ"),
    "無効時は標準ノイズを適用する必要があります")
assert(not find_effect(default_calls, "無印ノイズ"),
    "無効時に無印ノイズを適用してはいけません")

local calls = run_speedline(true, false)
local noise = assert(find_effect(calls, "無印ノイズ"),
    "有効時は無印ノイズを適用する必要があります")
assert(not find_effect(calls, "ノイズ"),
    "有効時に標準ノイズを適用してはいけません")

local expected = {
    "無印ノイズ",
    "強さ", 100,
    "速度X", 20,
    "速度Y", 0,
    "周期X", 0.1,
    "周期Y", 6,
    "しきい値", 20,
    "シード", 0,
    "合成モード", "アルファ値と乗算",
    "ノイズの種類", "Type3",
}
for index, value in ipairs(expected) do
    assert(noise[index] == value,
        ("無印ノイズの引数%dが不正です: expected=%s actual=%s")
            :format(index, tostring(value), tostring(noise[index])))
end

local failed_calls = run_speedline(true, true)
local last_load = failed_calls.loads[#failed_calls.loads]
assert(last_load and last_load[1] == "text",
    "無印ノイズの呼び出し失敗時はオブジェクトをテキストに変更する必要があります")
assert(last_load[2] == "無印ノイズ.anm2の呼び出しに失敗しました",
    "無印ノイズの呼び出し失敗時に原因が分かる文字列を表示する必要があります")
assert(failed_calls.pixelshader_count == 0,
    "エラー文字列に後続のピクセルシェーダーを適用してはいけません")
assert(not find_effect(failed_calls, "反転"),
    "エラー文字列に後続の反転を適用してはいけません")
assert(not find_effect(failed_calls, "単色化"),
    "エラー文字列に後続の単色化を適用してはいけません")

print("speedline tests passed")
