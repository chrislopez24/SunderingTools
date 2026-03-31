**MANDATORY** ALWAYS TO CHECK LATEST BLIZZARD API DOCS FOR INFORMATION ABOUT SECRET VALUES IN API https://github.com/Gethe/wow-ui-source/tree/live/Interface/AddOns/Blizzard_APIDocumentationGenerated
**MANDATORY** ALWAYS CHECK MINICC, LUXXINTERRUPTTRACKER AND KRYOS ADDON ON THE SAME LEVEL OF FOLDER OF SUNDERINGTOOLS TO MATCH FUNCIONALITY EVEN THO WE PUSH BOUNDARIES TO OFFER MORE AND BETTER QUALITY

CHATGPT PRO 5.4 SAYS THIS, HAVE THIS IN MIND

Ya tengo un eje claro para las pruebas: SendAddonMessage parece usable en party/raid y el punto a testear es si datos “secret” acaban serializados o si APIs no restringidas como GetSpellCooldownDuration/GetSpellChargeDuration, junto con auras visibles o el Cooldown Manager, permiten reconstruir CDs completos.

Además he visto que C_CooldownViewer parece dar metadatos del Cooldown Manager, no el estado dinámico, y que las APIs DurationObject pintan widgets sin revelar números. Esa diferencia es una superficie de prueba muy buena para distinguir display permitido de fuga real.

Thought for 31m 36s

No te voy a dar una guía para usar un bypass en live. Sí te voy a dar un plan muy concreto para encontrar fugas reales y reportarlas bien.

Mirando la docu que pasaste, yo no perdería tiempo intentando leer el CD de otro jugador directamente con C_Spell. Esas funciones toman solo spellIdentifier, no unit, y las rutas obvias están marcadas como secretas: GetSpellCooldown, GetSpellCharges, GetSpellCastCount y GetSpellDisplayCount llevan SecretWhenSpellCooldownRestricted. Blizzard, además, dice que el objetivo es justo ese: que los addons puedan mostrar estado, pero no conocer con certeza cooldowns o debuffs.

La zona buena para research es esta asimetría: GetSpellCooldownDuration y GetSpellChargeDuration devuelven un LuaDurationObject sin el flag SecretWhenSpellCooldownRestricted, y en auras pasa algo parecido con GetAuraDuration y GetCooldownAuraBySpellID, mientras muchos getters de aura sí están marcados como SecretWhenUnitAuraRestricted. Eso no prueba un bypass. De hecho, encaja bastante con la idea oficial de “mostrar sin saber”: el objeto puede existir para pintar una barra sin exponer números. La pregunta útil no es “¿me devuelve algo?”, sino “¿ese objeto es opaco o se puede abrir hasta sacar tiempo restante exacto?”.

Para party/raid sin cooperación, la superficie real está en auras visibles y eventos públicos. GetUnitAuraBySpellID y GetPlayerAuraBySpellID exigen aura no secreta, y la propia doc avisa de que GetUnitAuraBySpellID puede devolver nil si la unidad no es visible. COMBAT_LOG_EVENT y COMBAT_LOG_EVENT_UNFILTERED siguen existiendo, pero con restricciones. Eso te deja dos rutas reales: auras visibles y reconstrucción aproximada desde eventos públicos.

Para grupos coordinados, addon comms siguen vivos: SendAddonMessage manda texto a PARTY/RAID, pero con SecretArguments = "NotAllowed". Traducido: el camino viable para “recuperar OmniCD” en premades no es leer al otro desde fuera, sino que el dueño del spell sea autoritativo sobre su propio estado y lo sincronice, siempre que el cliente no considere ilegal ese dato en salida. Si encuentras que un estado que debía quedarse opaco acaba saliendo como texto útil a otro cliente, eso sí es un reporte fuerte.

Yo atacaría el research en este orden:

