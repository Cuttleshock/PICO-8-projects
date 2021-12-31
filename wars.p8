pico-8 cartridge // http://www.pico-8.com
version 32
__lua__
-- magic numbers

k_animspeed = 20
k_tilesize = 16
k_max_unit_hp = 100
k_damage_scale = 50
k_city_heal = 20
k_city_income = 10
k_max_funds = 9990
k_capture_max = 20
-- divides 1~10, 12, 14, 15:
k_timermax = 2*3*2*5*7*2*3

-- 'enums'
STATE_G_MAIN_MENU=1
STATE_G_BATTLE=2

FACTION_RED=1001
FACTION_BLUE=1002
FACTION_GREEN=1003
FACTION_YELLOW=1004

faction_colours={
	[FACTION_RED]=8,
	[FACTION_BLUE]=12,
	[FACTION_GREEN]=11,
	[FACTION_YELLOW]=10,
}

faction_names={
	[FACTION_RED]='red',
	[FACTION_BLUE]='blue',
	[FACTION_GREEN]='green',
	[FACTION_YELLOW]='yello',
}

MOVE_SLIME=2001
MOVE_SKEL=2002

ATK_SLIME=3001
ATK_SKEL=3002

DEF_SLIME=4001
DEF_SKEL=4002

-- sprite flags for each terrain
TERRAIN_PLAINS=0b1
TERRAIN_MOUNTAIN=0b10
TERRAIN_CITY=0b11
TERRAIN_HQ=0b100

-- sprite ref for city, to allow replacing a captured HQ
SPRITE_CITY=37

-- sprite ref for factory, to allow building
-- w/o needing a separate bitmask from city
SPRITE_FACTORY=41

-- todo: replace these with nifty, nasty bitfields
terrain_cost={
	[TERRAIN_PLAINS]={
		[MOVE_SLIME]=1,
		[MOVE_SKEL]=1,
	},
	[TERRAIN_MOUNTAIN]={
		[MOVE_SLIME]=2,
		[MOVE_SKEL]=2,
	},
	[TERRAIN_CITY]={
		[MOVE_SLIME]=1,
		[MOVE_SKEL]=1,
	},
	[TERRAIN_HQ]={
		[MOVE_SLIME]=1,
		[MOVE_SKEL]=1,
	},
}

terrain_def={
	[TERRAIN_PLAINS]=1,
	[TERRAIN_MOUNTAIN]=3,
	[TERRAIN_CITY]=2,
	[TERRAIN_HQ]=3,
}

capturable={
	[TERRAIN_CITY]=true,
	[TERRAIN_HQ]=true,
}

damage_table={
	[ATK_SLIME]={
		[DEF_SLIME]=1.1,
		[DEF_SKEL]=1.2,
	},
	[ATK_SKEL]={
		[DEF_SLIME]=0.7,
		[DEF_SKEL]=1,
	},
}

-- units
actor_metatable = {
	__index=(function(t,k)
		return rawget(t,k) or rawget(t,'base')[k]
	end),
}

pointer_base = {
	spr=1,
	frames=2,
}

slime_base = {
	spr=5,
	frames=2,
	range=3,
	captures=false,
	movetype=MOVE_SLIME,
	atk=ATK_SLIME,
	def=DEF_SLIME,
	name='slime',
	cost=60,
}

skel_base = {
	spr=9,
	frames=2,
	range=3,
	captures=true,
	movetype=MOVE_SKEL,
	atk=ATK_SKEL,
	def=DEF_SKEL,
	name='skel',
	cost=20,
}

land_units = {
	skel_base,
	slime_base,
}

-- menus
function noop() end
function truthy_noop() return true end

main_menu = {
	{ text='battle', cb=(function () push_game_state(STATE_G_BATTLE, init_battle) end) },
	{ text='nothing', cb=noop, stay=true },
	{ text='also no', cb=noop, stay=true },
	sticky=true,
}

battle_menu = {
	{ text='nope', cb=noop, stay=true },
	{ text='cool stats', cb=noop, stay=true },
	{ text='exit to menu', cb=(function () push_game_state(STATE_G_MAIN_MENU, init_main_menu) end) },
	{ text='end turn', cb=(function () end_turn() end) },
}

menuitem_move = { text='move', cb=(function () move_highlighted_unit() end) }
menuitem_attack = { text='attack', cb=(function() target_highlighted_unit() end) }
menuitem_capture = { text='capture', cb=(function() capture_highlighted_unit() end) }

