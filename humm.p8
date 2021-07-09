pico-8 cartridge // http://www.pico-8.com
version 32
__lua__
-- oo structuring

function ctor(self,o)
	for k,v in pairs(o) do
		self[k] = v or self[k]
	end
end

local obj = {init = ctor}
obj.__index = obj

function obj:__call(...)
	local o=setmetatable({},self)
	return o, o:init(...)
end

function obj:extend(proto)
	proto = proto or {}

	for k,v in pairs(self) do
		if sub(k,1,2) == '__' then
			proto[k] = v
		end
	end

	proto.__index = proto
	proto.__super = self

	return setmetatable(proto,self)
end

-->8
-- main logic

-- consts/magic numbers
sqrt2 = sqrt(2)
invsqrt2 = 1/sqrt(2)
eps = 0x0000.0001
scrnlt = 0
scrnrt = 128
scrntp = 10
scrnbt = 128
minspeed = 0.25
maxage = 2*3*2*5*7*2*3
lvls = {
	[0x0000.0200]=2,
	[0x0000.0400]=3,
	[0x0000.0700]=4,
	[0x0000.0a00]=5,
}
mns = { -- maxnextscores
	80,
	70,
	62,
	55,
	50,
}

-- state
nextspawn = 0
actorseed = rnd(1)
_time = 0
_lvl = 1
_maxnextscore = 80
_tonextscore = _maxnextscore
_score = 0
_fsm = 'title' --game,gmover...
_sgtype = nil
_sgparms = nil

-- actors
pc = nil
npcs = {}

function signal(name,parms)
	_sgtype,_sgparms=name,parms or {}
end

debug = {_names={}}
function _d(str,name)
	if (not name) then
		add(debug,str)
		if #debug > 8 then
			deli(debug,1)
		end
	else
		if not debug[name] then
			add(debug._names,name)
		end
		debug[name] = str
		 or (str==nil and 'nil')
		 or (str==false and 'false')
	end
end

function _d_pop()
	for d in all(debug) do
		print(d)
	end
	for i,n in ipairs(debug._names) do
		print(
		 n..': '..debug[n],
		 0,
		 64 + 6*i
		)
	end
end

local actor = obj:extend{
	sprage=0,
	x=0,
	y=0,
	dx=0,
	dy=0,
	w=8,
	h=8,
}

function actor:draw()
	self.sprage += 1
	self.sprage %= maxage
	local frame=
	 self.sprage%#self.sprites
	spr(
	 self.sprites[frame+1],
	 self.x,
	 self.y
	)
end

function actor:update()
	--todo:out-of-sync actors look
	--bad (moving alt. frames)
	self.x += self.dx
	self.y += self.dy
end

local block = actor:extend{
  name='blk',
}
function block:draw()
	rectfill(
	 self.x,
	 self.y,
	 self.x+self.w-1,
	 self.y+self.h-1,
	 12
	)
end

local spike = actor:extend{
	name='spk',
	sprites={4},
	w=7,
	h=7,
}

local flower = actor:extend{
	name='flw',
	sprites={5},
	juice=0,
	depleted=false,
}
function flower:draw()
	self.__super.draw(self)
	rectfill(
	 self.x,
	 self.y+9,
	 self.x+16*self.juice/80,
	 self.y+11,
	 self.depleted and 8 or 11
	)
end

function updatenpcs()
	nextspawn -= 1
	for n in all(npcs) do
		if (n.x < scrnlt) then
			del(npcs,n)
		end
	end
	if nextspawn < 0 then
		if (actorseed < 0.3-0.02*_lvl
		 or pc.juice < 60
		) then -- todo: and no non
		-- depleted flower exists?
			add(npcs,flower{
			 juice=80,
			 x=scrnrt,
			 y=scrntp+flr(rnd(scrnbt-scrntp-12)),
			 dx=-0.5-0.05*_lvl,
			})
		elseif actorseed < 0.6 then
			add(npcs,spike{
			 x=scrnrt,
			 y=scrntp+flr(rnd(scrnbt-scrntp-8)),
			 dx=-0.5-0.05*_lvl,
			})
		else
			local _h = 8+flr(rnd(15+_lvl))
			add(npcs,block{
			 x=scrnrt,
			 y=scrntp+flr(rnd(scrnbt-scrntp-_h)),
			 dx=-0.5-0.05*_lvl,
			 w=3,
			 h=_h,
			})
		end
		actorseed = rnd(1)
		nextspawn = 20-_lvl+flr(rnd(20-_lvl))
	end
