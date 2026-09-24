# 🤿 Deep Dive

배 없이 **직접 뛰어들어 잠수하는** 로블록스 시뮬레이터입니다. 로블록스의 카약·서핑 시뮬레이터를
다이빙 버전으로 옮긴 구조로, 스폰하자마자 눈앞의 블루홀(석호)에 뛰어들어 유물을 모으고,
선착장의 **보물 상점**(금색 판매 패드)에서 팔아 코인으로 바꿉니다. 코인으로 장비를 강화하고, 알에서 펫을 뽑고,
보물상자를 들고 올라와 다음 월드를 엽니다. **월드 1~20**은 같은 형식에 테마·깊이·보상만 달라지며,
뒤로 갈수록 더 강한 펫이 나옵니다.

- 모든 UI 글꼴은 둥근 **Fredoka One** (`Font.fromEnum(Enum.Font.FredokaOne)`)
- 월드·섬·장식·펫·유물·알은 전부 코드로 생성 (별도 에셋 업로드 불필요)
- 서버 권한 방식: 산소, 유물 획득, 판매, 구매는 모두 서버가 검증
- DataStore 세션 잠금 저장, 멱등 영수증 처리, 원격 호출 속도 제한
- **유물 도감**(월드별 5종, 미발견은 실루엣), **글로벌 리더보드**(누적 코인 TOP 10),
  머리 위 닉네임·코인 표시, 커스텀 **Tab 플레이어 목록**(닉네임 – 코인 – 유물 수)

## 빠른 시작

1. `DeepDive.rbxlx`를 Roblox Studio에서 엽니다.
2. **Play**를 누릅니다. 월드 1은 시작과 동시에 만들어지고, 나머지 19개는 백그라운드에서 이어서 지어집니다.
3. 저장 기능까지 테스트하려면 게임을 퍼블리시한 뒤
   **Game Settings → Security → Enable Studio Access to API Services**를 켭니다.
   (꺼져 있으면 세션 전용 프로필로 자동 전환되고 출력 창에 안내가 나옵니다.)

### Rojo로 개발할 때

```bash
rokit install                 # rojo / stylua / lune / luau-lsp 설치 (rokit.toml)
rojo serve                    # Studio의 Rojo 플러그인에서 Connect
rojo build -o DeepDive.rbxlx  # 플레이스 파일 다시 만들기
```

## 퍼블리시 체크리스트

| 항목 | 위치 | 설명 |
| --- | --- | --- |
| 게임패스 4종 | `src/shared/Config.luau` → `Config.Passes` | Creator Dashboard에서 만든 ID를 `id`에 입력. `0`이면 상점에 "Coming soon"으로 표시되고 구매 불가 |
| 코인 상품 3종 | `Config.Products` | 개발자 상품 ID 입력. 지급량은 현재 해금 월드 기준 "다이빙 N회분"으로 자동 계산 |
| 배경음악 (선택) | `Config.Music.Surface / Underwater` | `rbxassetid://...` 입력. 비워두면 무음 |
| 효과음 교체 (선택) | `Config.SoundIds` | 기본은 엔진 내장 소리를 겹쳐 만든 효과음. Creator Store(Audio)에서 고른 소리의 `rbxassetid://...`를 넣으면 해당 효과음(Collect, Sell, Hatch, Legendary 등)만 교체 |
| API 서비스 | Game Settings → Security | 저장(DataStore)에 필요 |

게임패스: **Double Coins**(코인 2배) · **Lucky Eggs**(에픽 이상 확률 2배) · **+2 Pet Slots** · **Swift Fins**(수영 속도 +25%)

## 조작

| | PC | 모바일 |
| --- | --- | --- |
| 수영 | WASD (카메라 방향으로) | 썸스틱 |
| 위로 / 수면 점프 | Space (수면에서 꾹) | UP 버튼 · 점프 버튼 |
| 아래로 | C · Ctrl · Q | DOWN 버튼 |
| 대시 | Shift | DASH 버튼 |
| 알·보물 상점·포털 | E (근접 프롬프트) | 탭 |
| 플레이어 목록 | Tab | 오른쪽 위 👥 버튼 |

