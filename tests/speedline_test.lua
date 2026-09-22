local script_path = arg[1] or "スピード線.obj2"

local function run_speedline(use_aviutl_noise, noise_available, copy_failure)
    local calls = {
        buffers = { object = { w = 1920, h = 1080, alpha = 255, marker = "original" } },
        clears = {}, copies = {}, effects = {}, loads = {}, pixeloptions = {},
        pixelshader_count = 0, probe_steps = {},
    }
    local obj = { w = 1920, h = 1080, frame = 0, id = 42 }

    local function clone(buffer)
        return buffer and {
            w = buffer.w, h = buffer.h, alpha = buffer.alpha, marker = buffer.marker,
        }
    end

    function obj.load(kind, value)
        calls.loads[#calls.loads + 1] = { kind, value }
    end

    function obj.effect(...)
        local args = { ... }
        calls.effects[#calls.effects + 1] = args
        if args[1] ~= "無印ノイズ" or not noise_available then return end

        local strength, mode
        for index = 2, #args, 2 do
            if args[index] == "強さ" then strength = args[index + 1] end
            if args[index] == "合成モード" then mode = args[index + 1] end
        end
        if strength == 200 and mode == "アルファ値と乗算" then
            calls.probe_steps[#calls.probe_steps + 1] = "effect"
            calls.buffers.object.alpha = 0
        end
    end

    function obj.copybuffer(dst, src)
        calls.copies[#calls.copies + 1] = { dst, src }
        if src == "object" and dst ~= "object" then
            calls.probe_steps[#calls.probe_steps + 1] = "save"
        elseif dst == "object" then
            calls.probe_steps[#calls.probe_steps + 1] = "restore"
        end
        if copy_failure == "save" and src == "object" and dst ~= "object" then return false end
        if copy_failure == "restore" and dst == "object" then return false end
        local source = calls.buffers[src]
        if not source then return false end
        calls.buffers[dst] = clone(source)
        if dst == "object" then obj.w, obj.h = source.w, source.h end
        return true
    end

    function obj.clearbuffer(target, w, h, color)
        calls.clears[#calls.clears + 1] = { target, w, h, color }
        calls.probe_steps[#calls.probe_steps + 1] = "clear"
        calls.buffers[target] = {
            w = w, h = h, alpha = color == nil and 0 or 255, marker = "probe",
        }
        if target == "object" then obj.w, obj.h = w, h end
    end

    function obj.pixeloption(...)
        calls.pixeloptions[#calls.pixeloptions + 1] = { ... }
        calls.probe_steps[#calls.probe_steps + 1] = "pixeloption"
    end

    function obj.getpixel()
        calls.probe_steps[#calls.probe_steps + 1] = "getpixel"
        return 255, 255, 255, calls.buffers.object.alpha
    end

    function obj.pixelshader() calls.pixelshader_count = calls.pixelshader_count + 1 end
    function obj.draw() end

    local env = setmetatable({
        obj = obj, width_track = 300, threshold = 20, thickness = 80,
        thinness = 0, spd = 20, blur = 150, periodX = 0.1, periodY = 6,
        seed = 0, color = 0xffffff, is_vertical = false, invert_alpha = true,
        width_per = false, effect_before = false,
        use_aviutl_noise = use_aviutl_noise,
    }, { __index = _G })

    local chunk, load_error
    if _VERSION == "Lua 5.1" then
        chunk, load_error = loadfile(script_path)
        if chunk then setfenv(chunk, env) end
    else
        chunk, load_error = loadfile(script_path, "t", env)
    end
    assert(chunk, load_error)
    chunk()
    return calls
end

local function find_effect(calls, name)
    for _, args in ipairs(calls.effects) do
        if args[1] == name then return args end
    end
end

local function find_effects(calls, name)
    local found = {}
    for _, args in ipairs(calls.effects) do
        if args[1] == name then found[#found + 1] = args end
    end
    return found
end

local default_calls = run_speedline(false, false)
assert(find_effect(default_calls, "ノイズ"), "無効時は標準ノイズを適用する必要があります")
assert(not find_effect(default_calls, "無印ノイズ"), "無効時に無印ノイズを適用してはいけません")

local calls = run_speedline(true, true)
local noises = find_effects(calls, "無印ノイズ")
assert(#noises == 2, "有効時は確認用と通常適用で無印ノイズを2回呼ぶ必要があります")
assert(not find_effect(calls, "ノイズ"), "有効時に標準ノイズを適用してはいけません")

local probe = noises[1]
assert(probe[2] == "強さ" and probe[3] == 200,
    "確認用ノイズは結果が必ず透明になる強さ200である必要があります")
assert(probe[4] == "合成モード" and probe[5] == "アルファ値と乗算",
    "確認用ノイズはアルファ値と乗算する必要があります")
assert(#calls.clears == 1 and calls.clears[1][1] == "object"
    and calls.clears[1][2] == 1 and calls.clears[1][3] == 1
    and calls.clears[1][4] == 0xffffff,
    "確認時はオブジェクトを不透明な白1x1へ置き換える必要があります")
assert(calls.pixeloptions[1][1] == "get" and calls.pixeloptions[1][2] == "object",
    "確認結果の読み出し前にピクセルキャッシュを更新する必要があります")
assert(table.concat(calls.probe_steps, ",") ==
    "save,clear,effect,pixeloption,getpixel,restore",
    "確認処理は退避、固定画像、ノイズ、キャッシュ更新、読取、復元の順である必要があります")
assert(calls.buffers.object.w == 1920 and calls.buffers.object.h == 1080,
    "確認後は元のオブジェクトを復元する必要があります")
assert(calls.buffers.object.alpha == 255 and calls.buffers.object.marker == "original",
    "確認後は元のオブジェクトの画像内容を復元する必要があります")

local noise = noises[2]
local expected = {
    "無印ノイズ", "強さ", 100, "速度X", 20, "速度Y", 0,
    "周期X", 0.1, "周期Y", 6, "しきい値", 20, "シード", 0,
    "合成モード", "アルファ値と乗算", "ノイズの種類", "Type3",
}
for index, value in ipairs(expected) do
    assert(noise[index] == value,
        ("無印ノイズの引数%dが不正です: expected=%s actual=%s")
            :format(index, tostring(value), tostring(noise[index])))
end

local failed_calls = run_speedline(true, false)
local last_load = failed_calls.loads[#failed_calls.loads]
assert(last_load and last_load[1] == "text",
    "無印ノイズの呼び出し失敗時はオブジェクトをテキストに変更する必要があります")
assert(last_load[2] == "無印ノイズ.anm2の呼び出しに失敗しました",
    "無印ノイズの呼び出し失敗時に原因が分かる文字列を表示する必要があります")
assert(failed_calls.pixelshader_count == 0,
    "エラー文字列に後続のピクセルシェーダーを適用してはいけません")
assert(#find_effects(failed_calls, "無印ノイズ") == 1,
    "確認に失敗した場合は通常の無印ノイズを適用してはいけません")
assert(failed_calls.buffers.object.w == 1920 and failed_calls.buffers.object.h == 1080,
    "確認に失敗した場合もエラー表示前に元のオブジェクトを復元する必要があります")

for _, failure in ipairs({ "save", "restore" }) do
    local copy_failed_calls = run_speedline(true, true, failure)
    local copy_failed_load = copy_failed_calls.loads[#copy_failed_calls.loads]
    assert(copy_failed_load and copy_failed_load[1] == "text",
        "オブジェクトの退避または復元失敗時はテキストエラーにする必要があります")
    assert(#find_effects(copy_failed_calls, "無印ノイズ") <= 1,
        "オブジェクトの退避または復元失敗時は通常の無印ノイズを適用してはいけません")
end

print("speedline tests passed")
