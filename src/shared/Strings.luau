--!strict
-- UI text in English and Korean. Keys are stable; display text is never used as data.

local Format = if script then require(script.Parent.Format) else require("./Format")

local Strings = {}

local EN: { [string]: string } = {
	title = "DEEP DIVE",
	subtitle = "20 worlds of sunken treasure",
	loading = "Diving in...",
	studioSave = "Studio test - progress is not saved",
	coins = "Coins",
	world = "World {n}",
	treasure = "Treasure {a}/{b}",
	findChest = "Find the Ancient Chest!",
	chestReady = "The Ancient Chest appeared at the bottom!",
	chestGot = "You got the Ancient Chest! Swim up to clear the world!",
	chestLost = "The Ancient Chest sank back down...",
	chest = "Ancient Chest",
	clearedTag = "Cleared",
	oxygen = "Oxygen",
	cargo = "Backpack",
	depth = "Depth",
	pressure = "Pressure {x}",
	full = "FULL",
	backpackFull = "Backpack full! Swim up to sell.",
	lowOxygen = "Low oxygen! Swim up!",
	hazardHit = "Ouch! -{n}s oxygen",
	depthRecord = "New depth record: {n}m!",
	newRelic = "New relic discovered!",

	["menu.worlds"] = "Worlds",
	["menu.upgrades"] = "Upgrades",
	["menu.pets"] = "Pets",
	["menu.shop"] = "Shop",
	["menu.settings"] = "Settings",
	["menu.index"] = "Index",

	up = "UP",
	down = "DOWN",
	dash = "DASH",

	["upgrade.tank"] = "Oxygen Tank",
	["upgrade.tank.desc"] = "Stay underwater longer",
	["upgrade.tank.value"] = "{n}s air",
	["upgrade.pack"] = "Backpack",
	["upgrade.pack.desc"] = "Carry more treasure per dive",
	["upgrade.pack.value"] = "{n} slots",
	["upgrade.fins"] = "Flippers",
	["upgrade.fins.desc"] = "Swim faster",
	["upgrade.fins.value"] = "Speed {n}",
	["upgrade.magnet"] = "Treasure Magnet",
	["upgrade.magnet.desc"] = "Pull in treasure from farther away",
	["upgrade.magnet.value"] = "Range {n}",
	level = "Lv. {n}",
	max = "MAX",
	buy = "Buy",
	notEnough = "Not enough coins",
	upgraded = "{name} upgraded!",

	worldsTitle = "Worlds",
	go = "Go!",
	here = "Here",
	locked = "Locked",
	lockedHint = "Clear World {n}",
	depthMax = "{n}m deep",
	eggPets = "Pets inside",

	petsTitle = "Pets",
	equipped = "Equipped {a}/{b}",
	equip = "Equip",
	unequip = "Unequip",
	equipBest = "Equip Best",
	delete = "Delete",
	lock = "Lock",
	unlock = "Unlock",
	boost = "{x} Coins",
	totalBoost = "Pet Boost {x}",
	noPets = "No pets yet! Hatch an egg at the dock.",
	inventory = "{a}/{b} pets",
	deleteConfirm = "Tap again to delete",

	hatch = "Hatch",
	hatch3 = "Hatch x3",
	chances = "Chances",
	newPet = "NEW!",
	inventoryFull = "Pet inventory full!",
	tapToContinue = "Tap to continue",

	["rarity.Common"] = "Common",
	["rarity.Uncommon"] = "Uncommon",
	["rarity.Rare"] = "Rare",
	["rarity.Epic"] = "Epic",
	["rarity.Legendary"] = "Legendary",
	["rarity.Secret"] = "Secret",

	shopTitle = "Shop",
	comingSoon = "Coming Soon",
	owned = "Owned",
	passes = "Game Passes",
	products = "Coin Packs",
	["pass.DoubleCoins"] = "2x Coins",
	["pass.DoubleCoins.desc"] = "Double every treasure sale, forever",
	["pass.LuckyEggs"] = "Lucky Eggs",
	["pass.LuckyEggs.desc"] = "2x chance for Epic, Legendary & Secret pets",
	["pass.PetSlots"] = "+2 Pet Slots",
	["pass.PetSlots.desc"] = "Equip 5 pets at once",
	["pass.SwiftFins"] = "Swift Fins",
	["pass.SwiftFins.desc"] = "Swim 25% faster",
	["product.CoinsSmall"] = "Coin Pouch",
	["product.CoinsMedium"] = "Coin Chest",
	["product.CoinsLarge"] = "Coin Vault",
	["product.desc"] = "+{n} Coins",
	thanks = "Thank you for your support!",

	settingsTitle = "Settings",
	["setting.music"] = "Music",
	["setting.sfx"] = "Sound Effects",
	["setting.lowFx"] = "Low Graphics",
	["setting.hidePets"] = "Hide Other Pets",
	["setting.language"] = "Language",
	on = "ON",
	off = "OFF",
	languageName = "English",

	sold = "Sold {n} treasures!",
	blackout = "You blacked out!",
	rescued = "The rescue team saved half your treasure",
	worldCleared = "WORLD CLEARED!",
	unlockedNext = "World {n} unlocked!",
	allCleared = "You conquered every world!",
	reward = "Reward",
	continue = "Continue",
	travelNow = "Travel now",
	stay = "Stay here",
	welcomeBack = "Welcome back, diver!",

	["tutorial.1"] = "Jump into the water to start diving!",
	["tutorial.2"] = "Swim to the glowing treasure!",
	["tutorial.3"] = "Swim back up to sell your treasure!",
	["tutorial.4"] = "Buy an upgrade!",
	["tutorial.5"] = "Hatch a pet at the egg!",
	["tutorial.6"] = "Fill the treasure bar to reveal the Ancient Chest!",
	controlsPc = "Look down + W to dive  -  Space: up  -  C: down  -  Shift: dash",
	controlsTouch = "Point the camera down and push forward to dive",

	["prompt.egg"] = "Hatch",
	["prompt.upgrades"] = "Upgrades",
	["prompt.portal"] = "Travel",
	["prompt.shop"] = "Shop",

	["err.busy"] = "One moment...",
	["err.diving"] = "Surface first!",
	["err.locked"] = "That world is locked",
	["err.generic"] = "Something went wrong",
	["err.notReady"] = "Still loading...",
}

