#!/usr/bin/env python3
"""Generates i18n/strings.csv (keys,en,es). Run from the game folder."""
import csv

S = []
def a(k, en, es): S.append((k, en, es))

# --- UI
a("TITLE", "DELVE", "DELVE")
a("SUBTITLE", "Twelve floors down. One ember heart. No second chances.", "Doce pisos bajo tierra. Un corazón de ascuas. Sin segundas oportunidades.")
a("CONTINUE", "Continue", "Continuar")
a("CONTINUE_INFO", "Depth {0} · Level {1} · Turn {2}", "Profundidad {0} · Nivel {1} · Turno {2}")
a("NEW_RUN", "New run", "Nueva partida")
a("HOW_TO", "How to play", "Cómo jugar")
a("LANG_BTN", "Español", "English")
a("HIGH_SCORES", "High scores", "Mejores puntuaciones")
a("NO_SCORES", "No runs yet. The dungeon awaits.", "Aún no hay partidas. La mazmorra espera.")
a("SCORE_ROW", "Depth {0} · {1}", "Prof. {0} · {1}")
a("RUNS_LINE", "Runs {0} · Escapes {1}", "Partidas {0} · Huidas {1}")
a("VICTORY", "Victory", "Victoria")
a("ABANDONED", "Abandoned", "Abandonada")
a("BTN_WAIT", "Wait", "Esperar")
a("BTN_SEARCH", "Search", "Buscar")
a("BTN_GRAB", "Grab", "Coger")
a("BTN_STAIRS", "Stairs", "Bajar")
a("BTN_PACK", "Pack", "Mochila")
a("BTN_MAP", "Map", "Mapa")
a("HUD_DEPTH", "Depth {0}", "Prof. {0}")
a("HUD_LV", "Lv {0}", "Nv {0}")
a("H_HUNGRY", "Hungry", "Hambre")
a("H_WEAK", "Weak", "Débil")
a("H_STARVING", "Starving", "Famélico")
a("ST_HASTE", "Fast", "Rápido")
a("ST_CONF", "Confused", "Confuso")
a("ST_POIS", "Poisoned", "Envenenado")
a("GENERATING", "Descending to depth {0}…", "Bajando a la profundidad {0}…")
a("PACK_TITLE", "Pack {0}/{1}", "Mochila {0}/{1}")
a("EQUIPPED", "in use", "en uso")
a("PACK_HINT", "Tap an item to see what you can do with it.", "Toca un objeto para ver qué puedes hacer con él.")
a("ACT_QUAFF", "Drink", "Beber")
a("ACT_READ", "Read", "Leer")
a("ACT_EAT", "Eat", "Comer")
a("ACT_ZAP", "Zap", "Usar")
a("ACT_WIELD", "Wield", "Empuñar")
a("ACT_WEAR", "Wear", "Vestir")
a("ACT_REMOVE", "Remove", "Quitar")
a("ACT_THROW", "Throw", "Lanzar")
a("ACT_DROP", "Drop", "Soltar")
a("CLOSE", "Close", "Cerrar")
a("AIM_THROW", "Tap a target to throw", "Toca un objetivo para lanzar")
a("AIM_ZAP", "Tap a direction to zap", "Toca una dirección para usar la varita")
a("CANCEL", "Cancel", "Cancelar")
a("PAUSED", "Paused", "Pausa")
a("MENU_RESUME", "Resume", "Reanudar")
a("MENU_LOG", "Message log", "Registro")
a("MENU_MAIN", "Save & quit to menu", "Guardar y salir al menú")
a("MENU_ABANDON", "Abandon run", "Abandonar partida")
a("CONFIRM_ABANDON", "Abandon this run? It will count as a death.", "¿Abandonar esta partida? Contará como una muerte.")
a("CONFIRM_NEW", "Start a new run? Your current run will be lost.", "¿Empezar otra partida? Perderás la actual.")
a("YES", "Yes", "Sí")
a("NO", "No", "No")
a("DEATH_TITLE", "YOU DIED", "HAS MUERTO")
a("WIN_TITLE", "YOU ESCAPED", "HAS ESCAPADO")
a("DEATH_CAUSE", "Slain by {0} on depth {1}", "Muerto por {0} en la profundidad {1}")
a("WIN_CAUSE", "You carried the Heart of Embers out of the depths.", "Sacaste el Corazón de Ascuas de las profundidades.")
a("QUIT_CAUSE", "Abandoned on depth {0}", "Abandonada en la profundidad {0}")
a("STAT_DEPTH", "Depth", "Profundidad")
a("STAT_TURNS", "Turns", "Turnos")
a("STAT_LEVEL", "Level", "Nivel")
a("STAT_GOLD", "Gold", "Oro")
a("STAT_KILLS", "Kills", "Bajas")
a("STAT_SCORE", "Score", "Puntos")
a("NEW_RECORD", "New high score!", "¡Nuevo récord!")
a("RANKED", "Rank #{0} on your table", "Puesto n.º {0} en tu tabla")
a("SEED", "Seed {0}", "Semilla {0}")
a("MAP_TITLE", "Depth {0}", "Profundidad {0}")
a("TAP_CLOSE", "Tap anywhere to close", "Toca para cerrar")
a("MENU_BTN", "Menu", "Menú")
a("LOG_TITLE", "Message log", "Registro de mensajes")
a("HELP_TITLE", "How to play", "Cómo jugar")
a("HELP_BODY",
  "Reach depth 12, defeat the Ashen King and carry off the Heart of Embers.\n\n"
  "• Tap a tile to walk there. Tap next to a monster to attack it. Swipe for a single step.\n"
  "• Tap yourself to pick up items, take the stairs or wait a turn.\n"
  "• Long-press anything to inspect it.\n"
  "• Potions, scrolls and wands are unidentified: colours and labels change every run. Try them to learn what they do — or find a scroll of identify.\n"
  "• Weapons and armour may be cursed: you can't take them off until enchanted.\n"
  "• Eat when Hungry. You heal slowly over time.\n"
  "• Your run is saved every turn. Death is permanent.",
  "Llega a la profundidad 12, derrota al Rey Ceniciento y llévate el Corazón de Ascuas.\n\n"
  "• Toca una casilla para caminar hasta ella. Toca junto a un monstruo para atacarlo. Desliza para dar un solo paso.\n"
  "• Tócate a ti mismo para coger objetos, bajar escaleras o esperar un turno.\n"
  "• Mantén pulsado cualquier cosa para examinarla.\n"
  "• Pociones, pergaminos y varitas no están identificados: sus colores y etiquetas cambian en cada partida. Pruébalos para saber qué hacen, o busca un pergamino de identificar.\n"
  "• Las armas y armaduras pueden estar malditas: no podrás quitártelas hasta encantarlas.\n"
  "• Come cuando tengas Hambre. Te curas poco a poco.\n"
  "• La partida se guarda en cada turno. La muerte es permanente.")