opacidad de LuaDurationObject;
combo aura visible -> auraInstanceID -> GetAuraDuration;
frontera de addon comms desde el cliente dueño;
huecos del Cooldown Manager;
reconstrucción por combat log. Blizzard sigue ampliando el Cooldown Manager con hotfixes, así que úsalo también como control positivo: han añadido o corregido seguimiento para cosas como Burning Rush, Divine Purpose, Judgment of Justice, Ancient Arts, Dash, Tiger Dash, Forestwalk, Ursine Vigor, Matted Fur, Frenzied Regeneration, Dance of the Wind, Transcendence y Maul.
Pasos concretos
1) Haz un addon mínimo de probe

Pega esto en un .lua cargado por un addon vacío:

local function dumpObject(tag, obj)
    print(tag, obj and tostring(obj) or "nil")
    if not obj then return end

    local mt = getmetatable(obj)
    local idx = mt and mt.__index
    if type(idx) ~= "table" then
        print(tag, "no enumerable __index")
        return
    end

    for name, fn in pairs(idx) do
        if type(fn) == "function" and (
            name:find("Get") or
            name:find("Remain") or
            name:find("Expire") or
            name:find("Progress") or
            name:find("Start") or
            name:find("End")
        ) then
            local ok, a, b, c = pcall(fn, obj)
            print(tag, name, ok, a, b, c)
        end
    end
end

SLASH_RSPELL1 = "/rspell"
SlashCmdList.RSPELL = function(msg)
    local spellID = tonumber(msg)
    if not spellID then
        print("uso: /rspell spellID")
        return
    end

    local ok1, cd = pcall(C_Spell.GetSpellCooldown, spellID)
    local ok2, cdDur = pcall(C_Spell.GetSpellCooldownDuration, spellID)
    local ok3, ch = pcall(C_Spell.GetSpellCharges, spellID)
    local ok4, chDur = pcall(C_Spell.GetSpellChargeDuration, spellID)
    local ok5, disp = pcall(C_Spell.GetSpellDisplayCount, spellID)

    print("spell", spellID,
        "GetSpellCooldown", ok1, cd and "non-nil" or "nil",
        "GetSpellCooldownDuration", ok2, cdDur and "non-nil" or "nil",
        "GetSpellCharges", ok3, ch and "non-nil" or "nil",
        "GetSpellChargeDuration", ok4, chDur and "non-nil" or "nil",
        "GetSpellDisplayCount", ok5, disp)

    dumpObject("CooldownDuration:" .. spellID, cdDur)
    dumpObject("ChargeDuration:" .. spellID, chDur)
end

SLASH_RAURA1 = "/raura"
SlashCmdList.RAURA = function(msg)
    local unit, spell = msg:match("^(%S+)%s+(%d+)$")
    local spellID = tonumber(spell)
    if not unit or not spellID then
        print("uso: /raura unit spellID")
        return
    end

    local ok1, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)
    local ok2, map = pcall(C_UnitAuras.GetCooldownAuraBySpellID, spellID)

    print("aura", unit, spellID,
        "GetUnitAuraBySpellID", ok1, aura and aura.auraInstanceID or "nil",
        "GetCooldownAuraBySpellID", ok2, map)

    if aura and aura.auraInstanceID then
        local ok3, dur = pcall(C_UnitAuras.GetAuraDuration, unit, aura.auraInstanceID)
        print("GetAuraDuration", ok3, dur and "non-nil" or "nil")
        dumpObject("AuraDuration:" .. unit .. ":" .. spellID, dur)
    end
end

C_ChatInfo.RegisterAddonMessagePrefix("RPROBE")

SLASH_RCOMM1 = "/rcomm"
SlashCmdList.RCOMM = function(msg)
    local payload = (msg ~= "" and msg) or "ok"
    local result = C_ChatInfo.SendAddonMessage("RPROBE", payload, "PARTY")
    print("SendAddonMessage result", tostring(result), "payload", payload)
end

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender = ...
        if prefix == "RPROBE" then
            print("RPROBE recv", channel, sender, text)
        end
    end
end)
2) Elige bien los spells

Usa dos tipos de spells:

Uno de control, que Blizzard ya haya metido o arreglado en Cooldown Manager en tu build actual.
Uno parecido que aún no aparezca allí para tu clase o para el caso que quieres probar.

3) Prueba primero el cliente dueño

