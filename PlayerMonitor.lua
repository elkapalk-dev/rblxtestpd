local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerMonitor = {}
PlayerMonitor.__index = PlayerMonitor

function PlayerMonitor.new(config)
    local self = setmetatable({}, PlayerMonitor)
    
    self.Config = {
        updateInterval = config and config.updateInterval or 0.1,
        fillColor = config and config.fillColor or Color3.fromRGB(255, 48, 51),
        maxDistance = config and config.maxDistance or 50,
        autoHighlight = config and config.autoHighlight or false  -- NEW: Control auto-highlighting
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
    
    -- Initialize existing players
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= self._localPlayer then
            self:_setupPlayer(player)
        end
    end
    
    -- Setup connection for new players (FIXED: This was missing before)
    self._connections.playerAdded = Players.PlayerAdded:Connect(function(player)
        if player ~= self._localPlayer then
            self:_setupPlayer(player)
        end
    end)
    
    self._connections.playerRemoving = Players.PlayerRemoving:Connect(function(player)
        self:_removePlayer(player)
    end)
    
    self._connections.heartbeat = RunService.Heartbeat:Connect(function()
        if self._needsUpdate and self._isRunning then
            self:_batchUpdatePlayers()
        end
    end)
    
    local updateTask = task.spawn(function()
        while self._isRunning do
            task.wait(self.Config.updateInterval)
            self._needsUpdate = true
        end
    end)
    self._connections.updateTask = {Disconnect = function() task.cancel(updateTask) end}
end

function PlayerMonitor:Stop()
    self._isRunning = false
    for _, connection in pairs(self._connections) do 
        if type(connection) == "table" and connection.Disconnect then
            connection:Disconnect()
        elseif typeof(connection) == "RBXScriptConnection" then
            connection:Disconnect()
        end
    end
    table.clear(self._connections)
    for player in pairs(self._players) do 
        self:_removePlayer(player) 
    end
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
    -- Don't create highlight immediately unless autoHighlight is true
    if self.Config.autoHighlight then
        self:_updatePlayer(player)
    else
        -- Just track the player without creating highlight
        if not self._players[player] then
            self._players[player] = {
                player = player,
                character = player.Character,
                humanoid = player.Character and player.Character:FindFirstChild("Humanoid"),
                highlight = nil,
                connections = {}
            }
        end
    end
    
    local function onCharacterAdded(character)
        self:_removePlayer(player)
        if self.Config.autoHighlight then
            self:_updatePlayer(player)
        else
            -- Just update tracking without highlight
            self._players[player] = {
                player = player,
                character = character,
                humanoid = character:WaitForChild("Humanoid"),
                highlight = nil,
                connections = {}
            }
        end
        
        local humanoid = character:WaitForChild("Humanoid")
        local healthConnection = humanoid.HealthChanged:Connect(function() 
            self._needsUpdate = true 
        end)
        
        if self._players[player] then 
            table.insert(self._players[player].connections, healthConnection) 
        end
    end
    
    local teamConnection = player:GetPropertyChangedSignal("Team"):Connect(function() 
        self._needsUpdate = true 
    end)
    
    if not self._players[player] then
        self._players[player] = {
            player = player,
            character = player.Character,
            humanoid = player.Character and player.Character:FindFirstChild("Humanoid"),
            highlight = nil,
            connections = {}
        }
    end
    
    table.insert(self._players[player].connections, teamConnection)
    
    if player.Character then
        onCharacterAdded(player.Character)
    end
    
    table.insert(self._players[player].connections, player.CharacterAdded:Connect(onCharacterAdded))
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
        -- Don't parent immediately unless autoHighlight is true
        if self.Config.autoHighlight then
            self._players[player].highlight.Parent = character
        end
    else
        -- Ensure highlight exists if autoHighlight is true
        if self.Config.autoHighlight and not self._players[player].highlight then
            self._players[player].highlight = Instance.new("Highlight")
            self._players[player].highlight.FillColor = (player.Team and player.Team.TeamColor.Color) or self.Config.fillColor
            self._players[player].highlight.OutlineColor = Color3.new(0, 0, 0)
            self._players[player].highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            self._players[player].highlight.Parent = character
        end
    end
    
    local data = self._players[player]
    if data.highlight then
        if data.highlight.Parent ~= character and self.Config.autoHighlight then
            data.highlight.Parent = character
        end
        if player.Team then 
            data.highlight.FillColor = player.Team.TeamColor.Color 
        end
    end
end

function PlayerMonitor:_removePlayer(player)
    local data = self._players[player]
    if not data then return end
    if data.highlight then 
        data.highlight:Destroy() 
    end
    for _, connection in pairs(data.connections) do 
        pcall(function() connection:Disconnect() end)
    end
    self._players[player] = nil
end

function PlayerMonitor:_batchUpdatePlayers()
    for player, data in pairs(self._players) do
        if player and player.Parent and data.character and data.character == player.Character then
            local humanoid = data.character:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then
                if data.highlight and data.highlight.Parent ~= data.character and self.Config.autoHighlight then
                    data.highlight.Parent = data.character
                end
            else
                if data.highlight then
                    data.highlight.Parent = nil
                end
            end
        else
            self:_removePlayer(player)
        end
    end
    self._needsUpdate = false
end

return PlayerMonitor
