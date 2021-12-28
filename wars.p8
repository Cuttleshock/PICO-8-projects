pico-8 cartridge // http://www.pico-8.com
version 32
__lua__
-- magic numbers

k_pointerframes = 2
k_animspeed = 20
k_pointerspr = 1
k_tilesize = 16
-- divides 1~10, 12, 14, 15:
k_timermax = 2*3*2*5*7*2*3

-- 'enums'
STATE_G_MAIN_MENU=1
STATE_G_BATTLE=2

STATE_B_SELECT=101
STATE_B_MENU=102
STATE_B_ANIM=103

FACTION_RED=1001
FACTION_BLUE=1002

faction_colours={
	[FACTION_RED]=8,
	[FACTION_BLUE]=1,
}

-- units, menus
slime_base = {
	spr=5,
	frames=2,
	range=3,
}

function noop() end

main_menu = {
	{ text='battle', cb=(function () push_game_state(STATE_G_BATTLE, init_battle) end) },
	{ text='nothing', cb=noop },
	{ text='also no', cb=noop },
}

battle_menu = {
	{ text='nope', cb=noop },
	{ text='cool stats', cb=noop },
	{ text='exit to menu', cb=(function () push_game_state(STATE_G_MAIN_MENU, init_main_menu) end) },
	{ text='end turn', cb=(function () end_turn() end) },
}

action_menu = {
	{ text='move', cb=(function () move_highlighted_unit() end) },
	{ text='attack', cb=noop },
}

