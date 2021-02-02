local Name, Addon = ...

-- Use route estimation
Addon.BFS = false
-- # of hops before limiting branching
Addon.BFS_BRANCH = 2
-- \# of hops to track back from previous result
Addon.BFS_TRACK_BACK = 15
-- Distance weight to same pull
Addon.BFS_WEIGHT_PULL = 0.1
-- Distance weight to a following pull
Addon.BFS_WEIGHT_FORWARD = 0.3
-- Distance weight to a previous pull
Addon.BFS_WEIGHT_ROUTE = 0.5
-- Distance weight to same group
Addon.BFS_WEIGHT_GROUP = 0.7
-- Weight by path length
Addon.BFS_WEIGHT_LENGTH = 0.95
-- Max rounds per frame
Addon.BFS_MAX_FRAME = 15
-- Scale MAX_FRAME with elapsed time
Addon.BFS_MAX_FRAME_SCALE = 0.5
-- Total time to spend on route estimation (in s)
Addon.BFS_MAX_TOTAL = 5
-- Max queue index for new candidates paths
Addon.BFS_QUEUE_INSERT = 300
-- Max # of path candidates in the queue
Addon.BFS_QUEUE_MAX = 1000

local queue, weights, pulls = {}, {}, {}
local hits, kills = {}, {}
local co, rerun, zoom, retry

local bfs = true

local function Node(enemyId, cloneId)
    return "e" .. enemyId .. "c" .. cloneId
end

local function Distance(ax, ay, bx, by, from, to)
    from, to = from or 1, to or 1
    if from == to then
        return math.sqrt(math.pow(ax - bx, 2) + math.pow(ay - by, 2))
    else
        local POIs = MDT.mapPOIs[Addon.GetCurrentDungeonId()]
        local p = Addon.FindWhere(POIs[from], "type", "mapLink", "target", to)
        local t = p and Addon.FindWhere(POIs[to], "type", "mapLink", "connectionIndex", p.connectionIndex)
        return t and Distance(ax, ay, p.x, p.y) + Distance(t.x, t.y, bx, by) or math.huge
    end
end

local function Path(path, node)
    return path .. "-" .. node .. "-"
end

local function Sub(path, n)
    for _=1,n or 1 do
       path = path:gsub("%-[^-]+-$", "")
    end
    return path
end

local function Contains(path, node)
    return path:find("%-" .. node .. "%-") ~= nil
end

local function Last(path, enemies)
    local enemyId, cloneId = path:match("-e(%d+)c(%d+)-$")
    if enemyId and cloneId then
        if enemies then
            return enemies[tonumber(enemyId)].clones[tonumber(cloneId)]
        else
            return Node(enemyId, cloneId)
        end
    end
end

local function Length(path)
    return path:gsub("e%d+c%d+", ""):len() / 2
end

local function Weight(path, weight, length, prev, curr, prevNode, currNode)
    if weight then
        local prevPull, currPull = prevNode and pulls[prevNode], currNode and pulls[currNode]
        local dist =
            -- Base distance
            Distance(prev.x, prev.y, curr.x, curr.y, prev.sublevel, curr.sublevel)
            -- Weighted by group
            * (prev.g and curr.g and prev.g == curr.g and Addon.BFS_WEIGHT_GROUP or 1)
            -- Weighted by direction
            * (currPull and (prevPull and (prevPull == currPull and Addon.BFS_WEIGHT_PULL or prevPull < currPull and Addon.BFS_WEIGHT_FORWARD) or Addon.BFS_WEIGHT_ROUTE) or 1)

            weights[path] = (weight * length * Addon.BFS_WEIGHT_LENGTH + dist) / (length + 1)
    end
    return weights[path]
end

