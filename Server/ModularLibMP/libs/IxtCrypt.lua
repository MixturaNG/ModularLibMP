--- IxtCrypt.lua
--- Created by hlebushek.
--- DateTime: 14.01.2025 3:05
local M = {}

local function string_to_number_array(s)
    local ascii_values = {}
    for i = 1, #s do
        local char = s:sub(i, i)
        local ascii_value = string.byte(char)
        table.insert(ascii_values, ascii_value)
    end
    return ascii_values
end

local function process_numbers(numbers)
    local length = #numbers
    local sum = 0
    local product = 1
    local xor_result = 0
    local shift_result = 0

    for i = 1, length do
        local value = numbers[i]
        if i <= 5 then
            -- Увеличиваем влияние первых трех символов
            sum = sum + value * 1000
            product = product * (value + i * 1000)
            xor_result = xor_result ~ (value * 1000)
            shift_result = shift_result | (value << (i % 32))
        else
            sum = sum + value
            product = product * (value + i)
            xor_result = xor_result ~ value
            shift_result = shift_result | (value << (i % 32))
        end
    end

    -- Комбинируем результаты
    local result = (sum * product) ~ xor_result ~ shift_result
    return math.floor(result)
end

local function number_to_byte_string(number)
    local byte_string = ""
    while number > 0 do
        local byte = number % 256
        byte_string = string.char(byte) .. byte_string
        number = math.floor(number / 256)
    end
    return byte_string
end

local function xor_encrypt_decrypt(data, key)
    if #key == 0 then
        error("Key length is zero")
    end

    local encrypted = {}
    local key_length = #key
    for i = 1, #data do
        local byte = string.byte(data, i)
        local key_byte = string.byte(key, (i - 1) % key_length + 1)
        local xor_byte = byte ~ key_byte
        table.insert(encrypted, string.char(xor_byte))
    end
    return table.concat(encrypted)
end


local function string_to_key(line)
    local number_array = string_to_number_array(line)
    local final_result = process_numbers(number_array)
    return number_to_byte_string(final_result)
end

M.getKey = string_to_key
M.encrypt = xor_encrypt_decrypt
M.decrypt = xor_encrypt_decrypt
return M

--[[
local data = "Secret message"
local input_string = "1Igor2026445623"

-- Преобразование строки в массив чисел

local encrypted_data = xor_encrypt_decrypt(data, key)

-- Расшифрование данных
local decrypted_data = xor_encrypt_decrypt(encrypted_data, key)
--]]