local Name, Addon = ...

-- # of hops to track back from previous result
Addon.ROUTE_TRACK_BACK = 15
-- Distance weight to route
Addon.ROUTE_WEIGHT_ROUTE = 0.5
-- Distance weight to a following pull
Addon.ROUTE_WEIGHT_FORWARD = 0.5
-- Distance weight to same group but different sublevels
Addon.ROUTE_WEIGHT_GROUP = 0.7
-- Max difference between the min/max and a given path for it to be considered
Addon.ROUTE_MAX_LENGTH_DIFF = 10
Addon.ROUTE_MAX_WEIGHT_DIFF = 3
-- Max rounds per frame
Addon.ROUTE_MAX_FRAME = 20
-- Scale MAX_FRAME with elapsed time
Addon.ROUTE_MAX_FRAME_SCALE = 0.3
-- Total time to spend on route estimation (in s)
Addon.ROUTE_MAX_TOTAL = 5

local queue, queueSize, weights = {}, 0, {}
local maxLength, minWeight = 0, math.huge
local pulls, groups, portals = {}, {}, {}
local hits, kills = {}, {}
local co, rerun, zoom, retry

-- DEBUG
local ignored = 0

local useRoute = true

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

local function Distance(from, to, forceSub)
    from, to = Position(from), Position(to)
    local fromSub, toSub = forceSub or from.sublevel, forceSub or to.sublevel

    if not fromSub or not toSub or fromSub == toSub then
        return math.sqrt(math.pow(from.x - to.x, 2) + math.pow(from.y - to.y, 2))
    else
        local pois = MDT.mapPOIs[Addon.GetCurrentDungeonId()]

        local min = math.huge
        for _,fromPoi in pairs(pois[fromSub]) do
            if fromPoi.type == "mapLink" then
                local i = fromPoi.connectionIndex
                local fromDist = Distance(from, fromPoi, fromSub)
                for _,toPoi in pairs(pois[toSub]) do
                    if toPoi.type == "mapLink" then
                        local j = toPoi.connectionIndex
                        local dist = portals[i][j]
                        if dist and dist < min then
                            min = math.min(min, fromDist + dist + Distance(toPoi, to, toSub))
                        end
                    end
                end
            end
        end

        return min
    end

    return math.huge
end