물속에서만 모바일 수영 패드가 나타납니다.

## 게임 루프

1. **잠수** – 스폰 앞 석호로 뛰어들면 다이빙 시작. 산소는 깊을수록 빨리 줄어듭니다(수압).
2. **수집** – 바닥의 유물에 다가가면 자석으로 흡수. 가방이 가득 차면 더 못 담습니다.
   화면 아래 중앙에는 남은 잠수 시간(산소)이 항상 표시됩니다.
3. **판매** – 올라와도 자동으로 팔리지 않습니다. 월드마다 선착장에 있는 **보물 상점**의 금색 패드를 밟거나
   E를 누르면 가방 속 유물이 한 번에 팔립니다(가방은 저장됨). 산소가 바닥나면 기절 → 구조되며 이번 잠수에서
   주운 유물의 절반을 잃습니다.
4. **강화** – 산소통 / 가방 / 오리발(속도) / 자석(범위) 4트랙.
5. **펫** – 월드마다 다른 알. 장착한 펫의 부스트가 합산되어 코인 배수가 됩니다.
6. **클리어** – 월드 목표(유물 판매 수)를 채우면 **고대 보물상자**가 가장 깊은 곳에 나타남 →
   들고 수면까지 올라오면 월드 클리어 + 첫 클리어 보상 + 다음 월드 해금.

밸런스(자동 시뮬레이션 기준): 월드 1 약 2분, 20개 월드 전체는 효율적으로 약 2시간(일반 플레이 3~4시간).

## 20개 월드

| # | 월드 | World | 깊이 | 목표 | 알 가격 | 전설 펫 | 시크릿 (1/2000) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 햇살 여울 | Sunny Shallows | 30m | 12 | 200 | 무지개 물고기 | |
| 2 | 해초 초원 | Seagrass Meadow | 60m | 14 | 360 | 나뭇잎해룡 | |
| 3 | 다시마 숲 | Kelp Forest | 110m | 17 | 650 | 다시마 크라켄 | |
| 4 | 조수 웅덩이 만 | Tidepool Cove | 170m | 21 | 1.2K | 달빛 가오리 | 황금 거북 |
| 5 | 무지개 산호초 | Rainbow Reef | 240m | 25 | 2.1K | 무지개 돌고래 | |
| 6 | 풍선껌 석호 | Bubblegum Lagoon | 320m | 30 | 3.8K | 유니콘 일각고래 | |
| 7 | 빛나는 동굴 | Glowing Grotto | 410m | 36 | 6.8K | 오로라 만타 | |
| 8 | 그레이트 배리어 | Great Barrier | 500m | 43 | 12K | 백상아리 | 무지개 서펜트 |
| 9 | 난파선 만 | Shipwreck Bay | 600m | 52 | 22K | 꼬마 크라켄 | |
| 10 | 해적의 무덤 | Pirate's Graveyard | 700m | 62 | 40K | 팬텀 크라켄 | |
| 11 | 가라앉은 신전 | Sunken Temple | 820m | 74 | 71K | 태양 드래곤 | |
| 12 | 아틀란티스 관문 | Atlantis Gate | 950m | 89 | 130K | 아기 리바이어던 | 포세이돈의 준마 |
| 13 | 얼어붙은 피오르 | Frozen Fjord | 1100m | 107 | 230K | 일각고래 | |
| 14 | 수정 동굴 | Crystal Caverns | 1300m | 128 | 420K | 프리즘 서펜트 | |
| 15 | 화산 분출구 | Volcanic Vents | 1550m | 154 | 750K | 용암 드래곤 | |
| 16 | 마그마 균열 | Magma Rift | 1800m | 185 | 1.3M | 지옥 고래 | 피닉스 가오리 |
| 17 | 황혼 수역 | Twilight Zone | 2100m | 222 | 2.4M | 황혼 고래 | |
| 18 | 한밤 해구 | Midnight Trench | 2500m | 266 | 4.4M | 한밤 리바이어던 | |
| 19 | 심연 평원 | Abyssal Plains | 3000m | 319 | 7.9M | 심연 크라켄 | |
| 20 | 리바이어던의 아가리 | Leviathan's Maw | 4000m | 383 | 14M | 리바이어던 | 우주 고래 |

