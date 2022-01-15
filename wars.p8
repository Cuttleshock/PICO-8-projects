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
k_mountain_vision = 5 -- how far a unit standing on a mountain sees
-- divides 1~10, 12, 14, 15:
k_timermax = 2*3*2*5*7*2*3

-- 'enums'
STATE_G_MAIN_MENU=1
STATE_G_BATTLE=2

-- TARGET_NONE ? see todo about resetting [targets]
TARGET_ATTACK=101
TARGET_UNLOAD=102

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
MOVE_WHEEL=2003

ATK_SLIME=3001
ATK_SKEL=3002
ATK_CATA=3003

DEF_SLIME=4001
DEF_SKEL=4002
DEF_CATA=4003
DEF_CART=4004

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
		[MOVE_WHEEL]=2,
	},
	[TERRAIN_MOUNTAIN]={
		[MOVE_SLIME]=2,
		[MOVE_SKEL]=2,
	},
	[TERRAIN_CITY]={
		[MOVE_SLIME]=1,
		[MOVE_SKEL]=1,
		[MOVE_WHEEL]=1,
	},
	[TERRAIN_HQ]={
		[MOVE_SLIME]=1,
		[MOVE_SKEL]=1,
		[MOVE_WHEEL]=1,
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
		[DEF_CATA]=1.3,
		[DEF_CART]=1.3,
	},
	[ATK_SKEL]={
		[DEF_SLIME]=0.7,
		[DEF_SKEL]=1,
		[DEF_CATA]=0.6,
		[DEF_CART]=0.5,
	},
	[ATK_CATA]={
		[DEF_SLIME]=1.6,
		[DEF_SKEL]=1.6,
		[DEF_CATA]=1.6,
		[DEF_CART]=1.6,
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
	vision=3,
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
	vision=2,
	captures=true,
	movetype=MOVE_SKEL,
	atk=ATK_SKEL,
	def=DEF_SKEL,
	name='skel',
	cost=20,
}

cata_base = {
	spr=43,
	frames=2,
	range=6,
	vision=2,
	ranged=true,
	r_min=2,
	r_max=4,
	movetype=MOVE_WHEEL,
	atk=ATK_CATA,
	def=DEF_CATA,
	name='cata',
	cost=80,
}

cart_base = {
	spr=64,
	frames=2,
	range=10,
	vision=3,
	carries={ [MOVE_SKEL]=true },
	carry_max=2,
	movetype=MOVE_WHEEL,
	def=DEF_CART,
	name='cart',
	cost=30,
}

land_units = {
	skel_base,
	cart_base,
	slime_base,
	cata_base,
}

-- menus
function noop() end
function truthy_noop() return true end

main_menu = {
	{ text='battle', cb=(function () push_game_state(STATE_G_BATTLE, init_battle) end) },
	{ text='load map', cb=noop, disabled=true },
	sticky=true,
}

