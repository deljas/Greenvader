# POC-05 自己検証報告（親が実装担当の返却本文から要約転記）

- 対象: HEAD 9901370＋既存未コミット差分。scripts/poc/assets・enemy・world・play・既存labは未変更。再現手順とhashは repro.txt。
- 新規: scripts/poc/environment/（poc_day、environment_view、ground_cover、water_view＋water_surface.gdshader、wall_layout、wall_growth、wall_view、wall_parts、wall_moss.gdshader）、data/poc/environment.json、data/poc/terrain/paved.tres（T_PAVED=6）、tests/poc/environment/logic.gd・gpu.gd。変更: poc_session.gd、poc_main.gd、play/poc_play_view.gd。
- 時計: 時刻はSimClock.elapsedのみから導出（1日600s、開始8:00、最大仰角55°）。北=画面上、東→南→西。キーライト1灯（昼=太陽、夜=月）。
- 日光係数: 1.0〜1.25（夜=1.0）、水分と独立。
- 地形別表示: 土は草の房が覆い、舗装は割れ目沿いの草。MultiMesh差分更新。表示密度は内部率に無関係。舗装はenvironment.jsonのpaving.rectsでpoc_main経由のオプトイン。
- 壁面植生: 素材台帳vine_surfaces＋metadataのreceiver面、窓枠沿いの蔓・ガラス縁の枝・苔、出入口0.30m回避、最大被覆15〜25%（壁の約75%以上が見える）、根元0.65m内の緑化平均で局所成長、緑喪失で停止・進捗保持、to_dict/load_dict。建物とは別Node（WallVeg_<instance_id>）。
- 水面: 地形waterに平面反射（描画サイズ/2）と太陽/月の受影。
- 結果: environment logic 81 PASS、combat logic 48 PASS（100％ 安定後186.5s / 上限237.0s）、base 40・assets 45・play 69 PASS、GPU 21 PASS（640/960×朝昼夕夜、壁植生、水面反射・受影、影同期）。0 FAIL。
- 撮影上の演出: 戦闘fixture撃破済み、地面を帯状に成熟後140s早送りで壁を実成長、木を移動、高い廃屋を非表示（プレイ状態ではない）。
- NOT_RUN: 物理入力、実時間テンポ、夜の街灯（任意、未実装）、遮蔽透過との組合せ（POC-06）、独立目視。