local function Insert(path, length, weight)
    length, weight = length or Length(path), weight or Weight(path)
    local lft, rgt = 1, #queue+1

    while rgt > lft do
        local m = math.floor(lft + (rgt - lft) / 2)
        local p = queue[m]
        local w, l = Weight(p), Length(p)

        if l ~= length and (length <= Addon.BFS_BRANCH or l <= Addon.BFS_BRANCH) then
            if length < l then
                rgt = m
            else
                lft = m+1
            end
        elseif weight < w then
            rgt = m
        else
            lft = m+1
        end
    end

    if lft <= Addon.BFS_QUEUE_INSERT then
        table.insert(queue, lft, path)
        if queue[Addon.BFS_QUEUE_MAX+1] then
            table.remove(queue)
        end
    end
end

function Addon.CalculateRoute()
    local dungeon = Addon.GetCurrentDungeonId()
    local enemies = Addon.GetCurrentEnemies()
    local t, i, n, g = GetTime(), 1, 1, {}

    -- Start route
    local start = Sub(MDTGuideRoute, Addon.BFS_TRACK_BACK)
    queue[1] = start
    weights[start] = 0

    -- Start POI
    if start == "" then
        if Addon.dungeons[dungeon] and Addon.dungeons[dungeon].start then
            start = Addon.dungeons[dungeon].start
        else
            for _,poi in ipairs(MDT.mapPOIs[dungeon][1]) do
                if poi.type == "graveyard" then
                    start = poi
                    break
                end
            end
        end

        if not start or start == "" then
            Addon.debug("No starting point!")
            return
        end
    end

    while true do
        local total = GetTime() - t

        -- Limit runtime
        if total >= Addon.BFS_MAX_TOTAL then
            print("|cff00bbbb[MDTGuide]|r Route calculation took too long, switching to enemy forces mode!")
            bfs, rerun = false, false
            break
        elseif i > Addon.BFS_MAX_FRAME * (1 - total * Addon.BFS_MAX_FRAME_SCALE / Addon.BFS_MAX_TOTAL) then
            i = 1
            coroutine.yield()
        end

        local path = table.remove(queue, 1)
        if not path then
            Addon.debug("No path found!")
            break
        end

        local weight, length, last, lastNode = Weight(path), Length(path), Last(path, enemies) or start, Last(path)
        local enemyId = Addon.kills[length+1]

        -- Success
        if length == #Addon.kills then
            MDTGuideRoute = path
            break
        end

        -- Next step
        local found
        for cloneId,clone in ipairs(enemies[enemyId].clones) do
            local node = Node(enemyId, cloneId)
            if not Contains(path, node) then
                local p = Path(path, node)
                local w = Weight(p, weight, length, last, clone, lastNode, node)
                if w < math.huge then
                    found = true
                    if not clone.g then
                        Insert(p, length+1, w)
                    elseif not g[clone.g] or w < Weight(g[clone.g]) then
                        g[clone.g] = p
                    end
                end
            end
        end

        -- Insert grouped and proceed or retry with next enemy
        if found then
            for _,p in pairs(g) do Insert(p, length+1) end
            weights[path] = nil
        else
            table.remove(Addon.kills, length+1)
            table.insert(queue, 1, path)
        end

        i, n = i+1, n+1
        wipe(g)
    end

    Addon.debug("N", n)
    Addon.debug("Time", GetTime() - t)
    Addon.debug("Queue", #queue)

    wipe(queue)
    wipe(weights)

    Addon.ColorEnemies()

    if zoom then
        zoom = rerun
        Addon.ZoomToCurrentPull()
    end
    if rerun then
        Addon.UpdateRoute()
    end
end

-- ---------------------------------------
--                 State
-- ---------------------------------------

function Addon.IsBFS()
    return Addon.BFS and bfs
end

function Addon.UpdateRoute(z)
    zoom = zoom or z
    rerun = false
    if Addon.IsCurrentInstance() then
        if co and coroutine.status(co) == "running" then
            rerun = true
        else
            co = coroutine.create(Addon.CalculateRoute)
            coroutine.resume(co)
        end
    end
end

function Addon.AddKill(npcId)
    for i,enemy in ipairs(MDT.dungeonEnemies[Addon.currentDungeon]) do
        if enemy.id == npcId then
            table.insert(Addon.kills, i)
            return i
        end
    end
end

function Addon.ClearKills()
    wipe(hits)
    wipe(kills)
    MDTGuideRoute = ""
    bfs = true
end

function Addon.GetCurrentPullByRoute()
    local path = MDTGuideRoute
    while path and path:len() > 0 do
        local node = Last(path)
        local n = pulls[node]
        if n then
            return Addon.IteratePull(n, function (_, _, cloneId, enemyId, pull)
                if not Contains(path, Node(enemyId, cloneId)) then
                    return n, pull
                end
            end) or n + 1
        end
        path = path:sub(1, -node:len() - 3)
    end
end

function Addon.SetDungeon()
    wipe(pulls)
    Addon.IteratePulls(function (_, _, cloneId, enemyId, _, pullId)
        pulls[Node(enemyId, cloneId)] = pullId
    end)
    Addon.UpdateRoute()
end

function Addon.SetInstanceDungeon(dungeon)
    Addon.currentDungeon = dungeon
    Addon.ClearKills()
    Addon.UpdateRoute()
end

-- ---------------------------------------
--                Events
-- ---------------------------------------

local Frame = CreateFrame("Frame")

local OnEvent = function (_, ev, ...)
    if not MDT or MDT:GetDB().devMode then return end

    if ev == "PLAYER_ENTERING_WORLD" then
        local _, instanceType = IsInInstance()
        if instanceType == "party" then
            local map = C_Map.GetBestMapForUnit("player")
            if map then
                local dungeon = Addon.GetInstanceDungeonId(EJ_GetInstanceForMap(map))

                if dungeon ~= Addon.currentDungeon then
                    Addon.SetInstanceDungeon(dungeon)

                    if dungeon then
                        Addon.debug("REGISTER")
                        Frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                    else
                        Addon.debug("UNREGISTER")
                        Frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                    end
                end
            else
                retry = {ev, ...}
            end
        else
            if instanceType then
                Addon.SetInstanceDungeon()
            end
            Frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        end
    elseif ev == "SCENARIO_COMPLETED" or ev == "CHAT_MSG_SYSTEM" and (...):match(Addon.PATTERN_INSTANCE_RESET) then
        Addon.debug("RESET")
        Addon.SetInstanceDungeon()
        Frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    elseif ev == "SCENARIO_CRITERIA_UPDATE" and not Addon.IsBFS() then
        Addon.ZoomToCurrentPull(true)
    elseif ev == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, event, _, _, _, sourceFlags, _, destGUID, _, destFlags = CombatLogGetCurrentEventInfo()

        if event == "UNIT_DIED" then
            if Addon.hits[destGUID] then
                Addon.debug("KILL")
                Addon.hits[destGUID] = nil
                local npcId = Addon.GetNPCId(destGUID)
                if Addon.AddKill(npcId) and Addon.IsBFS() then
                    Addon.ZoomToCurrentPull(true)
                end
            end
        elseif event:match("DAMAGE") or event:match("AURA_APPLIED") then
            local sourceIsParty = bit.band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER) == 0
            local destIsEnemy = bit.band(destFlags, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER) > 0 and bit.band(destFlags, COMBATLOG_OBJECT_REACTION_FRIENDLY) == 0
            if sourceIsParty and destIsEnemy and not Addon.hits[destGUID] then
                Addon.debug("HIT")
                Addon.hits[destGUID] = true
            end
        end
    end
end

-- Resume route calculation
local OnUpdate = function ()
    if co and coroutine.status(co) == "suspended" then
        coroutine.resume(co)
    end

    if retry then
        local args = retry
        retry = nil
        OnEvent(nil, unpack(args))
    end
end

Frame:SetScript("OnEvent", OnEvent)
Frame:SetScript("OnUpdate", OnUpdate)
Frame:RegisterEvent("PLAYER_ENTERING_WORLD")
Frame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
Frame:RegisterEvent("SCENARIO_COMPLETED")
Frame:RegisterEvent("CHAT_MSG_SYSTEM")