# --- monsters: id, en name, es name (with article)
MON = [
 ("rat", "rat", "la rata"), ("bat", "bat", "el murciélago"), ("goblin", "goblin", "el trasgo"),
 ("dog", "jackal", "el chacal"), ("slime", "green ooze", "el cieno verde"),
 ("archer", "goblin archer", "el arquero trasgo"), ("imp", "imp", "el diablillo"),
 ("zombie", "zombie", "el zombi"), ("skeleton", "skeleton", "el esqueleto"), ("orc", "orc", "el orco"),
 ("spider", "cave spider", "la araña de cueva"), ("wisp", "will-o'-wisp", "el fuego fatuo"),
 ("cultist", "ash cultist", "el sectario de ceniza"), ("troll", "troll", "el trol"),
 ("wraith", "wraith", "el espectro"), ("ogre", "ogre", "el ogro"), ("king", "Ashen King", "el Rey Ceniciento"),
]
for mid, en, es in MON:
    k = mid.upper()
    art_en = "the " + en
    a("M_" + k, art_en, es)
    a("MN_" + k, en, es.split(" ", 1)[1])
a("SHOOT_ARCHER", "{0} shoots an arrow.", "{0} dispara una flecha.")
a("SHOOT_WISP", "{0} crackles with light.", "{0} chisporrotea con luz.")
a("SHOOT_CULTIST", "{0} hurls a cinder bolt.", "{0} lanza un rayo de brasas.")
a("SHOOT_KING", "{0} hurls ashen fire.", "{0} arroja fuego ceniciento.")

