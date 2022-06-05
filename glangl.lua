-- langl: arc grains looper
-- by @burgess
-- based on angl by @tehn
-- engine: glut @artfwo
--
-- load files via param menu
--
-- E2 to switch modes:
--
-- SPEED
-- -- K2 then touch arc to
--    set speed to zero
--
-- LOOP
-- -- K2 sets loop window
--
-- PITCH
-- -- K2 sets coarse control
--
-- VOLUME, DENSITY, SIZE,
-- JITTER, SPREAD
-- -- K2 sets fine control


engine.name = 'Glut'

tau = math.pi * 2
pi = math.pi

pitch_limit = 24
VOICES = 4
modes = {"SPEED", "LOOP", "PITCH", "VOLUME", "DENSITY", "SIZE", "JITTER", "SPREAD"}
mode = 0
mode_float_pos = 0
hold = false
speed_mark_pos = 0
g_focus = { x = 1, y = 1, brightness = 15 }

data_dir = "/home/we/dust/data/glangl/"
DATA_FILE_NAME = "states.txt"

REFRESH_RATE = 0.02

loop_data = {}
function loop_data:new()
  local this = {
    percent = 1,
    current_percent = 0,
    loop_reset_pos = 0,
    loop_center_pos = 0,
    loop_in = 0,
    loop_out = 1,
    loop_over_seam = true
  }
  return this
end

state = {}
function state:new()
  local this = {
    speed = 100,
    loop_percent = 1,
    loop_center_pos = 0,
    pitch = 0,
    volume = 0,
    density = 1,
    size = 100,
    jitter = 0,
    spread = 0
  }
  return this
end

state_set = {}
function state_set:new()
  local this = {
    states = {
      state:new(),
      state:new(),
      state:new(),
      state:new()
    }
  }
  return this
end


track = {}
function track:new()
  local this = {
    param_focus = "speed",
    position = 1,
    state = state:new(),
    loop_data = loop_data:new()
  }
  return this
end

tracks = {
  track:new(),
  track:new(),
  track:new(),
  track:new()
}

-- 1: save, 2: recall
state_bank_mode = 1

grid_states = {}

session_info = {
  tracks = {}
}

g = grid.connect()
a = arc.connect()

function init()
  -- polls
  for v = 1, VOICES do
    local phase_poll = poll.set('phase_' .. v, function(pos) update_position(v, pos) end)
    phase_poll.time = REFRESH_RATE
    phase_poll:start()
  end
  
  -- setup params menu
  param_menu_init()

  grid_connected = g.device ~= nil and true or false
  columns = grid_connected and g.device.cols or 16
  rows = grid_connected and g.device.rows or 8

  for x = 1, columns-1 do
    grid_states[x] = {}
    for y = 1, rows do
      grid_states[x][y] = nil
    end
  end

  if grid_connected then
    -- load state list
    local loaded_states = tab.load(data_dir..DATA_FILE_NAME)
    if loaded_states ~= nil then grid_states = loaded_states end

    grid_redraw()
  end


  -- setup timed function calls
  local arc_redraw_timer = metro.init()
  arc_redraw_timer.time = REFRESH_RATE
  arc_redraw_timer.event = function() arc_redraw() end
  arc_redraw_timer:start()

  local loop_timer = metro.init()
  loop_timer.time = 0.01
  loop_timer.event = function()
    for v=1, VOICES do
      set_loop_ends(v)
      update_position(v, tracks[v].position)
      loop_pos(v)
    end 
  end
  loop_timer:start()

end

-- drawing
grid_redraw = function()
  if not grid_connected then return end

  local low = 3
  local mid = 7
  local high = 10
  local max = 15

  g:all(0)

  for x = 2, columns do
    for y = 1, rows do
      -- handle lights for state bank area
      if grid_states[x] ~= nil then
        if grid_states[x][y] ~= nil then
          g:led(x, y, 4) -- turn the light on dimly for any position that has a saved state
        end
      end
    end
  end

  -- back and forward param buttons
  g:led(1, 1, low)
  g:led(1, 2, low)

  -- save and recall buttons
  g:led(1, 7, state_bank_mode == 1 and mid or low)
  g:led(1, 8, state_bank_mode == 2 and mid or low)

  if g_focus.x ~= nil or g_focus.y ~= nil then
    g:led(g_focus.x, g_focus.y, max)
  end

  g:refresh()
  g_focus.x = nil
  g_focus.y = nil