end

local humm = actor:extend{
	name='pc',
	x=32,
	y=64,
	state='fly',--splode,drink...
	friction=0.5,
	impulse=1,
	juice=0,
	sprites={
	 	fly={1,1,2,2},
	 	splode={17,17,17,17,17,17,17,17,17,18,18,18,18,18,18,18,18},
	},
}

function humm:draw()
	self.sprage += 1
	self.sprage %= maxage
	local _sprs=self.sprites[self.state]
	local frame=
	 self.sprage%#_sprs
	spr(
	 _sprs[frame+1],
	 self.x,
	 self.y
	)
	spr(21,2,0)
	local jcefrac = self.juice/300
	local jceclr =
	    jcefrac < 0.25 and 8
	 or jcefrac < 0.5 and 9
	 or jcefrac < 0.75 and 10
	 or 11
	rectfill(
	 10,
	 3,
	 10+50*jcefrac,
	 5,
	 jceclr
	)
end

function humm:updatespeed()
	-- local dxy to queue changes
	-- local imp to save space
	local dx,dy,imp
	 =self.dx,self.dy,self.impulse

	local btnx,btny = 0,0
	if (btn(⬅️)) then
		btnx -= imp
	end
	if (btn(➡️)) then
		btnx += imp
	end
	if (btn(⬆️)) then
		btny -= imp
	end
	if (btn(⬇️)) then
		btny += imp
	end
	if (btnx~=0 and btny~=0) then
	 	btnx *= invsqrt2
	 	btny *= invsqrt2
	end
	dx += btnx
	dy += btny

	dx *= self.friction
	dy *= self.friction

	if (abs(dx) < minspeed) then
		dx = 0
	end
	if (abs(dy) < minspeed) then
		dy = 0
	end
	self.dx,self.dy = dx,dy
end

function humm:updatepos()
	local x = self.x + self.dx
	local y = self.y + self.dy
	local w,h = self.w,self.h

	if x+w>scrnrt then
		x = scrnrt-w
		self.state = 'splode'
	elseif x<scrnlt then
		x = scrnlt
		self.state = 'splode'
	end
	if y+h>scrnbt then
		y = scrnbt-h
		self.state = 'splode'
	elseif y<scrntp then
		y = scrntp
		self.state = 'splode'
	end

	self.x,self.y = x,y
end

function humm:handlecol(oldx,oldy)
	local x,y,w,h
	 =self.x,self.y,self.w,self.h
	for n in all(npcs) do
		if ( x + w > n.x
		 and x < n.x + n.w
		 and y + h > n.y
		 and y < n.y + n.h
		) then
			if (n.name == 'blk') then
				local oldxin =
				 oldx + w > n.x and
				 oldx < n.x + n.w
				local oldyin =
				 oldy + h > n.y and
				 oldy < n.y + n.h
				if oldxin and not oldyin then
					if oldy < n.y then
						y = n.y - h
					else
						y = n.y + n.h
					end
				elseif oldyin and not oldxin then
					if oldx < n.x then
						x = n.x - w
					else
						x = n.x + n.w
					end
				elseif oldyin and oldxin then
					-- fully inside object
					-- just push left
					x = n.x - w
				end
				self.x = x
				self.y = y
			elseif (n.name == 'spk') then
				self.state = 'splode'
			elseif (n.name == 'flw') then
				if n.juice > 0 then
					if self.juice < 300 then
						n.juice -= 1
						self.juice += 2
					else
						n.juice -= 0.5
						self.juice += 1
					end
				elseif not n.depleted then
					n.depleted = true
					signal('score',{
					 score=2+_lvl,
					})
				end
			end
		end
	end
end

function humm:update()
	if (self.state == 'fly') then
		self:updatespeed()
		local oldx,oldy=self.x,self.y
		self:updatepos()
		self:handlecol(oldx,oldy)
		self.juice -= 1
		if (self.juice <= 0) then
			self.state = 'splode'
		end
	elseif (self.state=='splode') then
		sfx(1,2,0,60)
		signal('gmover')
	end
