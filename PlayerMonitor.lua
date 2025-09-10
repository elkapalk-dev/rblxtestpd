local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerMonitor = {}
PlayerMonitor.__index = PlayerMonitor

function PlayerMonitor.new(config)
    local self = setmetatable({}, PlayerMonitor)
    
    self.Config = {
        updateInterval = config and config.updateInterval or 0.1,
        fillColor = config and config.fillColor or Color3.fromRGB(255, 48, 51),
        maxDistance = config and config.maxDistance or 50
    }
    
    self._players = {}
    self._needsUpdate = false
    self._isRunning = false
    self._connections = {}
    self._localPlayer = Players.LocalPlayer
    
    return self
end

function PlayerMonitor:Start()
    if self._isRunning then return end
    self._isRunning = true
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= self._localPlayer then
            self:_setupPlayer(player)
        end
    end
    
    table.insert(self._connections, Players.PlayerAdded:Connect(function(player)
        if player ~= self._localPlayer then
            self:_setupPlayer(player)
        end
    end))
    
    table.insert(self._connections, Players.PlayerRemoving:Connect(function(player)
        self:_removePlayer(player)
    end))
    
    table.insert(self._connections, RunService.Heartbeat:Connect(function()
        if self._needsUpdate and self._isRunning then
            self:_batchUpdatePlayers()
        end
    end))
    
    local updateTask = task.spawn(function()
        while self._isRunning do
            task.wait(self.Config.updateInterval)
            self._needsUpdate = true
        end
    end)
    table.insert(self._connections, {Disconnect = function() task.cancel(updateTask) end})
end

function PlayerMonitor:Stop()
    self._isRunning = false
    for _, connection in pairs(self._connections) do connection:Disconnect() end
    table.clear(self._connections)
    for player in pairs(self._players) do self:_removePlayer(player) end
    table.clear(self._players)
end

function PlayerMonitor:GetPlayer(player)
    return self._players[player]
end

function PlayerMonitor:GetAllPlayers()
    return self._players
end

function PlayerMonitor:HighlightPlayer(player, color)
    local data = self._players[player]
    if data and data.highlight then
        data.highlight.FillColor = color or self.Config.fillColor
        data.highlight.Parent = data.character
    end
end

function PlayerMonitor:HighlightAll(color)
    for _, data in pairs(self._players) do
        if data.highlight then
            data.highlight.FillColor = color or self.Config.fillColor
            data.highlight.Parent = data.character
        end
    end
end

function PlayerMonitor:UnhighlightPlayer(player)
    local data = self._players[player]
    if data and data.highlight then
        data.highlight.Parent = nil
    end
end

function PlayerMonitor:UnhighlightAll()
    for _, data in pairs(self._players) do
        if data.highlight then
            data.highlight.Parent = nil
        end
    end
end

-- Private methods
function PlayerMonitor:_setupPlayer(player)
    self:_updatePlayer(player)
    local function onCharacterAdded(character)
        self:_removePlayer(player)
        self:_updatePlayer(player)
        local humanoid = character:WaitForChild("Humanoid")
        local healthConnection = humanoid.HealthChanged:Connect(function() self._needsUpdate = true end)
        if self._players[player] then table.insert(self._players[player].connections, healthConnection) end
    end
    local teamConnection = player:GetPropertyChangedSignal("Team"):Connect(function() self._needsUpdate = true end)
    if self._players[player] then
        table.insert(self._players[player].connections, teamConnection)
        if player.Character then onCharacterAdded(player.Character) end
        table.insert(self._players[player].connections, player.CharacterAdded:Connect(onCharacterAdded))
    end
end

function PlayerMonitor:_updatePlayer(player)
    if player == self._localPlayer then return end
    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end
    
    if not self._players[player] then
        self._players[player] = {
            player = player,
            character = character,
            humanoid = humanoid,
            highlight = Instance.new("Highlight"),
            connections = {}
        }
        self._players[player].highlight.FillColor = (player.Team and player.Team.TeamColor.Color) or self.Config.fillColor
        self._players[player].highlight.OutlineColor = Color3.new(0, 0, 0)
        self._players[player].highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        self._players[player].highlight.Parent = character
    end
    
    local data = self._players[player]
    if data.highlight.Parent ~= character then data.highlight.Parent = character end
    if player.Team then data.highlight.FillColor = player.Team.TeamColor.Color end
end

function PlayerMonitor:_removePlayer(player)
    local data = self._players[player]
    if not data then return end
    if data.highlight then data.highlight:Destroy() end
    for _, connection in pairs(data.connections) do connection:Disconnect() end
    self._players[player] = nil
end

function PlayerMonitor:_batchUpdatePlayers()
    for player, data in pairs(self._players) do
        if player and player.Parent and data.character and data.character == player.Character then
            local humanoid = data.character:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then
                if data.highlight.Parent ~= data.character then data.highlight.Parent = data.character end
            else
                data.highlight.Parent = nil
            end
        else
            self:_removePlayer(player)
        end
    end
    self._needsUpdate = false
end

return PlayerMonitor