battle_menu = {
	{ text='do nothing', cb=noop, disabled=true },
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

function has(t,v1)
	for _,v2 in pairs(t) do
		if (v2==v1) return true
	end
end

-->8
-- state and update methods

-- state control
game_state=STATE_G_MAIN_MENU
state_coro_=nil

-- global state
menu_stack={}

anim_coro_=nil

timer=0

-- battle-specific state
units={}
properties={}
visible={}

pointer={}
highlight={}
path={ cost=0 }
targets={}
target_type=TARGET_ATTACK
battle_factions={}
faction_funds={}
active_faction=0
battle_turn=0
fog=true

map_w=0
map_h=0
cam_x=0
cam_y=0

function init_main_menu()
	cam_x,cam_y=0,0
	camera()
	push_menu(main_menu,40,50,48,true)
end

function init_battle()
	start_animation(truthy_noop, noop)
	fog=true
	visible={}
	units={}
	properties={
		[xy2n(1,1)]=FACTION_RED,
		[xy2n(1,3)]=FACTION_RED,
		[xy2n(1,9)]=FACTION_BLUE,
		[xy2n(2,9)]=FACTION_BLUE,
		[xy2n(14,2)]=FACTION_GREEN,
		[xy2n(12,2)]=FACTION_GREEN,
		[xy2n(13,8)]=FACTION_YELLOW,
		[xy2n(12,8)]=FACTION_YELLOW,
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
	highlight={}
	path={ cost=0 }
	map_w=15
	map_h=10
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
	if (base.carries) unit.carrying={}
	setmetatable(unit, actor_metatable)
	add(units, unit)
	update_visible()
	return unit -- to allow further tweaks
end

function delete_unit(unit)
	del(units, unit)
	update_visible()
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

function update_visible()
	if (not fog) return

	local faction=battle_factions[active_faction]
	visible={}
	for p,f in pairs(properties) do
		if f==faction then
			local x,y=n2xy(p)
			visible[p]=mget(x*2,y*2)
		end
	end
	for u in all(units) do
		if u.faction==faction then
			local vision=u.vision
			if (fget(mget(u.x*2,u.y*2))==TERRAIN_MOUNTAIN and has(land_units,u.base)) vision=k_mountain_vision
			local vision_range=get_attack_range(u,u.x,u.y,0,vision)
			for r in pairs(vision_range) do
				local x,y=n2xy(r)
				visible[r]=mget(x*2,y*2)
			end
		end
	end
	-- second pass to render enemy units invisible
	for u in all(units) do
		u.invisible=(not visible[xy2n(u.x,u.y)])
	end
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
		if (u1.faction!=u.faction and not u1.invisible) enemy_tiles[xy2n(u1.x,u1.y)]=true
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
	if fog then
		local tmp=active_faction
		active_faction=0
		update_visible()
		active_faction=tmp
	end
	start_animation(
		animate_end_turn_frame,
		(function()
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
					local x,y=n2xy(n)
					if fget(mget(x*2,y*2))==TERRAIN_HQ then
						pointer.x,pointer.y=x,y
					end
				end
			end
			update_visible()
			if (cb) cb()
		end),
		0
	)
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

function push_menu(ref,x,y,w,sticky)
	add(menu_stack,{
		ref=ref,
		selected=1,
		sticky=sticky,
		x=x,
		y=y,
		w=w,
	})
end

function pop_menu()
	deli(menu_stack,#menu_stack)
end

function close_menu()
	menu_stack={}
end

function open_action_menu(sticky)
	local menu,x={ menuitem_move },86
	if next(list_targets_from(highlight.unit,pointer.x,pointer.y,TARGET_ATTACK)) then
		add(menu, menuitem_attack, 1)
	end
	if highlight.unit.captures and ((properties[xy2n(pointer.x,pointer.y)] and properties[xy2n(pointer.x,pointer.y)]!=highlight.unit.faction) or (not properties[xy2n(pointer.x,pointer.y)] and capturable[fget(mget(pointer.x*2,pointer.y*2))])) then
		add(menu, menuitem_capture, 1)
	end
	if can_unload_from(highlight.unit,pointer.x,pointer.y) then
		for u in all(highlight.unit.carrying) do
			x=min(x,98-4*#u.name)
			add(menu, make_unload_menuitem(u), 1)
		end
	end
	push_menu(menu,x,1,126-x,sticky)
end

function control_menu()
	local menu=menu_stack[#menu_stack]

	if btnp(🅾️) and not menu.ref[menu.selected].disabled then
		menu.ref[menu.selected].cb()
		if (not menu.ref[menu.selected].stay) close_menu()
		return
	elseif btnp(❎) and not menu.sticky then
		return pop_menu()
	end

	local dm = 0
	if btnp(⬇️) then
		dm=1
	elseif btnp(⬆️) then
		dm=-1
	end

	if dm != 0 then
		sfx(3)
		menu.selected=(menu.selected+dm-1)%#menu.ref+1
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

-- indirect callers must update_visible() after all state is changed in their cb.
function move_highlighted_unit(cb)
	move_unit(highlight.unit, path, cb)
	highlight.unit.moved=true
	highlight={}
end

function move_unit(unit, path, cb)
	cb=cb or update_visible

	-- todo: this is the kicker. units _needs_ to be a hash.
	local trapped=false
	for i=1,#path do
		if not trapped then
			for u in all(units) do
				if u.invisible and u.faction!=highlight.unit.faction and xy2n(u.x,u.y)==path[i] then
					trapped=true
					cb=(function() hit_trap(unit,u) end)
					break
				end
			end
		end
		-- call this afterwards, as the path segment that we got trapped on
		-- must also be nullified
		if (trapped) path[i]=nil
	end

	if (unit.sfx) sfx(unit.sfx)

	unit.invisible=true

	start_animation(
		animate_unit_move_frame,
		(function()
			unit.invisible,unit.x,unit.y=false,n2xy(path[#path] or xy2n(unit.x,unit.y))
			cb()
		end),
		unit,false,path,0
	)
end

function hit_trap(trapped,trapper)
	targets={}
	update_visible()
	start_animation(
		animate_hit_trap_frame,
		noop,
		trapped,trapper,0
	)
end

-- r_min, r_max overrides to use this function for vision range
function get_attack_range(unit,x,y,r_min,r_max)
	local r_min,r_max=r_min or unit.r_min or 1,r_max or unit.r_max or 1
	local ret={}

	for x1=max(x-r_max,0),min(x+r_max,map_w) do
		for y1=max(y-r_max,0),min(y+r_max,map_h) do
			local distance=abs(x-x1)+abs(y-y1)
			if (distance>=r_min and distance<=r_max) ret[xy2n(x1,y1)]=true
		end
	end

	return ret
end

function list_targets_from(unit,x,y)
	if (not unit.atk or (unit.ranged and (x!=unit.x or y!=unit.y))) return {}

	local locations=get_attack_range(unit,x,y)
	local ret={}
	for u in all(units) do
		if (not u.invisible and u.faction!=unit.faction and locations[xy2n(u.x,u.y)]) ret[xy2n(u.x,u.y)]=u
	end
	return ret
end

function target_highlighted_unit()
	targets=list_targets_from(highlight.unit,pointer.x,pointer.y)
	target_type=TARGET_ATTACK
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
		local cb=noop
		if target_type==TARGET_ATTACK then
			cb=(function() attack(unit, targets[n]) end)
		elseif target_type==TARGET_UNLOAD then
			cb=(function()
				unload(unit,targets[n],n2xy(n))
			end)
		end
		move_highlighted_unit(cb)
		-- todo - should clear targets here, not inside attack()/unload()
	elseif btnp(❎) then
		targets={}
		pointer.x,pointer.y=n2xy(path[#path] or xy2n(highlight.unit.x,highlight.unit.y))
	end
end

function capture_highlighted_unit()
	local unit=highlight.unit -- keep reference after highlight cleared
	move_highlighted_unit(function() capture(unit) end)
end

function calc_damage(u1,u2,disable_rand)
	local dmg = k_damage_scale
	if (not disable_rand) dmg *= (1+rnd(0.1))
	dmg *= ceil(u1.hp*5/k_max_unit_hp)/5
	dmg *= damage_table[u1.atk][u2.def]
	dmg *= (1-get_defence(u2.x,u2.y)/10)
	return flr(dmg)
end

function attack(attacker, defender)
	update_visible()
	targets={}
	local attacker_hit=false

	defender.hp-=calc_damage(attacker,defender)
	if not attacker.ranged and not defender.ranged and defender.atk and defender.hp>0 then
		attacker.hp-=calc_damage(defender,attacker)
		attacker_hit=true
	end

	start_animation(
		animate_skirmish_frame,
		(function()
			if (attacker.hp<=0) delete_unit(attacker)
			if (defender.hp<=0) delete_unit(defender)
		end),
		attacker,defender,attacker_hit,0
	)
end

function capture(unit)
	update_visible()
	if (not unit.capture_count) unit.capture_count=k_capture_max
	local new_capture_count=max(unit.capture_count-ceil(unit.hp*10/k_max_unit_hp),0)
	start_animation(
		animate_property_capture_frame,
		(function()
			sfx(-2,3)
			unit.capture_count=new_capture_count
			local old_faction=properties[xy2n(unit.x,unit.y)]

			if unit.capture_count<=0 then
				properties[xy2n(unit.x,unit.y)]=unit.faction
				unit.capture_count=nil
				if fget(mget(unit.x*2,unit.y*2))==TERRAIN_HQ then
					mset(unit.x*2,unit.y*2,SPRITE_CITY)
					mset(unit.x*2+1,unit.y*2,SPRITE_CITY+1)
					mset(unit.x*2,unit.y*2+1,SPRITE_CITY+16)
					mset(unit.x*2+1,unit.y*2+1,SPRITE_CITY+17)
					clear_faction(old_faction)
				end
			end
		end),
		unit,unit.capture_count,new_capture_count,0
	)
end

function target_unload_highlighted_unit(locations)
	targets=locations
	target_type=TARGET_UNLOAD
	pointer.x,pointer.y=n2xy(next(targets))
end

function make_unload_menuitem(unit)
	local locations=list_unload_from(unit,pointer.x,pointer.y)

	return {
		text=unit.name..' '..tostr(ceil(unit.hp*10/k_max_unit_hp))..'/10',
		cb=(function() target_unload_highlighted_unit(locations) end),
		stay=true, -- prevent carrier from being 'reset' if unloading multiple units
		disabled=(not next(locations)) -- disabled if no available spots
	}
end

function can_unload_from(unit,x,y)
	-- unit must be able to load, and it must be on a valid unload spot -
	-- heuristically, a standable spot for the first loadable movetype.
	return unit.carries and terrain_cost[fget(mget(x*2,y*2))][next(unit.carries)]
end

-- unit is the one being unloaded
function list_unload_from(unit,x,y)
	local locations=get_attack_range(slime_base,x,y)
	for n in pairs(locations) do
		locations[n]=(get_mvmt(unit,n2xy(n))==0xff and nil or unit)
	end
	-- don't allow to drop on other units
	for u in all(units) do
		if (not u.invisible and u!=highlight.unit and locations[xy2n(u.x,u.y)]) locations[xy2n(u.x,u.y)]=nil
	end
	return locations
end

function unload(u1,u2,x,y)
	local trapper=nil
	for u in all(units) do
		if u.invisible and u.faction!=u1.faction and u.x==x and u.y==y then
			trapper=u
			break
		end
	end

	if trapper then
		hit_trap(u1,trapper)
	else
		start_animation(
			animate_unload_frame,
			(function()
				del(u1.carrying,u2)
				local u_new=make_unit(x,y,u2.faction,u2.base) -- todo: can we pass u2 itself as a base?
				u_new.moved=true
				u_new.hp=u2.hp
				u1.moved=false
				targets={}
				highlight={unit=u1} -- the fact that this is necessary is such a red flag
				-- consider AWDS carrier: it would erroneously be
				-- able to attack in the following menu. TODO.
				open_action_menu(true)
			end),
			u1,u2,x,y,0
		)
	end
end

function load_highlighted_unit(carrier)
	local unit=highlight.unit -- keep reference after highlight cleared
	move_highlighted_unit(function() load(unit,carrier) end)
end

function load(unit,carrier)
	add(carrier.carrying,unit)
	delete_unit(unit)
end

function control_battle()
	if animation_in_progress() then
		if btnp(🅾️) or btnp(❎) then
			end_animation()
		end
	elseif next(targets) then -- if menu and targets both active, prioritise targets
		return control_targets()
	elseif next(menu_stack) then
		return control_menu()
	else
		if btnp(🅾️) then
			sfx(2)
			local unit = nil
			for u in all(units) do
				if u.x==pointer.x and u.y==pointer.y and not u.invisible then
					unit = u
					break
				end
			end
			if highlight[xy2n(pointer.x,pointer.y)] then
				if highlight.unit.faction==battle_factions[active_faction] then
					if not unit or unit==highlight.unit then
						open_action_menu()
					elseif unit then
						if unit.carries and unit.carries[highlight.unit.movetype] and #unit.carrying<unit.carry_max then
							push_menu({{
								text='load',
								cb=(function() load_highlighted_unit(unit) end),
							}},86,1,40)
						elseif not unit.moved then
							highlight_range(unit)
						end
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
				push_menu(make_factory_menu(),1,1,60)
			else
				highlight={}
				push_menu(battle_menu,1,1,60)
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
	elseif not highlight[n] or next(targets) then
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

function on_screen(x,y)
	return ceil(x)>=cam_x and flr(x)<cam_x+128 and ceil(y)>=cam_y and flr(y)<cam_y+128
end

function draw_map()
	if fog then
		-- greyscale - taken from PICO docs
		pal({1,1,5,5,5,6,7,13,6,7,7,6,13,6,7,1})
		map()
		pal()
		for x=flr(cam_x),ceil(cam_x+7) do
			for y=flr(cam_y),ceil(cam_y+7) do
				local s=visible[xy2n(x,y)]
				if s then
					local x0,y0=x*k_tilesize,y*k_tilesize
					rectfill(x0,y0,x0+k_tilesize-1,y0+k_tilesize-1,3) -- grassy green
					spr(s,x0,y0,2,2)
				end
			end
		end
	else
		map()
	end
end

function draw_properties()
	for n,f in pairs(properties) do
		local x,y=n2xy(n)
		if on_screen(x,y) and (not fog or visible[n]) then
			local sprite=mget(x*2,y*2)
			pal(6,faction_colours[f]) -- recolour light-grey
			spr(sprite,x*k_tilesize,y*k_tilesize,2,2)
			pal()
		end
	end
end

function draw_highlight(h)
	local timing=(timer%40)\10
	fillp((0b1110110110110111.111011011011<<timing*4)&0xffff|0b0.1)
	local x,y
	for n,_ in pairs(h or highlight) do
		if type(n)!='string' then
			x,y=n2xy(n)
			rectfill(x*k_tilesize,y*k_tilesize,(x+1)*k_tilesize-1,(y+1)*k_tilesize-1,12)
		end
	end
	fillp(0)
end

function draw_path()
	if (not highlight.unit or #path==0) return

	local x1,y1,x0,y0=highlight.unit.x,highlight.unit.y
	for n in all(path) do
		x0,y0,x1,y1=x1,y1,n2xy(n)
		rectfill(min(x0,x1)*k_tilesize+6,min(y0,y1)*k_tilesize+6,max(x0,x1)*k_tilesize+9,max(y0,y1)*k_tilesize+9,7) -- white
	end

	-- draw arrowhead at the end. sick.
	spr(15,(x1+0.25)*k_tilesize,(y1+0.25)*k_tilesize,1,1,x0>x1,y0>=y1)
	spr(15,(x1+0.25)*k_tilesize,(y1+0.25)*k_tilesize,1,1,x0>=x1,y0>y1)
end

function draw_actor(a)
	if (a.invisible or not on_screen(a.x,a.y)) return

	local x0,y0,frame = a.x*k_tilesize,a.y*k_tilesize,timer%(a.frames*k_animspeed)\k_animspeed
	pal(8,a.moved and 5 or faction_colours[a.faction]) -- dark grey or faction
	spr(a.spr+2*frame,x0,y0,2,2)

	if a.carries then
		if fog and a.faction!=battle_factions[active_faction] then
			print('\#0?',x0,y0+11,7)
		elseif #a.carrying>0 then
			print('\#0c',x0,y0+11,7)
			if xy2n(pointer.x,pointer.y)==xy2n(a.x,a.y) then
				local xc0,yc0,yc1=(a.x-(#a.carrying-1)/2)*k_tilesize,(a.y-1)*k_tilesize,a.y*k_tilesize-1
				for i=1,#a.carrying do
					rect(xc0+k_tilesize*(i-1),yc0,xc0+k_tilesize*i-1,yc1,7) -- white
					spr(a.carrying[i].spr,xc0+k_tilesize*(i-1),yc0,2,2)
				end
			end
		end
	end
	pal()

	local display_hp=ceil(a.hp*10/k_max_unit_hp)
	if display_hp<10 then
		print('\#0'..display_hp,x0+12,y0+10,7) -- white on black
	end

	if a.capture_count then
		print('\#0'..a.capture_count,x0+1,y0+1,5) -- olive on black
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

function draw_pointer()
	local x0,y0,timing=pointer.x*k_tilesize,pointer.y*k_tilesize,(timer%20)\10
	spr(3,x0,y0,2,2)
	pal(7,faction_colours[battle_factions[active_faction]])
	sspr(124,4,4,4,x0+k_tilesize-timing%2,y0+k_tilesize-timing%2)
	pal()
	if target_type==TARGET_ATTACK then
		local u=targets[xy2n(pointer.x,pointer.y)]
		if u then
			local dmg=calc_damage(highlight.unit,u,true)
			rect(x0+12,y0-6,x0+30,y0+2,0) -- black
			rectfill(x0+13,y0-5,x0+29,y0+1,7) -- white
			print(tostr(dmg)..'%',x0+12+2*(4-#tostr(dmg)),y0-4,0)
		end
	end
	-- todo: if TARGET_UNLOAD, then draw_actor({...next(targets),pointer.x,pointer.y})
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
	if (not next(menu_stack)) return

	local menu=menu_stack[#menu_stack]
	local x,y,w=menu.x+cam_x*k_tilesize,menu.y+cam_y*k_tilesize,menu.w

	rectfill(x+2,y+2,x+w-2,y+1+#menu.ref*8,13) -- lilac
	rect(x,y,x+w,y+3+#menu.ref*8,7) -- white

	for i=1,#menu.ref do
		if (menu.selected==i) rectfill(x+2,y-6+i*8,x+w-2,y+1+i*8,2) -- burgundy
		if menu.ref[i].disabled then
			print(menu.ref[i].text,x+3,y-5+i*8,5) -- grey
		elseif menu.selected==i then
			print(menu.ref[i].text,x+3,y-5+i*8,10) -- yellow
		else
			print(menu.ref[i].text,x+3,y-4+i*8,7) -- white
		end
	end
end

function animate_end_turn_frame(frame)
	local x0,y0=cam_x*k_tilesize+64,cam_y*k_tilesize+64
	rectfill(x0-4*min(frame,16),y0-20,x0+4*min(frame,16),y0+19,faction_colours[battle_factions[active_faction]])
	if (frame>=6) print('\^w\^tday '..battle_turn,x0-24,y0-5,7) -- white
	return false,frame+1
end

function animate_skirmish_frame(attacker,defender,attacker_hit,frame)
	if (frame==0) sfx(7,3)

	local x,y=defender.x,defender.y
	if (frame>20) x,y=attacker.x,attacker.y
	spr(13,x*k_tilesize,y*k_tilesize,2,2,frame%10>5)

	local done=(attacker_hit and frame==40) or (not attacker_hit and frame==20)
	return done and (sfx(-2,3) or true),attacker,defender,attacker_hit,frame+1
end

function animate_property_capture_frame(unit,capture_start,capture_end,frame)
	if (frame==10) sfx(5,-1,0,12)
	if (capture_end<=0 and frame==34) sfx(6)

	local frame_effective=min(max(frame-5,0),20)
	local capture_mid=(frame_effective*capture_end+(20-frame_effective)*capture_start)/20
	local colour=15 -- peach
	if frame>=34 then
		-- draw a quickly rising faction-coloured bar
		colour=faction_colours[unit.faction]
		capture_mid=min(2*(frame-30),20)
	else
		-- draw a steadily dropping bar
		-- dangerous mutation of unit - ensure that this is set correctly by the caller
		unit.capture_count=ceil(capture_mid)
		local pf=properties[xy2n(unit.x,unit.y)]
		if (pf) colour=faction_colours[pf]
	end
	local x0,y0=unit.x*k_tilesize-4,(unit.y+1)*k_tilesize
	rectfill(x0,y0,x0+3,y0-capture_mid,colour)

	return (capture_end>0 and frame==29 or frame==48),unit,capture_start,capture_end,frame+1
end

function animate_unload_frame(u1,u2,x,y,frame)
	return true -- todo
end

function animate_hit_trap_frame(trapped,trapper,frame)
	if (frame==0) sfx(4)
	print('\#7!',trapped.x*k_tilesize+6,trapped.y*k_tilesize-2,8) -- red on white
	return frame>=10,trapped,trapper,frame+1
end

function animate_unit_move_frame(unit,flip,path,frame)
	local n=(frame\4)
	local k=(frame%4)/4

	-- path doesn't include unit's location
	local x1,y1=unit.x,unit.y
	if (n>0) x1,y1=n2xy(path[n])
	local x2,y2=n2xy(path[n+1])
	local x=k*x2+(1-k)*x1
	local y=k*y2+(1-k)*y1
	flip=(flip or (x2<x1)) and not (x2>x1)

	pal(8,faction_colours[unit.faction])
	spr(unit.spr,x*k_tilesize,y*k_tilesize,2,2,flip)
	pal()

	return (n>=#path),unit,flip,path,frame+1
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
	if game_state==STATE_G_MAIN_MENU then
		cls(5)
		print('\#0\^w\^t \f8w\fca\fbr\fas ',41,30)
	elseif game_state==STATE_G_BATTLE then
		camera(cam_x*k_tilesize,cam_y*k_tilesize)
		draw_map()
		draw_properties()
		draw_highlight()
		draw_path()
		draw_units()
		draw_targets()
		draw_pointer()
		draw_faction()
	end
	if (not next(targets)) draw_menu() -- if menu and targets both active, only draw targets
	animate()
	popd_()
end

__gfx__
00000000000000000000000077000000000000770000000000000000000000000000000000010000000000000017101110010000000000000000000000000000
00000000000000000000000070000000000000070000000000000000000000000000000000171011100100000017118881171000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000001111110000000171188811710000017788888771000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000018888881000000177888887710000017788888771000000000000ffff00000000000
000000000000000000000000000000000000000000000011110000000000187788881000001778888877100000018888888101000000fffff7777f0000007777
00000000000000000000000000000000000000000000018888100000000188778888100000018888888101000001871771711610000f777777777f0000007770
00000000000000000000000000000000000000000000187788810000000188888888100000018717717116100001777777711610000f77777f7ff00000007700
00000000000000000000000000000000000000000000187788881000000188888888810000017777777116100011177777101610000f777ff7777f0000007000
000000000000000000000000000000000000000000018888888881000018888888888100001117777710161001888111111016100000f77777777f0000000000
0000000000000000000000000000000000000000001888888888810000188888888888100188811111001610188888777771888100fff77777777f0000000000
000000000000000000000000000000000000000000188888888888100188888888888810188888177711888118888877111778100f7777f77777f00000000000
00000000000000000000000000000000000000000188888888888810188888888888888118888877717778100188871111711810f777777fff77f00000000000
00000000000000000000000000000000000000001888888888888881188888888888888101888711117118100011177777710100f77777777777f00000000000
000000000000000000000000000000000000000011111111111111111111111111111111001117777710010000001710171000000ffffff7777f000000000000
000000000000000000000000700000000000000700000000000000000000000000000000000017101711000000001710171100000000000ffff0000000000000
00000000000000000000000077000000000000770000000000000000000000000000000000017771177710000001777117771000000000000000000000000000
00000000333333333333333333333333333333333333333333333333333333333333333333333333333333330000000000000000000000000000000000000000
000000003333333377733333333333333333333333333333333333333333333666633333333333333dd333330011100000000000000000000000000000000000
000000003333333777733333333333333333333333333333666613333333333666633333333366666dd666630155510000000000001110000000000000000000
0000000033333337777733333333bbb33333333333333336666661333333333666633333333366666dd666631885551000000000015551000000000000000000
00000000333333777766333333bb33bb3333333333333366666666133333333733333333333666666dd666431888551000000000188555100000000000000000
000000003333336666663333333333333333333333366661666666613dd13dd73dd13dd133366666666666431888881110000000188855100000000000000000
000000003333366666663333333333333333333333666666144441333dd13dd73dd13dd133666666666663430188888881100000188888111110000000000000
00000000333336666666333333333333333bbb3336666666614dd1333dddddddddddddd1334444113dd343430011118888811000018888888881100000000000
0000000033333666666663333333333333bb3bb366666666661dd1333dddddddddddddd1334444113dd343430011111118888100001111111888810000000000
00000000333336666666633333333333333333333344444419944133333dddddddddd133334444113dd343430188888888888810018888888888881000000000
000000003333366666666333333333333333333333dd44dd19944133333dddddddddd133334444113dd343430011111111111100001111111111110000000000
00000000333366666666633333333333b333333333dd44dd19944133333dddd66dddd13333444413dddd43330188888888888810018888888888881000000000
000000003336666666666333333333bb3bb333333344994413333333333ddd6666ddd13333444413d99d43330141114111114100014414411114441000000000
00000000333666666666633333333bb333b333333344994413333333333ddd6666ddd13333444433dddd43330144144100141410014141410014141000000000
00000000336666666666663333333333333333333344994413333333333ddd6666ddd13333333333333333330014441000014100014444410014441000000000
00000000366666666666666333333333333333333333333333333333333333333333333333333333333333330001110000001000001111100001110000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000011111111111110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00111111111111100188888888888881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01888888888888810181111111111181000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01811111111111810188888888888881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01888888888888810181111111111181000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01811111111111810188888888888881000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01888888888888810014114111411410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00141141114114100014114101411410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00144441014444100014444101444410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00011110001111000001111000111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
0100000000000000000000000000000000000000000000000000000000000000000202010103030404030300000000000002020101030304040303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
2122212221222122212221222122232423242324232421222122212221220000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3132313231323132313231323132333433343334333431323132313231320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2324272821222122212221222324232423242324232423242324212223240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3334373831323132313231323334333433343334333433343334313233340000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
232423242526232421222122232423242122212223242324292a212227280000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
333433343536333431323132333433343132313233343334393a313237380000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2324292a23242324232423242324232423242526232423242324252623240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3334393a33343334333433343334333433343536333433343334353633340000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2324232423242324232425262324232421222122232423242324232423240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3334333433343334333435363334333431323132333433343334333433340000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2324232423242122212221222122212221222122232421222324232421220000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3334333433343132313231323132313231323132333431323334333431320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2324232423242324232425262324232425262324232423242122212221220000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3334333433343334333435363334333435363334333433343132313231320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2324212221222324232423242324232421222122232423242122252623240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3334313231323334333433343334333431323132333433343132353633340000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
212225262324232423242324232423242122232423242324292a272823240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
313235363334333433343334333433343132333433343334393a373833340000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
21222728292a2324232423242324232421222324232423242324232423240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
31323738393a3334333433343334333431323334333433343334333433340000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000600001f11013110001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
000600001d05020050210002200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000800002113021100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
000c0000192201f220002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200
000800041a1300e1300213000100001000010000100001001a1000e10002100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
000800000e13012130151301a13000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
480a000423233202331d2331b233132030c2030f20311203002030020300203002030020300203002030020300203002030020300203002030020300203002030020300203002030020300203002030020300203