# --- items
IT = [
 ("dagger", "dagger", "daga"), ("short_sword", "short sword", "espada corta"), ("spear", "spear", "lanza"),
 ("mace", "mace", "maza"), ("long_sword", "long sword", "espada larga"), ("battle_axe", "battle axe", "hacha de guerra"),
 ("darts", "dart", "dardo"), ("leather", "leather armour", "armadura de cuero"), ("ring_mail", "ring mail", "cota de anillas"),
 ("chain_mail", "chain mail", "cota de malla"), ("scale_mail", "scale mail", "cota de escamas"), ("plate", "plate armour", "armadura de placas"),
 ("ration", "food ration", "ración de comida"), ("apple", "apple", "manzana"), ("gold", "gold", "oro"),
 ("amulet", "Heart of Embers", "Corazón de Ascuas"),
 ("p_heal", "potion of healing", "poción de curación"), ("p_vigor", "potion of vigour", "poción de vigor"),
 ("p_might", "potion of might", "poción de fuerza"), ("p_haste", "potion of haste", "poción de celeridad"),
 ("p_sight", "potion of far sight", "poción de clarividencia"), ("p_confuse", "potion of confusion", "poción de confusión"),
 ("p_poison", "potion of poison", "poción de veneno"), ("p_sleep", "potion of sleep", "poción de sueño"),
 ("p_xp", "potion of insight", "poción de experiencia"),
 ("s_identify", "scroll of identify", "pergamino de identificar"), ("s_teleport", "scroll of teleport", "pergamino de teletransporte"),
 ("s_enchant_w", "scroll of sharpness", "pergamino de afilado"), ("s_enchant_a", "scroll of warding", "pergamino de protección"),
 ("s_map", "scroll of mapping", "pergamino de cartografía"), ("s_fear", "scroll of dread", "pergamino de pavor"),
 ("s_fire", "scroll of fire", "pergamino de fuego"), ("s_summon", "scroll of summoning", "pergamino de invocación"),
 ("w_lightning", "wand of lightning", "varita de relámpago"), ("w_sleep", "wand of slumber", "varita de letargo"),
 ("w_force", "wand of force", "varita de fuerza"),
]
for iid, en, es in IT:
    a("I_" + iid.upper(), en, es)