## 글꼴과 언어

로블록스의 둥근 글꼴(Fredoka One)에는 한글 글리프가 없어서, 한글은 로블록스 기본 대체 글꼴로 표시됩니다.
그래서 **기본 언어는 영어**(전부 둥근 글꼴)이고, 설정 창에서 **한국어**로 바꿀 수 있습니다(저장됨).
`Config.DefaultLanguage`를 `"ko"`(항상 한국어) 또는 `"auto"`(로블록스 언어 설정 따라감)로 바꿀 수 있습니다.

## 프로젝트 구조

```
src/
  shared/            ReplicatedStorage.Shared – 설정, 경제 공식, 월드 데이터, 문자열(EN/KO), 모델 생성기
    Data/Worlds.luau   20개 월드: 테마, 지형 색, 유물 5종, 펫 5종(+시크릿), 위험요소, 물고기
    Models/            Build(도형 헬퍼) · PetModels(24종 체형) · RelicModels(30종 유물, 상자, 알)
  server/            ServerScriptService.Server – 프로필 저장, 네트워크, 다이빙 루프, 펫, 구매
    World/             지형(섬 + 계단식 블루홀) · 장식 킷 18종 · 선착장/스폰 · 월드 빌더
  client/            StarterPlayerScripts.Client – HUD, 패널(도감 포함), 연출, 수영, 조명/수중 효과
    Sfx.luau           레이어드 효과음 (Config.SoundIds로 교체 가능)
    WorldFx.luau       반짝임·충격파 링·코인 분수 월드 이펙트
    Controllers/       Nameplates(머리 위 이름표) · Board(리더보드 화면) · Relics(외곽선) 등
tests/
  run.luau           단위 테스트 (데이터 무결성, 경제 곡선, 문자열, 프로필 복구, 진행 시뮬레이션)
  smoke.luau         런타임 스모크 테스트 (아래 참고)
  harness/engine.luau  Lune용 로블록스 엔진 에뮬레이터
  snapshots.luau     UI 미리보기 (HTML 내보내기, harness/html.luau)
tools/check.sh       전체 검증 스크립트
```

## 검증

```bash
tools/check.sh
```

1. **luau-lsp** 엄격 모드 타입 검사 (Roblox API 정의 기준)
2. **StyLua** 포맷 검사
3. **단위 테스트** `lune run tests/run.luau`
4. **런타임 스모크 테스트** `lune run tests/smoke.luau` / `--mobile`
   빌드된 `.rbxlx`를 불러와 서버·클라이언트 스크립트를 실제로 실행합니다. 모든 속성 쓰기를 리플렉션 DB로
   검증(잘못된 속성명·타입·읽기전용), 원격 호출 페이로드와 DataStore 값을 로블록스 직렬화 규칙으로 검사하면서
   접속 → 잠수·수집 → 보물 상점 판매 → 이름표·플레이어 목록·리더보드 → 강화 → 알·펫 → 보물상자·클리어 → 이동 → 기절·구조 → 사망·부활 → 한국어 전환 →
   구매(영수증 멱등성) → UI 버튼 전수 클릭 → 20개 월드 순회 → 퇴장·저장·재접속까지 플레이하고,
   모든 텍스트가 둥근 글꼴인지, 번역 키가 그대로 노출되지 않는지도 확인합니다.

### UI 미리보기 (Studio 없이)

```bash
lune run tests/snapshots.luau out            # PC (1280x720)
lune run tests/snapshots.luau out --mobile   # 휴대폰 가로 (844x390)
lune run tests/snapshots.luau out --ko       # 한국어
```

에뮬레이터에서 실제 UI 코드를 실행해 로딩 화면, HUD, 잠수 중 HUD, 판매 연출, 각 패널(도감 포함), 알 부화,
월드 클리어, 기절 화면을 `out/*.html`로 내보냅니다. 브라우저 창을 해당 해상도로 맞춰 열면 됩니다.
근사 렌더링이며, 3D 뷰포트(펫·알 미리보기)는 자리표시자로 보입니다.
