-- Script Well Hub | Rastreador de cartas "Morte de Memoria" (PlaceId 121031917607605)
-- Usa SOMENTE o que o servidor ja manda pra voce (CardRevealed, CardRemoved,
-- PairResult, BoardReset). NAO le carta fechada e NAO dispara remote nenhum.
--
-- Bolinha "Script Well Hub": arraste pra mover; toque pra abrir/fechar o painel.
-- O rastreador continua funcionando com o painel fechado.
--
-- O que faz: lembra cada carta que ja foi virada na SUA mesa (por voce ou pelo
-- oponente) e mostra o tipo nela. Estilo "Virada": a carta fechada passa a exibir
-- a figura do tipo (so no seu cliente); verde = par certo. Estilo "Icone": quadradinho
-- flutuando em cima. Tambem calcula a chance de cada tipo nas cartas desconhecidas.
--
-- Rode ANTES de o duelo comecar. Se entrar no meio, ele nao sabe o que ja saiu.
-- Estimativa: se o jogo trocar o baralho (outro modo), os numeros ficam errados.
-- NAO TESTADO no Delta (a logica de contagem foi testada com eventos do seu log).

--[[LOGIC-BEGIN]]
-- Estado de uma mesa: o que ja foi visto e quantos pares ja sairam.
local function newState(pairCfg)
    local types = {}
    for kind in pairs(pairCfg) do types[#types + 1] = kind end
    table.sort(types)
    return { cfg = pairCfg, types = types, known = {}, matched = {} }
end

local function resetState(st)
    st.known = {}
    st.matched = {}
end

local function onRevealed(st, idx, kind)
    if type(idx) == "number" and type(kind) == "string" then st.known[idx] = kind end
end

local function onRemoved(st, a, b)
    st.known[a] = nil
    st.known[b] = nil
end

local function onMatch(st, kind)
    if type(kind) == "string" then st.matched[kind] = (st.matched[kind] or 0) + 1 end
end

-- Resumo: por tipo -> quantas restam, quantas ja vistas, quantas desconhecidas, chance.
local function summary(st)
    local res = { types = {}, order = st.types, totalUnknown = 0, ready = {}, hitChance = 0 }
    local byType = {}
    for idx, kind in pairs(st.known) do
        byType[kind] = byType[kind] or {}
        table.insert(byType[kind], idx)
    end
    for _, kind in ipairs(st.types) do
        local total = (st.cfg[kind] or 0) * 2
        local left = total - (st.matched[kind] or 0) * 2
        local list = byType[kind] or {}
        table.sort(list)
        local unknown = math.max(left - #list, 0)
        res.types[kind] = { left = left, seen = #list, unknown = unknown, idx = list, prob = 0 }
        res.totalUnknown += unknown
        if #list >= 2 then table.insert(res.ready, { kind = kind, a = list[1], b = list[2] }) end
    end
    for _, kind in ipairs(st.types) do
        local t = res.types[kind]
        if res.totalUnknown > 0 then
            t.prob = t.unknown / res.totalUnknown
            -- virar uma desconhecida: acerta par se ja vi outra do mesmo tipo
            if t.seen >= 1 then res.hitChance += t.prob end
        end
    end
    return res
end
--[[LOGIC-END]]

-- ========== parte do jogo ==========
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local MK = RS:FindFirstChild("MemoryKill")
local Remotes = MK and MK:FindFirstChild("Remotes")
if not Remotes then
    warn("[Rastreador] ReplicatedStorage.MemoryKill.Remotes nao achado. Este e o jogo certo?")
    return
end

-- evita rodar duas vezes
local env = (getgenv and getgenv()) or _G
if env.MKTrackerStop then pcall(env.MKTrackerStop) end

local PAIRS = { BULLET = 6, SHIELD = 4, GUN = 6 }
pcall(function()
    local cfg = require(MK.Config)
    if type(cfg.PAIRS) == "table" then PAIRS = cfg.PAIRS end
end)

local st = newState(PAIRS)
local arenaCards = workspace:FindFirstChild("MatchOff_Arena") and workspace.MatchOff_Arena:FindFirstChild("Cards")
local conns, marks = {}, {}
local showMarks = true

local COLORS = {
    BULLET = Color3.fromRGB(255, 170, 60),
    SHIELD = Color3.fromRGB(90, 160, 255),
    GUN = Color3.fromRGB(255, 90, 90),
}

-- imagens de cada tipo (vistas no log da face das cartas); o script tambem
-- aprende a imagem real da carta quando ela e virada
local ICONS = {
    SHIELD = "rbxassetid://15540147793",
    GUN = "rbxassetid://12909703623",
    BULLET = "rbxassetid://18209609490",
}

local function cardInst(idx)
    return arenaCards and arenaCards:FindFirstChild("Card_" .. tostring(idx))
end

local function myTable() return lp:GetAttribute("DuelId") end

-- a carta e da minha mesa? (TableId da carta == DuelId do player)
local function mine(idx)
    local duel = myTable()
    if duel == nil then return false end
    local c = cardInst(idx)
    return c ~= nil and c:GetAttribute("TableId") == duel
end

local function posText(idx)
    local c = cardInst(idx)
    if c then return "L" .. tostring(c:GetAttribute("GridR")) .. "C" .. tostring(c:GetAttribute("GridC")) end
    return "#" .. tostring(idx)
end

-- ---------- GUI ----------
local gui = Instance.new("ScreenGui")
gui.Name = "MKRastreador"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 250, 0, 0)
frame.AutomaticSize = Enum.AutomaticSize.Y
frame.Position = UDim2.new(0, 8, 0.25, 0)
frame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
frame.BackgroundTransparency = 0.08
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Visible = false
frame.Parent = gui

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 6)
pad.PaddingBottom = UDim.new(0, 6)
pad.PaddingLeft = UDim.new(0, 6)
pad.PaddingRight = UDim.new(0, 6)
pad.Parent = frame

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = frame

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, 0, 0, 20)
titleLbl.BackgroundTransparency = 1
titleLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 14
titleLbl.Text = "Script Well Hub"
titleLbl.LayoutOrder = 0
titleLbl.Parent = frame