local KO: { [string]: string } = {
	title = "딥 다이브",
	subtitle = "20개 월드의 가라앉은 보물",
	loading = "잠수 준비 중...",
	studioSave = "스튜디오 테스트 - 진행 상황이 저장되지 않아요",
	coins = "코인",
	world = "월드 {n}",
	treasure = "보물 {a}/{b}",
	findChest = "고대 보물상자를 찾아라!",
	chestReady = "바닥에 고대 보물상자가 나타났어요!",
	chestGot = "고대 보물상자 획득! 수면으로 올라가면 클리어!",
	chestLost = "고대 보물상자가 다시 가라앉았어요...",
	chest = "고대 보물상자",
	clearedTag = "클리어",
	oxygen = "산소",
	cargo = "가방",
	depth = "수심",
	pressure = "수압 {x}",
	full = "가득",
	backpackFull = "가방이 가득 찼어요! 위로 올라가서 팔아요.",
	lowOxygen = "산소 부족! 올라가세요!",
	hazardHit = "아야! 산소 -{n}초",
	depthRecord = "최고 수심 경신: {n}m!",
	newRelic = "새 유물 발견!",

	["menu.worlds"] = "월드",
	["menu.upgrades"] = "업그레이드",
	["menu.pets"] = "펫",
	["menu.shop"] = "상점",
	["menu.settings"] = "설정",
	["menu.index"] = "도감",

	up = "위로",
	down = "아래로",
	dash = "대시",

	["upgrade.tank"] = "산소 탱크",
	["upgrade.tank.desc"] = "더 오래 잠수해요",
	["upgrade.tank.value"] = "산소 {n}초",
	["upgrade.pack"] = "가방",
	["upgrade.pack.desc"] = "한 번에 보물을 더 많이 담아요",
	["upgrade.pack.value"] = "{n}칸",
	["upgrade.fins"] = "오리발",
	["upgrade.fins.desc"] = "더 빨리 헤엄쳐요",
	["upgrade.fins.value"] = "속도 {n}",
	["upgrade.magnet"] = "보물 자석",
	["upgrade.magnet.desc"] = "더 멀리서 보물을 끌어당겨요",
	["upgrade.magnet.value"] = "범위 {n}",
	level = "Lv. {n}",
	max = "최대",
	buy = "구매",
	notEnough = "코인이 부족해요",
	upgraded = "{name} 업그레이드!",

	worldsTitle = "월드",
	go = "이동!",
	here = "현재",
	locked = "잠김",
	lockedHint = "월드 {n} 클리어 필요",
	depthMax = "수심 {n}m",
	eggPets = "나올 수 있는 펫",

	petsTitle = "펫",
	equipped = "장착 {a}/{b}",
	equip = "장착",
	unequip = "해제",
	equipBest = "최고 장착",
	delete = "삭제",
	lock = "잠금",
	unlock = "잠금 해제",
	boost = "코인 {x}",
	totalBoost = "펫 부스트 {x}",
	noPets = "아직 펫이 없어요! 부두의 알을 부화시켜 보세요.",
	inventory = "펫 {a}/{b}",
	deleteConfirm = "한 번 더 누르면 삭제",

	hatch = "부화",
	hatch3 = "3번 부화",
	chances = "확률",
	newPet = "NEW!",
	inventoryFull = "펫 가방이 가득 찼어요!",
	tapToContinue = "눌러서 계속",

	["rarity.Common"] = "일반",
	["rarity.Uncommon"] = "고급",
	["rarity.Rare"] = "희귀",
	["rarity.Epic"] = "영웅",
	["rarity.Legendary"] = "전설",
	["rarity.Secret"] = "비밀",

	shopTitle = "상점",
	comingSoon = "준비 중",
	owned = "보유 중",
	passes = "게임 패스",
	products = "코인 팩",
	["pass.DoubleCoins"] = "코인 2배",
	["pass.DoubleCoins.desc"] = "모든 보물 판매 금액이 영구 2배",
	["pass.LuckyEggs"] = "행운의 알",
	["pass.LuckyEggs.desc"] = "영웅·전설·비밀 펫 확률 2배",
	["pass.PetSlots"] = "펫 슬롯 +2",
	["pass.PetSlots.desc"] = "펫을 5마리까지 장착",
	["pass.SwiftFins"] = "쾌속 오리발",
	["pass.SwiftFins.desc"] = "25% 더 빠르게 헤엄쳐요",
	["product.CoinsSmall"] = "코인 주머니",
	["product.CoinsMedium"] = "코인 상자",
	["product.CoinsLarge"] = "코인 금고",
	["product.desc"] = "코인 +{n}",
	thanks = "응원해 주셔서 고마워요!",

	settingsTitle = "설정",
	["setting.music"] = "음악",
	["setting.sfx"] = "효과음",
	["setting.lowFx"] = "그래픽 낮춤",
	["setting.hidePets"] = "다른 펫 숨기기",
	["setting.language"] = "언어",
	on = "켜짐",
	off = "꺼짐",
	languageName = "한국어",

	sold = "보물 {n}개 판매!",
	blackout = "기절했어요!",
	rescued = "구조대가 보물 절반을 챙겨줬어요",
	worldCleared = "월드 클리어!",
	unlockedNext = "월드 {n} 해금!",
	allCleared = "모든 월드를 정복했어요!",
	reward = "보상",
	continue = "계속",
	travelNow = "지금 이동",
	stay = "머무르기",
	welcomeBack = "다시 온 걸 환영해요, 다이버!",

	["tutorial.1"] = "물속으로 뛰어들어 잠수를 시작하세요!",
	["tutorial.2"] = "빛나는 보물로 헤엄쳐 가세요!",
	["tutorial.3"] = "위로 올라가서 보물을 팔아요!",
	["tutorial.4"] = "업그레이드를 구매하세요!",
	["tutorial.5"] = "알을 부화시켜 펫을 얻어요!",
	["tutorial.6"] = "보물 게이지를 채우면 고대 보물상자가 나타나요!",
	controlsPc = "아래를 보고 W로 잠수  -  Space: 위로  -  C: 아래로  -  Shift: 대시",
	controlsTouch = "카메라를 아래로 향하고 앞으로 밀면 잠수해요",

	["prompt.egg"] = "부화",
	["prompt.upgrades"] = "업그레이드",
	["prompt.portal"] = "이동",
	["prompt.shop"] = "상점",

	["err.busy"] = "잠시만요...",
	["err.diving"] = "먼저 수면으로 올라오세요!",
	["err.locked"] = "잠긴 월드예요",
	["err.generic"] = "문제가 발생했어요",
	["err.notReady"] = "아직 불러오는 중이에요...",
}

local TABLES = { en = EN, ko = KO }

Strings.language = "en"
Strings.languages = { "en", "ko" }

function Strings.setLanguage(lang: string)
	if TABLES[lang] then
		Strings.language = lang
	end
end

function Strings.get(key: string, args: { [string]: any }?): string
	local text = TABLES[Strings.language][key] or EN[key] or key
	return Format.fill(text, args)
end

function Strings.name(named: { en: string, ko: string }): string
	return (named :: any)[Strings.language] or named.en
end

function Strings.hasKey(key: string): boolean
	return EN[key] ~= nil
end

-- Keys that exist in English but are missing in Korean (for tests).
function Strings.missingKorean(): { string }
	local missing = {}
	for key in EN do
		if KO[key] == nil then
			table.insert(missing, key)
		end
	end
	table.sort(missing)
	return missing
end

return Strings