local function Weight(path, enemies)
    if path == "" then
        return 0
    elseif not weights[path] then
        local parent = Sub(path, 1)
        local prevWeight, prevLength = Weight(parent, enemies), Length(parent)
        local prevNode, prev = Last(parent, enemies)
        local prevPull = prevNode and pulls[prevNode]

        local currNode, curr = Last(path, enemies)
        local currPull = currNode and pulls[currNode]
        
        -- Base distance
        local dist = Distance(prev, curr)

        -- Weighted by group
        if prev.g and curr.g and prev.g == curr.g then
            dist = dist * Addon.ROUTE_WEIGHT_GROUP
        end

        -- Weighted by direction
        if currPull then
            if not prevPull then
                dist = dist * Addon.ROUTE_WEIGHT_ROUTE
            else
                local diff = math.max(0.1, abs(currPull - prevPull) / #Addon.GetCurrentPulls())
                local forward = currPull > prevPull and Addon.ROUTE_WEIGHT_FORWARD or 1
                dist = dist * diff * forward
            end
        end

        weights[path] = prevWeight + (dist - prevWeight) / (prevLength + 1)
        -- weights[path] = prevWeight + dist
    end
    return weights[path]
end

local function CheckPath(path)
    local length, weight = Length(path), weights[path]

    local result = length > maxLength - Addon.ROUTE_MAX_LENGTH_DIFF
        and (length >= maxLength or weight < minWeight + Addon.ROUTE_MAX_WEIGHT_DIFF)

    if result then
        maxLength = math.max(maxLength, length)
        minWeight = math.min(minWeight, weight)
    else
        ignored = ignored + 1
    end

    return result
end

local function Enqueue(path)
    local weight = weights[path]

    queueSize = queueSize + 1

    local i, p = queueSize, math.floor(queueSize/2)
    while i > 1 and weights[queue[p]] > weight do
        queue[i] = queue[p]
        i, p = p, math.floor(p/2)
    end

    queue[i] = path
end

local function Dequeue()
    if queueSize > 0 then
        local val = queue[1]

        queue[1], queue[queueSize], queueSize = queue[queueSize], nil, queueSize - 1
        
        -- Heapify
        local min, i, l, r = 1
        repeat
            i, l, r = min, 2*min, 2*min+1
            if l <= queueSize and weights[queue[l]] < weights[queue[min]] then 
                min = l
            end
            if r <= queueSize and weights[queue[r]] < weights[queue[min]] then
                min = r
            end
            if min ~= i then
                queue[i], queue[min] = queue[min], queue[i]
            end
        until min == i

        return val
    end
end

local function DeepSearch(path, enemies, grp)
    local enemyId = kills[Length(path)+1]
    local minPath

    if grp and grp[enemyId] then
        for cloneId,clone in pairs(grp[enemyId].clones) do
            local node = Node(enemyId, cloneId)

            if not Contains(path, node) then
                local p = DeepSearch(Path(path, node), enemies, grp)
                local w = Weight(p, enemies)

                if not minPath or w < weights[minPath] then
                    minPath = p

                    if grp.sublevel then
                        break
                    end
                end
            end
        end
    end
    
    return minPath or path
end

local function WideSearch(path, enemies, grps)
    local enemyId = kills[Length(path)+1]
    local found

    if enemies and enemies[enemyId] then
        for cloneId,clone in pairs(enemies[enemyId].clones) do
            local node = Node(enemyId, cloneId)

            if not Contains(path, node) then
                local p = DeepSearch(Path(path, node), enemies, groups[clone.g])
                local w = Weight(p, enemies)

                if w < math.huge then
                    found = true
                    if not clone.g then
                        Enqueue(p)
                    elseif not grps[clone.g] or w < weights[grps[clone.g]] then
                        grps[clone.g] = p
                    end
                end
            end
        end
    end

    for _,p in pairs(grps) do
        Enqueue(p)
    end
    
    return found
end

function Addon.CalculateRoute()
    local enemies = Addon.GetCurrentEnemies()
    local dungeon = Addon.GetCurrentDungeonId()
    local t, i, n, grps = GetTime(), 1, 1, {}

    -- Start route
    local start = Sub(MDTGuideRoute, Addon.ROUTE_TRACK_BACK)
    weights[start] = 0
    Enqueue(start)

    while true do
        local total = GetTime() - t

        -- Limit runtime
        if total >= Addon.ROUTE_MAX_TOTAL then
            Addon.Echo(nil, "Route calculation took too long, switching to enemy forces mode!")
            useRoute, rerun = false, false
            break
        elseif i > Addon.ROUTE_MAX_FRAME * (1 - total * Addon.ROUTE_MAX_FRAME_SCALE / Addon.ROUTE_MAX_TOTAL) then
            i = 1
            coroutine.yield()
        end

        local path = Dequeue()

        -- Failure
        if not path then
            Addon.Echo(nil, "Route calculation didn't work, switching to enemy forces mode!")
            useRoute, rerun = false, false
            break
        end
        
        local length = Length(path)
        
        -- Success
        if length == #kills then
            MDTGuideRoute = path
            break
        end

        -- Find next paths
        if CheckPath(path) then
            local found = WideSearch(path, enemies, grps)

            -- Skip current enemy if no path was found
            if not found then
                table.remove(kills, length+1)
                Enqueue(path)
            end

            wipe(grps)
        end

        i, n = i+1, n+1
    end

    debug("LENGTH", Length(MDTGuideRoute))
    debug("WEIGHT", weights[MDTGuideRoute])
    debug("LOOPS", n)
    debug("TIME", GetTime() - t)
    debug("QUEUE", queueSize)
    debug("IGNORED", ignored)

    wipe(queue)
    wipe(weights)
    queueSize, maxLength, minWeight = 0, 0, math.huge
    ignored = 0

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

function Addon.UseRoute(val)
    if val ~= nil then
        MDTGuideOptions.route = val
        if val == true then
            useRoute = true
        end
    end

    return MDTGuideOptions.route and useRoute
end

function Addon.UpdateRoute(z)
    zoom = zoom or z
    rerun = false
    if Addon.IsCurrentInstance() then
        if co and coroutine.status(co) == "running" then
            rerun = true
        else
            co = coroutine.create(Addon.CalculateRoute)
            local ok, err = coroutine.resume(co)
            if not ok then error(err) end
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
    useRoute = true
end

function Addon.GetCurrentPullByRoute()
    local path = MDTGuideRoute
    while path and path:len() > 0 do
        local node = Last(path)
        local n = pulls[node]
        if n then
            local a, b = Addon.IteratePull(n, function (_, _, cloneId, enemyId, pull)
                if not Contains(path, Node(enemyId, cloneId)) then
                    return n, pull
                end
            end)

            if a then
                return a, b
            else
                local currPulls = Addon.GetCurrentPulls()
                if n < #currPulls then n = n + 1 end
                return n, currPulls[n]
            end
        end
        path = path:sub(1, -node:len() - 3)
    end
end

function Addon.SetDungeon()
    wipe(pulls)

    Addon.BuildGroups()
    Addon.BuildPortals()
    Addon.UpdateRoute()
end

function Addon.SetInstanceDungeon(dungeon)
    Addon.currentDungeon = dungeon
    Addon.ClearKills()
    Addon.UpdateRoute()
end

function Addon.BuildGroups()
    wipe(groups)

    Addon.IteratePulls(function (clone, _, cloneId, enemyId, _, pullId)
        pulls[Node(enemyId, cloneId)] = pullId

        if clone.g then
            groups[clone.g] = groups[clone.g] or { x = 0, y = 0, length = 0 }
            local grp = groups[clone.g]

            grp[enemyId] = grp[enemyId] or { clones = {} }
            grp[enemyId].clones[cloneId] = clone
            grp.length = grp.length + 1

            if grp.sublevel == nil or grp.sublevel == clone.sublevel then
                grp.sublevel = clone.sublevel
                grp.x = grp.x + (clone.x - grp.x) / grp.length
                grp.y = grp.y + (clone.y - grp.y) / grp.length
            else
                grp.sublevel = false
                grp.x, grp.y = nil
            end
        end
    end)
end

function Addon.BuildPortals()
    local start = GetTime()
    local levels = MDT.mapPOIs[Addon.GetCurrentDungeonId()]
    local numLevels = #levels

    wipe(portals)

    -- Build cost matrix
    for level,pois in pairs(levels) do
        for _,poi in pairs(pois) do
            if poi.type == "mapLink" then
                local i = poi.connectionIndex
                portals[i] = portals[i] or {}
                for _,poi2 in pairs(pois) do
                    if poi2.type == "mapLink" then
                        local j = poi2.connectionIndex
                        portals[i][j] = i == j and 0 or math.min(portals[i][j] or math.huge, Distance(poi, poi2))
                    end
                end
            end
        end
    end

    local n = #portals

    -- Find shortest paths
    for k=1,n do
        for i=1,n do
            for j=1,n do
                local path = (portals[i][k] or math.huge) + (portals[k][j] or math.huge)
                if path < (portals[i][j] or math.huge) then
                   portals[i][j] = path
                end
            end
        end
    end
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
                if Addon.AddKill(npcId) and Addon.UseRoute() then
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
        local ok, err = coroutine.resume(co)
        if not ok then error(err) end
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