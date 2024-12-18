local util = {}
local colors
local blue = Color3.fromRGB(73, 180, 242)

function util:start(main)
	colors = main.types.colors
	return self
end

function util:translateColor(compare)
	local mag, returned = 4, ''

	for color, code in colors do
		local diff = math.abs(compare.R - color.R) + math.abs(compare.G - color.G) + math.abs(compare.B - color.B)
		if diff < mag then
			mag, returned = diff, '/c/'..code
		end
	end

	if compare == blue then
		mag, returned = 0, '/c/9'
	end

	return returned
end

return util