D = {
 "ration": ("A filling meal. Keeps hunger away for a long time.", "Una comida contundente. Aleja el hambre durante mucho tiempo."),
 "apple": ("A crisp apple. A small snack.", "Una manzana crujiente. Un tentempié."),
 "gold": ("Shiny coins. Adds to your score.", "Monedas brillantes. Suman puntos."),
 "amulet": ("The prize of the depths.", "El tesoro de las profundidades."),
 "p_heal": ("Heals wounds and cures poison and confusion.", "Cura heridas, veneno y confusión."),
 "p_vigor": ("Restores all health and raises your maximum.", "Restaura toda la salud y aumenta el máximo."),
 "p_might": ("Permanently makes your blows stronger.", "Hace tus golpes más fuertes para siempre."),
 "p_haste": ("You move twice as fast for a while.", "Te mueves el doble de rápido un tiempo."),
 "p_sight": ("Reveals this floor and every creature on it.", "Revela este piso y a todas sus criaturas."),
 "p_confuse": ("Makes you stumble around at random.", "Te hace tropezar sin rumbo."),
 "p_poison": ("Poisonous. Best thrown away.", "Venenosa. Mejor tirarla."),
 "p_sleep": ("Puts you to sleep. Dangerous near monsters.", "Te duerme. Peligrosa cerca de monstruos."),
 "p_xp": ("Grants a whole experience level.", "Otorga un nivel de experiencia entero."),
 "s_identify": ("Reveals the nature of one unknown item.", "Revela la naturaleza de un objeto desconocido."),
 "s_teleport": ("Whisks you to a random spot on this floor.", "Te lleva a un punto al azar de este piso."),
 "s_enchant_w": ("Improves your weapon and lifts its curse.", "Mejora tu arma y rompe su maldición."),
 "s_enchant_a": ("Improves your armour and lifts its curse.", "Mejora tu armadura y rompe su maldición."),
 "s_map": ("Draws the whole floor into your memory.", "Graba todo el piso en tu memoria."),
 "s_fear": ("Visible monsters flee from you in terror.", "Los monstruos visibles huyen aterrados."),
 "s_fire": ("Engulfs everything nearby in flames — you too.", "Envuelve en llamas todo lo cercano, a ti también."),
 "s_summon": ("Calls monsters to your side. Not friendly ones.", "Atrae monstruos a tu lado. No amistosos."),
 "w_lightning": ("A bolt that pierces every monster in a line.", "Un rayo que atraviesa a todos los monstruos en línea."),
 "w_sleep": ("Puts the first monster hit into a deep sleep.", "Duerme profundamente al primer monstruo alcanzado."),
 "w_force": ("Slams the first monster hit and knocks it back.", "Golpea al primer monstruo y lo empuja."),
}
for k, (en, es) in D.items():
    a("D_" + k.upper(), en, es)
a("D_UNK_POTION", "An unknown potion. Drink it to find out — if you dare.", "Una poción desconocida. Bébela para averiguarlo, si te atreves.")
a("D_UNK_SCROLL", "An unknown scroll. Reading it reveals its power.", "Un pergamino desconocido. Leerlo revela su poder.")
a("D_UNK_WAND", "An unknown wand. Zap it at something to learn more.", "Una varita desconocida. Úsala contra algo para descubrirla.")
for k, en, es in [("C_RED", "red", "roja"), ("C_BLUE", "blue", "azul"), ("C_GREEN", "green", "verde"), ("C_AMBER", "amber", "ámbar"),
                  ("C_VIOLET", "violet", "violeta"), ("C_PINK", "pink", "rosa"), ("C_TEAL", "teal", "turquesa"), ("C_MILKY", "milky", "lechosa"),
                  ("C_BLACK", "smoky", "humeante"), ("C_GOLDEN", "golden", "dorada"), ("C_FIZZY", "fizzy", "burbujeante"),
                  ("W_OAK", "oak", "roble"), ("W_BONE", "bone", "hueso"), ("W_ASH", "ash", "fresno"), ("W_IRON", "iron", "hierro"),
                  ("W_GLASS", "glass", "cristal"), ("W_EBONY", "ebony", "ébano")]:
    a(k, en, es)
a("GOLD_N", "{0} gold", "{0} de oro")
a("ENCH", "{0} {1}", "{1} {0}")
a("POTION_UNK", "{0} potion", "poción {0}")
a("SCROLL_UNK", "scroll labelled {0}", "pergamino «{0}»")
a("WAND_UNK", "{0} wand", "varita de {0}")
a("CHARGES", "{0} ({1})", "{0} ({1})")
a("COUNT", "{0} ×{1}", "{0} ×{1}")
a("LIST2", "{0}, {1}", "{0}, {1}")
a("INFO_DMG", "Damage {0}", "Daño {0}")
a("INFO_THROW", "Thrown damage {0}", "Daño lanzado {0}")
a("INFO_THROWABLE", "Can be thrown.", "Se puede lanzar.")
a("INFO_UNK_ENCH", "Enchantment unknown until used.", "Encantamiento desconocido hasta usarlo.")
a("INFO_CURSED", "Cursed: it won't come off.", "Maldito: no se puede quitar.")
a("INFO_AC", "Armour {0}", "Armadura {0}")

