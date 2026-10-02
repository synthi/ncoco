-- Comparacion de rendimiento del punto #13: recorrido lineal vs busqueda
-- binaria en la ventana de tiempo del secuenciador.
--
-- Mide el trabajo REAL por ventana de 33 ms (el clock.sleep(1/30) de
-- ncoco.lua:267) con 4 secuenciadores a la vez, que es como corre de verdad.

--------------------------------------------------------------------
local function buscar_lineal(data, t_start, t_end)
  local n = 0
  for _, event in ipairs(data) do
    if event.dt >= t_start and event.dt < t_end then n = n + 1 end
  end
  return n
end

local function buscar_binaria(data, t_start, t_end)
  local n_total = #data
  local n = 0
  if n_total == 0 then return 0 end

  local lo, hi = 1, n_total + 1
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if data[mid].dt < t_start then lo = mid + 1 else hi = mid end
  end
  local i = lo
  while i <= n_total and data[i].dt < t_end do
    n = n + 1
    i = i + 1
  end
  return n
end

local function generar(n, duracion, semilla)
  math.randomseed(semilla)
  local d = {}
  for i = 1, n do
    d[i] = { x = i % 16, y = i % 8, z = 1, dt = (i - 1) * (duracion / n) }
  end
  return d
end

--------------------------------------------------------------------
print('== #13: coste por fotograma (4 secuenciadores, ventana de 33 ms) ==')
print('')
print(string.format('  %-22s %14s %14s %8s', 'secuenciadores', 'lineal/seg', 'binaria/seg', 'ahorro'))

for _, caso in ipairs{ 4, 20, 100, 500, 2000, 10000 } do
  -- 4 secuenciadores, cada uno con 'caso' eventos en 30 s
  local seqs = {}
  for i = 1, 4 do seqs[i] = generar(caso, 30.0, i * 7) end

  -- una ventana de 33 ms: el playhead avanza de 33 ms en 33 ms
  local dt_win = 33 / 1000.0
  local iter = 200

  -- lineal
  local t0 = os.clock()
  local suma_l = 0
  for k = 1, iter do
    local t0w = (k - 1) * dt_win
    for i = 1, 4 do suma_l = suma_l + buscar_lineal(seqs[i], t0w, t0w + dt_win) end
  end
  local t_lineal = os.clock() - t0

  -- binaria
  local t1 = os.clock()
  local suma_b = 0
  for k = 1, iter do
    local t0w = (k - 1) * dt_win
    for i = 1, 4 do suma_b = suma_b + buscar_binaria(seqs[i], t0w, t0w + dt_win) end
  end
  local t_bin = os.clock() - t1

  -- a fotogramas de 30 Hz = 30 ventanas por segundo
  local por_seg_l = (t_lineal / iter) * 30
  local por_seg_b = (t_bin / iter) * 30

  local etiqueta
  if caso == 4 then etiqueta = '4 (uso normal)'
  elseif caso == 100 then etiqueta = '100'
  elseif caso == 10000 then etiqueta = '10000 (tope)'
  else etiqueta = tostring(caso) end

  if suma_l ~= suma_b then
    print(string.format('  %-22s DISCORDANCIA: lineal=%d binaria=%d', etiqueta, suma_l, suma_b))
  else
    print(string.format('  %-22s %14.1f %14.1f %7.0fx', etiqueta,
      por_seg_l * 1e6, por_seg_b * 1e6, por_seg_l / por_seg_b))
  end
end

print('')
print('(los numeros son comparaciones por segundo en esta maquina)')
print('el objetivo es el caso de 4 eventos: ahi el secuenciador va sobrado y')
print('cualquier diferencia de CPU es imperceptible para el oido.')