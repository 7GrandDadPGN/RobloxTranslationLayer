repeat task.wait() until game:IsLoaded()

if game.GameId == 2619619496 then
    local KnitInit, Knit
	repeat
		KnitInit, Knit = pcall(function() return debug.getupvalue(require(game:GetService('Players').LocalPlayer.PlayerScripts.TS.knit).setup, 6) end)
		if KnitInit then break end
		task.wait()
	until KnitInit

	if not debug.getupvalue(Knit.Start, 1) then
		repeat task.wait() until debug.getupvalue(Knit.Start, 1)
	end

    setfpscap(40)
    --game:GetService('RunService'):Set3dRenderingEnabled(true)
    loadstring(readfile('client/init.lua'), 'client/init.lua')()
end