local info = Instance.new("TextLabel")
info.Size = UDim2.new(1, 0, 0, 0)
info.AutomaticSize = Enum.AutomaticSize.Y
info.BackgroundTransparency = 1
info.TextColor3 = Color3.fromRGB(235, 235, 235)
info.Font = Enum.Font.Code
info.TextSize = 12
info.TextWrapped = true
info.TextXAlignment = Enum.TextXAlignment.Left
info.TextYAlignment = Enum.TextYAlignment.Top
info.Text = "..."
info.LayoutOrder = 1
info.Parent = frame

local row = Instance.new("Frame")
row.Size = UDim2.new(1, 0, 0, 28)
row.BackgroundTransparency = 1
row.LayoutOrder = 2
row.Parent = frame

local function btn(text, x, w, color, fn, parent)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 1, 0)
    b.Position = UDim2.new(0, x, 0, 0)
    b.BackgroundColor3 = color
    b.BorderSizePixel = 0
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Text = text
    b.Parent = parent or row
    b.Activated:Connect(function() fn(b) end)
    return b
end

-- ---------- marcacao das cartas ja vistas ----------
-- Estilo "Virada": troca a textura do VERSO da carta (so no seu cliente) pela
--   figura do tipo, entao a carta fechada parece virada. Restaura ao sumir.
-- Estilo "Icone": quadradinho flutuando em cima da carta (modo alternativo).
local STYLE = "Virada"
local decalState = {} -- idx -> { decal, tex, color }

local function backDecal(card)
    for _, d in ipairs(card:GetDescendants()) do
        if d:IsA("Decal") and d.Name ~= "MK_IconDecal" then return d end
    end
    return nil
end

local function restoreDecal(idx)
    local s = decalState[idx]
    if s then
        if s.decal and s.decal.Parent then
            s.decal.Texture = s.tex
            s.decal.Color3 = s.color
        end
        decalState[idx] = nil
    end
end

local function applyDecal(idx, kind, paired)
    local card = cardInst(idx)
    local icon = ICONS[kind]
    if not card or not icon then return false end
    local s = decalState[idx]
    if not s or not s.decal or not s.decal.Parent then
        local d = backDecal(card)
        if not d then return false end
        s = { decal = d, tex = d.Texture, color = d.Color3 }
        decalState[idx] = s
    end
    s.decal.Texture = icon
    s.decal.Color3 = paired and Color3.fromRGB(150, 255, 170) or Color3.new(1, 1, 1)
    return true
end