end

function popsignal()
	if _sgtype == 'reset' then
		_time = 0
		pc = nil
		for n in all(npcs) do
			del(npcs,n)
		end
		_fsm = 'title'
		-- todo: make not horrible
		-- sfx(2,0)
	elseif _sgtype=='start' then
		sfx(0,0)
		pc = humm(_sgparms.humm)
		_fsm = 'game'
		_score = 0
		_time = 0
	elseif _sgtype=='gmover' then
		_fsm = 'gmover'
	elseif _sgtype=='score' then
		sfx(4,1)
		_score += _sgparms.score
	end
	_sgtype,_sgparms=nil,nil
end

-->8
-- top-level flow

function _init()
	-- currently nothing!
end

function _update()
	if _fsm == 'title' then
		_time += eps
		if btnp(🅾️) or btnp(❎) then
			signal('start',{
			 humm={
			  friction=0.8,
			  impulse=2,
			  juice=300,
			 },
			})
		end
	elseif _fsm == 'game' then
		pc:update()
		for n in all(npcs) do
			n:update()
		end
		updatenpcs()
		_time += eps
		if lvls[_time] then
			_lvl = lvls[_time]
			_maxnextscore = mns[_lvl]
			sfx(3,1)
		end
		_tonextscore -= 1
		if _tonextscore == 0 then
			_score += 1
			_tonextscore = _maxnextscore
		end
	elseif _fsm == 'gmover' then
		if btnp(🅾️) or btnp(❎) then
			signal('reset')
		end
	end
	popsignal()
end

function _draw()
	if _fsm == 'title' then
		cls(2)
		print(
		 '\#1\^w\^t\fbh\fau\f9m\f8m',
		 49,
		 48
		)
		if _time*0x100*0x100%40<25 then
			print(
			 '\#1press any button',
			 32,
			 62,
			 10
			)
		end
	elseif _fsm == 'game' then
		cls()
		rectfill(
		 scrnlt,
		 scrntp,
		 scrnrt,
		 scrnbt,
		 3
		)
		pc:draw()
		for n in all(npcs) do
			n:draw()
		end
		print(
		 'score: '.._score,
		 64,
		 2,
		 8
		)
		print(
		 'lvl'.._lvl,
		 112,
		 2,
		 11
		)
	elseif _fsm == 'gmover' then
		cls()
		rectfill(
		 scrnlt,
		 scrntp,
		 scrnrt,
		 scrnbt,
		 3
		)
		print(
		 'lvl'.._lvl,
		 112,
		 2,
		 11
		)
		pc:draw()
		for n in all(npcs) do
			n:draw()
		end
		print(
		 '\#1game over',
		 46,
		 40,
		 14
		)
		print(
		 '\#1score: '.._score,
		 50-2*#tostr(_score),
		 46,
		 8
		)
	end
	_d_pop()
end