debug = {_names={}}
function d_(str)
	add(debug,str)
	if (#debug > 12) deli(debug,1)
end

function popd_()
	cursor(cam_x*k_tilesize,cam_y*k_tilesize)
	for d in all(debug) do
		-- print(tostr(d,true))
		print(d)
	end
end

-->8
-- state and update methods

-- state control
game_state=STATE_G_MAIN_MENU
queued_game_state=nil
queued_game_state_cb=noop
battle_state=STATE_B_ANIM

-- global state
menu_item=1
active_menu={}

timer=0

-- battle-specific state
units={}
pointer={}
highlight={}
path={ cost=0 }
battle_factions={}
active_faction=0

map_w=0
map_h=0
cam_x=0
cam_y=0

-- todo: use coroutines!
animate=noop
anim_on_exit=noop

-- note that this is misleadingly named:
-- it's a replacement, not a real push.
-- todo: use coroutines?
function push_game_state(state, cb)
	queued_game_state=state
	queued_game_state_cb=cb or noop
end

function pop_game_state()
	if (not queued_game_state) return

	game_state=queued_game_state
	queued_game_state_cb()

	queued_game_state=nil
	queued_game_state_cb=noop
end

function init_main_menu()
	active_menu.ref=main_menu
	active_menu.x=40
	active_menu.y=20
	active_menu.w=48
	active_menu.on_exit=nil
	menu_item=1
end

function init_battle()
	battle_state=STATE_B_ANIM
	animate=(function() return true end)
	anim_on_exit=(function() battle_state=STATE_B_SELECT end)
	clear_menu()
	units={}
	init_pointer(3,3)
	update_camera()
	battle_factions={ FACTION_RED, FACTION_BLUE }
	active_faction=1
	make_unit(7,5,FACTION_RED,slime_base)
	make_unit(4,6,FACTION_RED,slime_base)
	make_unit(5,4,FACTION_BLUE,slime_base)
	highlight={}
	path={ cost=0 }
	map_w=16
	map_h=16
end

function init_pointer(x,y)
	pointer.x = x
	pointer.y = y
	pointer.spr = k_pointerspr
	pointer.frames = k_pointerframes
end

function make_unit(x,y,faction,base)
	local unit = {
		x=x,
		y=y,
		faction=faction,
		dx=0,
		dy=0,
		spr=base.spr,
		frames=base.frames,
		range=base.range,
		visible=true,
		unit=true,
	}
	add(units, unit)
	return unit -- to allow further tweaks
end

-- serialised data structure (no. bits):
-- x y cost mvmt unused
-- 8 8 4    4    8
-- needed to write highlight
function xy2n(x,y,cost,mvmt)
	cost = cost or 0
	mvmt = mvmt or 0
	return ((x & 0xff) << 8) | (y & 0xff) | ((cost & 0xf) >> 4) | ((mvmt & 0xf) >> 8)
end

-- needed to iterate through highlight and read paths
function n2xy(n)
	n = n or 0xffff.f
	return (n >> 8) & 0xff, n & 0xff, (n & 0x0.f) << 4, (n & 0x0.0f) << 8
end

function get_mvmt(x,y)
	if 0<=x and x<=map_w and 0<=y and y<=map_h then
		return 1 -- movement cost here!
	else
		return 0xff -- "too big"
	end
end

function highlight_range(u)
	-- clear, then init w/ starting location
	path={ cost=0 }
	highlight = { unit=u }
	search = { xy2n(u.x,u.y) }
	highlight[xy2n(u.x,u.y)] = xy2n(0xff,0xff,0,1) -- mvmt irrelevant?
	-- depth-first search
	while search[1] do
		local x,y = n2xy(search[1])
		local _,_,cost = n2xy(highlight[search[1]])
		for tab in all({{x+1,y},{x,y+1},{x-1,y},{x,y-1}}) do
			local x1,y1 = tab[1],tab[2]
			local mvmt = get_mvmt(x1,y1)
			local cost1 = cost + mvmt--SHOOT WAIT WHAT
			local _,_,cost2 = n2xy(highlight[xy2n(x1,y1)])
			if cost1 < cost2 and cost1 <= u.range then
				highlight[xy2n(x1,y1)] = xy2n(x,y,cost1,mvmt)
				if cost1 < u.range then -- strict <
					add(search, xy2n(x1,y1))
				end
			end
		end
		deli(search,1)
	end
end

function end_turn()
	active_faction=active_faction%#battle_factions + 1
end

function clear_menu()
	active_menu.ref=nil
	menu_item=1
end

function control_menu()
	if btnp(🅾️) then
		return active_menu.ref[menu_item].cb()
	elseif btnp(❎) and active_menu.on_exit then
		-- allow nil on_exit, indicating you can't back out
		clear_menu()
		return active_menu.on_exit()
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

function move_highlighted_unit()
	clear_menu()
	move_unit(highlight.unit, pointer.x, pointer.y)
	highlight={}
end

function move_unit(unit, x, y)
	unit.x,unit.y=x,y
	if (unit.sfx) sfx(unit.sfx)

	unit.visible=false
	battle_state=STATE_B_ANIM
	animate=(function() return true end)
	anim_on_exit=(function()
		battle_state=STATE_B_SELECT
		unit.visible=true
	end)
end

function control_battle()
	if battle_state==STATE_B_SELECT then
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
						active_menu.ref=action_menu
						active_menu.y=1
						active_menu.w=40
						active_menu.x=126-active_menu.w
						active_menu.on_exit=(function() battle_state=STATE_B_SELECT end)
						battle_state=STATE_B_MENU
					elseif unit then
						highlight_range(unit)
					end
				else
					if unit then
						highlight_range(unit)
					else
						highlight={}
					end
				end
			elseif unit then
				highlight_range(unit)
			else
				highlight={}
				active_menu.ref=battle_menu
				active_menu.x=1
				active_menu.y=1
				active_menu.w=60
				active_menu.on_exit=(function() battle_state=STATE_B_SELECT end)
				battle_state=STATE_B_MENU
			end
		elseif btnp(❎) then
			highlight={}
			battle_state=STATE_B_SELECT
		else
			move_pointer()
		end
	elseif battle_state==STATE_B_MENU then
		control_menu() -- oh can these also be consolidated?
	elseif battle_state==STATE_B_ANIM then
		if animate() or btnp(🅾️) or btnp(❎) then
			anim_on_exit()
		end
	end
end

function update_actor(a)
	if a.dx != 0 or a.dy != 0 then
		a.x,a.y = a.x+a.dx,a.y+a.dy
		a.dx,a.dy = 0,0
		if (a.sfx) sfx(a.sfx)
	end
end

function update_units()
	for u in all(units) do
		update_actor(u)
	end
end

-- need to run this after moving pointer
-- to prevent jumpiness
function update_camera()
	-- move camera right/left
	if pointer.x < cam_x+2 then
		cam_x = max(0,pointer.x-2)
	elseif pointer.x > cam_x+5 then
		cam_x = min(map_w-8,pointer.x-5)
	end
	-- move camera up/down
	if pointer.y < cam_y+2 then
		cam_y = max(0,pointer.y-2)
	elseif pointer.y > cam_y+5 then
		cam_y = min(map_h-8,pointer.y-5)
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
	return path.cost+get_mvmt(xloc,yloc)<=highlight.unit.range
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
			path.cost -= get_mvmt(xp,yp)
			path[j] = nil
		end
	elseif can_append(n) then
		add(path, n)
		path.cost += get_mvmt(x,y)
	else
		path = { cost=0 }
		local curr,next=n,highlight[n]
		local xn=n2xy(next)
		while xn!=0xff do
			add(path, curr, 1)
			path.cost+=get_mvmt(x,y)
			x,y=n2xy(next)
			curr,next=next,highlight[xy2n(x,y)]
			xn=n2xy(next)
		end
	end
end

-->8
-- draw methods

function draw_highlight()
	local sprite = 16*(((timer%30)\10)+1)
	for x=0,map_w do
		for y=0,map_h do
			if highlight[xy2n(x,y)] then
				-- draw 2*2 on every metatile
				spr(sprite,x*k_tilesize,y*k_tilesize)
				spr(sprite,(x+0.5)*k_tilesize,y*k_tilesize)
				spr(sprite,x*k_tilesize,(y+0.5)*k_tilesize)
				spr(sprite,(x+0.5)*k_tilesize,(y+0.5)*k_tilesize)
			end
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
	local frame = timer%(a.frames*k_animspeed)\k_animspeed
	pal(8,faction_colours[a.faction])
	spr(a.spr+2*frame,a.x*k_tilesize,a.y*k_tilesize,2,2)
	pal()
end

function draw_units()
	for a in all(units) do
		draw_actor(a)
	end
end

function draw_faction()
	rectfill(cam_x*k_tilesize+112,cam_y*k_tilesize,cam_x*k_tilesize+128,cam_y*k_tilesize+6,faction_colours[battle_factions[active_faction]])
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

-->8
-- init, update, draw

function _init()
	init_main_menu()
end

function _update()
	update_timer()
	if game_state==STATE_G_MAIN_MENU then
		control_menu()
	elseif game_state==STATE_G_BATTLE then
		control_battle()
		update_units()
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
		draw_highlight()
		draw_path()
		draw_units()
		draw_actor(pointer)
		draw_faction()
	end
	draw_menu()
	popd_()
end

__gfx__
00000000000000000000000077000000000000770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000077000000000077070000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000070000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000008888880000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000008778888000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000008888000000000088778888000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000087788800000000088888888000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000087788880000000088888888800000000000000000000000000000000000000000000000000000000000
0c000c00000000000000000000000000000000000000888888888000000888888888800000000000000000000000000000000000000000000000000000000000
c000c000000000000000000000000000000000000008888888888000000888888888880000000000000000000000000000000000000000000000000000000000
000c000c000000000000000000000000000000000008888888888800008888888888880000000000000000000000000000000000000000000000000000000000
00c000c0000000000000000000000000000000000088888888888800088888888888888800000000000000000000000000000000000000000000000000000000
0c000c00000000000000000000000000000000008888888888888888888888888888888800000000000000000000000000000000000000000000000000000000
c000c000070000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c000c077000000000077070000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00c000c0000000000000000077000000000000770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
c000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c000c000000007770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00c000c0000000077770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0c000c0000000007777700000000bbb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
c000c000000000777766000000bb00bb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c000c000000666666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00c000c0000006666666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0c000c00000006666666000000000000000bbb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00c000c000000666666660000000000000bb0bb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0c000c00000006666666600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
c000c000000006666666600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c000c000066666666600000000000b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00c000c00006666666666000000000bb0bb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0c000c00000666666666600000000bb000b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
c000c000006666666666660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c000c066666666666666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
0001010100000000000000000000000000010101000000000000000000000000000101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
2324000000000000232400000000000000000000000000000000212221222324000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3334000000000000333400000000000000000000000000000000313231323334000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000021222122000000002324232400002324000023242324212200002324000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000031323132000000003334333400003334000033343334313200003334000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000232400000000212221220000000021222122000023242122212223240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000333400000000313231320000000031323132000033343132313233340000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000023240000000000000000232400002122232400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000033340000000000000000333400003132333400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000232400002324232400002324000023242324000000002324232400002324000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000333400003334333400003334000033343334000000003334333400003334000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000232400000000000000000000000000002324000000000000000021222122000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000333400000000000000000000000000003334000000000000000031323132000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2324232400000000000023240000000023242122000000002122212221220000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3334333400000000000033340000000033343132000000003132313231320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000002324232400000000000000002122232400002122000023240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000003334333400000000000000003132333400003132000033340000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2122000000000000000000000000000021220000000023240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3132000000000000000000000000000031320000000033340000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2122000023242324000023240000232421220000000023240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3132000033343334000033340000333431320000000033340000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
