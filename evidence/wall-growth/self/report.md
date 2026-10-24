# TECH-3D-11 自己確認

対象: HEAD `99013702eaf36db72a64d60d284680fb834f13c5` + 共有未コミット成果。2026-10-16、Sol実装。製品コード凍結済み。

変更は `map.gd`、新規 `wall_growth_controller.gd`、`water_surface.gdshader`、共通 `growth_patch.gd` / `surface_layers.gd`。自己確認2件と原本との差分・SHA256は [source-manifest.json](source-manifest.json)、[implementation.patch](implementation.patch)。水面script/session/actor/groundを含む保全117件は全件SHA一致 ([integrity.json](integrity.json))。

建物A/Bの既存front/right表面へ共通ツタ・コケを接続。根元/パッチの下を基壇外側0.2mへ投影し、半径0.65m内の対象セルを固定対応付けする。未緑化も分母に含め、発芽以上の内部growthを平均。0.5ゲーム秒のgrowth tickで視覚進行を蓄積し、入力1ならツタ90秒・コケ135秒。部分入力は速度を下げるだけで上限を制限しない。緑消失は保持/停止、再緑化で再開。屋根・追加地面草・ひびは生成しない。幹/枝は同じroot進行と既存累積距離を使用し、枝の開始距離まで描画しない。コケはパッチ別material coverageを持つ。

水面は既存の反射色を保持し、現1方向太陽の実shadow mapによるATTENUATIONだけをcustom lightで適用。影内は42%を下限とする美術的受影で、汎用物理水shaderではない。反射への太陽色/光量の再乗算は行わない。

検証は条件別各1回、Godot 4.7.2。headless logic **17 PASS / 0 FAIL** ([結果](logic-results.json)、[raw](logic-raw.json)、[ログ](logic.log))。実sessionへの種散布→発芽→時計接続、局所遅延、別棟非影響、コケ独立、停止/保持/再開、土/舗装同等、内部counter不変を確認。保存原本と新defaultのA/B/C生成・50%成長signatureおよびmoss配置は全て一致。旧lab全走行の代用とはしない。

Vulkan Forward+ / RTX 5070 Ti GPU **6 PASS / 0 FAIL** ([結果](gpu-results.json)、[raw](gpu-raw.json)、[ログ](gpu.log))。A前面の成熟帯を試験内で直接用意し0→45→135ゲーム秒を撮影。右面/別棟未成長、地面counter不変を確認。反射OFFでcaster ON/OFFの池内57画素が暗化し、caster OFFで反射ON/OFFの908画素が変化。太陽225→270で影領域が移動。元640画像からGPU nearest 1920画像の全画素3倍一致を1枚確認。自己目視と親目視で局所成長・水面影を確認済み。

代表画像:

- [初期](initial_wall_zero_ui_1920.png) → [45秒](front_wall_after45_ui_1920.png) → [135秒](front_wall_after135_ui_1920.png)
- [水面の反射と影ON](water_reflection_shadow_ON_ui_1920.png)、[影のみ](water_shadow_only_ui_1920.png)、[両OFF](water_reflection_shadow_OFF_ui_1920.png)、[反射のみ](water_reflection_only_ui_1920.png)、[太陽270](water_sun270_ui_1920.png)

実行は自動GPU root.unfocusable=true / Start-Process -WindowStyle Hidden、エンジン内状態操作とviewport撮影のみ。APPDATAは本証拠配下profile。自己GPU PID27960は自然終了exit0 ([process.json](process.json))。最終確認時Godotプロセスなし、実行資源返却・編集停止。全ログにERROR出力なし。新たなimport/editor起動、OS入力、前面化、カーソル操作は実施していない。

NOT_RUN: 物理入力経路、長時間/負荷、保存、全マップ汎用性、屋根接続、最終美術評価。建物定義の可視2面を使う固定試作で、任意建築の自動解析はしない。独立検証と最終受入は親担当。