__gfx__
00000000050000000000000000cccc00400400400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000555088000000880000cccc00040404008880000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000006508c1100008c1100cccc00004440000988800000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000065aa000555aa0000cccc00444444400aa988bb00000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000055aa005565aa0000cccc00004440000aa988bb00000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000009550000095500000cccc00040404000988800000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000099500000995000000cccc00400400408880000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000990000009900000000cccc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000007700770000000000000000000bbba0000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000070070007700770000000000000000000bbaa0000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000007700000077000000000000000000000baa90000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000007700000077000000000000000000000aa990000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000070070007700770000000000000000000a9980000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000770077000000000000000000099880000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000098880000000000000000000000000000000000000000000000000000000000000000000000000000000000
__label__
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888eeeeee888777777888eeeeee888888888888888888888888888888888888888888888888888888ff8ff8888228822888222822888888822888888228888
8888ee888ee88778877788ee888ee88888888888888888888888888888888888888888888888888888ff888ff888222222888222822888882282888888222888
888eee8e8ee8777787778eeeee8ee88888e88888888888888888888888888888888888888888888888ff888ff888282282888222888888228882888888288888
888eee8e8ee8777787778eee888ee8888eee8888888888888888888888888888888888888888888888ff888ff888222222888888222888228882888822288888
888eee8e8ee8777787778eee8eeee88888e88888888888888888888888888888888888888888888888ff888ff888822228888228222888882282888222288888
888eee888ee8777888778eee888ee888888888888888888888888888888888888888888888888888888ff8ff8888828828888228222888888822888222888888
888eeeeeeee8777777778eeeeeeee888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
555555555eee5ee55ee5555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555e555e5e5e5e555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555ee55e5e5e5e555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555e555e5e5e5e555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555eee5e5e5eee555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555888885555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555eee55ee5eee5555557556658666856655555eee5ee555555665566655665566557555555ee555ee5555555555555555555555555555555555555555
555555555e555e5e5e5e55555755565686868655555555e55e5e55555656565656555655555755555e5e5e5e5555555555555555555555555555555555555555
555555555ee55e5e5ee555555755565686668655555555e55e5e55555656566656555666555755555e5e5e5e5555555555555555555555555555555555555555
555555555e555e5e5e5e55555755565686888655555555e55e5e55555656565556555556555755555e5e5e5e5555555555555555555555555555555555555555
555555555e555ee55e5e5555557556568688856655555eee5e5e55555656565555665665557555555eee5ee55555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555eee5eee55555575555556565555575555555665566655665555565655555555555555555555555555555555555555555555555555555555
555555555555555555e55e5555555755555556565555557555555656565656555555565655555555555555555555555555555555555555555555555555555555
555555555555555555e55ee555555755555555655555555755555656566656555555556555555555555555555555555555555555555555555555555555555555
555555555555555555e55e5555555755555556565555557555555656565556555555565655555555555555555555555555555555555555555555555555555555
55555555555555555eee5e5555555575555556565555575555555656565555665575565655555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555555555555555eee5ee55ee555555656555555575555566556665566555556565555555555555ccc5555555555555555555555555555555555555555
555555555555555555555e5e5e5e5e5e55555656555555755555565656565655555556565555557555555c5c5555555555555555555555555555555555555555
555555555555555555555eee5e5e5e5e55555565555557555555565656665655555555655555577755555ccc5555555555555555555555555555555555555555
555555555555555555555e5e5e5e5e5e55555656555555755555565656555655555556565555557555555c5c5555555555555555555555555555555555555555
555555555555555555555e5e5e5e5eee55555656555555575555565656555566557556565555555555555ccc5555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555555555555555eee5ee55ee5555556565555575555555665566655665555565655555555555555555555555555555555555555555555555555555555
555555555555555555555e5e5e5e5e5e555556565555557555555656565656555555565655555555555555555555555555555555555555555555555555555555
555555555555555555555eee5e5e5e5e555556665555555755555656566656555555566655555555555555555555555555555555555555555555555555555555
555555555555555555555e5e5e5e5e5e555555565555557555555656565556555555555655555555555555555555555555555555555555555555555555555555
555555555555555555555e5e5e5e5eee555556665555575555555656565555665575566655555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555555555555555eee5ee55ee555555656555555575555566556665566555556565555555555555ccc5555555555555555555555555555555555555555
555555555555555555555e5e5e5e5e5e55555656555555755555565656565655555556565555557555555c5c5555555555555555555555555555555555555555
555555555555555555555eee5e5e5e5e55555666555557555555565656665655555556665555577755555ccc5555555555555555555555555555555555555555
555555555555555555555e5e5e5e5e5e55555556555555755555565656555655555555565555557555555c5c5555555555555555555555555555555555555555
555555555555555555555e5e5e5e5eee55555666555555575555565656555566557556665555555555555ccc5555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
5555555555555555557555555ee555ee555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
5555555555555555555755555e5e5e5e555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
5555555555555555555755555e5e5e5e555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
5555555555555555555755555e5e5e5e555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
5555555555555555557555555eee5ee5555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555556565555565655555566566656555666555556565666566556655655566655665566565555755665566655665555565655555656
55555555555555555555555556565555565657775655565556555655557556565656565656565655565556555656565557555656565656555555565655555656
55555555555555555555555555655555566655555666566556555665555556665666565656565655566556555656565557555656566656555555556555555666
55555555555555555555555556565575555657775556565556555655557556565656565656565655565556555656565557555656565556555575565655755556
55555555555555555555555556565755566655555665566656665655555556565656565656665666566655665665566655755656565555665755565657555666
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555eee5ee55ee55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555e555e5e5e5e5555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555ee55e5e5e5e5555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555e555e5e5e5e5555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555eee5e5e5eee5555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555eee5ee55ee5555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555e555e5e5e5e555555555555555555555555555555555555555555555555555555555555555555555555555555555155555555555555555555555555
555555555ee55e5e5e5e555555555555555555555555555555555555555555555555555555555555555555555555555555551715555555555555555555555555
555555555e555e5e5e5e555555555555555555555555555555555555555555555555555555555555555555555555555555551771555555555555555555555555
555555555eee5e5e5eee555555555555555555555555555555555555555555555555555555555555555555555555555555551777155555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555551777715555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555551771155555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555117155555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555556656665655566655555656555555665666565556665555565655555555555556565555565655555555555555555555555555555555555555555555
55555555565556555655565555555656555556555655565556555555565655555777555556565555565655555555555555555555555555555555555555555555
55555555566656655655566555555565555556665665565556655555566655555555555555655555566655555555555555555555555555555555555555555555
55555555555656555655565555555656557555565655565556555555555655555777555556565575555655555555555555555555555555555555555555555555
55555555566556665666565555755656575556655666566656555575566655555555555556565755566655555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
5eee5ee55ee555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
5e555e5e5e5e55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
5ee55e5e5e5e55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
5e555e5e5e5e55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
5eee5e5e5eee55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
5eee5e5e5ee555ee5eee5eee55ee5ee5555556565656566656665555565656665665566556555666556655665655557556655666556655755555555555555555
5e555e5e5e5e5e5555e555e55e5e5e5e555556565656566656665575565656565656565656555655565556565655575556565656565555575555555555555555
5ee55e5e5e5e5e5555e555e55e5e5e5e555556665656565656565555566656665656565656555665565556565655575556565666565555575555555555555555
5e555e5e5e5e5e5555e555e55e5e5e5e555556565656565656565575565656565656565656555655565556565655575556565655565555575555555555555555
5e5555ee5e5e55ee55e55eee5ee55e5e555556565566565656565555565656565656566656665666556656655666557556565655556655755555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555eee5eee5555557556655666556655555665566656665666555555555555555555c55ccc5c555c5c55c5557555555eee5e5e5eee5ee5555555555555
5555555555e55e55555557555656565656555555565656565666565555555777577755555c555c5c5c555c5c5c555557555555e55e5e5e555e5e555555555555
5555555555e55ee55555575556565666565555555656566656565665555555555555555555555cc55c555cc555555557555555e55eee5ee55e5e555555555555
5555555555e55e555555575556565655565555555656565656565655555557775777555555555c5c5c555c5c55555557555555e55e5e5e555e5e555555555555
555555555eee5e555555557556565655556655755656565656565666555555555555555555555ccc5ccc5c5c55555575555555e55e5e5eee5e5e555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
55555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555eee5ee55ee5555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555e555e5e5e5e555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555ee55e5e5e5e555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555e555e5e5e5e555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
555555555eee5e5e5eee555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555555
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
82888222822882228888822882288222888282288282822288888888888888888888888888888888888888888222822282228882822282288222822288866688
82888828828282888888882888288288882888288282828288888888888888888888888888888888888888888288888288828828828288288282888288888888
82888828828282288888882888288222882888288222828288888888888888888888888888888888888888888222822288228828822288288222822288822288
82888828828282888888882888288882882888288882828288888888888888888888888888888888888888888882828888828828828288288882828888888888
82228222828282228888822282228222828882228882822288888888888888888888888888888888888888888222822282228288822282228882822288822288
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888

__sfx__
000305000d050140501a0501e05021050220000400004000250000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00030014264201f4201a4201642012420104200f4200e4200e4200c4000c4000c4003b4003b4003b4000040000400004000040000400004000040000400004000040000400004000040000400004000040000400
002002002513021130211002110021100211000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
0004040022130221302e1302e13035100271002710027100291000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
0004040022050220502e0502e05000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