debug = {_names={}}
function d_(str)
	add(debug,tostr(str))
	if (#debug > 12) deli(debug,1)
end

function popd_()
	cursor(cam_x*k_tilesize,cam_y*k_tilesize)
	for d in all(debug) do
		print(d)
	end
end

-- sadly O(n)
function last(t,k_curr)
	local k_last=nil
	for k,v in pairs(t) do
		if (k==k_curr) break
		k_last=k
	end
	return k_last,t[k_last]
end

-->8
-- state and update methods

-- state control
game_state=STATE_G_MAIN_MENU
state_coro_=nil

-- global state
menu_item=1
active_menu={}

anim_coro_=nil

timer=0

-- battle-specific state
units={}
properties={}

pointer={}
highlight={}
path={ cost=0 }
targets={}
battle_factions={}
faction_funds={}
active_faction=0
battle_turn=0

map_w=0
map_h=0
cam_x=0
cam_y=0

function init_main_menu()
	active_menu.ref=main_menu
	active_menu.x=40
	active_menu.y=20
	active_menu.w=48
	menu_item=1
end

function init_battle()
	start_animation(truthy_noop, noop)
	units={}
	properties={
		[xy2n(7,2)]=FACTION_RED,
		[xy2n(3,2)]=FACTION_BLUE,
		[xy2n(9,6)]=FACTION_GREEN,
		[xy2n(3,8)]=FACTION_YELLOW,
	}
	init_pointer(3,3)
	update_camera()
	battle_factions={ FACTION_RED, FACTION_BLUE, FACTION_GREEN, FACTION_YELLOW }
	faction_funds={
		[FACTION_RED]=0,
		[FACTION_BLUE]=0,
		[FACTION_GREEN]=0,
		[FACTION_YELLOW]=0,
	}
	battle_turn=0
	active_faction=0
	make_unit(7,5,FACTION_RED,slime_base)
	make_unit(4,6,FACTION_RED,skel_base)
	make_unit(5,4,FACTION_BLUE,slime_base)
	make_unit(4,4,FACTION_BLUE,skel_base)
	make_unit(8,3,FACTION_GREEN,slime_base)
	make_unit(9,4,FACTION_GREEN,skel_base)
	make_unit(3,7,FACTION_YELLOW,slime_base)
	make_unit(4,8,FACTION_YELLOW,skel_base)
	highlight={}
	path={ cost=0 }
	map_w=16
	map_h=16
	end_turn()
end

function init_pointer(x,y)
	pointer.x = x
	pointer.y = y
	pointer.base=pointer_base
	setmetatable(pointer, actor_metatable)
end

function make_unit(x,y,faction,base)
	local unit = {
		x=x,
		y=y,
		hp=k_max_unit_hp,
		faction=faction,
		base=base,
		moved=false,
	}
	setmetatable(unit, actor_metatable)
	add(units, unit)
	return unit -- to allow further tweaks
end

function delete_unit(unit)
	del(units, unit)
	check_faction_defeated(unit.faction)
end

-- serialised data structure (no. bits):
-- x y cost unused
-- 8 8 4    12
-- needed to write highlight
function xy2n(x,y,cost)
	cost = cost or 0
	return ((x & 0xff) << 8) | (y & 0xff) | ((cost & 0xf) >> 4)
end

-- needed to iterate through highlight and read paths
function n2xy(n)
	n = n or 0xffff.f
	return (n >> 8) & 0xff, n & 0xff, (n & 0x0.f) << 4
end

function get_mvmt(unit,x,y)
	if 0<=x and x<=map_w and 0<=y and y<=map_h then
		return terrain_cost[fget(mget(x*2,y*2))][unit.movetype] or 0xff
	else
		return 0xff -- "too big"
	end
end

function get_defence(x,y)
	return terrain_def[fget(mget(x*2,y*2))] or 0
end

function highlight_range(u)
	-- clear, then init w/ starting location
	path={ cost=0 }
	highlight = { unit=u }
	search = { xy2n(u.x,u.y) }
	highlight[xy2n(u.x,u.y)] = xy2n(0xff,0xff,0)
	local enemy_tiles={}
	for u1 in all(units) do
		if (u1.faction!=u.faction) enemy_tiles[xy2n(u1.x,u1.y)]=true
	end
	-- depth-first search
	while search[1] do
		local x,y = n2xy(search[1])
		local _,_,cost = n2xy(highlight[search[1]])
		for tab in all({{x+1,y},{x,y+1},{x-1,y},{x,y-1}}) do
			local x1,y1 = tab[1],tab[2]
			local mvmt = get_mvmt(u,x1,y1)
			local cost1 = cost + mvmt
			if (enemy_tiles[xy2n(x1,y1)]) cost1+=0xff -- ugly but safe
			local _,_,cost2 = n2xy(highlight[xy2n(x1,y1)])
			if cost1 < cost2 and cost1 <= u.range then
				highlight[xy2n(x1,y1)] = xy2n(x,y,cost1)
				if cost1 < u.range then -- strict <
					add(search, xy2n(x1,y1))
				end
			end
		end
		deli(search,1)
	end
end

function end_turn(cb)
	active_faction=active_faction%#battle_factions + 1
	if (active_faction==1) battle_turn+=1
	for u in all(units) do
		u.moved=false
		if u.faction==battle_factions[active_faction] and u.faction==properties[xy2n(u.x,u.y)] then
			u.hp = min(u.hp+k_city_heal, k_max_unit_hp)
		end
	end
	for n,f in pairs(properties) do
		if f==battle_factions[active_faction] then
			local newfunds=faction_funds[battle_factions[active_faction]]+k_city_income
			faction_funds[battle_factions[active_faction]]=min(newfunds,k_max_funds)
		end
	end
	start_animation(truthy_noop, cb or noop)
end

function make_factory_menu()
	local ret={}
	for u in all(land_units) do
		local text=(u.name..' g'..tostr(u.cost)..'0')
		if faction_funds[battle_factions[active_faction]]>=u.cost then
			add(ret,{
				text=text,
				cb=(function ()
					faction_funds[battle_factions[active_faction]]-=u.cost
					make_unit(pointer.x,pointer.y,battle_factions[active_faction],u).moved=true
				end),
			})
		else
			add(ret,{
				text=text,
				cb=noop,
				stay=true,
			})
		end
	end
	return ret
end

function close_menu()
	active_menu.ref=nil
	menu_item=1
end

function control_menu()
	if btnp(🅾️) then
		active_menu.ref[menu_item].cb()
		if (not active_menu.ref[menu_item].stay) close_menu()
		return
	elseif btnp(❎) and not active_menu.ref.sticky then
		return close_menu()
	end

	local dm = 0
	if btnp(⬇️) then
		dm=1
	elseif btnp(⬆️) then
		dm=-1
	end

	if dm != 0 then
		sfx(3)
		menu_item=(menu_item+dm-1)%#active_menu.ref+1
	end
end

function update_timer()
	timer=(timer+1)%k_timermax
end

-- todo: doesn't quite feel right - try
-- chording ⬆️ -> ⬆️➡️, and ➡️ -> ➡️⬆️.
-- requires keeping track of 'lead' direction...
function move_pointer()
	local dx,dy=0,0
	local updown = btn(⬆️) or btn(⬇️)

	if btnp(⬇️) then
		dy = 1
	elseif not btn(⬇️) and btnp(⬆️) then
		dy = -1
	end

	-- if holding up/down, keep left/right
	-- mvmt in sync with btnp(up/down)
	if updown then
		if dy == 0 then
			dx = 0
		elseif btn(➡️) then
			dx = 1
		elseif btn(⬅️) then
			dx = -1
		end
	elseif btnp(➡️) then
		dx = 1
	elseif not btn(➡️) and btnp(⬅️) then
		dx = -1
	end

	-- keep from leaving map
	if (pointer.x+dx<0 or pointer.x+dx>=map_w) dx=0
	if (pointer.y+dy<0 or pointer.y+dy>=map_h) dy=0

	if dx != 0 or dy != 0 then
		pointer.x += dx
		pointer.y += dy
		sfx(1)
	end
end

function move_highlighted_unit(cb)
	move_unit(highlight.unit, pointer.x, pointer.y, cb)
	highlight.unit.moved=true
	highlight={}
end

function move_unit(unit, x, y, cb)
	if (unit.sfx) sfx(unit.sfx)

	unit.invisible=true

	start_animation(
		animate_unit_move_frame,
		(function()
			unit.invisible,unit.x,unit.y=false,x,y
			if (cb) cb()
		end),
		unit,path,0
	)
end

function list_targets_from(unit,x,y)
	local locations={
		[xy2n(x+1,y)]=true,
		[xy2n(x,y+1)]=true,
		[xy2n(x-1,y)]=true,
		[xy2n(x,y-1)]=true,
	}
	local ret={}
	for u in all(units) do
		if (u.faction!=unit.faction and locations[xy2n(u.x,u.y)]) ret[xy2n(u.x,u.y)]=u
	end
	return ret
end

function target_highlighted_unit()
	targets=list_targets_from(highlight.unit,pointer.x,pointer.y)
	pointer.x,pointer.y=n2xy(next(targets))
end

function control_targets()
	local n=xy2n(pointer.x,pointer.y)
	if btnp(➡️) or btnp(⬇️) then
		pointer.x,pointer.y=n2xy(next(targets,n) or next(targets))
	elseif btnp(⬅️) or btnp(⬆️) then
		pointer.x,pointer.y=n2xy(last(targets,n) or last(targets))
	elseif btnp(🅾️) then
		local unit = highlight.unit -- need reference after highlight cleared
		pointer.x,pointer.y=n2xy(path[#path] or xy2n(unit.x,unit.y)) -- if attacked from standing position
		move_highlighted_unit(function() attack(unit, targets[n]) end)
	elseif btnp(❎) then
		targets={}
		pointer.x,pointer.y=n2xy(path[#path])
	end
end

function capture_highlighted_unit()
	local unit=highlight.unit -- keep reference after highlight cleared
	move_highlighted_unit(function() capture(unit) end)
end

function damage(u1,u2)
	local dmg = k_damage_scale
	dmg *= (1+rnd(0.1))
	dmg *= ceil(u1.hp*5/k_max_unit_hp)/5
	dmg *= damage_table[u1.atk][u2.def]
	dmg *= (1-get_defence(u2.x,u2.y)/10)
	u2.hp -= flr(dmg)
end

function attack(attacker, defender)
	start_animation(
		animate_skirmish_frame,
		(function()
			targets={}
			damage(attacker, defender)
			if defender.hp>0 then
				damage(defender, attacker)
				if (attacker.hp<=0) delete_unit(attacker)
			else
				delete_unit(defender)
			end
		end),
		attacker,defender,0
	)
end

function capture(unit)
	if (not unit.capture_count) unit.capture_count=k_capture_max
	unit.capture_count-=ceil(unit.hp*10/k_max_unit_hp)
	local cb,old_faction=noop,properties[xy2n(unit.x,unit.y)]

	if unit.capture_count<=0 then
		properties[xy2n(unit.x,unit.y)]=unit.faction
		unit.capture_count=nil
		if fget(mget(unit.x*2,unit.y*2))==TERRAIN_HQ then
			mset(unit.x*2,unit.y*2,SPRITE_CITY)
			mset(unit.x*2+1,unit.y*2,SPRITE_CITY+1)
			mset(unit.x*2,unit.y*2+1,SPRITE_CITY+16)
			mset(unit.x*2+1,unit.y*2+1,SPRITE_CITY+17)
			cb=(function() clear_faction(old_faction) end)
		end
	end

	start_animation(
		animate_property_capture_frame,
		cb,
		unit,0
	)
end

function control_battle()
	if animation_in_progress() then
		if btnp(🅾️) or btnp(❎) then
			end_animation()
		end
	elseif active_menu.ref then
		return control_menu()
	elseif next(targets) then
		return control_targets()
	else
		if btnp(🅾️) then
			sfx(2)
			local unit = nil
			for u in all(units) do
				if u.x==pointer.x and u.y==pointer.y then
					unit = u
					break
				end
			end
			if highlight[xy2n(pointer.x,pointer.y)] then
				if highlight.unit.faction==battle_factions[active_faction] then
					if not unit or unit==highlight.unit then
						active_menu.ref={ menuitem_move }
						if next(list_targets_from(highlight.unit,pointer.x,pointer.y)) then
							add(active_menu.ref, menuitem_attack, 1)
						end
						if highlight.unit.captures and ((properties[xy2n(pointer.x,pointer.y)] and properties[xy2n(pointer.x,pointer.y)]!=highlight.unit.faction) or (not properties[xy2n(pointer.x,pointer.y)] and capturable[fget(mget(pointer.x*2,pointer.y*2))])) then
							add(active_menu.ref, menuitem_capture, 1)
						end
						active_menu.y=1
						active_menu.w=40
						active_menu.x=126-active_menu.w
					elseif unit and not unit.moved then
						highlight_range(unit)
					end
				else
					if unit and not unit.moved then
						highlight_range(unit)
					else
						highlight={}
					end
				end
			elseif unit and not unit.moved then
				highlight_range(unit)
			elseif not unit and properties[xy2n(pointer.x,pointer.y)]==battle_factions[active_faction] and mget(pointer.x*2,pointer.y*2)==SPRITE_FACTORY then
				highlight={}
				active_menu.ref=make_factory_menu()
				active_menu.x=1
				active_menu.y=1
				active_menu.w=60
			else
				highlight={}
				active_menu.ref=battle_menu
				active_menu.x=1
				active_menu.y=1
				active_menu.w=60
			end
		elseif btnp(❎) then
			highlight={}
		else
			move_pointer()
		end
	end
end

-- need to run this after moving pointer
-- to prevent jumpiness
function update_camera()
	-- move camera right/left
	if pointer.x < cam_x+2 then
		cam_x = max(0,cam_x-0.5)
	elseif pointer.x > cam_x+5 then
		cam_x = min(map_w-8,cam_x+0.5)
	end
	-- move camera up/down
	if pointer.y < cam_y+2 then
		cam_y = max(0,cam_y-0.5)
	elseif pointer.y > cam_y+5 then
		cam_y = min(map_h-8,cam_y+0.5)
	end
end

-- assumes highlight is initialised
-- assumes loc is in highlight but not in path
-- does _not_ assume loc is not on unit
function can_append(loc)
	local xloc,yloc=n2xy(loc)
	local xend,yend=highlight.unit.x,highlight.unit.y
	if (xend==xloc and yend==yloc) return false

	if #path > 0 then
		xend,yend=n2xy(path[#path])
	end

	-- must be adjacent to end of path
	if (abs(xloc-xend)+abs(yloc-yend)!=1) return false
	-- total cost must be within mvmt
	return path.cost+get_mvmt(highlight.unit,xloc,yloc)<=highlight.unit.range
end

function find_on_path(loc)
	local x,y=n2xy(loc)
	for i=1,#path do
		local x1,y1=n2xy(path[i])
		if xy2n(x1,y1)==loc then
			return i
		end
	end
	return nil
end

function update_path()
	local x,y=pointer.x,pointer.y
	local n=xy2n(x,y)

	if not highlight.unit then
		path={ cost=0 }
		return
	elseif not highlight[n] then
		return
	end

	-- integer or nil
	local i=find_on_path(n)
	if i then
		for j=i+1,#path do
			local xp,yp = n2xy(path[j])
			path.cost -= get_mvmt(highlight.unit,xp,yp)
			path[j] = nil
		end
	elseif can_append(n) then
		add(path, n)
		path.cost += get_mvmt(highlight.unit,x,y)
	else
		path = { cost=0 }
		local curr,next=n,highlight[n]
		local xn=n2xy(next)
		while xn!=0xff do
			add(path, curr, 1)
			path.cost+=get_mvmt(highlight.unit,x,y)
			x,y=n2xy(next)
			curr,next=next,highlight[xy2n(x,y)]
			xn=n2xy(next)
		end
	end
end

-- currently only supports defeat by rout
function check_faction_defeated(faction)
	for u in all(units) do
		if (u.faction==faction) return
	end
	-- all units are gone
	clear_faction(faction)
end

function clear_faction(faction)
	-- unnecessary if all units are gone, but this
	-- future-proofs for alternative win conditions
	for u in all(units) do
		if (u.faction==faction) del(units,u)
	end

	for n,f in pairs(properties) do
		if f==faction then
			properties[n]=nil
			local x,y=n2xy(n)
			if fget(mget(x*2,y*2))==TERRAIN_HQ then
				mset(x*2,y*2,SPRITE_CITY)
				mset(x*2+1,y*2,SPRITE_CITY+1)
				mset(x*2,y*2+1,SPRITE_CITY+16)
				mset(x*2+1,y*2+1,SPRITE_CITY+17)
			end
		end
	end

	local n
	for i,f in pairs(battle_factions) do
		if f==faction then
			n=i
			break
		end
	end

	if #battle_factions==2 then
		-- battle is over, declare victory for not-n
		end_battle(battle_factions[3-n])
	elseif active_faction<n then
		deli(battle_factions,n)
	elseif active_faction==n then
		end_turn(function ()
			deli(battle_factions,n)
			if (active_faction!=1) active_faction-=1
		end)
	else
		deli(battle_factions,n)
		active_faction-=1
	end
end

function end_battle(faction)
	start_animation(
		animate_battle_end_frame,
		(function() push_game_state(STATE_G_MAIN_MENU, init_main_menu) end),
		faction, 0
	)
end

-->8
-- draw methods

function on_screen()
	return true
end

function draw_properties()
	for n,f in pairs(properties) do
		local x,y=n2xy(n)
		if on_screen(x,y) then
			local sprite=mget(x*2,y*2)
			pal(6,faction_colours[f]) -- recolour light-grey
			spr(sprite,x*k_tilesize,y*k_tilesize,2,2)
			pal()
		end
	end
end

function draw_highlight(h)
	local sprite = 16*(((timer%30)\10)+1)
	local x,y
	for n,_ in pairs(h or highlight) do
		if type(n)!='string' then
			x,y=n2xy(n)
			spr(sprite,x*k_tilesize,y*k_tilesize)
			spr(sprite,(x+0.5)*k_tilesize,y*k_tilesize)
			spr(sprite,x*k_tilesize,(y+0.5)*k_tilesize)
			spr(sprite,(x+0.5)*k_tilesize,(y+0.5)*k_tilesize)
		end
	end
end

function draw_path()
	for n in all(path) do
		local x,y=n2xy(n)
		rectfill(x*16+5,y*16+5,x*16+10,y*16+10)
	end
end

function draw_actor(a)
	if (a.invisible or not on_screen(a.x,a.y)) return

	local frame = timer%(a.frames*k_animspeed)\k_animspeed
	if a.moved then
		pal(8,5) -- grimy olive brown
	elseif a.faction then
		pal(8,faction_colours[a.faction])
	end
	spr(a.spr+2*frame,a.x*k_tilesize,a.y*k_tilesize,2,2)
	pal()

	if a.hp then
		local display_hp=ceil(a.hp*10/k_max_unit_hp)
		if display_hp<10 then
			local x1,y1=(a.x+1)*k_tilesize-1,(a.y+1)*k_tilesize-1
			rectfill(x1-4,y1-6,x1,y1,0) -- black
			print(display_hp,x1-3,y1-5,7) -- white
		end
	end

	if a.capture_count then
		local x0,y0=a.x*k_tilesize,a.y*k_tilesize
		local x1 = a.capture_count>=10 and x0+8 or x0+4
		rectfill(x0,y0,x1,y0+6,0) -- black
		print(a.capture_count,x0+1,y0+1,5) -- olive
	end
end

function draw_units()
	for a in all(units) do
		draw_actor(a)
	end
end

function draw_targets()
	pal(12,14) -- blue to pink
	draw_highlight(targets)
	pal()
end

function draw_faction()
	local x1,y0=cam_x*k_tilesize+128,cam_y*k_tilesize
	rectfill(x1-25,y0,x1,y0+6,faction_colours[battle_factions[active_faction]])
	print('day '..battle_turn%100,x1-24,y0+1,7) -- white

	rectfill(x1-27,y0+7,x1,y0+13,6) -- light grey
	print('g',x1-26,y0+8,0) -- black
	local str=tostr(faction_funds[battle_factions[active_faction]])
	if (faction_funds[battle_factions[active_faction]]>0) str=str..'0'
	print(str,x1-20,y0+8)
end

function draw_menu()
	if (not active_menu.ref) return

	local x,y,w=active_menu.x+cam_x*k_tilesize,active_menu.y+cam_y*k_tilesize,active_menu.w

	rectfill(x+2,y+2,x+w-2,y+1+#active_menu.ref*8,13) -- lilac
	rect(x,y,x+w,y+3+#active_menu.ref*8,7) -- white

	for i=1,#active_menu.ref do
		if menu_item==i then
			rectfill(x+2,y-6+i*8,x+w-2,y+1+i*8,2) -- burgundy
			print(active_menu.ref[i].text,x+3,y-5+i*8,10) -- yellow
		else
			print(active_menu.ref[i].text,x+3,y-4+i*8,7) -- white
		end
	end
end

function animate_skirmish_frame(attacker,defender,frame)
	return true -- todo
end

function animate_property_capture_frame(unit,frame)
	return true -- todo
end

function animate_unit_move_frame(unit,path,frame)
	local n=(frame\4)
	local k=(frame%4)/4

	-- path doesn't include unit's location
	local x1,y1=unit.x,unit.y
	if (n>0) x1,y1=n2xy(path[n])
	local x2,y2=n2xy(path[n+1])
	local x=k*x2+(1-k)*x1
	local y=k*y2+(1-k)*y1

	pal(8,faction_colours[unit.faction])
	spr(unit.spr,x*k_tilesize,y*k_tilesize,2,2)
	pal()

	return (n>=#path),unit,path,frame+1
end

function animate_battle_end_frame(faction, frame)
	local x0,y0=cam_x*k_tilesize+30,cam_y*k_tilesize+24
	rectfill(x0,y0,x0+68,y0+19,faction_colours[faction])
	print('\^w\^t'..faction_names[faction]..' wins',x0+2,y0+5,15) -- cream

	return false,faction,frame+1
end

function init_state_coro_()
	state_coro_ = cocreate(function(state,cb)
		while true do
			local state_,cb_=yield()
			if state then
				game_state=state
				cb()
			end
			state,cb=state_,cb_
		end
	end)
	coresume(state_coro_)
end

function push_game_state(state, cb)
	coresume(state_coro_, state, cb)
end

function pop_game_state()
	coresume(state_coro_)
end

function start_animation(cb, on_exit, ...)
	anim_coro_ = cocreate(function(...)
		local complete,args=false,{...}
		while not complete and not yield() do
			-- feels like there must be a one-liner
			-- for the inner loop...
			local ret = { cb(unpack(args)) }
			complete,args=ret[1],{ select(2,unpack(ret)) }
		end
		on_exit()
	end)
	assert(coresume(anim_coro_, ...))
end

function animation_in_progress()
	return costatus(anim_coro_)!='dead'
end

function end_animation()
	if (animation_in_progress()) assert(coresume(anim_coro_,true))
end

function animate()
	if (animation_in_progress()) assert(coresume(anim_coro_,false))
end

-->8
-- init, update, draw

function _init()
	init_state_coro_()
	anim_coro_=cocreate(noop)
	init_main_menu()
end

function _update()
	update_timer()
	if game_state==STATE_G_MAIN_MENU then
		control_menu()
	elseif game_state==STATE_G_BATTLE then
		control_battle()
		update_path()
		update_camera()
	end
	pop_game_state()
end

function _draw()
	cls(3)
	camera(cam_x*k_tilesize,cam_y*k_tilesize)
	map()
	if game_state==STATE_G_MAIN_MENU then
		cls(5)
	elseif game_state==STATE_G_BATTLE then
		draw_properties()
		draw_highlight()
		draw_path()
		draw_units()
		draw_targets()
		draw_actor(pointer)
		draw_faction()
	end
	draw_menu()
	animate()
	popd_()
end

__gfx__
00000000000000000000000077000000000000770000000000000000000000000000000000010000000000000017101110010000000000000000000000000000
00000000077000000000077070000000000000070000000000000000000000000000000000171011100100000017118881171000000000000000000000000000
00000000070000000000007000000000000000000000000000000000000001111110000000171188811710000017788888771000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000018888881000000177888887710000017788888771000000000000000000000000000
00000000000000000000000000000000000000000000001111000000000018778888100000177888887710000001888888810100000000000000000000000000
00000000000000000000000000000000000000000000018888100000000188778888100000018888888101000001871771711610000000000000000000000000
00000000000000000000000000000000000000000000187788810000000188888888100000018717717116100001777777711610000000000000000000000000
00000000000000000000000000000000000000000000187788881000000188888888810000017777777116100011177777101610000000000000000000000000
0c000c00000000000000000000000000000000000001888888888100001888888888810000111777771016100188811111101610000000000000000000000000
c000c000000000000000000000000000000000000018888888888100001888888888881001888111110016101888887777718881000000000000000000000000
000c000c000000000000000000000000000000000018888888888810018888888888881018888817771188811888887711177810000000000000000000000000
00c000c0000000000000000000000000000000000188888888888810188888888888888118888877717778100188871111711810000000000000000000000000
0c000c00000000000000000000000000000000001888888888888881188888888888888101888711117118100011177777710100000000000000000000000000
c000c000070000000000007000000000000000001111111111111111111111111111111100111777771001000000171017100000000000000000000000000000
000c000c077000000000077070000000000000070000000000000000000000000000000000001710171100000000171017110000000000000000000000000000
00c000c0000000000000000077000000000000770000000000000000000000000000000000017771177710000001777117771000000000000000000000000000
c000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c000c0000000077700000000000000000000000000000000000000000000666600000000000000dd000000000000000000000000000000000000000000000
00c000c00000000777700000000000000000000000000000666610000000000666600000000066666dd666600000000000000000000000000000000000000000
0c000c0000000007777700000000bbb00000000000000006666661000000000666600000000066666dd666600000000000000000000000000000000000000000
c000c000000000777766000000bb00bb0000000000000066666666100000000700000000000666666dd666400000000000000000000000000000000000000000
000c000c0000006666660000000000000000000000066661666666610dd10dd70dd10dd100066666666666400000000000000000000000000000000000000000
00c000c00000066666660000000000000000000000666666144441000dd10dd70dd10dd100666666666660400000000000000000000000000000000000000000
0c000c00000006666666000000000000000bbb0006666666614dd1000dddddddddddddd1004444110dd040400000000000000000000000000000000000000000
00c000c000000666666660000000000000bb0bb066666666661dd1000dddddddddddddd1004444110dd040400000000000000000000000000000000000000000
0c000c00000006666666600000000000000000000044444419944100000dddddddddd100004444110dd040400000000000000000000000000000000000000000
c000c0000000066666666000000000000000000000dd44dd19944100000dddddddddd100004444110dd040400000000000000000000000000000000000000000
000c000c000066666666600000000000b000000000dd44dd19944100000dddd66dddd10000444410dddd40000000000000000000000000000000000000000000
00c000c00006666666666000000000bb0bb000000044994410000000000ddd6666ddd10000444410d99d40000000000000000000000000000000000000000000
0c000c00000666666666600000000bb000b000000044994410000000000ddd6666ddd10000444400dddd40000000000000000000000000000000000000000000
c000c000006666666666660000000000000000000044994410000000000ddd6666ddd10000000000000000000000000000000000000000000000000000000000
000c000c066666666666666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
0100000000000000000000000000000000000000000000000000000000000000000202010103030404030300000000000002020101030304040303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
2324000000000000232400000000000000000000000000000000212221222324000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3334000000000000333400000000000000000000000000000000313231323334000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000021222122000000002324232400002324000023242324212200002324000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000031323132000000003334333400003334000033343334313200003334000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000232400002728212221220000272821222122000023242122212223240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000333400003738313231320000373831323132000033343132313233340000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000023242526000000002526232400002122232400002526252600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000033343536000000003536333400003132333400003536353600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000232400002324232400002324000023242324000000002324232400002324000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000333400003334333400003334000033343334000000003334333400003334000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00002324000000000000292a0000000000002324000000000000000021222122000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00003334000000000000393a0000000000003334000000000000000031323132000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2324232400000000000023240000000023242728000000002122212221220000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3334333400000000000033340000000033343738000000003132313231320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000002324232400000000252625262122252600002122000023240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000003334333400000000353635363132353600003132000033340000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2122252600002728000000000000252621222526252623240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3132353600003738000000000000353631323536353633340000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2122252623242324252623240000232421220000000023240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3132353633343334353633340000333431320000000033340000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2122212221220000000000000000000000002324232400000000232423242324000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3132313231320000000000000000000000003334333400000000333433343334000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2122212200002324000000000000000000000000000023240000232400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3132313200003334000000000000000000000000000033340000333400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2122212200002324000000002324232423240000000000002122212200002324000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3132313200003334000000003334333433340000000000003132313200003334000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2122000023240000000023240000212221222122232421222122212221222122000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3132000033340000000033340000313231323132333431323132313231323132000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2122000023240000000021222122000021220000232400000000212221222122000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3132000033340000000031323132000031320000333400000000313231323132000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000002324000023240000232400000000000000002324000021222122000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000003334000033340000333400000000000000003334000031323132000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000600001f11013110001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
000600001d05020050210002200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000800002113021100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