# --- messages
M = [
 ("MSG_WELCOME", "Find the Heart of Embers, twelve floors below.", "Encuentra el Corazón de Ascuas, doce pisos más abajo."),
 ("MSG_BOSS_FLOOR", "Depth 12. The air smells of ash. The Ashen King awaits.", "Profundidad 12. El aire huele a ceniza. El Rey Ceniciento espera."),
 ("MSG_DEPTH", "You arrive at depth {0}.", "Llegas a la profundidad {0}."),
 ("MSG_BUMP", "You stumble into a wall.", "Tropiezas con una pared."),
 ("MSG_OPEN_DOOR", "You open the door.", "Abres la puerta."),
 ("MSG_GOLD", "You pick up {0} gold.", "Recoges {0} de oro."),
 ("MSG_SEE_HERE", "You see here: {0}.", "Ves aquí: {0}."),
 ("MSG_SEE_SEVERAL", "There are {0} items here.", "Hay {0} objetos aquí."),
 ("MSG_ON_STAIRS", "Stairs lead down. Tap yourself to descend.", "Unas escaleras bajan. Tócate para descender."),
 ("MSG_TRAP_DART", "A dart shoots out of the floor!", "¡Un dardo sale disparado del suelo!"),
 ("MSG_POISONED", "You feel very sick.", "Te sientes muy enfermo."),
 ("MSG_TRAP_TELE", "A rune flares and the world twists!", "¡Una runa destella y el mundo se retuerce!"),
 ("MSG_TRAP_ALARM", "A shrill alarm echoes through the floor!", "¡Una alarma estridente resuena por el piso!"),
 ("MSG_FOUND_TRAP", "You find a hidden trap.", "Encuentras una trampa oculta."),
 ("MSG_NOTHING_HERE", "There is nothing here.", "Aquí no hay nada."),
 ("MSG_AMULET", "You take the Heart of Embers! Its warmth lifts you out of the dark.", "¡Tomas el Corazón de Ascuas! Su calor te saca de la oscuridad."),
 ("MSG_PACK_FULL", "Your pack is full.", "Tu mochila está llena."),
 ("MSG_PICKUP", "You pick up: {0}.", "Recoges: {0}."),
 ("MSG_NO_STAIRS", "There are no stairs here.", "Aquí no hay escaleras."),
 ("MSG_QUAFF", "You drink the {0}.", "Bebes: {0}."),
 ("MSG_READ", "You read the {0}.", "Lees: {0}."),
 ("MSG_EAT_RATION", "That hit the spot.", "Eso te ha sentado de maravilla."),
 ("MSG_EAT_APPLE", "Crunchy and sweet.", "Crujiente y dulce."),
 ("MSG_CURSED_STUCK", "You can't. It's cursed!", "No puedes. ¡Está maldito!"),
 ("MSG_REMOVE", "You take off: {0}.", "Te quitas: {0}."),
 ("MSG_WIELD", "You wield: {0}.", "Empuñas: {0}."),
 ("MSG_WEAR", "You put on: {0}.", "Te pones: {0}."),
 ("MSG_CURSED", "A chill runs through you. It's cursed!", "Un escalofrío te recorre. ¡Está maldito!"),
 ("MSG_DROP", "You drop: {0}.", "Sueltas: {0}."),
 ("MSG_THROW_HIT", "You hit {1} with the {0}.", "Alcanzas a {1} con: {0}."),
 ("MSG_THROW_MISS", "The {0} misses {1}.", "{0}: falla a {1}."),
 ("MSG_SHATTER", "The flask shatters.", "El frasco se hace añicos."),
 ("MSG_WAND_EMPTY", "The wand sputters. It's out of charges.", "La varita chisporrotea. Está agotada."),
 ("MSG_ZAP_NOTHING", "It's a {0}! The bolt hits nothing.", "¡Es una {0}! El rayo no alcanza a nadie."),
 ("MSG_BOLT_HITS", "Lightning strikes {0}!", "¡El relámpago alcanza a {0}!"),
 ("MSG_SLEEPS", "{0} falls asleep.", "{0} se queda dormido."),
 ("MSG_FORCE", "An unseen force slams {0}!", "¡Una fuerza invisible golpea a {0}!"),
 ("MSG_P_HEAL", "You feel much better.", "Te sientes mucho mejor."),
 ("MSG_P_VIGOR", "Vigour floods your body!", "¡El vigor inunda tu cuerpo!"),
 ("MSG_P_MIGHT", "Your muscles swell with strength!", "¡Tus músculos se llenan de fuerza!"),
 ("MSG_P_HASTE", "Everything around you slows down.", "Todo a tu alrededor se ralentiza."),
 ("MSG_P_SIGHT", "Your mind's eye sees the whole floor.", "Tu mente ve el piso entero."),
 ("MSG_P_CONFUSE", "The room spins around you.", "La sala da vueltas a tu alrededor."),
 ("MSG_P_POISON", "Ugh! That was poison.", "¡Puaj! Era veneno."),
 ("MSG_P_SLEEP", "You suddenly feel very drowsy…", "De pronto te entra mucho sueño…"),
 ("MSG_P_XP", "Visions of battle fill your mind.", "Visiones de batallas llenan tu mente."),
 ("MSG_S_TELEPORT", "You blink and find yourself elsewhere.", "Parpadeas y apareces en otro lugar."),
 ("MSG_S_ENCHANT_NONE", "Your hands tingle briefly.", "Te hormiguean las manos un instante."),
 ("MSG_S_ENCHANT", "Your {0} glows blue.", "{0}: brilla en azul."),
 ("MSG_S_MAP", "A map of the floor forms in your mind.", "Un mapa del piso se forma en tu mente."),
 ("MSG_S_FEAR", "A dreadful howl fills the air.", "Un aullido terrible llena el aire."),
 ("MSG_S_FIRE", "The scroll bursts into flames!", "¡El pergamino estalla en llamas!"),
 ("MSG_S_SUMMON", "Monsters appear around you!", "¡Aparecen monstruos a tu alrededor!"),
 ("MSG_S_IDENTIFY_NONE", "You already know everything you carry.", "Ya conoces todo lo que llevas."),
 ("MSG_S_IDENTIFY", "You now know: {0}.", "Ahora conoces: {0}."),
 ("MSG_LEVEL_UP", "Welcome to experience level {0}!", "¡Alcanzas el nivel de experiencia {0}!"),
 ("MSG_YOU_HIT", "You hit {0}.", "Golpeas a {0}."),
 ("MSG_YOU_MISS", "You miss {0}.", "Fallas contra {0}."),
 ("MSG_KILL", "You defeat {0}!", "¡Derrotas a {0}!"),
 ("MSG_KING_DIES", "The Ashen King crumbles. Something glows among the ashes…", "El Rey Ceniciento se desmorona. Algo brilla entre las cenizas…"),
 ("MSG_YOU_DIE", "You die…", "Mueres…"),
 ("MSG_WAKE_UP", "You wake up.", "Te despiertas."),
 ("MSG_HASTE_END", "You slow down.", "Vuelves a tu ritmo normal."),
 ("MSG_CONF_END", "Your head clears.", "Se te despeja la cabeza."),
 ("MSG_HUNGRY", "You are getting hungry.", "Empiezas a tener hambre."),
 ("MSG_WEAK", "You feel weak from hunger.", "Te sientes débil de hambre."),
 ("MSG_STARVING", "You are starving!", "¡Te mueres de hambre!"),
 ("MSG_SPOT", "You spot {0}.", "Ves a {0}."),
 ("MSG_BOSS_SUMMON", "{0} raises the dead!", "¡{0} alza a los muertos!"),
 ("MSG_SHOT_MISS", "It misses you.", "No te alcanza."),
 ("MSG_MON_MISS", "{0} misses you.", "{0} falla."),
 ("MSG_STEAL", "{0} snatches some gold and vanishes!", "¡{0} te roba oro y desaparece!"),
 ("MSG_MON_HIT", "{0} hits you.", "{0} te golpea."),
 ("MSG_DRAINED", "You feel your life force drain away.", "Sientes que tu fuerza vital se escapa."),
]
for k, en, es in M:
    a(k, en, es)