end

arc_redraw = function()
  a:all(0)
  if mode == 0 then
    for v=1,VOICES do
      if tracks[v].loop_data.percent < 1 then
        update_position(v, tracks[v].position)
        if (tracks[v].state.speed > 0) then
          speed_mark_pos = util.linlin(0, tracks[v].loop_data.percent, 0, 1, tracks[v].loop_data.current_percent)
        else
          speed_mark_pos = util.linlin(0, tracks[v].loop_data.percent, 1, 0, tracks[v].loop_data.current_percent)
        end
      else
        speed_mark_pos = tracks[v].position
      end
      a:segment(v,speed_mark_pos*tau,tau*speed_mark_pos+0.2,15)
    end
  elseif mode == 1 then
    for v=1,VOICES do
      if tracks[v].loop_data.percent < 0.95 then
        a:segment(v, tracks[v].loop_data.loop_in*tau, tau*tracks[v].loop_data.loop_out+0.2, 15)
      else 
        a:segment(v, 0.001*tau, 0.999*tau, 15)
      end
    end
  elseif mode == 2 then
    for v=1,VOICES do
      local pitch = params:get(v.."pitch") / 10
      if pitch > 0 then
        a:segment(v,0.5,0.5+pitch,15)
      else
        a:segment(v,pitch-0.5,-0.5,15)
      end
    end
  elseif mode == 3 then
    for v=1,VOICES do
      local volume = params:get(v.."volume")
      if volume > 0 then
        a:segment(v,0.5,util.linlin(0, 20, 0.5, pi - 0.5, volume),15)
      else
        util.linlin(-60, 0, -pi + 0.5, -0.5, volume)
        a:segment(v,util.linlin(-60, 0, -pi + 0.5, -0.5, volume),-0.5,15)
      end
    end
  elseif mode == 4 then
    for v=1,VOICES do
      local density = params:get(v.."density")
      a:segment(v, 0, util.linlin(0, 512, 0, tau*0.999, density), 15)
    end
  elseif mode == 5 then
    for v=1,VOICES do
      local size = params:get(v.."size")
      a:segment(v, 0, util.linlin(1, 500, tau/64, tau*0.999, size), 15)
    end
  elseif mode == 6 then
    for v=1,VOICES do
      local jitter = params:get(v.."jitter")
      a:segment(v, 0, util.linlin(0, 500, 0, tau*0.999, jitter), 15)
    end
  else
    for v=1,VOICES do
      local spread = params:get(v.."spread")
      a:segment(v, 0, util.linlin(0, 100, 0, tau*0.999, spread), 15)
    end
  end
  a:refresh()
end

function norns_redraw()
  screen.clear()
  screen.font_face(7)
  screen.font_size(14)
  local height = 15
  local m = mode + 1

  for y=1, 4 do
    screen.move(0, y*height)
    local level = m == y and 15 or 2
    if (hold == true and m == y) then level = 8 end
    screen.level(level)
    screen.text(modes[y])  
  end
  
  for y=1, 4 do
    screen.move(64, y*height)
    local level = m == y+4 and 15 or 2
    if (hold == true and m == y+4) then level = 8 end
    screen.level(level)
    screen.text(modes[y+4])  
  end

  screen.update()
end


-- interactions
key = function(n,z)
  if n==2 then hold = z==1 and true or false end
  norns_redraw()
end

enc = function(n,d)
  if n==2 then
    update_mode(d/8)
  end
end

g.key = function(x,y,z)
  if z==1 then
    button_down_last_frame = true
    handle_state(x, y)
  end
  grid_redraw()
end

