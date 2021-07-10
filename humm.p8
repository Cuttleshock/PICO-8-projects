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
nsoverride = nil
actorseed = rnd(1)
asoverride = nil
_time = 0
_lvl = 1
_tonextscore = mns[_lvl]
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
  clr=12,
}
function block:draw()
	rectfill(
	 self.x,
	 self.y,
	 self.x+self.w-1,
	 self.y+self.h-1,
	 self.clr
	)
end

local lvlline = block:extend{
	name='lvl',
	y=scrntp,
	w=2,
	h=scrnbt-scrntp,
	clr=14,
	lvl=1,
	hit=false,
}

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
		elseif n.y<scrntp and n.dy<0 then
			n.dy = -n.dy
		elseif n.y+n.h>scrnbt and n.dy>0 then
			n.dy = -n.dy
		end
	end
	if nextspawn < 0 then
		spawnnpc()
		actorseed = asoverride or rnd(1)
		nextspawn = nsoverride or 20-_lvl+flr(rnd(20-_lvl))
		asoverride = nil
		nsoverride = nil
	end
end

function spawnnpc()
	if _lvl == 1 then
		if (actorseed < 0.28
		 or pc.juice < 60
		) then
			add(npcs,flower{
			 juice=80,
			 x=scrnrt,
			 y=scrntp+flr(rnd(scrnbt-scrntp-12)),
			 dx=-0.55,
			})
		elseif actorseed < 0.6 then
			add(npcs,spike{
			 x=scrnrt,
			 y=scrntp+flr(rnd(scrnbt-scrntp-8)),
			 dx=-0.55,
			})
		else
			local _h=16+flr(rnd(15))
			add(npcs,block{
			 x=scrnrt,
			 y=scrntp+flr(rnd(scrnbt-scrntp-_h)),
			 dx=-0.55,
			 w=3,
			 h=_h,
			})
		end
	elseif _lvl == 2 then
		if (actorseed < 0.26
		 or pc.juice < 60
		) then
			add(npcs,flower{
			 juice=80,
			 x=scrnrt,
			 y=scrntp+flr(rnd(scrnbt-scrntp-12)),
			 dx=-0.6,
			})
		elseif actorseed < 0.6 then
			local _h=scrntp+flr(rnd(scrnbt-scrntp-18))
			add(npcs,spike{
			 x=scrnrt,
			 y=_h,
			 dx=-0.6,
			})
			add(npcs,spike{
			 x=scrnrt,
			 y=_h+10,
			 dx=-0.6,
			})
		else
			local _h = 20+flr(rnd(15))
			add(npcs,block{
			 x=scrnrt,
			 y=scrntp+flr(rnd(scrnbt-scrntp-_h)),
			 dx=-0.6,
			 w=3,
			 h=_h,
			})
		end
	elseif _lvl == 3 then
		if (actorseed < 0.24
		 or pc.juice < 60
		) then
			add(npcs,flower{
			 juice=80,
			 x=scrnrt,
			 y=scrntp+flr(rnd(scrnbt-scrntp-12)),
			 dx=-0.65,
			})
		elseif actorseed < 0.6 then
			local _h=scrntp+flr(rnd(scrnbt-scrntp-18))
			local _dy=0.4*(flr(rnd(3))-1)
			add(npcs,spike{
			 x=scrnrt,
			 y=_h,
			 dx=-0.65,
			 dy=_dy,
			})
			add(npcs,spike{
			 x=scrnrt,
			 y=_h+10,
			 dx=-0.65,
			 dy=_dy,
			})
		else
			local _h = 24+flr(rnd(15))
			add(npcs,block{
			 x=scrnrt,
			 y=scrntp+flr(rnd(scrnbt-scrntp-_h)),
			 dx=-0.65,
			 w=3,
			 h=_h,
			})
		end
	elseif _lvl == 4 then
		if (actorseed < 0.22
		 or pc.juice < 60
		) then
			add(npcs,flower{
			 juice=80,
			 x=scrnrt,
			 y=scrntp+flr(rnd(scrnbt-scrntp-12)),
			 dx=-0.7,
			 dy=0.5*(flr(rnd(3))-1),
			})
		elseif actorseed < 0.6 then
			local _h=scrntp+flr(rnd(scrnbt-scrntp-18))
			local _dy=0.5*(flr(rnd(3))-1)
			add(npcs,spike{
			 x=scrnrt,
			 y=_h,
			 dx=-0.7,
			 dy=_dy,
			})
			add(npcs,spike{
			 x=scrnrt,
			 y=_h+10,
			 dx=-0.7,
			 dy=_dy,
			})
		else
			local _h = 26+flr(rnd(15+4*_lvl))
			add(npcs,block{
			 x=scrnrt,
			 y=scrntp+flr(rnd(scrnbt-scrntp-_h)),
			 dx=-0.7,
			 w=3,
			 h=_h,
			 dy=0.5*(flr(rnd(3))-1),
			})
		end
	elseif _lvl == 5 then
		if actorseed=='spkwall' then
			local gap=flr(rnd(1)*9)+1
			local _y=scrntp+2
			for x=1,9 do
				if x~=gap then
					add(npcs,spike{
					 x=scrnrt,
					 y=_y,
					 dx=-0.75,
					})
					_y += 10.5
				else
					_y += 12
					add(npcs,flower{
					 juice=80,
					 x=scrnrt,
					 y=_y,
					 dx=-0.75,
					})
					_y += 22
				end
			end
			nsoverride = 50
		elseif (actorseed < 0.2
		 or pc.juice < 60
		) then
			local _yf=scrntp+flr(rnd(scrnbt-scrntp-12))
			local _ys = _yf-(scrnbt-scrntp)/2
			if _ys < scrntp then
				_ys += scrnbt-scrntp-8
			end
			local _dy=0.5*(flr(rnd(3))-1)
			add(npcs,flower{
			 juice=80,
			 x=scrnrt,
			 y=_yf,
			 dx=-0.75,
			 dy=_dy,
			})
			add(npcs,spike{
			 x=scrnrt,
			 y=_ys,
			 dx=-0.75,
			 dy=_dy,
			})
		elseif actorseed < 0.54 then
			local _h=scrntp+flr(rnd(scrnbt-scrntp-18))
			local _dy=0.5*(flr(rnd(3))-1)
			add(npcs,spike{
			 x=scrnrt,
			 y=_h,
			 dx=-0.75,
			 dy=_dy,
			})
			add(npcs,spike{
			 x=scrnrt,
			 y=_h+10,
			 dx=-0.75,
			 dy=_dy,
			})
		elseif actorseed < 0.6 then
			nsoverride=50
			asoverride='spkwall'
		else
			local _h = 28+flr(rnd(15+4*_lvl))
			add(npcs,block{
			 x=scrnrt,
			 y=scrntp+flr(rnd(scrnbt-scrntp-_h)),
			 dx=-0.75,
			 w=3,
			 h=_h,
			 dy=0.5*(flr(rnd(3))-1),
			})
		end
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
					local jcmult = 19+_lvl
					if self.juice < 300 then
						n.juice-=jcmult/20
						self.juice+=jcmult/10
					else
						n.juice-=jcmult/40
						self.juice+=jcmult/20
					end
				elseif not n.depleted then
					n.depleted = true
					signal('score',{
					 score=2+_lvl,
					})
				end
			elseif n.name=='lvl' and not n.hit then
				n.hit = true
				n.clr = 11
				self.juice=min(self.juice+100,300)
				_score += 5*n.lvl-5
				_lvl = n.lvl
				sfx(3,1)
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
			self.juice = 0
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
		_lvl = 1
		_tonextscore = mns[_lvl]
		_fsm = 'game'
		_score = 0
		_time = 0
		nextspawn = 0
		nsoverride = nil
		actorseed = rnd(1)
		asoverride = nil
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
			add(npcs,lvlline{
			 x=scrnrt,
			 lvl=lvls[_time],
			 dx=-0.5-0.05*_lvl,
			})
		end
		_tonextscore -= 1
		if _tonextscore <= 0 then
			_score += 1
			_tonextscore = mns[_lvl]
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
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222111111111111111111111111111111111122222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222111111111111111111111111111111111122222222222222222222222222222222222222222222222
2222222222222222222222222222222222222222222222211bb11bb11aa11aa11999999118888881122222222222222222222222222222222222222222222222
2222222222222222222222222222222222222222222222211bb11bb11aa11aa11999999118888881122222222222222222222222222222222222222222222222
2222222222222222222222222222222222222222222222211bb11bb11aa11aa11999999118888881122222222222222222222222222222222222222222222222
2222222222222222222222222222222222222222222222211bb11bb11aa11aa11999999118888881122222222222222222222222222222222222222222222222
2222222222222222222222222222222222222222222222211bbbbbb11aa11aa11991199118811881122222222222222222222222222222222222222222222222
2222222222222222222222222222222222222222222222211bbbbbb11aa11aa11991199118811881122222222222222222222222222222222222222222222222
2222222222222222222222222222222222222222222222211bb11bb11aa11aa11991199118811881122222222222222222222222222222222222222222222222
2222222222222222222222222222222222222222222222211bb11bb11aa11aa11991199118811881122222222222222222222222222222222222222222222222
2222222222222222222222222222222222222222222222211bb11bb1111aaaa11991199118811881122222222222222222222222222222222222222222222222
2222222222222222222222222222222222222222222222211bb11bb1111aaaa11991199118811881122222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222111111111111111111111111111111111122222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222111111111111111111111111111111111122222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222221111111111111111111111111111111111111111111111111111111111111111122222222222222222222222222222222
22222222222222222222222222222221aaa1aaa1aaa11aa11aa11111aaa1aa11a1a11111aaa1a1a1aaa1aaa11aa1aa1122222222222222222222222222222222
22222222222222222222222222222221a1a1a1a1a111a111a1111111a1a1a1a1a1a11111a1a1a1a11a111a11a1a1a1a122222222222222222222222222222222
22222222222222222222222222222221aaa1aa11aa11aaa1aaa11111aaa1a1a1aaa11111aa11a1a11a111a11a1a1a1a122222222222222222222222222222222
22222222222222222222222222222221a111a1a1a11111a111a11111a1a1a1a111a11111a1a1a1a11a111a11a1a1a1a122222222222222222222222222222222
22222222222222222222222222222221a111a1a1aaa1aa11aa111111a1a1a1a1aaa11111aaa11aa11a111a11aa11a1a122222222222222222222222222222222
22222222222222222222222222222221111111111111111111111111111111111111111111111111111111111111111122222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222

__sfx__
000305000d050140501a0501e05021050220000400004000250000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00030014264201f4201a4201642012420104200f4200e4200e4200c4000c4000c4003b4003b4003b4000040000400004000040000400004000040000400004000040000400004000040000400004000040000400
002002002513021130211002110021100211000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
0004040022130221302e1302e13035100271002710027100291000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
0004040022050220502e0502e05000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