for k, en, es in [("CAUSE_TRAP", "a dart trap", "una trampa de dardos"), ("CAUSE_FIRE", "their own fire", "su propio fuego"),
                  ("CAUSE_POISON", "poison", "el veneno"), ("CAUSE_STARVE", "hunger", "el hambre"),
                  ("CAUSE_WON", "victory", "la victoria"), ("CAUSE_QUIT", "giving up", "rendición"),
                  ("CN_TRAP", "dart trap", "trampa"), ("CN_FIRE", "own fire", "fuego propio"), ("CN_POISON", "poison", "veneno"),
                  ("CN_STARVE", "hunger", "hambre"), ("CN_QUIT", "abandoned", "abandonada"), ("CN_WON", "victory", "victoria")]:
    a(k, en, es)
for k, en, es in [
 ("INS_UNKNOWN", "Unexplored.", "Sin explorar."), ("INS_YOU", "You — HP {0}/{1}, level {2}", "Tú: PV {0}/{1}, nivel {2}"),
 ("INS_AWAKE", "awake", "despierto"), ("INS_ASLEEP", "asleep", "dormido"), ("INS_AFRAID", "fleeing", "huyendo"),
 ("INS_MON", "{0} — HP {1}/{2}, {3}", "{0}: PV {1}/{2}, {3}"),
 ("TR_RANGED", "attacks from afar", "ataca a distancia"), ("TR_THIEF", "steals gold", "roba oro"),
 ("TR_ERRATIC", "flies erratically", "vuela errático"), ("TR_BOSS", "summons the dead", "invoca muertos"),
 ("TR_FAST", "fast", "rápido"), ("TR_SLOW", "slow", "lento"), ("TR_PACK", "hunts in packs", "caza en manada"),
 ("TR_POISON", "poisonous", "venenoso"), ("TR_DRAIN", "drains life", "drena vida"), ("TR_REGEN", "regenerates", "se regenera"),
 ("TR_COWARD", "flees when hurt", "huye si está herido"),
 ("TRAP_DART", "Dart trap", "Trampa de dardos"), ("TRAP_TELEPORT", "Teleport rune", "Runa de teletransporte"), ("TRAP_ALARM", "Alarm trap", "Trampa de alarma"),
 ("T_WALL", "Rough stone wall.", "Muro de piedra."), ("T_FLOOR", "Stone floor.", "Suelo de piedra."), ("T_CORRIDOR", "A dark passage.", "Un pasadizo oscuro."),
 ("T_DOOR", "A closed door.", "Una puerta cerrada."), ("T_OPEN_DOOR", "An open door.", "Una puerta abierta."),
 ("T_STAIRS", "Stairs leading down.", "Escaleras que bajan."), ("T_UPSTAIRS", "The way you came in.", "Por donde entraste.")]:
    a(k, en, es)

keys = [k for k, _, _ in S]
assert len(keys) == len(set(keys)), [k for k in keys if keys.count(k) > 1]
with open("i18n/strings.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["keys", "en", "es"])
    for row in S:
        w.writerow(row)
print(len(S), "keys")
