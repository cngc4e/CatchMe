local linkedlist 
do
	-- linked list library by Leafileaf
	linkedlist = {
		push_front = function( ll , v )
			local n = {v=v,next=ll.__front}
			if not ll.__back then ll.__back = n end
			ll.__front = n
			ll.n = ll.n + 1
		end,
		push_back = function( ll , v )
			local n = {v=v}
			if not ll.__front then ll.__front = n end
			if ll.__back then ll.__back.next = n end
			ll.__back = n
			ll.n = ll.n + 1
		end,
		pop_front = function( ll )
			local v = ll.__front.v
			ll.__front = ll.__front.next
			if not ll.__front then ll.__back = nil end
			ll.n = ll.n - 1
			return v
		end,
		front = function( ll )
			return ll.__front.v
		end,
		new = function( ll )
			return setmetatable( {n=0} , ll )
		end
	}
	linkedlist.__index = linkedlist
end

local PairTable
do
    local function cnext(tbl, k)
        local v
        k, v = next(tbl, k)
        if k ~= "_len" then 
            return k,v
        else
            k, v = next(tbl, k)
            return k,v
        end
    end
    local PairTableProto = {
        add = function(self, key)
            self[key] = true
            self._len = self._len + 1
        end,
        remove = function(self, key)
            self[key] = nil
            self._len = self._len - 1
        end,
        len = function(self)
            return self._len
        end,
        pairs = function(self)
            return cnext, self, nil
        end,
    }
    PairTableProto.__index = PairTableProto
    PairTable = {
        new = function(self, t)
            local tbl
            if t then
                tbl = {}
                local len = 0
                for k, v in cnext, t do
                    tbl[k] = v
                    len = len + 1
                end
                tbl._len = len
            else
                tbl = { _len = 0 }
            end
            return setmetatable(tbl, PairTableProto)
        end,
    }
end

local room = tfm.get.room

local PHASE_START = 0
--local PHASE_TIMESUP = 1
local PHASE_OVER = 2

-- Key trigger types
local DOWN_ONLY = 1
local UP_ONLY = 2
local DOWN_UP = 3

local roundv = {}
--local toRespawn = linkedlist:new()

local players = {}
local Player = {}
do
    Player.linkMice = function(self, pn)
        if not players[pn] then return end
        if self.linked_mice[pn] then return end  -- already linked

        tfm.exec.linkMice(self.pn, pn, true)

        self.linked_mice:add(pn)
        players[pn].linked_mice:add(self.pn)
    end

    Player.unlinkMice = function(self, pn)
        if not players[pn] then return end
        if not self.linked_mice[pn] then return end  -- already unlinked

        tfm.exec.linkMice(self.pn, pn, false)

        self.linked_mice:remove(pn)
        players[pn].linked_mice:remove(self.pn)
    end

    Player.unlinkMiceAll = function(self)
        local names, sz = {}, 0
        for name in self.linked_mice:pairs() do
            if players[name] then
                sz = sz + 1
                names[sz] = name
            end
        end
        for i = 1, sz do
            self:unlinkMice(names[i])
        end
        self.linked_mice = PairTable:new()
    end

    --[[Player.doDash = function(self)
        if not self.next_dash or os.time() >= self.next_dash then
            self.next_dash = os.time() + 3000
            tfm.exec.movePlayer(self.pn, 0, 0, true, xSpeed, ySpeed, speedOffset )
        end
    end]]

    Player.new = function(pn)
        return setmetatable({
            pn = pn,
            linked_mice = PairTable:new(),
            --next_dash = nil,
        }, Player)
    end

    Player.__index = Player
end
local mapsched = {}
do
    local queued_code
    local queued_mirror
    local call_after
    local is_waiting = false

    local function load(code, mirror)
        queued_code = code
        queued_mirror = mirror
        if not call_after or call_after <= os.time() then
            is_waiting = false
            call_after = os.time() + 3000
            tfm.exec.newGame(code, mirror)
        else
            is_waiting = true
        end
    end

   local function run()
        if is_waiting and call_after <= os.time() then
            call_after = nil
            load(queued_code, queued_mirror)
        end
    end

    mapsched.load = load
    mapsched.run = run
end

local pL = {}
do
    local states = {
        "room",
		"alive",
        "dead",
        "normal"  -- everyone except police
    }
    for i = 1, #states do
        pL[states[i]] = PairTable:new()
    end
end

local function pythag(x1, y1, x2, y2, r)
	local x,y,r = x2-x1, y2-y1, r+r
	return x*x+y*y<r*r
end

-- Local funcs
local catchMice = function(pn)
    local police = roundv.police
    if not players[police] then return end

    tfm.exec.killPlayer(pn)
    tfm.exec.respawnPlayer(pn)
    players[police]:linkMice(pn)

    -- Check all mice caught
    if players[police].linked_mice:len() >= pL.normal:len() then
        tfm.exec.chatMessage("<J>The Police caught everyone!")
        eventGameOver()
    end