a.delta = function(n,d)
  if mode==0 then
    if hold == true then
      params:set(n.."speed",0)
    else
      local s = params:get(n.."speed")
      s = s + d/10
      params:set(n.."speed",s)
      track_speed[n] = s
    end
  elseif mode == 1 then
    if hold == true then
      loop_data[n].percent = util.clamp(loop_data[n].percent + d/300, 0.00001, 1)
      params:set(n.."loop_percent", loop_data[n].percent)
    else
      tracks[n].loop_data.loop_center_pos = (tracks[n].loop_data.loop_center_pos + d/300) % 1
      params:set(n.."loop_center_pos", tracks[n].loop_data.loop_center_pos)
    end 
    set_loop_ends(n)

  elseif mode == 2 then
    tracks[n].state.pitch = util.clamp(tracks[n].state.pitch + d/10, -pitch_limit, pitch_limit)

    if hold == true then
      params:set(n.."pitch", util.round(tracks[n].state.pitch, 4))
    else
      params:set(n.."pitch", tracks[n].state.pitch)
    end
  elseif mode == 3 then
    if hold == true then
      params:delta(n.."volume", d/20)
    else
      params:delta(n.."volume", d/4)
    end
  elseif mode == 4 then
    if hold == true then
      params:delta(n.."density", d/20)
    else
      params:delta(n.."density", d/4)
    end
  elseif mode == 5 then
    if hold == true then
      params:delta(n.."size", d/20)
    else
      params:delta(n.."size", d/4)
    end
  elseif mode == 6 then
    if hold == true then
      params:delta(n.."jitter", d/20)
    else
      params:delta(n.."jitter", d/4)
    end
  else
    if hold == true then
      params:delta(n.."spread", d/20)
    else
      params:delta(n.."spread", d/4)
    end
  end
end


-- functions
function update_mode(delta)
  mode_float_pos = mode_float_pos + delta

  if math.abs(delta) == 1 then
    mode = mode + delta
    mode_float_pos = mode + 0.5
  else
    mode =  math.floor(mode_float_pos)
  end
  
  mode = mode % 8

  norns_redraw()
end

function handle_state(x, y)
  if x == 1 then
    if y == 1 then
      update_mode(-1)
    elseif y == 2 then
      update_mode( 1)
    elseif y == 7 then
      state_bank_mode = 1
    elseif y == 8 then
      state_bank_mode = 2
    end
  end

  if x > 1 then
    if state_bank_mode == 1 then
      save_state(x, y)
    else
      load_state(x, y)
    end
  end

  g_focus.x = x
  g_focus.y = y
end

function save_state(x, y)
  local v = get_voice_from_grid_position(x)
  states[x][y].speed = params:get(v.."speed")
  states[x][y].loop_percent = params:get(v.."loop_percent")
  states[x][y].loop_center_pos = params:get(v.."loop_center_pos")
  states[x][y].pitch = params:get(v.."pitch")
  states[x][y].volume = params:get(v.."volume")
  states[x][y].density = params:get(v.."density")
  states[x][y].size = params:get(v.."size")
  states[x][y].jitter = params:get(v.."jitter")
  states[x][y].spread = params:get(v.."spread")
  
  tab.save(states, data_dir..DATA_FILE_NAME)
end

function load_state(x, y)
  local v = get_voice_from_grid_position(x)
  params:set(v.."speed", states[x][y].speed)
  params:set(v.."loop_percent", states[x][y].loop_percent)
  params:set(v.."loop_center_pos", states[x][y].loop_center_pos)
  params:set(v.."pitch", states[x][y].pitch)
  params:set(v.."volume", states[x][y].volume)
  params:set(v.."density", states[x][y].density)
  params:set(v.."size", states[x][y].size)  
  params:set(v.."jitter", states[x][y].jitter)
  params:set(v.."spread", states[x][y].spread)

  -- tracks[v].state.speed = states[x][y].speed
  -- tracks[v].state.pitch = states[x][y].pitch
  -- loop_center_pos[v] = states[x][y].loop_center_pos
end

function get_voice_from_grid_position(x)
  return math.floor((x-0.5)/4)+1
end

function set_loop_ends(v)
  local ld = tracks[v].loop_data
  local half_percent = ld.percent/2
  ld.loop_in  = (ld.loop_center_pos - half_percent) % 1
  ld.loop_out = (ld.loop_center_pos + half_percent) % 1
end

