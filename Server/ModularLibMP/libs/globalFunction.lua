function split(inputstr, sep)
	if sep == nil then sep = "%s" end
	local t={}
	for str in string.gmatch(inputstr, "([^"..sep.."]+)") do table.insert(t, str) end
	return t
end

function is_integer(data)
    if string.match(data,"^%d+.%d?$") then
        return true
    end
    if string.match(data,"^%d+$") then
        return true
    end
    if type(data) == "number" then
        return true
    end
    local status, result = pcall(tonumber,data)
	if not status or result == nil then
		return false
	end
	return data == tostring(math.floor(result))
end
