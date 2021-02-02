local Name, Addon = ...

-- Use route estimation
Addon.BFS = false
-- # of hops to track back from previous result
Addon.BFS_TRACK_BACK = 15
-- Distance weight to same pull
Addon.BFS_WEIGHT_PULL = 0.1
-- Distance weight to a following pull
Addon.BFS_WEIGHT_FORWARD = 0.3
-- Distance weight to a previous pull
Addon.BFS_WEIGHT_ROUTE = 0.5
-- Distance weight to same group but different sublevels
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

local queue, weights = {}, {}
local pulls, groups = {}, {}
local hits, kills = {}, {}
local co, rerun, zoom, retry

local bfs = true

local debug = Addon.Debug

local function Node(enemyId, cloneId)
    return "e" .. enemyId .. "c" .. cloneId
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
    if path == "" then
        local dungeon = Addon.GetCurrentDungeonId()

        if Addon.dungeons[dungeon] and Addon.dungeons[dungeon].start then
            return nil, Addon.dungeons[dungeon].start
        else
            for _,poi in ipairs(MDT.mapPOIs[dungeon][1]) do
                if poi.type == "graveyard" then
                    return nil, poi
                end
            end
        end

        debug("No starting point!")
        return
    else
        local enemyId, cloneId = path:match("-e(%d+)c(%d+)-$")
        if enemyId and cloneId then
            return Node(enemyId, cloneId), enemies and enemies[tonumber(enemyId)].clones[tonumber(cloneId)]
        end
    end
end

local function Length(path)
    return path:gsub("e%d+c%d+", ""):len() / 2
end

local function Position(clone)
    local grp = clone.g and groups[clone.g]
    return grp and grp.sublevel and grp or clone
end

local function Distance(a, b)
    a, b = Position(a), Position(b)
    local from, to = a.sublevel or 1, b.sublevel or 1

    if from == to then
        return math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2))
    else
        local POIs = MDT.mapPOIs[Addon.GetCurrentDungeonId()]
        local p = Addon.FindWhere(POIs[from], "type", "mapLink", "target", to)
        local t = p and Addon.FindWhere(POIs[to], "type", "mapLink", "connectionIndex", p.connectionIndex)
        return t and Distance(a, p) + Distance(t, b) or math.huge
    end
end

local function Weight(path, enemies)
    if path == "" then
        return 0
    elseif not weights[path] then
        enemies = enemies or Addon.GetCurrentEnemies()
        local parent = Sub(path, 1)
        local prevWeight, prevLength = Weight(parent), Length(parent)
        local prevNode, prev = Last(parent, enemies)
        local prevPull = prevNode and pulls[prevNode]

        local currNode, curr = Last(path, enemies)
        local currPull = currNode and pulls[currNode]
        
        -- Base distance
        local dist = Distance(prev, curr)

        -- Weighted by group
        if prev.g and curr.g and prev.g == curr.g then
            dist = dist * Addon.BFS_WEIGHT_GROUP
        end

        -- Weighted by direction
        if currPull then
            if not prevPull or prevPull > currPull then
                dist = dist * Addon.BFS_WEIGHT_ROUTE
            elseif prevPull == currPull then
                dist = dist * Addon.BFS_WEIGHT_PULL
            else
                dist = dist * Addon.BFS_WEIGHT_FORWARD
            end
        end

        weights[path] = prevWeight + (dist - prevWeight) / (prevLength + 1)
    end
    return weights[path]
end

local function Insert(path)
    local weight = Weight(path)
    local lft, rgt = 1, #queue+1

    while rgt > lft do
        local m = math.floor(lft + (rgt - lft) / 2)

        if weight < Weight(queue[m]) then
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