end

--Local events

eventGameOver = function()
    roundv.phase = PHASE_OVER
    tfm.exec.setGameTime(5)
end

eventTimesUp = function(elapsed)
    if roundv.phase >= PHASE_OVER then
        local police = roundv.police
        if players[police] then
            players[police]:unlinkMiceAll()
        end
        for name in pL.room:pairs() do
            tfm.exec.giveCheese(name)
            tfm.exec.playerVictory(name)
        end
        mapsched.load("@7765491")
    else
        tfm.exec.chatMessage("<J>Times Up!")
        eventGameOver()
    end
end

-- TFM events
eventLoop = function(elapsed, remaining)
    mapsched.run()

    if not roundv.running then return end
    if remaining <= 0 then
        eventTimesUp(elapsed)
    end

    --[[if roundv.phase < PHASE_TIMESUP and toRespawn.n > 0 then
		local flag
		repeat
			local r = toRespawn:front()
			flag = false
			if os.time() >= r[2] then
				flag = true
				tfm.exec.respawnPlayer(r:pop_front()[1])
			end
		until not flag or r.n <= 0
	end]]
end

local keys = {
    [32] = {
        func = function(pn, d, x, y)  -- SPACEBAR
            if pn ~= roundv.police then return end
            for name in pL.normal:pairs() do
                local p = room.playerList[name]
                if p and not players[pn].linked_mice[name] and pythag(p.x, p.y, x, y, 11) then
                    catchMice(name)
                    break  -- only catch one at a time
                end
            end
        end,
        trigger = DOWN_ONLY
    },
}
eventKeyboard = function(pn, k, d, x, y)
    if keys[k] then
        keys[k].func(pn, d, x, y)
    end
end

eventNewGame = function()
    pL.dead = PairTable:new()
    pL.alive = PairTable:new(pL.room)

    roundv = {
        running = true,
        phase = PHASE_START,
    }

    -- TODO: optimise nd rotate
    local pls = {}
    for name in pL.room:pairs() do
        pls[#pls+1] = name
    end
    roundv.police = pls[math.random(#pls)]
    tfm.exec.setShaman(roundv.police)  -- TODO: auto shaman pls

    -- non-police players
    pL.normal = PairTable:new(pL.room)
    pL.normal:remove(roundv.police)

    tfm.exec.chatMessage(string.format("<J>%s is now the police! Scatter away!", roundv.police), nil)
    tfm.exec.chatMessage("<J>You are now the police! Press Spacebar to catch the mice!", roundv.police)
end

eventNewPlayer = function(pn)
    pL.room:add(pn)
    pL.dead:add(pn)

    tfm.exec.chatMessage("\t<ROSE>== MoLua Catch Me Daddy v0.0069 ==", pn)
    players[pn] = Player.new(pn)

    for key, a in pairs(keys) do
        if a.trigger == DOWN_ONLY then
            system.bindKeyboard(pn, key, true)
        elseif a.trigger == UP_ONLY then
            system.bindKeyboard(pn, key, false)
        elseif a.trigger == DOWN_UP then
            system.bindKeyboard(pn, key, true)
            system.bindKeyboard(pn, key, false)
        end
    end

    tfm.exec.lowerSyncDelay(pn)
end

eventPlayerLeft = function(pn)
    pL.room:remove(pn)
    if not roundv.running then return end
    if pn == roundv.police then
        tfm.exec.chatMessage("<J>The police died. noob.")
        eventGameOver()
    end
    if players[pn] then
        players[pn]:unlinkMiceAll()
        players[pn] = nil
    end
end

eventPlayerDied = function(pn)
    pL.alive:remove(pn)
    pL.dead:add(pn)

    if not roundv.running then return end
    if pn == roundv.police then
        tfm.exec.chatMessage("<J>The police died. noob.")
        eventGameOver()
    elseif players[pn] and players[pn].linked_mice:len() > 0 then
        local p  = room.playerList[roundv.police]
        if p and not pL.dead[roundv.police] then
            tfm.exec.respawnPlayer(pn)
            tfm.exec.freezePlayer(pn)
            tfm.exec.movePlayer(pn, p.x, p.y)
        end
    end
end

eventPlayerWon = function(pn, elapsed)
    pL.alive:remove(pn)
    pL.dead:add(pn)
end

eventPlayerRespawn = function(pn)
    pL.dead:remove(pn)
    pL.alive:add(pn)
end

local init = function()
    for _,v in ipairs({'AfkDeath','AutoNewGame','AutoScore','AutoTimeLeft','AutoShaman','PhysicalConsumables','MortCommand'}) do
        tfm.exec['disable'..v](true)
    end
    for name in pairs(room.playerList) do eventNewPlayer(name) end
    mapsched.load("@7765491")
end

init()