local function ensureBillboard(idx, kind, paired)
    local card = cardInst(idx)
    if not card then return end
    local m = marks[idx]
    if not m then
        m = Instance.new("BillboardGui")
        m.AlwaysOnTop = true
        m.Size = UDim2.fromOffset(54, 54)
        m.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        m.Adornee = card

        local back = Instance.new("Frame")
        back.Name = "B"
        back.Size = UDim2.fromScale(1, 1)
        back.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
        back.BackgroundTransparency = 0.25
        back.BorderSizePixel = 0
        back.Parent = m
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = back
        local stroke = Instance.new("UIStroke")
        stroke.Name = "S"
        stroke.Thickness = 2
        stroke.Parent = back

        local img = Instance.new("ImageLabel")
        img.Name = "I"
        img.Size = UDim2.new(1, -8, 1, -8)
        img.Position = UDim2.fromOffset(4, 4)
        img.BackgroundTransparency = 1
        img.ScaleType = Enum.ScaleType.Fit
        img.Parent = back

        local txt = Instance.new("TextLabel")
        txt.Name = "T"
        txt.Size = UDim2.fromScale(1, 1)
        txt.BackgroundTransparency = 1
        txt.Font = Enum.Font.GothamBold
        txt.TextSize = 12
        txt.Visible = false
        txt.Parent = back

        m.Parent = gui
        marks[idx] = m
    end
    local back = m:FindFirstChild("B")
    local color = paired and Color3.fromRGB(120, 255, 140) or (COLORS[kind] or Color3.new(1, 1, 1))
    back.S.Color = color
    local icon = ICONS[kind]
    back.I.Image = icon or ""
    back.I.Visible = icon ~= nil
    back.T.Visible = icon == nil
    back.T.Text = kind
    back.T.TextColor3 = color
end

local function clearMarks()
    for idx in pairs(decalState) do restoreDecal(idx) end
    for idx, m in pairs(marks) do
        m:Destroy()
        marks[idx] = nil
    end
end

local function syncMarks(sum)
    -- limpa o que nao vale mais (carta fechada de novo, removida, estilo trocado...)
    for idx in pairs(decalState) do
        if (not showMarks) or STYLE ~= "Virada" or st.known[idx] == nil then restoreDecal(idx) end
    end
    for idx, m in pairs(marks) do
        if (not showMarks) or STYLE ~= "Icone" or st.known[idx] == nil then
            m:Destroy()
            marks[idx] = nil
        end
    end
    if not showMarks then return end
    for idx, kind in pairs(st.known) do
        local t = sum.types[kind]
        local paired = t ~= nil and t.seen >= 2
        if STYLE == "Virada" then
            if not applyDecal(idx, kind, paired) then ensureBillboard(idx, kind, paired) end
        else
            ensureBillboard(idx, kind, paired)
        end
    end
end