local function DeepSearch(path, enemies)
    local enemyId = kills[Length(path)+1]
    local res

    if enemies and enemyId and enemies[enemyId] then
        for cloneId,clone in pairs(enemies[enemyId].clones) do
            local node = Node(enemyId, cloneId)

            if not Contains(path, node) then
                local p = DeepSearch(Path(path, node), enemies)

                if not res or Weight(p) < Weight(res) then
                    res = p

                    if enemies.sublevel then
                        break
                    end
                end
            end
        end
    end
    
    return res or path
end

local function WideSearch(path, enemies, grps)
    local enemyId = kills[Length(path)+1]
    local found

    if enemies and enemyId and enemies[enemyId] then
        for cloneId,clone in pairs(enemies[enemyId].clones) do
            local node = Node(enemyId, cloneId)

            if not Contains(path, node) then
                local p = DeepSearch(Path(path, node), groups[clone.g])
                local w = Weight(p)

                if w < math.huge then
                    found = true
                    if not clone.g then
                        Insert(p)
                    elseif not grps[clone.g] or w < Weight(grps[clone.g]) then
                        grps[clone.g] = p
                    end
                end
            end
        end
    end

    if grps then
        for _,p in pairs(grps) do Insert(p) end
    end
    
    return found
end

function Addon.CalculateRoute()
    local dungeon = Addon.GetCurrentDungeonId()
    local enemies = Addon.GetCurrentEnemies()
    local t, i, n, grps = GetTime(), 1, 1, {}

    -- Start route
    local start = Sub(MDTGuideRoute, Addon.BFS_TRACK_BACK)
    queue[1] = start
    weights[start] = 0

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

        -- Failure or success
        if not path then
            print("|cff00bbbb[MDTGuide]|r Route calculation didn't work, switching to enemy forces mode!")
            bfs, rerun = false, false
            break
        elseif Length(path) == #kills then
            MDTGuideRoute = path
            break
        end

        -- Find next paths
        local found = WideSearch(path, enemies, grps)

        -- Skip current enemy if no path was found
        if not found then
            table.remove(kills, length+1)
            table.insert(queue, 1, path)
        end

        i, n = i+1, n+1
        wipe(grps)
    end

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
            table.insert(kills, i)
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
    wipe(groups)

    Addon.IteratePulls(function (clone, _, cloneId, enemyId, _, pullId)
        pulls[Node(enemyId, cloneId)] = pullId

        if clone.g then
            groups[clone.g] = groups[clone.g] or { x = 0, y = 0 }
            local grp = groups[clone.g]

            grp[enemyId] = grp[enemyId] or { clones = {} }
            grp[enemyId].clones[cloneId] = clone

            if grp.sublevel == nil or grp.sublevel == clone.sublevel then
                grp.sublevel = clone.sublevel
                grp.x = grp.x + (clone.x - grp.x) / #grp
                grp.y = grp.y + (clone.y - grp.y) / #grp
            else
                grp.sublevel = false
                grp.x, grp.y = nil
            end
        end
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
                        Frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
                    else
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
        Addon.SetInstanceDungeon()
        Frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    elseif ev == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, event, _, _, _, sourceFlags, _, destGUID, _, destFlags = CombatLogGetCurrentEventInfo()

        if event == "UNIT_DIED" then
            if hits[destGUID] then
                hits[destGUID] = nil
                local npcId = Addon.GetNPCId(destGUID)
                if Addon.AddKill(npcId) and Addon.IsBFS() then
                    Addon.ZoomToCurrentPull(true)
                end
            end
        elseif event:match("DAMAGE") or event:match("AURA_APPLIED") then
            local sourceIsParty = bit.band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER) == 0
            local destIsEnemy = bit.band(destFlags, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER) > 0 and bit.band(destFlags, COMBATLOG_OBJECT_REACTION_FRIENDLY) == 0
            if sourceIsParty and destIsEnemy and not hits[destGUID] then
                hits[destGUID] = true
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
Frame:RegisterEvent("SCENARIO_COMPLETED")
Frame:RegisterEvent("CHAT_MSG_SYSTEM")