function update_position(v, pos)
  local t = tracks[v]
  t.position = pos
  
  local ref_pos = t.state.speed > 0 and t.loop_data.loop_in or t.loop_data.loop_out
  local dist_from_ref_pos = math.abs(pos - ref_pos)
  t.loop_data.loop_over_seam = t.loop_data.loop_out < t.loop_data.loop_in
  
  if t.loop_data.loop_over_seam then
    if t.state.speed > 0 then
      if pos < t.loop_data.loop_out and pos < t.loop_data.loop_in then
        dist_from_ref_pos = 1 - dist_from_ref_pos
      end
    else
      if pos > t.loop_data.loop_out and pos > t.loop_data.loop_in then
        dist_from_ref_pos = 1 - dist_from_ref_pos
      end
    end
  end

  t.loop_data.loop_reset_pos = ref_pos
  t.loop_data.current_percent = dist_from_ref_pos 
end

function loop_pos(v)
  local t = tracks[v]

  if t.loop_data.loop_over_seam then
    if t.position > t.loop_data.loop_out and t.position < t.loop_data.loop_in then
      update_position(v, t.loop_data.loop_reset_pos)
      engine.seek(v, t.loop_data.loop_reset_pos)
    end
  else
    if t.loop_data.current_percent >= t.loop_data.percent then
      update_position(v, t.loop_data.loop_reset_pos)
      engine.seek(v, t.loop_data.loop_reset_pos)
    end     
  end
end










function param_menu_init()
  local sep = ": "

  params:add_taper("reverb_mix", "*"..sep.."mix", 0, 100, 50, 0, "%")
  params:set_action("reverb_mix", function(value) engine.reverb_mix(value / 100) end)

  params:add_taper("reverb_room", "*"..sep.."room", 0, 100, 50, 0, "%")
  params:set_action("reverb_room", function(value) engine.reverb_room(value / 100) end)

  params:add_taper("reverb_damp", "*"..sep.."damp", 0, 100, 50, 0, "%")
  params:set_action("reverb_damp", function(value) engine.reverb_damp(value / 100) end)

  params:add_separator()
  for v = 1, VOICES do
    params:add_file(v.."sample", v..sep.."sample")
    params:set_action(v.."sample", function(file) engine.read(v, file) end)
  end

  for v = 1, VOICES do
    params:add_separator()

    params:add_option(v.."play", v..sep.."play", {"off","on"}, 2)
    params:set_action(v.."play", function(x) engine.gate(v, x-1) end)
    
    params:add_taper(v.."volume", v..sep.."volume", -60, 20, 0, 0, "dB")
    params:set_action(v.."volume", function(value) engine.volume(v, math.pow(10, value / 20)) end)

    params:add_taper(v.."speed", v..sep.."speed", -200, 200, 100, 0, "%")
    params:set_action(v.."speed", function(value) 
      engine.speed(v, value / 100)
      tracks[v].state.speed = value
    end)

    params:add_taper(v.."jitter", v..sep.."jitter", 0, 500, 0, 5, "ms")
    params:set_action(v.."jitter", function(value) engine.jitter(v, value / 1000) end)

    params:add_taper(v.."size", v..sep.."size", 1, 500, 100, 5, "ms")
    params:set_action(v.."size", function(value) engine.size(v, value / 1000) end)

    params:add_taper(v.."density", v..sep.."density", 0, 512, 20, 6, "hz")
    params:set_action(v.."density", function(value) engine.density(v, value) end)

    params:add_taper(v.."pitch", v..sep.."pitch", -pitch_limit, pitch_limit, 0, 0, "st")
    params:set_action(v.."pitch", function(value) 
      engine.pitch(v, math.pow(0.5, -value / 12)) 
      tracks[v].state.pitch = value
    end)

    params:add_taper(v.."spread", v..sep.."spread", 0, 100, 0, 0, "%")
    params:set_action(v.."spread", function(value) engine.spread(v, value / 100) end)

    params:add_taper(v.."fade", v..sep.."att / dec", 1, 9000, 1000, 3, "ms")
    params:set_action(v.."fade", function(value) engine.envscale(v, value / 1000) end)

    params:add_taper(v.."loop_center_pos", v..sep.."loop pos", 0, 1, 0, 0, "%")
    params:set_action(v.."loop_center_pos", function(value) tracks[v].loop_data.loop_center_pos = value end)

    params:add_taper(v.."loop_percent", v..sep.."loop percent", 0, 1, 1, 0, "%")
    params:set_action(v.."loop_percent", function(value) tracks[v].loop_data.percent = util.clamp(value, 0.001, 1) end)
  end

  params:bang()
end