-- ---------- atualizacao da tela ----------
local function refresh()
    local duel = myTable()
    if duel == nil then
        info.Text = "Fora de duelo. Entre numa mesa e o rastreador comeca sozinho."
        clearMarks()
        return
    end
    local sum = summary(st)
    local lines = { "Mesa " .. tostring(duel) .. "  |  cartas desconhecidas: " .. sum.totalUnknown }
    for _, kind in ipairs(sum.order) do
        local t = sum.types[kind]
        lines[#lines + 1] = string.format("%-6s restam %2d | vistas %d | chance %2d%%",
            kind, t.left, t.seen, math.floor(t.prob * 100 + 0.5))
    end
    if #sum.ready > 0 then
        for _, p in ipairs(sum.ready) do
            lines[#lines + 1] = ">> PAR CERTO " .. p.kind .. ": " .. posText(p.a) .. " + " .. posText(p.b)
        end
    else
        lines[#lines + 1] = "Sem par certo agora."
        lines[#lines + 1] = string.format("Virar carta desconhecida: %d%% de achar par com uma ja vista.",
            math.floor(sum.hitChance * 100 + 0.5))
    end
    info.Text = table.concat(lines, "\n")
    syncMarks(sum)
end

local row2 = Instance.new("Frame")
row2.Size = UDim2.new(1, 0, 0, 28)
row2.BackgroundTransparency = 1
row2.LayoutOrder = 3
row2.Parent = frame

btn("Marcar: ON", 0, 80, Color3.fromRGB(40, 140, 60), function(b)
    showMarks = not showMarks
    b.Text = "Marcar: " .. (showMarks and "ON" or "OFF")
    b.BackgroundColor3 = showMarks and Color3.fromRGB(40, 140, 60) or Color3.fromRGB(150, 40, 40)
    refresh()
end)
btn("Estilo: Virada", 0, 208, Color3.fromRGB(60, 90, 160), function(b)
    STYLE = (STYLE == "Virada") and "Icone" or "Virada"
    b.Text = "Estilo: " .. STYLE
    refresh()
end, row2)
btn("Zerar", 86, 56, Color3.fromRGB(80, 80, 95), function()
    resetState(st)
    refresh()
end)

local function stop()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    clearMarks()
    gui:Destroy()
    env.MKTrackerStop = nil
end
env.MKTrackerStop = stop
btn("Sair", 148, 60, Color3.fromRGB(150, 40, 40), stop)

-- ---------- bolinha "Script Well Hub" (arrastavel; clique abre/fecha o painel) ----------
local UIS = game:GetService("UserInputService")

local ball = Instance.new("TextButton")
ball.Name = "Bolinha"
ball.Size = UDim2.fromOffset(66, 66)
ball.Position = UDim2.new(0, 10, 0.12, 0)
ball.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
ball.BorderSizePixel = 0
ball.AutoButtonColor = false
ball.Text = "Script\nWell\nHub"
ball.TextColor3 = Color3.fromRGB(255, 255, 255)
ball.Font = Enum.Font.GothamBold
ball.TextSize = 12
ball.ZIndex = 5
ball.Parent = gui

local ballCorner = Instance.new("UICorner")
ballCorner.CornerRadius = UDim.new(1, 0)
ballCorner.Parent = ball
local ballStroke = Instance.new("UIStroke")
ballStroke.Color = Color3.fromRGB(90, 160, 255)
ballStroke.Thickness = 2.5
ballStroke.Parent = ball

local function placePanelNextToBall()
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    local bx, by = ball.AbsolutePosition.X, ball.AbsolutePosition.Y
    local pw = 250
    local x = bx + ball.AbsoluteSize.X + 8
    if x + pw > vp.X then x = math.max(bx - pw - 8, 0) end
    local y = math.clamp(by, 0, math.max(vp.Y - 260, 0))
    frame.Position = UDim2.fromOffset(x, y)
end

local function togglePanel()
    frame.Visible = not frame.Visible
    ballStroke.Color = frame.Visible and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(90, 160, 255)
    if frame.Visible then
        placePanelNextToBall()
        pcall(refresh)
    end
end

-- arrasto manual: se mexeu menos de 8 px, conta como clique
local dragging, moved, dragStart, startPos = false, false, Vector2.new(), ball.Position
local function isPointer(i)
    return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end
conns[#conns + 1] = ball.InputBegan:Connect(function(input)
    if not isPointer(input) then return end
    dragging, moved = true, false
    dragStart, startPos = input.Position, ball.Position
    local c
    c = input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            c:Disconnect()
            dragging = false
            if not moved then togglePanel() end
        end
    end)
end)
conns[#conns + 1] = UIS.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local d = input.Position - dragStart
    if d.Magnitude > 8 then moved = true end
    if moved then
        ball.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        if frame.Visible then placePanelNextToBall() end
    end
end)

-- ---------- eventos que o servidor ja manda pra voce ----------
local function listen(name, fn)
    local r = Remotes:FindFirstChild(name)
    if r and r:IsA("RemoteEvent") then
        conns[#conns + 1] = r.OnClientEvent:Connect(function(...)
            local ok, err = pcall(fn, ...)
            if not ok then warn("[Rastreador] " .. name .. ": " .. tostring(err)) end
            pcall(refresh)
        end)
    else
        warn("[Rastreador] remote nao achado: " .. name)
    end
end

listen("CardRevealed", function(idx, kind)
    if not mine(idx) then return end
    onRevealed(st, idx, kind)
    -- aprende a imagem real da face (ela e preenchida logo apos o evento)
    task.delay(0.2, function()
        local c = cardInst(idx)
        if not c or type(kind) ~= "string" then return end
        for _, d in ipairs(c:GetDescendants()) do
            if d:IsA("ImageLabel") and d.Name == "IconImage" and d.Image ~= "" then
                if ICONS[kind] ~= d.Image then
                    ICONS[kind] = d.Image
                    pcall(refresh)
                end
                break
            end
        end
    end)
end)
listen("CardRemoved", function(a, b)
    if mine(a) or mine(b) then onRemoved(st, a, b) end
end)
listen("PairResult", function(tableId, _, result, kind)
    if tableId == myTable() and result == "MATCH" then onMatch(st, kind) end
end)
listen("BoardReset", function(tableId)
    if tableId == myTable() then resetState(st) end
end)

conns[#conns + 1] = lp:GetAttributeChangedSignal("DuelId"):Connect(function()
    resetState(st)
    refresh()
end)

refresh()
task.spawn(function()
    while gui.Parent do
        task.wait(1)
        pcall(refresh)
    end
end)
print("[Rastreador] Script Well Hub pronto. Toque na bolinha para abrir/fechar o painel. Baralho:", PAIRS.BULLET, "BULLET,", PAIRS.SHIELD, "SHIELD,", PAIRS.GUN, "GUN (pares)")