En el personaje que lanza el spell:

ejecuta /rspell SPELLID con el spell listo;
vuelve a ejecutar justo después de usarlo;
otra vez a mitad del CD;
otra vez casi al final.

Lo importante no es que GetSpellCooldownDuration devuelva “algo”. Lo importante es si dumpObject saca valores útiles como remaining, start, end o progress, mientras GetSpellCooldown o GetSpellCharges están capados o no te dan la misma info. Si el LuaDurationObject solo es un handle opaco, eso huele a diseño previsto. Si te da tiempo exacto legible, ya tienes una posible fuga.

4) Luego prueba auras visibles

Con spells que dejan buff o debuff visible, haz:

/raura player SPELLID
/raura party1 SPELLID
/raura target SPELLID

Hazlo en cuatro estados:

con el aura activa y visible;
con la unidad visible pero sin target/focus;
con la unidad fuera de visibilidad;
con el aura ya caída.

Aquí buscas tres cosas:

si GetUnitAuraBySpellID devuelve aura donde no debería;
si GetAuraDuration da un objeto legible aunque el aura base esté restringida;
si GetCooldownAuraBySpellID te da un mapeo útil para spells que Blizzard quiere ocultar.
5) Solo después mira addon comms

Primero, usa /rcomm hola como control para ver que la mensajería funciona entre dos clientes del grupo.

La prueba útil aquí no es montar un tracker. Es esta: si antes has visto un estado sospechoso en el cliente dueño, comprueba en entorno privado si el cliente te deja resumir ese estado en una salida útil para otro cliente. Si eso cruza, ese es el centro del reporte. Si no cruza, ya sabes que por esa vía no vas a reconstruir OmniCD cooperativo.

6) Haz una pasada de combat log

Añade logging temporal para COMBAT_LOG_EVENT y COMBAT_LOG_EVENT_UNFILTERED y captura el payload bruto alrededor de un cast. No busques “que haya eventos”; ya sabes por la doc que existen. Busca esto: si el observer recibe suficiente detalle para reconstruir el ready time exacto de un spell no soportado, sin sync del dueño y sin aura visible, entonces sí tienes una fuga interesante.

Qué cuenta como bug bueno

Esto sí merece reporte claro:

GetSpellCooldown o GetSpellCharges no te dan el dato legible, pero el LuaDurationObject sí te lo da con precisión suficiente para reconstruir el CD.
GetUnitAuraBySpellID o GetPlayerAuraBySpellID devuelven una aura que la doc marca como no secreta solo bajo condiciones más limitadas.
GetAuraDuration te da duración legible de una aura que no deberías poder conocer.
Un estado que debía quedarse opaco sale del cliente dueño y llega por addon comms de forma útil.
Un spell que Blizzard ya dice que entra en Cooldown Manager sigue fallando por talento, forma, override o build concreta.

Esto no basta por sí solo:

que el objeto exista;
que una aura visible tenga duración visible;
que puedas estimar un CD fijo desde un cast público;
que un spell no esté aún en Cooldown Manager si Blizzard no ha dicho que ya debería estar.
Cómo escribir el reporte

Usa este formato:

build exacta;
spellID;
clase, spec y talentos;
si el test es self, party, raid, target o nameplate;
si la unidad estaba visible o no;
secuencia exacta de llamadas;
salida cruda del chat/log;
esperado;
actual;
impacto práctico.

Títulos útiles:

C_Spell.GetSpellCooldownDuration returns readable time for a cooldown hidden by GetSpellCooldown
C_UnitAuras.GetAuraDuration exposes readable duration for a restricted aura instance
Secret cooldown state can be turned into useful addon comm payload
Cooldown Manager tracking missing for <spell> in <talent/form/build>

Mi lectura final es esta: para pugs, no veo una vía estable para volver a la OmniCD vieja exacta. Para premades, la única ruta realista es sync cooperativo del dueño del spell, y tu research debería centrarse en si los LuaDurationObject son de verdad opacos o no. Si luego me pasas el dump de un spellID concreto, te digo rápido si eso huele a diseño previsto o a fuga seria.
